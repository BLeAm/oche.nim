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
      
      # อัปเดต: ใส่ {.size: 4.} ให้อัตโนมัติเพื่อให้ตรงกับ ffi.Int32 ของ Dart
      var newBody = body.copyNimTree()
      var pragmas = newTree(nnkPragma, newColonExpr(ident("size"), newLit(4)))
      if newBody[0].kind == nnkPragmaExpr:
        newBody[0][1].add pragmas[0]
      else:
        newBody[0] = newTree(nnkPragmaExpr, newBody[0], pragmas)
      return newBody
    else:
      var fields: seq[OcheField] = @[]
      let recList = tyNode[2]
      for field in recList:
        if field.kind != nnkIdentDefs: continue
        let tNode = field[^2]
        let t = parseType(tNode)
        for i in 0 ..< field.len - 2:
          var fNameNode = field[i]
          if fNameNode.kind == nnkPostfix: fNameNode = fNameNode[1]
          fields.add OcheField(name: fNameNode.strVal, typ: t)
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
      let pPtr = ident(p.name & "_ptr")
      let pLen = ident(p.name & "_len")
      let iT = ident(p.typ.inner)
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

  let resName = ident("res")
  var conversion: NimNode
  if obj.retType.isSeq:
    let innerT = ident(obj.retType.inner)
    conversion = quote do:
      let L = `resName`.len
      let p = cast[ptr byte](alloc0(8 + (L * sizeof(`innerT`))))
      cast[ptr int](p)[] = L
      if L > 0: copyMem(cast[pointer](cast[uint](p) + 8), unsafeAddr `resName`[0], L * sizeof(`innerT`))
      p
  elif obj.retType.isOption:
    let innerT = ident(obj.retType.inner)
    conversion = quote do:
      if `resName`.isNone: nil
      else:
        let p = cast[ptr `innerT`](alloc0(sizeof(`innerT`)))
        p[] = `resName`.get
        p
  elif obj.retType.name in ["string", "cstring"]:
    conversion = quote do:
      let s = $ `resName`
      let p = cast[cstring](alloc0(s.len + 1))
      copyMem(p, s.cstring, s.len + 1)
      p
  else:
    conversion = resName

  let finalBody = quote do:
    `reconstruction`
    proc internal(): `originalRetType` =
      `originalBody`
    
    try:
      let `resName` = internal()
      result = `conversion`
    except Exception as e:
      lastOcheError = e.msg
      when `originalRetType` is int | float | bool | int32 | int64: result = default(`originalRetType`)
      else: result = nil

  result = newTree(nnkProcDef, procName, newEmptyNode(), newEmptyNode(), ffiParams, newTree(nnkPragma, ident("exportc"), ident("dynlib")), newEmptyNode(), finalBody)

# ─── Type Mapping ─────────────────────────────────────────────────────────────

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

# ─── Generator ────────────────────────────────────────────────────────────────

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
      toFfi.add "    " & f.name & "._pack(target." & f.name & ", a);"
      fromFfi.add "    " & f.name & ": " & f.typ.name & "._unpack(source." & f.name & "),"
    elif f.typ.name in ["string", "cstring"]:
      ffiFields.add "  external ffi.Pointer<Utf8> " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ".toNativeUtf8(allocator: a);"
      fromFfi.add "    " & f.name & ": (source." & f.name & ".address == 0) ? '' : source." & f.name & ".toDartString(),"
    elif enumBanks.hasKey(f.typ.name):
      ffiFields.add "  @ffi.Int32() external int " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ".index;"
      fromFfi.add "    " & f.name & ": " & f.typ.name & ".values[source." & f.name & "],"
    else:
      ffiFields.add "  @" & nT & "() external " & dT & " " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ";"
      fromFfi.add "    " & f.name & ": source." & f.name & ","
    dartFields.add "  final " & dT & " " & f.name & ";"

  let ffiStruct = "final class N" & s.name & " extends ffi.Struct {\n" & ffiFields.join("\n") & "\n}\n"
  let dartClass = "class " & s.name & " {\n" & dartFields.join("\n") & "\n" &
                  "  const " & s.name & "({\n" & s.fields.mapIT("    required this." & it.name).join(",\n") & "\n  });\n\n" &
                  "  void _pack(N" & s.name & " target, ffi.Allocator a) {\n" & toFfi.join("\n") & "\n  }\n\n" &
                  "  static " & s.name & " _unpack(N" & s.name & " source) {\n" &
                  "    return " & s.name & "(\n" & fromFfi.join("\n") & "\n    );\n  }\n" &
                  "}\n"
  result = ffiStruct & "\n" & dartClass

