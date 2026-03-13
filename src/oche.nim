## Oche: Nim FFI codegen for Dart and Python. Core in oche_core, emitters in oche_dart and oche_python.
## Usage:
##   {.oche.}        — export proc/type to all targets
##   {.oche: view.}  — export proc to all targets, view mode (seq return is zero-copy)
##   generate()      — emit all binding files, names derived from callsite filename
##   generate(dart="path/api.dart", python="path/api.py")  — custom paths / select targets
import std/[macros, os, strutils, tables, sequtils, hashes, algorithm]
import oche_core
import oche_dart
import oche_python

## Build a short ABI fingerprint from all exported struct layouts and proc signatures.
## ooBanks is the single source of truth now — both targets share the same bank.
proc buildAbiHash(): string {.compileTime.} =
  var parts: seq[string] = @[]
  for name, s in structBanks:
    var line = "S:" & name
    for f in s.fields: line &= "," & f.name & ":" & f.typ.name
    parts.add line
  for o in ooBanks:
    var line = "F:" & o.name & "(" & o.params.mapIt(it.typ.name).join(",") & "):" & o.retType.name
    parts.add line
  let combined = parts.sorted.join("|")
  var h: uint32 = 5381
  for c in combined: h = h * 33 xor uint32(c.ord)
  result = h.toHex(8).toLowerAscii

var lastOcheError {.threadvar.}: string

proc toOcheStr*(s: string): cstring =
  if s.len == 0: return nil
  result = cast[cstring](alloc0(s.len + 1))
  copyMem(result, s.cstring, s.len + 1)

type
  OcheBuffer*[T] = object
    p*: pointer

## Zero-copy read-only view into a caller-owned contiguous buffer.
## Used for input parameters — Nim never copies, never frees.
type
  OcheArray*[T] = object
    p*: ptr UncheckedArray[T]
    len*: int

## True zero-copy raw pointer input — caller allocates with malloc/calloc and
## manages lifetime entirely. No length metadata on wire — caller passes len separately.
## In Dart: pass ffi.Pointer<T> directly (outside VM heap, GC-safe).
## In Python: pass numpy array or ctypes pointer (same zero-copy path as OcheArray).
type
  OchePtr*[T] = object
    p*:   ptr UncheckedArray[T]
    len*: int

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

## OcheArray helpers — zero-copy view, never frees
proc `[]`*[T](a: OcheArray[T], idx: int): T =
  a.p[idx]

proc `[]=`*[T](a: OcheArray[T], idx: int, val: T) =
  a.p[idx] = val

iterator items*[T](a: OcheArray[T]): T =
  for i in 0 ..< a.len: yield a.p[i]

iterator pairs*[T](a: OcheArray[T]): (int, T) =
  for i in 0 ..< a.len: yield (i, a.p[i])

proc toSeq*[T](a: OcheArray[T]): seq[T] =
  result = newSeq[T](a.len)
  if a.len > 0: copyMem(addr result[0], a.p, a.len * sizeof(T))

## OchePtr helpers — same API as OcheArray, distinct type for emitter routing
proc `[]`*[T](a: OchePtr[T], idx: int): T =
  a.p[idx]

proc `[]=`*[T](a: OchePtr[T], idx: int, val: T) =
  a.p[idx] = val

iterator items*[T](a: OchePtr[T]): T =
  for i in 0 ..< a.len: yield a.p[i]

iterator pairs*[T](a: OchePtr[T]): (int, T) =
  for i in 0 ..< a.len: yield (i, a.p[i])

proc toSeq*[T](a: OchePtr[T]): seq[T] =
  result = newSeq[T](a.len)
  if a.len > 0: copyMem(addr result[0], a.p, a.len * sizeof(T))

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

