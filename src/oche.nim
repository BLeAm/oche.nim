## Oche: Nim FFI codegen for Dart and Python. Core in oche_core, emitters in oche_dart and oche_python.
import std/[macros, os, strutils, tables, sequtils]
import oche_core
import oche_dart
import oche_python
export oche_core.Backend

var ocheFreeInjected {.compileTime.}: bool = false

var lastOcheError {.threadvar.}: string

proc toOcheStr*(s: string): cstring =
  if s.len == 0: return nil
  result = cast[cstring](alloc0(s.len + 1))
  copyMem(result, s.cstring, s.len + 1)

type
  OcheBuffer*[T] = object
    p*: pointer

proc len*[T](b: OcheBuffer[T]): int =
  if b.p.isNil: return 0
  cast[ptr int64](b.p)[]

template dataPtr*[T](b: OcheBuffer[T]): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](cast[uint](b.p) + 16)

proc `[]`*[T](b: OcheBuffer[T], idx: int): var T =
  if idx < 0 or idx >= b.len: raise newException(IndexDefect, "OcheBuffer index out of bounds")
  b.dataPtr[idx]

proc `[]=`*[T](b: OcheBuffer[T], idx: int, val: T) =
  if idx < 0 or idx >= b.len: raise newException(IndexDefect, "OcheBuffer index out of bounds")
  b.dataPtr[idx] = val

proc newOcheBuffer*[T](n: int, typeId: int = 0): OcheBuffer[T] =
  let p = cast[ptr byte](alloc0(16 + (n * sizeof(T))))
  cast[ptr int64](p)[] = n
  cast[ptr int32](cast[uint](p) + 8)[] = int32(typeId)
  OcheBuffer[T](p: p)

macro ocheId*(T: typedesc): int =
  let name = T.getTypeInst[1].strVal
  if structBanks.hasKey(name): result = newLit(structBanks[name].typeId)
  else: result = newLit(0)

template newOche*[T](n: int): OcheBuffer[T] =
  newOcheBuffer[T](n, typeId = ocheId(T))

proc ocheGetError(): cstring {.exportc, dynlib.} =
  if lastOcheError == "": return nil
  let L = lastOcheError.len
  result = cast[cstring](alloc0(L + 1))
  copyMem(result, lastOcheError.cstring, L + 1)
  lastOcheError = ""

# proc ocheFree*(p: pointer) {.exportc: "ocheFree", dynlib, cdecl.} =
#   if not p.isNil: dealloc(p)

# proc ocheFreeDeep*(p: pointer) {.exportc: "ocheFreeDeep", dynlib, cdecl.} =
#   if not p.isNil: dealloc(p)

