import std/[
  macros,
  os,
  strutils,
  strformat,
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

var ooBanks {.compileTime.}: seq[OcheObject] = @[]
var structBanks {.compileTime.}: Table[string, OcheStruct]
var enumBanks {.compileTime.}: Table[string, OcheEnum]

var lastOcheError {.threadvar.}: string

proc ocheGetError(): cstring {.exportc, dynlib.} =
  if lastOcheError == "": return nil
  let L = lastOcheError.len
  result = cast[cstring](alloc0(L + 1))
  copyMem(result, lastOcheError.cstring, L + 1)
  lastOcheError = ""

# ─── AST Helpers ──────────────────────────────────────────────────────────────

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
    let name = nameNode.strVal
    let tyNode = body[2]
    if tyNode.kind == nnkEnumTy:
      var vals: seq[string] = @[]
      for i in 1 ..< tyNode.len:
        if tyNode[i].kind == nnkIdent: vals.add tyNode[i].strVal
        elif tyNode[i].kind == nnkEnumFieldDef: vals.add tyNode[i][0].strVal
      enumBanks[name] = OcheEnum(name: name, values: vals)
      return body
    else:
      var fields: seq[OcheField] = @[]
      let recList = tyNode[2]
      for field in recList:
        if field.kind != nnkIdentDefs: continue
        var fNameNode = field[0]
        if fNameNode.kind == nnkPostfix: fNameNode = fNameNode[1]
        fields.add OcheField(name: fNameNode.strVal, typ: parseType(field[1]))
      structBanks[name] = OcheStruct(name: name, fields: fields)
      return body

  let obj = parseOche(body)
  ooBanks.add(obj)
  let procName = body[0]
  let originalBody = body[6]
  let originalRetType = body[3][0]
  
  var ffiParams = newTree(nnkFormalParams)
  if obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"]:
    ffiParams.add ident("pointer")
  else:
    ffiParams.add originalRetType

  var reconstruction = newStmtList()
  for p in obj.params:
    if p.typ.isSeq:
      let pPtr = ident(p.name & "_ptr"); let pLen = ident(p.name & "_len"); let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pPtr, newTree(nnkPtrTy, iT))
      ffiParams.add newIdentDefs(pLen, ident("int"))
      reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("@"), newTree(nnkCall, ident("toOpenArray"), newTree(nnkCast, newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)), pPtr), newLit(0), newTree(nnkInfix, ident("-"), pLen, newLit(1)))))
    elif p.typ.name in ["string", "cstring"]:
      let rawName = ident(p.name & "_raw")
      ffiParams.add newIdentDefs(rawName, ident("cstring"))
      reconstruction.add newLetStmt(ident(p.name), newTree(nnkPrefix, ident("$"), rawName))
    elif enumBanks.hasKey(p.typ.name):
      ffiParams.add newIdentDefs(ident(p.name), ident("int32"))
    else:
      ffiParams.add newIdentDefs(ident(p.name), ident(p.typ.name))

  var coreLogic: NimNode
  if obj.retType.isSeq:
    let innerT = ident(obj.retType.inner)
    coreLogic = quote do:
      let res = `originalBody`
      let L = res.len
      let p = cast[ptr byte](alloc0(8 + (L * sizeof(`innerT`))))
      cast[ptr int](p)[] = L
      if L > 0: copyMem(cast[pointer](cast[uint](p) + 8), unsafeAddr res[0], L * sizeof(`innerT`))
      p
  elif obj.retType.isOption:
    let innerT = ident(obj.retType.inner)
    coreLogic = quote do:
      let res = `originalBody`
      if res.isNone: nil
      else:
        let p = cast[ptr `innerT`](alloc0(sizeof(`innerT`)))
        p[] = res.get
        p
  elif obj.retType.name in ["string", "cstring"]:
    coreLogic = quote do:
      let s = $ `originalBody`
      let p = cast[cstring](alloc0(s.len + 1))
      copyMem(p, s.cstring, s.len + 1)
      p
  else:
    coreLogic = originalBody

  let finalBody = quote do:
    `reconstruction`
    try:
      result = `coreLogic`
    except Exception as e:
      lastOcheError = e.msg
      when `originalRetType` is int | float | bool | int32 | int64: result = default(`originalRetType`)
      else: result = nil

  result = newTree(nnkProcDef, procName, newEmptyNode(), newEmptyNode(), ffiParams, newTree(nnkPragma, ident("exportc"), ident("dynlib")), newEmptyNode(), finalBody)