proc processOche(body: NimNode, isView: bool): NimNode {.compileTime.} =
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

  # Always register in both banks — targets are decided at generate() time, not here
  let obj = parseOche(body, isView)
  ooBanks.add(obj)
  ooBanksPython.add(obj)
  let procName = body[0]; let originalBody = body[6]; var originalRetType = body[3][0]
  if originalRetType.kind == nnkEmpty: originalRetType = ident"void"

  var ffiParams = newTree(nnkFormalParams)
  let retByPointer = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"] or obj.retType.isShared or structBanks.hasKey(obj.retType.name)
  if retByPointer: ffiParams.add ident("pointer") else: ffiParams.add originalRetType

  # reconstruction: build local vars for non-seq params
  # seq params are passed inline via toOpenArray() in the call — no local needed
  var reconstruction = newStmtList()
  var internalCallArgs: seq[NimNode]
  for p in obj.params:
    if p.typ.isSeq:
      let pP = ident(p.name & "_ptr"); let pL = ident(p.name & "_len"); let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pP, newTree(nnkPtrTy, iT)); ffiParams.add newIdentDefs(pL, ident("int"))
      # Pass toOpenArray() directly as call arg — openArray cannot be a local variable
      internalCallArgs.add newTree(nnkCall, ident("toOpenArray"),
        newTree(nnkCast,
          newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)),
          pP),
        newLit(0),
        newTree(nnkInfix, ident("-"), pL, newLit(1)))
    elif p.typ.isArray:
      let pP = ident(p.name & "_ptr"); let pL = ident(p.name & "_len"); let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pP, newTree(nnkPtrTy, iT)); ffiParams.add newIdentDefs(pL, ident("int"))
      internalCallArgs.add newTree(nnkObjConstr,
        newTree(nnkBracketExpr, ident("OcheArray"), iT),
        newColonExpr(ident("p"),
          newTree(nnkCast,
            newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)),
            pP)),
        newColonExpr(ident("len"), pL))
    elif p.typ.isPtr:
      # OchePtr[T] — same wire format as OcheArray (ptr + len), different emitter routing
      let pP = ident(p.name & "_ptr"); let pL = ident(p.name & "_len"); let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pP, newTree(nnkPtrTy, iT)); ffiParams.add newIdentDefs(pL, ident("int"))
      internalCallArgs.add newTree(nnkObjConstr,
        newTree(nnkBracketExpr, ident("OchePtr"), iT),
        newColonExpr(ident("p"),
          newTree(nnkCast,
            newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)),
            pP)),
        newColonExpr(ident("len"), pL))
    elif p.typ.isShared:
      # OcheBuffer[T] as input — wire: single pointer (the buffer header pointer)
      # Nim side reconstructs OcheBuffer[T] from the raw pointer
      let iT = ident(p.typ.inner)
      let pRaw = ident(p.name & "_raw")
      ffiParams.add newIdentDefs(pRaw, ident("pointer"))
      reconstruction.add newLetStmt(ident(p.name),
        newTree(nnkObjConstr,
          newTree(nnkBracketExpr, ident("OcheBuffer"), iT),
          newColonExpr(ident("p"), pRaw)))
      internalCallArgs.add ident(p.name)
    elif p.typ.name in ["string", "cstring"]:
      ffiParams.add newIdentDefs(ident(p.name & "_raw"), ident("cstring"))
      reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("$"), ident(p.name & "_raw")))
      internalCallArgs.add ident(p.name)
    elif enumBanks.hasKey(p.typ.name):
      ffiParams.add newIdentDefs(ident(p.name), ident("int32"))
      # int32 on wire → must cast back to enum type for internal proc
      internalCallArgs.add newTree(nnkCall, ident(p.typ.name), ident(p.name))
    else:
      if structBanks.hasKey(p.typ.name):
        let pPtr = ident(p.name & "_ptr")
        ffiParams.add newIdentDefs(pPtr, newTree(nnkPtrTy, ident(p.typ.name)))
        reconstruction.add newLetStmt(ident(p.name), newTree(nnkDerefExpr, pPtr))
      else:
        ffiParams.add newIdentDefs(ident(p.name), ident(p.typ.name))
      internalCallArgs.add ident(p.name)

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

  # Build internalProc's formal params — seq[T] params become openArray[T]
  # so toOpenArray() result can be passed without heap allocation.
  var internalFormalParams = newTree(nnkFormalParams)
  if isVoid: internalFormalParams.add newEmptyNode()
  else:      internalFormalParams.add originalRetType
  for p in obj.params:
    if p.typ.isSeq:
      let iT = ident(p.typ.inner)
      internalFormalParams.add newIdentDefs(ident(p.name),
        newTree(nnkBracketExpr, ident("openArray"), iT))
    elif p.typ.isArray:
      let iT = ident(p.typ.inner)
      internalFormalParams.add newIdentDefs(ident(p.name),
        newTree(nnkBracketExpr, ident("OcheArray"), iT))
    elif p.typ.isPtr:
      let iT = ident(p.typ.inner)
      internalFormalParams.add newIdentDefs(ident(p.name),
        newTree(nnkBracketExpr, ident("OchePtr"), iT))
    elif p.typ.isShared:
      let iT = ident(p.typ.inner)
      internalFormalParams.add newIdentDefs(ident(p.name),
        newTree(nnkBracketExpr, ident("OcheBuffer"), iT))
    elif p.typ.name in ["string", "cstring"]:
      internalFormalParams.add newIdentDefs(ident(p.name), ident("string"))
    elif enumBanks.hasKey(p.typ.name):
      internalFormalParams.add newIdentDefs(ident(p.name), ident(p.typ.name))
    elif structBanks.hasKey(p.typ.name):
      internalFormalParams.add newIdentDefs(ident(p.name), ident(p.typ.name))
    else:
      internalFormalParams.add newIdentDefs(ident(p.name), ident(p.typ.name))

  # Build call args for internalProc() — pass reconstructed locals
  let internalCall = newCall(internalProc, internalCallArgs)

  var wrappedBody: NimNode
  if isVoid:
    let internalProcDef = newTree(nnkProcDef, internalProc, newEmptyNode(), newEmptyNode(),
      internalFormalParams, newEmptyNode(), newEmptyNode(), originalBody)
    wrappedBody = quote do:
      `reconstruction`
      `internalProcDef`
      try: `internalCall`
      except Exception as e: lastOcheError = e.msg
  else:
    let internalProcDef = newTree(nnkProcDef, internalProc, newEmptyNode(), newEmptyNode(),
      internalFormalParams, newEmptyNode(), newEmptyNode(), originalBody)
    wrappedBody = quote do:
      `reconstruction`
      `internalProcDef`
      try:
        let `resNode` = `internalCall`
        result = `conv`
      except Exception as e:
        lastOcheError = e.msg
        result = default(type(result))

  result = newTree(nnkProcDef, procName, newEmptyNode(), newEmptyNode(), ffiParams, newTree(nnkPragma, ident("exportc"), ident("dynlib")), newEmptyNode(), wrappedBody)