proc processOche(body: NimNode, isView: bool, backend: static Backend = bDart): NimNode {.compileTime.} =
  if body.kind == nnkTypeDef:
    var nameNode = body[0]; (if nameNode.kind == nnkPragmaExpr: nameNode = nameNode[0])
    let name = nameNode.strVal; let tyNode = body[2]
    if tyNode.kind == nnkEnumTy:
      var v: seq[string] = @[]; (for i in 1..<tyNode.len: (if tyNode[i].kind == nnkIdent: v.add tyNode[i].strVal elif tyNode[i].kind == nnkEnumFieldDef: v.add tyNode[i][0].strVal))
      enumBanks[name] = OcheEnum(name: name, values: v)
      let prag = newTree(nnkPragma, newColonExpr(ident("size"), newLit(4)))
      return newTree(nnkTypeDef, newTree(nnkPragmaExpr, nameNode, prag), newEmptyNode(), tyNode)
    else:
      var f: seq[OcheField] = @[]; let rec = tyNode[2]; var pod = true
      let newRec = newTree(nnkRecList)
      for field in rec:
         if field.kind == nnkIdentDefs:
           var ft = field[^2]
           if ft.kind == nnkIdent and ft.strVal == "string": ft = ident("cstring")
           let t = parseType(ft)
           for i in 0..<field.len-2:
             var fn = field[i]; (if fn.kind == nnkPostfix: fn = fn[1]); f.add OcheField(name: fn.strVal, typ: t)
           if t.name in ["string", "cstring"]:
             pod = false
           elif structBanks.hasKey(t.name):
             if not structBanks[t.name].isPOD: pod = false
           var newNode = newTree(nnkIdentDefs)
           for i in 0..<field.len-2: newNode.add field[i]
           newNode.add ft; newNode.add newEmptyNode()
           newRec.add newNode
      structBanks[name] = OcheStruct(name: name, typeId: structBanks.len + 1, fields: f, isPOD: pod)
      return newTree(nnkTypeDef, nameNode, newEmptyNode(), newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), newRec))

  let obj = parseOche(body, isView)
  if backend == bDart:     ooBanks.add(obj)
  elif backend == bPython: ooBanksPython.add(obj)
  else:                    ooBanks.add(obj); ooBanksPython.add(obj)
  let procName = body[0]; let originalBody = body[6]; var originalRetType = body[3][0]
  if originalRetType.kind == nnkEmpty: originalRetType = ident"void"

  var ffiParams = newTree(nnkFormalParams)
  let retByPointer = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"] or obj.retType.isShared or structBanks.hasKey(obj.retType.name)
  if retByPointer: ffiParams.add ident("pointer") else: ffiParams.add originalRetType

  var reconstruction = newStmtList()
  for p in obj.params:
    if p.typ.isSeq:
      let pP = ident(p.name & "_ptr"); let pL = ident(p.name & "_len"); let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pP, newTree(nnkPtrTy, iT)); ffiParams.add newIdentDefs(pL, ident("int"))
      reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("@"), newTree(nnkCall, ident("toOpenArray"), newTree(nnkCast, newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)), pP), newLit(0), newTree(nnkInfix, ident("-"), pL, newLit(1)))))
    elif p.typ.name in ["string", "cstring"]:
      ffiParams.add newIdentDefs(ident(p.name & "_raw"), ident("cstring")); reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("$"), ident(p.name & "_raw")))
    elif enumBanks.hasKey(p.typ.name): ffiParams.add newIdentDefs(ident(p.name), ident("int32"))
    else:
      if structBanks.hasKey(p.typ.name):
        let pPtr = ident(p.name & "_ptr")
        ffiParams.add newIdentDefs(pPtr, newTree(nnkPtrTy, ident(p.typ.name)))
        reconstruction.add newLetStmt(ident(p.name), newTree(nnkDerefExpr, pPtr))
      else:
        ffiParams.add newIdentDefs(ident(p.name), ident(p.typ.name))

  let resNode = ident"res"
  var conv: NimNode
  if obj.retType.isSeq:
    let iT = ident(obj.retType.inner); let s = if structBanks.hasKey(obj.retType.inner): structBanks[obj.retType.inner] else: OcheStruct(isPOD: true)
    let tid = s.typeId; var flags = 0; (if s.isPOD: flags = flags or 2)
    conv = quote do:
      let L = int64(`resNode`.len)
      let p = cast[ptr byte](alloc0(16 + (L * sizeof(`iT`))))
      cast[ptr int64](p)[] = L
      cast[ptr int32](cast[uint](p) + 8)[] = int32(`tid`)
      cast[ptr int32](cast[uint](p) + 12)[] = int32(`flags`)
      if L > 0: copyMem(cast[pointer](cast[uint](p) + 16), unsafeAddr `resNode`[0], int(L) * sizeof(`iT`))
      p
  elif obj.retType.isShared:
    conv = quote do: `resNode`.p
  elif obj.retType.isOption:
    let iT = ident(obj.retType.inner)
    conv = quote do: (if `resNode`.isNone: nil else: (let p = cast[ptr `iT`](alloc0(sizeof(`iT`))); p[] = `resNode`.get; p))
  elif obj.retType.name in ["string", "cstring"]:
    conv = quote do: (let s = $ `resNode`; let p = cast[cstring](alloc0(s.len + 1)); copyMem(p, s.cstring, s.len + 1); p)
  elif structBanks.hasKey(obj.retType.name):
    let iT = ident(obj.retType.name)
    conv = quote do: (let p = cast[ptr `iT`](alloc0(sizeof(`iT`))); p[] = `resNode`; p)
  else: conv = resNode

  let internalProc = ident"internal"
  let isVoid = originalRetType.kind == nnkIdent and originalRetType.strVal == "void"

  var wrappedBody: NimNode
  if isVoid:
    wrappedBody = quote do:
      `reconstruction`
      proc `internalProc`() = `originalBody`
      try: `internalProc`()
      except Exception as e: lastOcheError = e.msg
  else:
    wrappedBody = quote do:
      `reconstruction`
      proc `internalProc`(): `originalRetType` = `originalBody`
      try:
        let `resNode` = `internalProc`()
        result = `conv`
      except Exception as e:
        lastOcheError = e.msg
        result = default(type(result))

  result = newTree(nnkProcDef, procName, newEmptyNode(), newEmptyNode(), ffiParams, newTree(nnkPragma, ident("exportc"), ident("dynlib")), newEmptyNode(), wrappedBody)

