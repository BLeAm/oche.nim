import std/[
  macros,
  os,
  strutils,
  strformat,
  tables
]

type
  OcheType = object
    name:  string
    isSeq: bool
    inner: string
  OcheField = object
    name: string
    typ:  OcheType
  OcheStruct = object
    name:   string
    fields: seq[OcheField]
  OcheParam = object
    name: string
    typ:  OcheType
  OcheObject = object
    name:    string
    retType: OcheType
    params:  seq[OcheParam]

var ooBanks {.compileTime.}: seq[OcheObject] = @[]
var structBanks {.compileTime.}: Table[string, OcheStruct]

# ─── AST Helpers ──────────────────────────────────────────────────────────────

proc parseType(node: NimNode): OcheType =
  case node.kind
  of nnkIdent:
    return OcheType(name: node.strVal, isSeq: false)
  of nnkBracketExpr:
    if node[0].strVal == "seq":
      return OcheType(name: node.repr, isSeq: true, inner: node[1].strVal)
    return OcheType(name: node.repr, isSeq: false)
  else:
    return OcheType(name: node.repr, isSeq: false)

proc parseOche(body: NimNode): OcheObject =
  var o: OcheObject
  o.name    = body[0].strVal
  o.retType = parseType(body[3][0])
  for i in 1 ..< body[3].len:
    let node = body[3][i]
    if node.kind != nnkIdentDefs: continue
    let t = parseType(node[^2])
    for n in node[0 ..< node.len - 2]:
      o.params.add OcheParam(name: n.strVal, typ: t)
  o

# ─── Macro ────────────────────────────────────────────────────────────────────

macro oche*(body: untyped): untyped =
  if body.kind == nnkTypeDef:
    var nameNode = body[0]
    if nameNode.kind == nnkPragmaExpr: nameNode = nameNode[0]
    let structName = nameNode.strVal
    var fields: seq[OcheField] = @[]
    let recList = body[2][2]
    for field in recList:
      if field.kind != nnkIdentDefs: continue
      var fNameNode = field[0]
      if fNameNode.kind == nnkPostfix: fNameNode = fNameNode[1]
      let fName = fNameNode.strVal
      let fType = parseType(field[1])
      fields.add OcheField(name: fName, typ: fType)
    structBanks[structName] = OcheStruct(name: structName, fields: fields)
    return body

  let obj = parseOche(body)
  ooBanks.add(obj)
  let procName = body[0]
  let originalBody = body[6]
  let originalRetType = body[3][0]
  
  var ffiParams = newTree(nnkFormalParams)
  if obj.retType.isSeq or obj.retType.name in ["string", "cstring"]:
    ffiParams.add ident("pointer")
  else:
    ffiParams.add originalRetType

  var reconstruction = newStmtList()
  for p in obj.params:
    if p.typ.isSeq:
      let pPtr = ident(p.name & "_ptr")
      let pLen = ident(p.name & "_len")
      let iT   = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pPtr, newTree(nnkPtrTy, iT))
      ffiParams.add newIdentDefs(pLen, ident("int"))
      reconstruction.add newLetStmt(ident(p.name),
        newTree(nnkPrefix, ident("@"), 
          newTree(nnkCall, ident("toOpenArray"), 
            newTree(nnkCast, newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)), pPtr),
            newLit(0), newTree(nnkInfix, ident("-"), pLen, newLit(1)))))
    elif p.typ.name in ["string", "cstring"]:
      # --- FIX: INCOMING STRING HANDLING ---
      let rawName = ident(p.name & "_raw")
      ffiParams.add newIdentDefs(rawName, ident("cstring"))
      reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("$"), rawName))
    else:
      ffiParams.add newIdentDefs(ident(p.name), ident(p.typ.name))

  var finalBody: NimNode
  if obj.retType.isSeq:
    let innerT = ident(obj.retType.inner)
    finalBody = quote do:
      `reconstruction`
      proc impl(): `originalRetType` = `originalBody`
      let res = impl()
      let length = res.len
      var totalSize = 8
      if length > 0: totalSize += length * sizeof(`innerT`)
      let p = cast[ptr byte](alloc0(totalSize))
      cast[ptr int](p)[] = length
      if length > 0: copyMem(cast[pointer](cast[uint](p) + 8), unsafeAddr res[0], length * sizeof(`innerT`))
      return p
  elif obj.retType.name in ["string", "cstring"]:
    finalBody = quote do:
      `reconstruction`
      proc impl(): string =
        let r = block: `originalBody`
        $r
      let s = impl()
      let L = s.len
      let p = cast[cstring](alloc0(L + 1))
      copyMem(p, s.cstring, L + 1)
      p
  else:
    finalBody = newStmtList(reconstruction, originalBody)

  result = newTree(nnkProcDef,
    procName, newEmptyNode(), newEmptyNode(), ffiParams,
    newTree(nnkPragma, ident("exportc"), ident("dynlib")),
    newEmptyNode(), finalBody)