# ─── Type Mapping ─────────────────────────────────────────────────────────────

proc toNativeFfi(t: string): string =
  case t
  of "int", "int64": return "ffi.Int64"
  of "float", "float64": return "ffi.Double"
  of "bool": return "ffi.Bool"
  of "cstring", "string": return "ffi.Pointer<Utf8>"
  of "void", "": return "ffi.Void"
  else:
    if enumBanks.hasKey(t): return "ffi.Int32"
    elif structBanks.hasKey(t): return t
    else: return "ffi.Void"

proc toDartFfi(t: string): string =
  case t
  of "int", "int64": return "int"
  of "float", "float64": return "double"
  of "bool": return "bool"
  of "cstring", "string": return "ffi.Pointer<Utf8>"
  of "void", "": return "void"
  else:
    if enumBanks.hasKey(t): return "int"
    elif structBanks.hasKey(t): return t
    else: return "void"

proc toDart(t: string): string =
  if t.startsWith("seq["): return "List<" & toDart(t[4..^2]) & ">"
  if t.startsWith("Option["): return toDart(t[7..^2]) & "?"
  case t
  of "int", "int64": return "int"
  of "float", "float64": return "double"
  of "bool": return "bool"
  of "cstring", "string": return "String"
  of "void", "": return "void"
  else: return t

# ─── Generator ────────────────────────────────────────────────────────────────

proc genDEnum(e: OcheEnum): string =
  var lines: seq[string] = @[]
  for v in e.values: lines.add "  " & v & ","
  result = "enum " & e.name & " {\n" & lines.join("\n") & "\n}\n"

proc genDStruct(s: OcheStruct): string =
  var fields: seq[string] = @[]
  for f in s.fields:
    let n = toNativeFfi(f.typ.name); let d = toDartFfi(f.typ.name)
    if structBanks.hasKey(f.typ.name): fields.add "  external " & f.typ.name & " " & f.name & ";"
    else: fields.add "  @" & n & "() external " & d & " " & f.name & ";"
  result = "final class " & s.name & " extends ffi.Struct {\n" & fields.join("\n") & "\n}\n"