# Check if a pragma list node contains a given pragma name
proc hasPragma(pragmas: NimNode, name: string): bool {.compileTime.} =
  if pragmas.kind != nnkPragma: return false
  for p in pragmas:
    if p.kind == nnkIdent and p.strVal == name: return true
    if p.kind == nnkExprColonExpr and p[0].strVal == name: return true
  false

# Extract view flag from a pragma node (e.g. {.oche: view.} or {.porche: view.})
proc pragmaIsView(pragmas: NimNode, name: string): bool {.compileTime.} =
  if pragmas.kind != nnkPragma: return false
  for p in pragmas:
    if p.kind == nnkExprColonExpr and p[0].strVal == name:
      if p[1].kind == nnkIdent and p[1].strVal == "view": return true
  false

macro oche*(body: untyped): untyped =
  # When used as {.oche, porche.} the pragma node on the proc is still intact
  # at this point — we can peek at it before replacing the proc node.
  var alsoPorche = false
  var porcheView = false
  if body.kind == nnkProcDef:
    let pragmas = body[4]   # pragma list is index 4 on a ProcDef
    alsoPorche = hasPragma(pragmas, "porche")
    porcheView = pragmaIsView(pragmas, "porche")
  if alsoPorche:
    let obj = parseOche(body, porcheView)
    ooBanksPython.add(obj)
  processOche(body, false, bDart)

macro oche*(arg: untyped, body: untyped): untyped =
  var isView = false
  if arg.kind == nnkIdent and arg.strVal == "view": isView = true
  var alsoPorche = false
  var porcheView = false
  if body.kind == nnkProcDef:
    let pragmas = body[4]
    alsoPorche = hasPragma(pragmas, "porche")
    porcheView = pragmaIsView(pragmas, "porche")
  if alsoPorche:
    let obj = parseOche(body, porcheView)
    ooBanksPython.add(obj)
  processOche(body, isView, bDart)

macro porche*(body: untyped): untyped =
  if body.kind == nnkProcDef:
    if hasPragma(body[4], "oche"):
      ooBanks.add(parseOche(body, pragmaIsView(body[4], "oche")))
  processOche(body, false, bPython)

macro porche*(arg: untyped, body: untyped): untyped =
  var isView = false
  if arg.kind == nnkIdent and arg.strVal == "view": isView = true
  if body.kind == nnkProcDef:
    if hasPragma(body[4], "oche"):
      ooBanks.add(parseOche(body, pragmaIsView(body[4], "oche")))
  processOche(body, isView, bPython)

## {.ocheAll.} / {.ocheAll: view.}
## Registers the proc in BOTH Dart and Python banks in one pragma.
## Use instead of {.oche, porche.} which silently drops porche due to
## macro expansion order replacing the proc node before porche runs.
macro ocheAll*(body: untyped): untyped =
  ooBanks.add(parseOche(body, false))
  ooBanksPython.add(parseOche(body, false))
  processOche(body, false, bDart)   # bDart generates the actual exportc proc

macro ocheAll*(arg: untyped, body: untyped): untyped =
  var isView = false
  if arg.kind == nnkIdent and arg.strVal == "view": isView = true
  ooBanks.add(parseOche(body, isView))
  ooBanksPython.add(parseOche(body, isView))
  processOche(body, isView, bDart)