# ─── Type Mapping ─────────────────────────────────────────────────────────────

proc toNativeFfi(t: string): string =
  case t
  of "int", "int64": "ffi.Int64"
  of "float", "float64": "ffi.Double"
  of "bool": "ffi.Bool"
  of "cstring", "string": "ffi.Pointer<Utf8>"
  of "void", "": "ffi.Void"
  else:
    if structBanks.hasKey(t): return t
    "ffi.Void"

proc toDartFfi(t: string): string =
  case t
  of "int", "int64": "int"
  of "float", "float64": "double"
  of "bool": "bool"
  of "cstring", "string": "ffi.Pointer<Utf8>"
  of "void", "": "void"
  else:
    if structBanks.hasKey(t): return t
    "void"

# ─── Code Generation ──────────────────────────────────────────────────────────

proc genDStruct(s: OcheStruct): string =
  var fields: seq[string] = @[]
  for field in s.fields:
    if field.typ.isSeq: continue 
    let native = toNativeFfi(field.typ.name)
    let dart = toDartFfi(field.typ.name)
    if structBanks.hasKey(field.typ.name):
      fields.add "  external " & field.typ.name & " " & field.name & ";"
    else:
      fields.add "  @" & native & "() external " & dart & " " & field.name & ";"
  result = "final class " & s.name & " extends ffi.Struct {\n" & fields.join("\n") & "\n}\n"