proc genDInterface(obj: OcheObject): string =
  let callName = "n" & obj.name & "Call"
  var nativeParams, dartFfiParams, wrapperParams, callArgs, prepWork: seq[string]
  for p in obj.params:
    let dT = toDartType(p.typ.name)
    let pN = "v_" & p.name
    wrapperParams.add "final " & dT & " " & pN # FIX: USE toDartType DIRECTLY FOR THE WHOLE TYPE
    if p.typ.isSeq:
      let iI = p.typ.inner; let isC = structBanks.hasKey(iI)
      let nT = if isC: "N" & iI else: toNativeType(iI)
      let bS = if isC: "ffi.sizeOf<N" & iI & ">()" else: "8"
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      prepWork.add "    final _" & pN & "Ptr = a.allocate<" & nT & ">(" & pN & ".length * " & bS & ");"
      if isC:
        prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { " & pN & "[i]._pack(_" & pN & "Ptr[i], a); }"
      elif enumBanks.hasKey(iI):
        prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i].index; }"
      else:
        prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i]; }"
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

  let sR = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"]
  let nR = if sR: "ffi.Pointer<ffi.Void>" else: toNativeType(obj.retType.name)
  let dT_ret = toDartType(obj.retType.name)
  let dR = if sR: "ffi.Pointer<ffi.Void>" else: (if nR.contains("Int") or nR.contains("Double") or nR.contains("Bool"): dT_ret else: nR)
  
  var body: string
  if obj.retType.isSeq:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI)
    let nT = if isC: "N" & iI else: toNativeType(iI)
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      if (p.address == 0) return []; try {\n" &
           "        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<" & nT & ">.fromAddress(p.address + 8);\n" &
           (if isC: "        return List<" & iI & ">.generate(L, (i) => " & iI & "._unpack(d[i]));" else: "        return d.asTypedList(L).toList();") & "\n      } finally { _ocheFree(p); }"
  elif obj.retType.isOption:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI)
    let nTI = if isC: "N" & iI else: toNativeType(iI)
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      if (p.address == 0) return null; try {\n" &
           (if isC: "        return " & iI & "._unpack(p.cast<" & nTI & ">().ref);" else: "        return p.cast<" & nTI & ">().value;") & "\n      } finally { _ocheFree(p); }"
  elif obj.retType.name in ["string", "cstring"]:
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }"
  else:
    body = "      final r = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      return " & (if enumBanks.hasKey(obj.retType.name): dT_ret & ".values[r];" else: "r;")

  result = "  typedef N" & obj.name & "N = " & nR & " Function(" & nativeParams.join(", ") & ");\n" &
           "  typedef N" & obj.name & "D = " & dR & " Function(" & dartFfiParams.join(", ") & ");\n" &
           "  final " & callName & " = dynlib.lookupFunction<N" & obj.name & "N, N" & obj.name & "D>('" & obj.name & "');\n\n" &
           "  " & dT_ret & " " & obj.name & "(" & wrapperParams.join(", ") & ") {\n" &
           "    return using((a) {\n" & prepWork.join("\n") & "\n" & body & "\n    });\n  }\n\n" &
           "  Future<" & dT_ret & "> " & obj.name & "Async(" & wrapperParams.join(", ") & ") => Isolate.run(() => " & obj.name & "(" & obj.params.mapIT("v_" & it.name).join(", ") & "));\n"

macro generate*(output: varargs[untyped]): untyped =
  let info = output[0].lineInfoObj; let baseName = "lib" & info.filename.splitFile.name
  var code = "import 'dart:ffi' as ffi;\nimport 'dart:isolate';\nimport 'dart:io' show Platform;\nimport 'package:ffi/ffi.dart';\n\n" &
             "final String _libName = Platform.isWindows ? '" & baseName & ".dll' : (Platform.isMacOS ? '" & baseName & ".dylib' : '" & baseName & ".so');\n" &
             "final dynlib = ffi.DynamicLibrary.open('./$_libName');\n" &
             "final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\n" &
             "final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');\n" &
             "void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }\n"
  for s in enumBanks.values: code &= genDEnum(s) & "\n"
  for s in structBanks.values: code &= genDStruct(s) & "\n"
  for obj in ooBanks: code &= genDInterface(obj)
  writeFile(output[0].strVal, code)
  result = quote do:
    proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))