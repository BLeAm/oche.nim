import std/[
  macros,
  os,
  strutils,
  tables,
  sequtils
]

type
  OcheType = object
    name:  string
    isSeq: bool
    isOption: bool
    inner: string
  OcheField = object
    name: string
    typ:  OcheType
  OcheStruct = object
    name:   string
    fields: seq[OcheField]
  OcheEnum = object
    name:   string
    values: seq[string]
  OcheParam = object
    name: string
    typ:  OcheType
  OcheObject = object
    name:    string
    retType: OcheType
    params:  seq[OcheParam]
    isView:  bool

var ooBanks {.compileTime.}: seq[OcheObject] = @[]
var structBanks {.compileTime.}: Table[string, OcheStruct]
var enumBanks {.compileTime.}: Table[string, OcheEnum]
var typeDefBanks {.compileTime.}: seq[string] = @[]

var lastOcheError {.threadvar.}: string

proc ocheGetError(): cstring {.exportc, dynlib.} =
  if lastOcheError == "": return nil
  let L = lastOcheError.len
  result = cast[cstring](alloc0(L + 1))
  copyMem(result, lastOcheError.cstring, L + 1)
  lastOcheError = ""

proc parseType(node: NimNode): OcheType =
  case node.kind
  of nnkIdent:
    return OcheType(name: node.strVal, isSeq: false)
  of nnkBracketExpr:
    let base = node[0].strVal
    if base == "seq":
      return OcheType(name: node.repr, isSeq: true, inner: node[1].repr)
    elif base == "Option":
      return OcheType(name: node.repr, isOption: true, inner: node[1].repr)
    return OcheType(name: node.repr)
  else:
    return OcheType(name: node.repr)

proc parseOche(body: NimNode, isView: bool): OcheObject =
  var o: OcheObject
  if body.kind == nnkProcDef:
    o.name    = body[0].strVal
    o.isView  = isView
    o.retType = parseType(body[3][0])
    for i in 1 ..< body[3].len:
      let node = body[3][i]
      if node.kind != nnkIdentDefs: continue
      let t = parseType(node[^2])
      for n in node[0 ..< node.len - 2]:
        o.params.add OcheParam(name: n.strVal, typ: t)
  o

proc toNativeType(t: string): string =
  case t
  of "int", "int64": return "ffi.Int64"
  of "float", "float64": return "ffi.Double"
  of "bool": return "ffi.Bool"
  of "cstring", "string": return "ffi.Pointer<Utf8>"
  else:
    if enumBanks.hasKey(t): return "ffi.Int32"
    elif structBanks.hasKey(t): return "N" & t
    else: return "ffi.Void"

proc toDartType(t: string): string =
  if t.startsWith("seq["): return "List<" & toDartType(t[4..^2]) & ">"
  if t.startsWith("Option["): return toDartType(t[7..^2]) & "?"
  case t
  of "int", "int64": return "int"
  of "float", "float64": return "double"
  of "bool": return "bool"
  of "cstring", "string": return "String"
  else: return t

proc genDEnum(e: OcheEnum): string =
  var lines: seq[string] = @[]
  for v in e.values: lines.add "  " & v & ","
  result = "\nenum " & e.name & " {\n" & lines.join("\n") & "\n}\n"