proc genDInterface(obj: OcheObject): string =
  let
    capName    = obj.name[0].toUpperAscii & obj.name[1 .. ^1]
    nativeName = "N" & capName & "Native"
    dartName   = "N" & capName & "Dart"
    callName   = "n" & obj.name & "Call"
  var nativeParams, dartFfiParams, wrapperParams, callArgs, prepWork: seq[string]
  for p in obj.params:
    if p.typ.isSeq:
      let isCustom = structBanks.hasKey(p.typ.inner)
      let nT = if isCustom: p.typ.inner else: toNativeFfi(p.typ.inner)
      let dT = if p.typ.inner == "int": "int" elif p.typ.inner == "float": "double" else: p.typ.inner
      let byteSize = if isCustom: "ffi.sizeOf<" & p.typ.inner & ">()" else: "8"
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      wrapperParams.add "List<" & dT & "> " & p.name
      prepWork.add "    final _" & p.name & "Ptr = arena.allocate<" & nT & ">(" & p.name & ".length * " & byteSize & ");"
      prepWork.add "    for (var i = 0; i < " & p.name & ".length; i++) { _" & p.name & "Ptr[i] = " & p.name & "[i]; }"
      callArgs.add "_" & p.name & "Ptr, " & p.name & ".length"
    elif structBanks.hasKey(p.typ.name):
      nativeParams.add p.typ.name; dartFfiParams.add p.typ.name
      wrapperParams.add p.typ.name & " " & p.name; callArgs.add p.name
    else:
      let dT = if p.typ.name == "int": "int" elif p.typ.name == "float": "double" elif p.typ.name in ["string", "cstring"]: "String" else: p.typ.name
      nativeParams.add toNativeFfi(p.typ.name); dartFfiParams.add toDartFfi(p.typ.name)
      wrapperParams.add dT & " " & p.name
      if p.typ.name in ["string", "cstring"]: callArgs.add p.name & ".toNativeUtf8(allocator: arena)"
      else: callArgs.add p.name

  let 
    isSpecRet = obj.retType.isSeq or obj.retType.name in ["string", "cstring"]
    nativeRet = if isSpecRet: "ffi.Pointer<ffi.Void>" else: toNativeFfi(obj.retType.name)
    dartFfiRet = if isSpecRet: "ffi.Pointer<ffi.Void>" else: toDartFfi(obj.retType.name)
    retTypeDart = if obj.retType.isSeq: "List<" & obj.retType.inner & ">" elif obj.retType.name in ["string", "cstring"]: "String" else: toDartFfi(obj.retType.name)

  var body: string
  if obj.retType.isSeq:
    let isCustomInner = structBanks.hasKey(obj.retType.inner)
    let nTI = if isCustomInner: obj.retType.inner else: toNativeFfi(obj.retType.inner)
    let dT = obj.retType.inner
    if isCustomInner:
      body = "    final _ptr = " & callName & "(" & callArgs.join(", ") & ");\n" &
             "    if (_ptr.address == 0) return [];\n" &
             "    try { final _len = _ptr.cast<ffi.Int64>().value; final _dataPtr = ffi.Pointer<" & nTI & ">.fromAddress(_ptr.address + 8); return List<" & dT & ">.generate(_len, (i) => _dataPtr[i]); } finally { _ocheFree(_ptr); }"
    else:
      body = "    final _ptr = " & callName & "(" & callArgs.join(", ") & ");\n" &
             "    if (_ptr.address == 0) return [];\n" &
             "    try { final _len = _ptr.cast<ffi.Int64>().value; final _view = ffi.Pointer<" & nTI & ">.fromAddress(_ptr.address + 8).asTypedList(_len); return _view.toList(); } finally { _ocheFree(_ptr); }"
  elif obj.retType.name in ["string", "cstring"]:
    body = "    final _ptr = " & callName & "(" & callArgs.join(", ") & ");\n" &
           "    if (_ptr.address == 0) return '';\n" &
           "    try { return _ptr.cast<Utf8>().toDartString(); } finally { _ocheFree(_ptr); }"
  elif obj.retType.name == "void": body = "    " & callName & "(" & callArgs.join(", ") & ");"
  else: body = "    return " & callName & "(" & callArgs.join(", ") & ");"

  let nPStr = nativeParams.join(", "); let dFStr = dartFfiParams.join(", ")
  let wPStr = wrapperParams.join(", "); let pWStr = prepWork.join("\n")

  result = "  typedef " & nativeName & " = " & nativeRet & " Function(" & nPStr & ");\n" &
           "  typedef " & dartName & " = " & dartFfiRet & " Function(" & dFStr & ");\n" &
           "  final " & callName & " = dynlib.lookupFunction<" & nativeName & ", " & dartName & ">('" & obj.name & "');\n" &
           "  " & retTypeDart & " " & obj.name & "(" & wPStr & ") {\n" &
           "    return using((arena) {\n" &
           "  " & pWStr & "\n" &
           body & "\n" &
           "    });\n  }\n"

macro generate*(output: varargs[untyped]): untyped =
  let info = output[0].lineInfoObj
  let libname = "lib" & info.filename.splitFile.name & ".so"
  var code = "import 'dart:ffi' as ffi;\nimport 'package:ffi/ffi.dart';\nfinal dynlib = ffi.DynamicLibrary.open('./" & libname & "');\nfinal _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\n"
  for s in structBanks.values: code &= genDStruct(s) & "\n"
  for obj in ooBanks: code &= genDInterface(obj)
  writeFile(output[0].strVal, code)
  result = quote do:
    proc ocheFree(p: pointer) {.exportc, dynlib.} =
      if not p.isNil: dealloc(p)