## {.oche.} — export proc or type to all targets (Dart + Python)
## {.oche: view.} — export seq-returning proc as zero-copy view (no allocation, Nim owns data)
##
## Types ({.oche.} on object/enum): register struct/enum layout for all emitters.
## Procs ({.oche.} or {.oche: view.}): wrap proc with FFI ABI and register in both banks.
## Target languages and output paths are decided at generate() time, not here.

macro oche*(body: untyped): untyped =
  ## {.oche.} — plain export, copy mode for seq returns
  processOche(body, false)

macro oche*(arg: untyped, body: untyped): untyped =
  ## {.oche: view.} — view mode: seq return is a zero-copy pointer into Nim memory
  var isView = false
  if arg.kind == nnkIdent and arg.strVal == "view": isView = true
  processOche(body, isView)


proc ocheInjectHelpers(): string {.compileTime.} =
  ## Generate the Nim-side helper procs that get injected into the compiled .so.
  ## Called once by generate(); the result is parsed at compile time so the procs
  ## are available in the final binary.
  var free = "proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))\n"
  free &= "proc ocheAllocBytes(n: csize_t): pointer {.exportc, dynlib.} = alloc0(n)\n"
  free &= "proc ocheStrAlloc(s: cstring): pointer {.exportc, dynlib.} =\n"
  free &= "  if s.isNil: return nil\n"
  free &= "  let n = s.len\n"
  free &= "  result = alloc0(n + 1)\n"
  free &= "  copyMem(result, s, n + 1)\n"
  free &= "proc ocheStrFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))\n"
  let abiHash = buildAbiHash()
  free &= "proc ocheAbiHash(): cstring {.exportc, dynlib.} = \"" & abiHash & "\"\n"

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
  result = free