proc genDStruct(s: OcheStruct): string =
  var dartFields, toFfi, fromFfi, ffiFields: seq[string]
  for f in s.fields:
    let nT = toNativeType(f.typ.name)
    let dT = toDartType(f.typ.name)
    if structBanks.hasKey(f.typ.name):
      ffiFields.add "  external N" & f.typ.name & " " & f.name & ";"
      toFfi.add "    this." & f.name & "._pack(target." & f.name & ", a);"
      fromFfi.add "    " & f.name & ": " & f.typ.name & "._unpack(source." & f.name & "),"
    elif f.typ.name in ["string", "cstring"]:
      ffiFields.add "  external ffi.Pointer<Utf8> " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ".toNativeUtf8(allocator: a);"
      fromFfi.add "    " & f.name & ": (source." & f.name & ".address == 0) ? '' : source." & f.name & ".toDartString(),"
    elif enumBanks.hasKey(f.typ.name):
      ffiFields.add " @ffi.Int32() external int " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ".index;"
      fromFfi.add "    " & f.name & ": " & f.typ.name & ".values[source." & f.name & "],"
    else:
      ffiFields.add "  @" & nT & "() external " & dT & " " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ";"
      fromFfi.add "    " & f.name & ": source." & f.name & ","
    dartFields.add "  final " & dT & " " & f.name & ";"

  let ffiStruct = "final class N" & s.name & " extends ffi.Struct {\n" & ffiFields.join("\n") & "\n}\n"
  var extType = "\nextension type " & s.name & "View(ffi.Pointer<N" & s.name & "> _ptr) {\n"
  for f in s.fields:
    let dT = toDartType(f.typ.name)
    if f.typ.name in ["string", "cstring"]:
      extType &= "  " & dT & " get " & f.name & " => (_ptr.ref." & f.name & ".address == 0) ? '' : _ptr.ref." & f.name & ".toDartString();\n"
    elif enumBanks.hasKey(f.typ.name):
      extType &= "  " & dT & " get " & f.name & " => " & f.typ.name & ".values[_ptr.ref." & f.name & "];\n"
    elif structBanks.hasKey(f.typ.name):
      extType &= "  " & f.typ.name & "View get " & f.name & " => " & f.typ.name & "View(_ptr.ref." & f.name & ".address as ffi.Pointer<N" & f.typ.name & ">);\n"
    else:
      extType &= "  " & dT & " get " & f.name & " => _ptr.ref." & f.name & ";\n"
  extType &= "}\n"
  let dartClass = "class " & s.name & " {\n" & dartFields.join("\n") & "\n" &
                  "  const " & s.name & "({\n" & s.fields.mapIT("    required this." & it.name).join(",\n") & "\n  });\n\n" &
                  "  void _pack(N" & s.name & " target, ffi.Allocator a) {\n" & toFfi.join("\n") & "\n  }\n\n" &
                  "  static " & s.name & " _unpack(N" & s.name & " source) {\n" &
                  "    return " & s.name & "(\n" & fromFfi.join("\n") & "\n    );\n  }\n" &
                  "}\n"
  result = ffiStruct & extType & "\n" & dartClass

proc genDInterface(obj: OcheObject): string =
  let callName = "n" & obj.name & "Call"
  var nativeParams, dartFfiParams, wrapperParams, callArgs, prepWork: seq[string]
  for p in obj.params:
    let dT = toDartType(p.typ.name)
    let pN = "v_" & p.name
    wrapperParams.add "final " & dT & " " & pN
    if p.typ.isSeq:
      let iI = p.typ.inner; let isC = structBanks.hasKey(iI)
      let nT = if isC: "N" & iI else: toNativeType(iI)
      let sz = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      prepWork.add "    final _" & pN & "Ptr = a.allocate<" & nT & ">(" & pN & ".length * " & sz & ");"
      if isC: prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { " & pN & "[i]._pack(_" & pN & "Ptr[i], a); }"
      elif enumBanks.hasKey(iI): prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i].index; }"
      else: prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i]; }"
      callArgs.add "_" & pN & "Ptr, " & pN & ".length"
    elif structBanks.hasKey(p.typ.name):
      nativeParams.add "ffi.Pointer<N" & p.typ.name & ">"
      dartFfiParams.add "ffi.Pointer<N" & p.typ.name & ">"
      prepWork.add "    final _" & pN & "Ptr = a.allocate<N" & p.typ.name & ">(ffi.sizeOf<N" & p.typ.name & ">());"
      prepWork.add "    " & pN & "._pack(_" & pN & "Ptr.ref, a);"
      callArgs.add "_" & pN & "Ptr"
    else:
      let nT = toNativeType(p.typ.name)
      nativeParams.add nT
      dartFfiParams.add (if nT.contains("Int") or nT.contains("Double") or nT.contains("Bool"): toDartType(p.typ.name) else: nT)
      if p.typ.name in ["string", "cstring"]: callArgs.add pN & ".toNativeUtf8(allocator: a)"
      elif enumBanks.hasKey(p.typ.name): callArgs.add pN & ".index"
      else: callArgs.add pN

  var actualRetType = toDartType(obj.retType.name)
  if obj.isView:
    if obj.retType.isSeq: 
      let innerV = if structBanks.hasKey(obj.retType.inner): obj.retType.inner & "View" else: toDartType(obj.retType.inner)
      actualRetType = "NativeListView<" & innerV & ">"
    elif structBanks.hasKey(obj.retType.name): actualRetType = obj.retType.name & "View"

  let sR = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"]
  let nR = if sR: "ffi.Pointer<ffi.Void>" else: toNativeType(obj.retType.name)
  let dT_ret = toDartType(obj.retType.name)
  let dR = if sR: "ffi.Pointer<ffi.Void>" else: (if nR.contains("Int") or nR.contains("Double") or nR.contains("Bool"): dT_ret else: nR)
  
  var body: string
  if obj.retType.isSeq:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI); let nT = if isC: "N" & iI else: toNativeType(iI)
    if obj.isView:
      let sz = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      return NativeListView<" & (if isC: iI & "View" else: toDartType(iI)) & ">(p, '" & (if isC: iI else: obj.retType.name) & "', (ptr) => " & (if isC: iI & "View(ptr.cast<N" & iI & ">())" else: "ptr.cast<" & nT & ">().value") & ", " & sz & ");"
    else:
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      if (p.address == 0) return []; try {\n" &
             "        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<" & nT & ">.fromAddress(p.address + ffi.sizeOf<ffi.Int64>());\n" &
             (if isC: "        return List<" & iI & ">.generate(L, (i) => " & iI & "._unpack(d[i]));" else: "        return d.asTypedList(L).toList();") & "\n" &
             "      } finally { using((Arena a) => _ocheFreeDeep(p, '" & obj.retType.name & "'.toNativeUtf8(allocator: a))); }"
  elif obj.retType.isOption:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI); let nTI = if isC: "N" & iI else: toNativeType(iI)
    if obj.isView:
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      return " & (if isC: iI & "View(p.cast<N" & iI & ">());" else: "p.cast<" & nTI & ">().value;")
    else:
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      if (p.address == 0) return null; try {\n" &
             (if isC: "        return " & iI & "._unpack(p.cast<" & nTI & ">().ref);" else: "        return p.cast<" & nTI & ">().value;") & "\n" &
             "      } finally { using((Arena a) => _ocheFreeDeep(p, '" & obj.retType.name & "'.toNativeUtf8(allocator: a))); }"
  elif obj.retType.name in ["string", "cstring"]:
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }"
  else:
    body = "      final r = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      return " & (if enumBanks.hasKey(obj.retType.name): dT_ret & ".values[r];" else: "r;")

  typeDefBanks.add "typedef N" & obj.name & "N = " & nR & " Function(" & nativeParams.join(", ") & ");"
  typeDefBanks.add "typedef N" & obj.name & "D = " & dR & " Function(" & dartFfiParams.join(", ") & ");"

  result = "  late final " & callName & " = dynlib.lookupFunction<N" & obj.name & "N, N" & obj.name & "D>('" & obj.name & "');\n\n" &
           "  " & actualRetType & " " & obj.name & "(" & wrapperParams.join(", ") & ") {\n" &
           "    return using((a) {\n" & prepWork.join("\n") & "\n" & body & "\n    });\n  }\n"