macro generate*(output: static string): untyped =
  
  let
    info = lineInfoObj(callsite())
    libname = "lib" & info.filename.splitFile.name

  var code = "//------------------ Generated by Oche ------------------\n"
  code &= "//              Don't edit this file by hand!\n"
  code &= "// ------------------------------------------------------\n"
  code &= "import 'dart:ffi' as ffi;\nimport 'dart:io' show Platform;\nimport 'dart:collection';\nimport 'package:ffi/ffi.dart';\n\nfinal String _libName = Platform.isWindows ? '" & libname & ".dll' : (Platform.isMacOS ? '" & libname & ".dylib' : '" & libname & ".so');\nfinal dynlib = ffi.DynamicLibrary.open('./$_libName');\nfinal _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\nfinal _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');\nfinal _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');\nfinal _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');\nvoid _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }\n"

  var inner = ""
  for o in ooBanks: inner &= genDInterface(o)

  for s in enumBanks.values: code &= genDEnum(s)
  for s in structBanks.values: code &= genDStruct(s)
  for t in typeDefBanks: code &= t & "\n"

  code &= "final _finalizerDeep = Finalizer<ffi.Pointer<ffi.Void>>((ptr) => _ocheFreeDeep(ptr));\n\n" &
          "abstract class OcheView<T> extends ListBase<T> {\n" &
          "  ffi.Pointer<ffi.Void> get _nativePtr;\n" &
          "  @override int get length;\n" &
          "  @override set length(int value) => throw UnsupportedError('Cannot resize native buffer');\n" &
          "  @override Iterator<T> get iterator => _NativeListIterator<T>(this);\n" &
          "}\n\n" &
          "class NativeListView<T> extends OcheView<T> {\n" &
          "  ffi.Pointer<ffi.Void> _ptr;\n" &
          "  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;\n" &
          "  final int _elemSize;\n" &
          "  @override late final int length;\n" &
          "  NativeListView(this._ptr, this._unpacker, this._elemSize) {\n" &
          "    if (_ptr.address == 0) { length = 0; return; }\n" &
          "    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;\n" &
          "    _finalizerDeep.attach(this, _ptr, detach: this);\n" &
          "  }\n" &
          "  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;\n" &
          "  @override T operator [](int index) {\n" &
          "    if (_ptr.address == 0) throw StateError('NativeListView has been disposed');\n" &
          "    if (index < 0 || index >= length) throw RangeError.index(index, this);\n" &
          "    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize)));\n" &
          "  }\n" &
          "  @override void operator []=(int index, T value) => throw UnsupportedError('View mode is read-only. Use Buffer mode for mutation.');\n" &
          "  void dispose() {\n" &
          "    if (_ptr.address == 0) return;\n" &
          "    _finalizerDeep.detach(this);\n" &
          "    _ocheFreeDeep(_ptr);\n" &
          "    _ptr = ffi.Pointer.fromAddress(0);\n" &
          "  }\n" &
          "}\n\n" &
          "class SharedListView<T> extends OcheView<T> {\n" &
          "  final ffi.Pointer<ffi.Void> _ptr;\n" &
          "  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;\n" &
          "  final void Function(ffi.Pointer<ffi.Void> ptr, dynamic value)? _packer;\n" &
          "  final int _elemSize;\n" &
          "  @override late final int length;\n" &
          "  SharedListView(this._ptr, this._unpacker, this._packer, this._elemSize) {\n" &
          "    if (_ptr.address == 0) { length = 0; return; }\n" &
          "    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;\n" &
          "  }\n" &
          "  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;\n" &
          "  @override T operator [](int index) {\n" &
          "    if (_ptr.address == 0) throw StateError('SharedListView has been disposed');\n" &
          "    if (index < 0 || index >= length) throw RangeError.index(index, this);\n" &
          "    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize)));\n" &
          "  }\n" &
          "  @override void operator []=(int index, dynamic value) {\n" &
          "    if (_ptr.address == 0) throw StateError('SharedListView has been disposed');\n" &
          "    if (index < 0 || index >= length) throw RangeError.index(index, this);\n" &
          "    final flags = ffi.Pointer<ffi.Int32>.fromAddress(_ptr.address + 12).value;\n" &
          "    if ((flags & 1) != 0) throw StateError('Buffer is frozen (READ-ONLY)');\n" &
          "    final p = ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize));\n" &
          "    if (_packer != null) { _packer!(p, value); }\n" &
          "    else if (value is int) { ffi.Pointer<ffi.Int64>.fromAddress(p.address).value = value; }\n" &
          "    else if (value is double) { ffi.Pointer<ffi.Double>.fromAddress(p.address).value = value; }\n" &
          "    else if (value is bool) { ffi.Pointer<ffi.Bool>.fromAddress(p.address).value = value; }\n" &
          "    else { throw UnsupportedError('Mutation via []= not supported for this type.'); }\n" &
          "  }\n" &
          "}\n\n" &
          "class _NativeListIterator<T> implements Iterator<T> {\n" &
          "  final OcheView<T> _view; int _index = -1;\n" &
          "  _NativeListIterator(this._view);\n" &
          "  @override T get current => _view[_index];\n" &
          "  @override bool moveNext() => ++_index < _view.length;\n" &
          "}\n"

  code &= "class Oche {\n" & inner & "\n}\nfinal oche = Oche();\n"
  writeFile(output, code)

  var free = "proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))\n"

  for s in structBanks.values:
    free &= "proc ocheFreeInner" & s.name & "(o: ptr " & s.name & ") = \n"
    for f in s.fields:
      if f.typ.name in ["string", "cstring"]:
        free &= "  if not o." & f.name & ".isNil: dealloc(cast[pointer](o." & f.name & "))\n"
      elif structBanks.hasKey(f.typ.name) and not structBanks[f.typ.name].isPOD:
        free &= "  ocheFreeInner" & f.typ.name & "(addr o." & f.name & ")\n"
    if s.fields.allIt(it.typ.name notin ["string", "cstring"] and (not structBanks.hasKey(it.typ.name) or structBanks[it.typ.name].isPOD)): free &= "  discard\n"

  free &= "proc ocheFreeInner(p: pointer, typeId: int32) {.exportc, dynlib.} = \n"
  for s in structBanks.values:
    free &= "  if typeId == " & $s.typeId & ": ocheFreeInner" & s.name & "(cast[ptr " & s.name & "](p)); return\n"
  free &= "  discard\n\n"

  free &= "proc ocheFreeDeep(p: pointer) {.exportc, dynlib.} = \n"
  free &= "  if p.isNil: return\n"
  free &= "  let flags = cast[ptr int32](cast[uint](p) + 12)[]\n"
  free &= "  if (flags and int32(2)) != 0: dealloc(p); return\n"
  free &= "  let L = cast[ptr int64](p)[]\n"
  free &= "  let typeId = cast[ptr int32](cast[uint](p) + 8)[]\n"
  for s in structBanks.values:
    if not s.isPOD:
      free &= "  if typeId == int32(" & $s.typeId & "):\n"
      free &= "    let dataPtr = cast[uint](p) + 16\n"
      free &= "    for i in 0 ..< L:\n"
      free &= "      let o = cast[ptr " & s.name & "](dataPtr + uint(i * sizeof(" & s.name & ")))\n"
      free &= "      ocheFreeInner" & s.name & "(o)\n"
      free &= "    dealloc(p); return\n"
  free &= "  dealloc(p)\n"

  # if not ocheFreeInjected: 
  #   discard parseStmt(free)
  #   ocheFreeInjected = true

  let wrapper = """
when not declared(ocheFree):
  $1
""" % [free]

  discard parseStmt(wrapper)