## generate() — emit Dart and/or Python bindings.
##
## Call at the bottom of your .nim file after all {.oche.} annotations.
##
##   generate()
##     → emits <callsite>.dart and <callsite>.py  (both targets, auto-named)
##
##   generate(dart="path/api.dart")
##     → emits Dart only, custom path
##
##   generate(python="path/api.py")
##     → emits Python only, custom path
##
##   generate(dart="a.dart", python="b.py")
##     → emits both, custom paths
##
## If dart= or python= is omitted the filename is derived from the callsite source file.
## Passing an empty string "" explicitly disables that target.

macro generate*(dart: static string = "\x00", python: static string = "\x00"): untyped =
  ## Emit Dart and/or Python FFI bindings.
  ##
  ##   generate()                         → both targets, names from callsite filename
  ##   generate(dart="api.dart")          → Dart only
  ##   generate(python="api.py")          → Python only
  ##   generate(dart="a.dart", python="b.py") → both, custom names
  let
    info        = lineInfoObj(callsite())
    stem        = info.filename.splitFile.name   # e.g. "olib"
    libname     = "lib" & stem                   # e.g. "libolib"
    # "\x00" means "omitted by caller"
    dartOmitted   = dart   == "\x00"
    pythonOmitted = python == "\x00"
    # Both omitted → generate both auto-named.
    # Only one given → generate only that target.
    # Both given → generate both with given names.
    dartOut   = if dartOmitted and pythonOmitted: stem & ".dart"  # both omitted
                elif dartOmitted:                 ""               # python-only call
                elif dart == "":                  stem & ".dart"   # dart="" → auto-name
                else:                             dart             # explicit path
    pythonOut = if dartOmitted and pythonOmitted: stem & ".py"    # both omitted
                elif pythonOmitted:               ""               # dart-only call
                elif python == "":                stem & ".py"     # python="" → auto-name
                else:                             python           # explicit path
    abiHash     = buildAbiHash()

  result = newStmtList()

  # ── Dart ─────────────────────────────────────────────────────────────────
  if dartOut != "":
    var code = "//------------------ Generated by Oche ------------------\n"
    code &= "//              Don't edit this file by hand!\n"
    code &= "// ------------------------------------------------------\n"
    code &= "// ABI hash: " & abiHash & "\n"
    code &= "import 'dart:ffi' as ffi;\nimport 'dart:io' show Platform;\nimport 'dart:collection';\nimport 'dart:typed_data' as typed_data;\nimport 'dart:typed_data';\nimport 'package:ffi/ffi.dart';\n\n"
    code &= "final String _libName = Platform.isWindows ? '" & libname & ".dll' : (Platform.isMacOS ? '" & libname & ".dylib' : '" & libname & ".so');\n"
    code &= "final dynlib = ffi.DynamicLibrary.open('./$_libName');\n"
    code &= "final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\n"
    code &= "final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');\n"
    code &= "final _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');\n"
    code &= "final _ocheStrAlloc = dynlib.lookupFunction<ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>), ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)>('ocheStrAlloc');\n"
    code &= "final _ocheStrFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>), void Function(ffi.Pointer<ffi.Void>)>('ocheStrFree');\n"
    code &= "final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');\n"
    code &= "void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }\n"
    code &= "const _ocheExpectedAbiHash = '" & abiHash & "';\n"
    code &= "String _ocheLibAbiHash() {\n"
    code &= "  try {\n"
    code &= "    final fn = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheAbiHash');\n"
    code &= "    return fn().toDartString();\n"
    code &= "  } catch (_) { return ''; }\n"
    code &= "}\n"
    code &= "void _ocheCheckAbi() {\n"
    code &= "  final libHash = _ocheLibAbiHash();\n"
    code &= "  if (libHash.isNotEmpty && libHash != _ocheExpectedAbiHash) {\n"
    code &= "    throw StateError('Oche ABI mismatch: .so was compiled with hash \\$libHash but bindings expect " & abiHash & ". Recompile Nim and regenerate bindings.');\n"
    code &= "  }\n"
    code &= "}\n"
    code &= "final _abiChecked = () { _ocheCheckAbi(); return true; }();\n\n"

    var inner = ""
    var extensions = ""
    for o in ooBanks:
      let raw = genDInterface(o)
      # Split on sentinel — part before sentinel goes inside class Oche,
      # part after goes outside (top-level Dart extension declarations).
      let parts = raw.split("\n##OCHE_EXT##\n")
      inner &= parts[0]
      if parts.len > 1: extensions &= parts[1]

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
            "    if (_ptr.address == 0) throw StateError('NativeListView has been freed');\n" &
            "    if (index < 0 || index >= length) throw RangeError.index(index, this);\n" &
            "    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize)));\n" &
            "  }\n" &
            "  @override void operator []=(int index, T value) => throw UnsupportedError('View mode is read-only. Use Buffer mode for mutation.');\n" &
            "  void free() {\n" &
            "    if (_ptr.address == 0) return;\n" &
            "    _finalizerDeep.detach(this);\n" &
            "    _ocheFreeDeep(_ptr);\n" &
            "    _ptr = ffi.Pointer.fromAddress(0);\n" &
            "  }\n" &
            "}\n\n" &
            "class SharedListView<T> extends OcheView<T> {\n" &
            "  ffi.Pointer<ffi.Void> _ptr;\n" &
            "  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;\n" &
            "  final void Function(ffi.Pointer<ffi.Void> ptr, dynamic value)? _packer;\n" &
            "  final int _elemSize;\n" &
            "  @override late final int length;\n" &
            "  SharedListView(this._ptr, this._unpacker, this._packer, this._elemSize) {\n" &
            "    if (_ptr.address == 0) { length = 0; return; }\n" &
            "    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;\n" &
            "    _finalizerDeep.attach(this, _ptr, detach: this);\n" &
            "  }\n" &
            "  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;\n" &
            "  @override T operator [](int index) {\n" &
            "    if (_ptr.address == 0) throw StateError('SharedListView has been freed');\n" &
            "    if (index < 0 || index >= length) throw RangeError.index(index, this);\n" &
            "    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize)));\n" &
            "  }\n" &
            "  @override void operator []=(int index, dynamic value) {\n" &
            "    if (_ptr.address == 0) throw StateError('SharedListView has been freed');\n" &
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
            "  typed_data.TypedData? toTypedData() {\n" &
            "    if (_ptr.address == 0) return null;\n" &
            "    final dataAddr = _ptr.address + 16;\n" &
            "    if (_elemSize == 8) return ffi.Pointer<ffi.Int64>.fromAddress(dataAddr).asTypedList(length);\n" &
            "    if (_elemSize == 4) return ffi.Pointer<ffi.Int32>.fromAddress(dataAddr).asTypedList(length);\n" &
            "    if (_elemSize == 2) return ffi.Pointer<ffi.Int16>.fromAddress(dataAddr).asTypedList(length);\n" &
            "    if (_elemSize == 1) return ffi.Pointer<ffi.Uint8>.fromAddress(dataAddr).asTypedList(length);\n" &
            "    return null;\n" &
            "  }\n" &
            "  void free() {\n" &
            "    if (_ptr.address == 0) return;\n" &
            "    _finalizerDeep.detach(this);\n" &
            "    _ocheFreeDeep(_ptr);\n" &
            "    _ptr = ffi.Pointer.fromAddress(0);\n" &
            "  }\n" &
            "}\n\n" &
            "class _NativeListIterator<T> implements Iterator<T> {\n" &
            "  final OcheView<T> _view; int _index = -1;\n" &
            "  _NativeListIterator(this._view);\n" &
            "  @override T get current => _view[_index];\n" &
            "  @override bool moveNext() => ++_index < _view.length;\n" &
            "}\n"

    code &= "class Oche {\n" & inner & "\n}\nfinal oche = Oche();\n"
    if extensions.len > 0: code &= "\n" & extensions
    writeFile(dartOut, code)

  # ── Python ───────────────────────────────────────────────────────────────
  if pythonOut != "":
    var code = "# ------------------ Generated by Oche ------------------\n"
    code &= "#              Don't edit this file by hand!\n"
    code &= "# -------------------------------------------------------\n"
    code &= "# ABI hash: " & abiHash & "\n"
    code &= "from typing import Optional, Any, List, Union\n"
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
    code &= "_lib.ocheStrAlloc.argtypes = [ctypes.c_char_p]\n"
    code &= "_lib.ocheStrAlloc.restype = ctypes.c_void_p\n"
    code &= "_lib.ocheStrFree.argtypes = [ctypes.c_void_p]\n"
    code &= "_lib.ocheStrFree.restype = None\n"
    code &= "_oche_get_error = _lib.ocheGetError\n"
    code &= "_oche_get_error.restype = ctypes.c_void_p\n"
    code &= "def _check_error():\n"
    code &= "    p = _oche_get_error()\n"
    code &= "    if p is not None:\n"
    code &= "        msg = ctypes.string_at(p).decode('utf-8')\n"
    code &= "        _lib.ocheFree(p)\n"
    code &= "        raise RuntimeError('NimError: ' + msg)\n\n"
    code &= "_OCHE_EXPECTED_ABI_HASH = '" & abiHash & "'\n"
    code &= "try:\n"
    code &= "    _abi_fn = _lib.ocheAbiHash\n"
    code &= "    _abi_fn.restype = ctypes.c_char_p\n"
    code &= "    _lib_hash = _abi_fn().decode('utf-8')\n"
    code &= "    if _lib_hash and _lib_hash != _OCHE_EXPECTED_ABI_HASH:\n"
    code &= "        raise RuntimeError(\n"
    code &= "            f'Oche ABI mismatch: .so was compiled with hash {_lib_hash!r} '\n"
    code &= "            f'but bindings expect {_OCHE_EXPECTED_ABI_HASH!r}. '\n"
    code &= "            'Recompile Nim and regenerate bindings.')\n"
    code &= "except AttributeError:\n"
    code &= "    pass  # older .so without ocheAbiHash — skip check\n\n"
    for s in structBanks.values: code &= genPStruct(s)
    for e in enumBanks.values: code &= genPEnum(e)
    code &= "class Oche:\n"
    if ooBanksPython.len == 0:
      code &= "  pass\n"
    for o in ooBanksPython:
      code &= genPInterface(o)
    code &= "\noche = Oche()\n"
    writeFile(pythonOut, code)

    # Emit compile-time warnings for procs that used {.oche: view.} on a
    # single-struct return — silently downgraded to copy mode.
    for o in ooBanksPython:
      if o.isView and structBanks.hasKey(o.retType.name):
        let msg = "[Oche] '" & o.name &
                  "' returns single struct with {.oche: view.} — " &
                  "view mode is unsafe for stack-allocated returns. " &
                  "Downgraded to copy mode automatically."
        result.add parseStmt("{.warning: \"" & msg & "\".}")

  # ── Inject helper procs into the compiled .so ─────────────────────────────
  # Indent every line of helpers so they sit inside the `when` block correctly
  let helpers = ocheInjectHelpers()
  let indented = helpers.strip().splitLines().mapIt("  " & it).join("\n")
  let wrapper = "when not declared(ocheFree):\n" & indented
  result.add parseStmt(wrapper)