proc processOche(body: NimNode, isView: bool): NimNode {.compileTime.} =
  if body.kind == nnkProcDef:
    echo "DEBUG: processOche for Proc ", body[0].repr, " view=", isView
  elif body.kind == nnkTypeDef:
    echo "DEBUG: processOche for Type ", body[0].repr
  else:
    echo "DEBUG: processOche for ", body.kind

  if body.kind == nnkTypeDef:
    var nameNode = body[0]; (if nameNode.kind == nnkPragmaExpr: nameNode = nameNode[0])
    let name = nameNode.strVal; let tyNode = body[2]
    if tyNode.kind == nnkEnumTy:
      var v: seq[string] = @[]; (for i in 1..<tyNode.len: (if tyNode[i].kind == nnkIdent: v.add tyNode[i].strVal elif tyNode[i].kind == nnkEnumFieldDef: v.add tyNode[i][0].strVal))
      enumBanks[name] = OcheEnum(name: name, values: v)
      let prag = newTree(nnkPragma, newColonExpr(ident("size"), newLit(4)))
      return newTree(nnkTypeDef, newTree(nnkPragmaExpr, nameNode, prag), newEmptyNode(), tyNode)
    else:
      var f: seq[OcheField] = @[]; let rec = tyNode[2]
      for field in rec: (if field.kind == nnkIdentDefs: (let t = parseType(field[^2]); (for i in 0..<field.len-2: (var fn = field[i]; (if fn.kind == nnkPostfix: fn = fn[1]); f.add OcheField(name: fn.strVal, typ: t)))))
      structBanks[name] = OcheStruct(name: name, fields: f); return body

  let obj = parseOche(body, isView); ooBanks.add(obj)
  let procName = body[0]; let originalBody = body[6]; let originalRetType = body[3][0]; var ffiParams = newTree(nnkFormalParams)
  if obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"]: ffiParams.add ident("pointer") else: ffiParams.add originalRetType
  var reconstruction = newStmtList()
  for p in obj.params:
    if p.typ.isSeq:
      let pP = ident(p.name & "_ptr"); let pL = ident(p.name & "_len"); let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pP, newTree(nnkPtrTy, iT)); ffiParams.add newIdentDefs(pL, ident("int"))
      reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("@"), newTree(nnkCall, ident("toOpenArray"), newTree(nnkCast, newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)), pP), newLit(0), newTree(nnkInfix, ident("-"), pL, newLit(1)))))
    elif p.typ.name in ["string", "cstring"]:
      ffiParams.add newIdentDefs(ident(p.name & "_raw"), ident("cstring")); reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("$"), ident(p.name & "_raw")))
    elif enumBanks.hasKey(p.typ.name): ffiParams.add newIdentDefs(ident(p.name), ident("int32"))
    else: ffiParams.add newIdentDefs(ident(p.name), ident(p.typ.name))
  
  let resNode = ident"res"
  var conv: NimNode
  if obj.retType.isSeq:
    let iT = ident(obj.retType.inner)
    conv = quote do:
      let L = `resNode`.len
      let p = cast[ptr byte](alloc0(sizeof(int) + (L * sizeof(`iT`))))
      cast[ptr int](p)[] = L
      if L > 0: copyMem(cast[pointer](cast[uint](p) + uint(sizeof(int))), unsafeAddr `resNode`[0], L * sizeof(`iT`))
      p
  elif obj.retType.isOption:
    let iT = ident(obj.retType.inner)
    conv = quote do: (if `resNode`.isNone: nil else: (let p = cast[ptr `iT`](alloc0(sizeof(`iT`))); p[] = `resNode`.get; p))
  elif obj.retType.name in ["string", "cstring"]:
    conv = quote do: (let s = $ `resNode`; let p = cast[cstring](alloc0(s.len + 1)); copyMem(p, s.cstring, s.len + 1); p)
  else: conv = resNode

  let internalProc = ident"internal"
  result = newTree(nnkProcDef, procName, newEmptyNode(), newEmptyNode(), ffiParams, newTree(nnkPragma, ident("exportc"), ident("dynlib")), newEmptyNode(), quote do:
    `reconstruction`
    proc `internalProc`(): `originalRetType` = `originalBody`
    try:
      let `resNode` = `internalProc`()
      result = `conv`
    except Exception as e:
      lastOcheError = e.msg
      result = default(type(result))
  )