macro generatePython*(output: static string): untyped =
  let
    info = lineInfoObj(callsite())
    libname = "lib" & info.filename.splitFile.name

  var code = "# ------------------ Generated by Porche ------------------\n"
  code &= "#              Don't edit this file by hand!\n"
  code &= "# -----------------------------------------------------------\n"
  code &= "from typing import Optional, Any, List\n"
  code &= "import ctypes\n"
  code &= "import os\n\n"
  code &= genPythonPrelude()
  const ext = if hostOS == "windows": ".dll" elif hostOS == "macosx": ".dylib" else: ".so"
  code &= "_lib_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '" & libname & ext & "')\n"
  code &= "_lib = ctypes.CDLL(_lib_path)\n\n"
  code &= "_lib.ocheFree.argtypes = [ctypes.c_void_p]\n"
  code &= "_lib.ocheFree.restype = None\n"
  code &= "_lib.ocheFreeDeep.argtypes = [ctypes.c_void_p]\n"
  code &= "_lib.ocheFreeDeep.restype = None\n"
  code &= "_ocheFreeInner = _lib.ocheFreeInner\n"
  code &= "_ocheFreeInner.argtypes = [ctypes.c_void_p, ctypes.c_int32]\n"
  code &= "_ocheFreeInner.restype = None\n"
  code &= "_lib.ocheAllocBytes.argtypes = [ctypes.c_size_t]\n"
  code &= "_lib.ocheAllocBytes.restype = ctypes.c_void_p\n"
  code &= "_oche_get_error = _lib.ocheGetError\n"
  code &= "_oche_get_error.restype = ctypes.c_void_p\n"
  code &= "def _check_error():\n"
  code &= "    p = _oche_get_error()\n"
  code &= "    if p is not None:\n"
  code &= "        msg = ctypes.string_at(p).decode('utf-8')\n"
  code &= "        _lib.ocheFree(p)\n"
  code &= "        raise RuntimeError('NimError: ' + msg)\n\n"
  for s in structBanks.values: code &= genPStruct(s)
  for e in enumBanks.values: code &= genPEnum(e)
  code &= "class Porche:\n"
  if ooBanksPython.len == 0:
    code &= "  pass\n"
  for o in ooBanksPython:
    code &= genPInterface(o)
  code &= "\nporche = Porche()\n"
  writeFile(output, code)
  result = newEmptyNode()

  var free = "proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))\n"
  free &= "proc ocheAllocBytes(n: csize_t): pointer {.exportc, dynlib.} = alloc0(n)\n"

  for s in structBanks.values:
    free &= "proc ocheFreeInner" & s.name & "(o: ptr " & s.name & ") = \n"
    for f in s.fields:
      if f.typ.name in ["string", "cstring"]:
        free &= "  if not o." & f.name & ".isNil: dealloc(cast[pointer](o." & f.name & "))\n"
      elif structBanks.hasKey(f.typ.name) and not structBanks[f.typ.name].isPOD:
        free &= "  ocheFreeInner" & f.typ.name & "(addr o." & f.name & ")\n"
    if s.fields.allIt(it.typ.name notin ["string", "cstring"] and (not structBanks.hasKey(it.typ.name) or structBanks[it.typ.name].isPOD)): free &= "  discard\n"

  free &= "proc ocheFreeInner(p: pointer, typeId: int32) {.exportc, dynlib.} = \n"
  for s in structBanks.values:
    free &= "  if typeId == " & $s.typeId & ": ocheFreeInner" & s.name & "(cast[ptr " & s.name & "](p)); return\n"
  free &= "  discard\n\n"

  free &= "proc ocheFreeDeep(p: pointer) {.exportc, dynlib.} = \n"
  free &= "  if p.isNil: return\n"
  free &= "  let flags = cast[ptr int32](cast[uint](p) + 12)[]\n"
  free &= "  if (flags and int32(2)) != 0: dealloc(p); return\n"
  free &= "  let L = cast[ptr int64](p)[]\n"
  free &= "  let typeId = cast[ptr int32](cast[uint](p) + 8)[]\n"
  for s in structBanks.values:
    if not s.isPOD:
      free &= "  if typeId == int32(" & $s.typeId & "):\n"
      free &= "    let dataPtr = cast[uint](p) + 16\n"
      free &= "    for i in 0 ..< L:\n"
      free &= "      let o = cast[ptr " & s.name & "](dataPtr + uint(i * sizeof(" & s.name & ")))\n"
      free &= "      ocheFreeInner" & s.name & "(o)\n"
      free &= "    dealloc(p); return\n"
  free &= "  dealloc(p)\n"

  result = parseStmt(free)