proc genDInterface(obj: OcheObject): string =
  let callName = "n" & obj.name & "Call"
  var nativeParams, dartFfiParams, wrapperParams, callArgs, prepWork: seq[string]
  for p in obj.params:
    if p.typ.isSeq:
      let iInner = p.typ.inner
      let isC = structBanks.hasKey(iInner)
      let nT = if isC: iInner else: toNativeFfi(iInner)
      let dT = toDart(iInner)
      let bS = if isC: "ffi.sizeOf<" & iInner & ">()" else: "8"
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      wrapperParams.add "List<" & dT & "> " & p.name
      prepWork.add "    final _" & p.name & "Ptr = a.allocate<" & nT & ">(" & p.name & ".length * " & bS & ");"
      if enumBanks.hasKey(iInner): 
        prepWork.add "    for (var i = 0; i < " & p.name & ".length; i++) { _" & p.name & "Ptr[i] = " & p.name & "[i].index; }"
      else:
        prepWork.add "    for (var i = 0; i < " & p.name & ".length; i++) { _" & p.name & "Ptr[i] = " & p.name & "[i]; }"
      callArgs.add "_" & p.name & "Ptr, " & p.name & ".length"
    elif enumBanks.hasKey(p.typ.name):
      nativeParams.add "ffi.Int32"; dartFfiParams.add "int"; wrapperParams.add p.typ.name & " " & p.name
      callArgs.add p.name & ".index"
    elif structBanks.hasKey(p.typ.name):
      nativeParams.add p.typ.name; dartFfiParams.add p.typ.name; wrapperParams.add p.typ.name & " " & p.name; callArgs.add p.name
    else:
      nativeParams.add toNativeFfi(p.typ.name); dartFfiParams.add toDartFfi(p.typ.name); wrapperParams.add toDart(p.typ.name) & " " & p.name
      if p.typ.name in ["string", "cstring"]: callArgs.add p.name & ".toNativeUtf8(allocator: a)"
      else: callArgs.add p.name

  let sRet = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"]
  let nR = if sRet: "ffi.Pointer<ffi.Void>" else: toNativeFfi(obj.retType.name)
  let dR = if sRet: "ffi.Pointer<ffi.Void>" else: toDartFfi(obj.retType.name)
  let rTD = toDart(obj.retType.name)

  var bodyCode = ""
  if obj.retType.isSeq:
    let iInner = obj.retType.inner
    let isC = structBanks.hasKey(iInner)
    let nTI = if isC: iInner else: toNativeFfi(iInner)
    let dT = toDart(iInner)
    bodyCode = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
               "      if (p.address == 0) return []; try {\n" &
               "        final L = p.cast<ffi.Int64>().value; final d = ffi.Pointer<" & nTI & ">.fromAddress(p.address + 8);\n" &
               (if isC: "        return List<" & dT & ">.generate(L, (i) => d[i]);" else: "        return d.asTypedList(L).toList();") & "\n      } finally { _ocheFree(p); }"
  elif obj.retType.isOption:
    let nTI = toNativeFfi(obj.retType.inner)
    bodyCode = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
               "      if (p.address == 0) return null; try {\n" &
               "        return p.cast<" & nTI & ">().value;\n" &
               "      } finally { _ocheFree(p); }"
  elif obj.retType.name in ["string", "cstring"]:
    bodyCode = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
               "      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }"
  else:
    bodyCode = "      final r = " & callName & "(" & callArgs.join(", ") & "); \n      _checkError();\n    return " & (if enumBanks.hasKey(obj.retType.name): rTD & ".values[r];" else: "r;")

  let pNames = obj.params.mapIT(it.name).join(", ")
  result = "  typedef N" & obj.name & "Native = " & nR & " Function(" & nativeParams.join(", ") & ");\n" &
           "  typedef N" & obj.name & "Dart = " & dR & " Function(" & dartFfiParams.join(", ") & ");\n" &
           "  final " & callName & " = dynlib.lookupFunction<N" & obj.name & "Native, N" & obj.name & "Dart>('" & obj.name & "');\n" &
           "  " & rTD & " " & obj.name & "(" & wrapperParams.join(", ") & ") {\n" &
           "    return using((a) {\n" & prepWork.join("\n") & "\n" & bodyCode & "\n    });\n  }\n" &
           "  Future<" & rTD & "> " & obj.name & "Async(" & wrapperParams.join(", ") & ") => Isolate.run(() => " & obj.name & "(" & pNames & "));\n"

macro generate*(output: varargs[untyped]): untyped =
  let info = output[0].lineInfoObj; let libname = "./lib" & info.filename.splitFile.name & ".so"
  var code = "import 'dart:ffi' as ffi;\nimport 'dart:isolate';\nimport 'package:ffi/ffi.dart';\nfinal dynlib = ffi.DynamicLibrary.open('" & libname & "');\nfinal _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\nfinal _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');\nvoid _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }\n"
  for s in enumBanks.values: code &= genDEnum(s) & "\n"
  for s in structBanks.values: code &= genDStruct(s) & "\n"
  for obj in ooBanks: code &= genDInterface(obj)
  writeFile(output[0].strVal, code)
  result = quote do:
    proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))