macro oche*(body: untyped): untyped = processOche(body, false)
macro oche*(arg: untyped, body: untyped): untyped =
  var isView = false
  if arg.kind == nnkIdent and arg.strVal == "view": isView = true
  processOche(body, isView)

macro generate*(output: static string): untyped =
  var code = "import 'dart:ffi' as ffi;\nimport 'dart:isolate';\nimport 'dart:io' show Platform;\nimport 'package:ffi/ffi.dart';\n\nfinal String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');\nfinal dynlib = ffi.DynamicLibrary.open('./$_libName');\nfinal _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\nfinal _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Pointer<Utf8>), void Function(ffi.Pointer, ffi.Pointer<Utf8>)>('ocheFreeDeep');\nfinal _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');\nvoid _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }\n"
  code &= "class NativeListView<T> {\n  final ffi.Pointer<ffi.Void> _ptr;\n  final String _typeName;\n  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;\n  final int _elemSize;\n  late final int length;\n  NativeListView(this._ptr, this._typeName, this._unpacker, this._elemSize) { length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value; }\n  T operator [](int index) { if (index < 0 || index >= length) throw RangeError.index(index, this); return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + ffi.sizeOf<ffi.Int64>() + (index * _elemSize))); }\n  void dispose() { using((Arena a) => _ocheFreeDeep(_ptr, _typeName.toNativeUtf8(allocator: a))); }\n}\n"
  
  var inner = ""
  for o in ooBanks: inner &= genDInterface(o)
  
  for s in enumBanks.values: code &= genDEnum(s)
  for s in structBanks.values: code &= genDStruct(s)
  for t in typeDefBanks: code &= t & "\n"
  
  code &= "class Oche {\n" & inner & "\n}\nfinal oche = Oche();\n"
  writeFile(output, code)
  
  var free = "proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))\nproc ocheFreeDeep(p: pointer, typeName: cstring) {.exportc, dynlib.} = \n  if p.isNil: return\n  let name = $typeName\n"
  for s in structBanks.values:
    free &= "  if name == \"" & s.name & "\":\n    let o = cast[ptr " & s.name & "](p)\n"
    for f in s.fields: (if f.typ.name in ["string", "cstring"]: free &= "    if not o." & f.name & ".isNil: dealloc(o." & f.name & ")\n")
    free &= "    dealloc(p); return\n"
  free &= "  dealloc(p)\n"
  parseStmt(free)