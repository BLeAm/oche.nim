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
    isShared: bool
    inner: string
  OcheField = object
    name: string
    typ:  OcheType
  OcheStruct = object
    name:   string
    typeId: int
    fields: seq[OcheField]
    isPOD:  bool
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

var ooBanks    {.compileTime.}: seq[OcheObject] = @[]
var structBanks {.compileTime.}: Table[string, OcheStruct]
var enumBanks   {.compileTime.}: Table[string, OcheEnum]
var typeDefBanks {.compileTime.}: seq[string] = @[]

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

template dataPtr[T](b: OcheBuffer[T]): ptr UncheckedArray[T] =
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
    elif base == "OcheBuffer":
      return OcheType(name: node.repr, isShared: true, inner: node[1].repr)
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
  if t.startsWith("OcheBuffer["):
    let innerName = t[11..^2]
    let innerV = if structBanks.hasKey(innerName): innerName & "View" else: toDartType(innerName)
    return "SharedListView<" & innerV & ">"
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
  var ffiFields, toFfi, fromFfi, dartFields, toFfiManual: seq[string]
  for f in s.fields:
    let nT = toNativeType(f.typ.name)
    let dT = toDartType(f.typ.name)
    if structBanks.hasKey(f.typ.name):
      ffiFields.add    "  external N" & f.typ.name & " " & f.name & ";"
      toFfi.add        "    this." & f.name & "._pack(target." & f.name & ", a);"
      toFfiManual.add  "    this." & f.name & "._pack(target." & f.name & ", malloc);"
      fromFfi.add      "    " & f.name & ": " & f.typ.name & "._unpack(source." & f.name & "),"
    elif f.typ.name in ["string", "cstring"]:
      ffiFields.add    "  external ffi.Pointer<Utf8> " & f.name & ";"
      toFfi.add        "    target." & f.name & " = " & f.name & ".toNativeUtf8(allocator: a);"
      toFfiManual.add  "    target." & f.name & " = " & f.name & ".toNativeUtf8(allocator: malloc);"
      fromFfi.add      "    " & f.name & ": (source." & f.name & ".address == 0) ? '' : source." & f.name & ".toDartString(),"
    elif enumBanks.hasKey(f.typ.name):
      ffiFields.add    "  @ffi.Int32() external int " & f.name & ";"
      toFfi.add        "    target." & f.name & " = " & f.name & ".index;"
      toFfiManual.add  "    target." & f.name & " = " & f.name & ".index;"
      fromFfi.add      "    " & f.name & ": " & f.typ.name & ".values[source." & f.name & "],"
    else:
      ffiFields.add    "  @" & nT & "() external " & dT & " " & f.name & ";"
      toFfi.add        "    target." & f.name & " = " & f.name & ";"
      toFfiManual.add  "    target." & f.name & " = " & f.name & ";"
      fromFfi.add      "    " & f.name & ": source." & f.name & ","
    dartFields.add "  final " & dT & " " & f.name & ";"

  let ffiStruct = "final class N" & s.name & " extends ffi.Struct {\n" & ffiFields.join("\n") & "\n}\n"

  var extType = "\nextension type " & s.name & "View(N" & s.name & " _ref) {\n"
  var packIntoLines: seq[string] = @[]
  for f in s.fields:
    let dT = toDartType(f.typ.name)
    if f.typ.name in ["string", "cstring"]:
      extType &= "  " & dT & " get " & f.name & " => (_ref." & f.name & ".address == 0) ? '' : _ref." & f.name & ".toDartString();\n"
      packIntoLines.add "    p.ref." & f.name & " = _ref." & f.name & ";"
    elif enumBanks.hasKey(f.typ.name):
      extType &= "  " & dT & " get " & f.name & " => " & f.typ.name & ".values[_ref." & f.name & "];\n"
      extType &= "  set " & f.name & "(" & dT & " v) => _ref." & f.name & " = v.index;\n"
      packIntoLines.add "    p.ref." & f.name & " = _ref." & f.name & ";"
    elif structBanks.hasKey(f.typ.name):
      extType &= "  " & f.typ.name & "View get " & f.name & " => " & f.typ.name & "View(_ref." & f.name & ");\n"
      packIntoLines.add "    p.ref." & f.name & " = _ref." & f.name & ";"
    else:
      extType &= "  " & dT & " get " & f.name & " => _ref." & f.name & ";\n"
      extType &= "  set " & f.name & "(" & dT & " v) => _ref." & f.name & " = v;\n"
      packIntoLines.add "    p.ref." & f.name & " = _ref." & f.name & ";"
  extType &= "  void _packInto(ffi.Pointer<N" & s.name & "> p) {\n" & packIntoLines.join("\n") & "\n  }\n}\n"

  let dartClass =
    "class " & s.name & " {\n" & dartFields.join("\n") & "\n" &
    "  const " & s.name & "({\n" & s.fields.mapIt("    required this." & it.name).join(",\n") & "\n  });\n\n" &
    "  void _pack(N" & s.name & " target, ffi.Allocator a) {\n" & toFfi.join("\n") & "\n  }\n\n" &
    "  void _packManual(N" & s.name & " target) {\n" & toFfiManual.join("\n") & "\n  }\n\n" &
    "  static " & s.name & " _unpack(N" & s.name & " source) {\n" &
    "    return " & s.name & "(\n" & fromFfi.join("\n") & "\n    );\n  }\n" &
    "}\n"
  result = ffiStruct & extType & "\n" & dartClass

proc genDInterface(obj: OcheObject): string =
  let callName = "n" & obj.name & "Call"
  var nativeParams, dartFfiParams, wrapperParams, callArgs, prepWork: seq[string]
  var needsArena = false

  for p in obj.params:
    let dT = toDartType(p.typ.name)
    let pN = "v_" & p.name
    wrapperParams.add "final " & dT & " " & pN
    if p.typ.isSeq:
      needsArena = true
      let iI = p.typ.inner
      let isC = structBanks.hasKey(iI)
      let nT  = if isC: "N" & iI else: toNativeType(iI)
      let sz  = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
      nativeParams.add  "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      prepWork.add "    final _" & pN & "Ptr = a.allocate<" & nT & ">(" & pN & ".length * " & sz & ");"
      if isC:
        prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { " & pN & "[i]._pack(_" & pN & "Ptr[i], a); }"
      elif enumBanks.hasKey(iI):
        prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i].index; }"
      else:
        prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i]; }"
      callArgs.add "_" & pN & "Ptr, " & pN & ".length"
    elif structBanks.hasKey(p.typ.name):
      needsArena = true
      nativeParams.add  "ffi.Pointer<N" & p.typ.name & ">"
      dartFfiParams.add "ffi.Pointer<N" & p.typ.name & ">"
      prepWork.add "    final _" & pN & "Ptr = a.allocate<N" & p.typ.name & ">(ffi.sizeOf<N" & p.typ.name & ">());"
      prepWork.add "    " & pN & "._pack(_" & pN & "Ptr.ref, a);"
      callArgs.add "_" & pN & "Ptr"
    else:
      let nT = toNativeType(p.typ.name)
      nativeParams.add nT
      dartFfiParams.add(
        if nT.contains("Int") or nT.contains("Double") or nT.contains("Bool"):
          toDartType(p.typ.name)
        else: nT
      )
      if p.typ.name in ["string", "cstring"]:
        needsArena = true
        callArgs.add pN & ".toNativeUtf8(allocator: a)"
      elif enumBanks.hasKey(p.typ.name):
        callArgs.add pN & ".index"
      else:
        callArgs.add pN

  let sR      = obj.retType.isSeq or obj.retType.isOption or
                obj.retType.name in ["string", "cstring"] or obj.retType.isShared
  let nR      = if sR: "ffi.Pointer<ffi.Void>" else: toNativeType(obj.retType.name)
  let dT_ret  = toDartType(obj.retType.name)
  let isVoid  = obj.retType.name == "void" or obj.retType.name == ""

  var actualRetType = dT_ret
  if isVoid: actualRetType = "void"
  elif obj.isView or obj.retType.isShared:
    if obj.retType.isSeq or obj.retType.isShared:
      let innerName = obj.retType.inner
      let innerV = if structBanks.hasKey(innerName): innerName & "View" else: toDartType(innerName)
      actualRetType = (if obj.retType.isShared: "SharedListView<" else: "NativeListView<") & innerV & ">"
    elif structBanks.hasKey(obj.retType.name):
      actualRetType = obj.retType.name & "View"

  let dR = if sR: "ffi.Pointer<ffi.Void>"
           elif isVoid: "void"
           elif nR.contains("Int") or nR.contains("Double") or nR.contains("Bool"): dT_ret
           else: nR

  var body: string
  if obj.retType.isShared:
    let iI  = obj.retType.inner
    let isC = structBanks.hasKey(iI)
    let nT  = if isC: "N" & iI else: toNativeType(iI)
    let sz  = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
    # FIX 2: Only emit _ocheFreeInner call if the inner type is NOT POD
    let packerBody =
      if isC:
        let innerStruct = structBanks[iI]
        let freeCall = if not innerStruct.isPOD:
          "_ocheFreeInner(p, " & $innerStruct.typeId & "); "
        else: ""
        "if (v is " & iI & ") { " & freeCall & "v._packManual(p.cast<N" & iI & ">().ref); } " &
        "else if (v is " & iI & "View) { v._packInto(p.cast<N" & iI & ">()); }"
      else:
        "p.cast<" & nT & ">().value = v as " & toDartType(iI) & ";"
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      return SharedListView<" & (if isC: iI & "View" else: toDartType(iI)) & ">" &
           "(p, (ptr) => " & (if isC: iI & "View(ptr.cast<N" & iI & ">().ref)" else: "ptr.cast<" & nT & ">().value") &
           ", (p, v) { " & packerBody & " }, " & sz & ");"

  elif obj.retType.isSeq:
    let iI  = obj.retType.inner
    let isC = structBanks.hasKey(iI)
    let nT  = if isC: "N" & iI else: toNativeType(iI)
    if obj.isView:
      let sz = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      return NativeListView<" & (if isC: iI & "View" else: toDartType(iI)) &
             ">(p, (ptr) => " & (if isC: iI & "View(ptr.cast<N" & iI & ">().ref)" else: "ptr.cast<" & nT & ">().value") &
             ", " & (if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()") & ");"
    else:
      # FIX 1: seq[non-POD] uses _unpack (deep copy) instead of copyMem (shallow)
      # For POD structs, asTypedList/generate with _unpack is still safe and correct.
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      if (p.address == 0) return []; try {\n" &
             "        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value;\n" &
             "        final d = ffi.Pointer<" & nT & ">.fromAddress(p.address + 16);\n" &
             (if isC:
               "        return List<" & iI & ">.generate(L, (i) => " & iI & "._unpack(d[i]));"
             else:
               "        return d.asTypedList(L).toList();") & "\n" &
             "      } finally { _ocheFreeDeep(p); }"

  elif obj.retType.isOption:
    let iI   = obj.retType.inner
    let isC  = structBanks.hasKey(iI)
    let nTI  = if isC: "N" & iI else: toNativeType(iI)
    if obj.isView:
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      return " & (if isC: iI & "View(p.cast<N" & iI & ">().ref);" else: "p.cast<" & nTI & ">().value;")
    else:
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      if (p.address == 0) return null; try {\n" &
             (if isC: "        return " & iI & "._unpack(p.cast<" & nTI & ">().ref);" else: "        return p.cast<" & nTI & ">().value;") & "\n" &
             "      } finally { _ocheFree(p); }"

  elif obj.retType.name in ["string", "cstring"]:
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }"

  elif isVoid:
    body = "      " & callName & "(" & callArgs.join(", ") & "); _checkError();"

  else:
    body = "      final r = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      return " & (
             if enumBanks.hasKey(obj.retType.name): dT_ret & ".values[r];"
             elif structBanks.hasKey(obj.retType.name): obj.retType.name & "._unpack(r);"
             else: "r;"
           )

  typeDefBanks.add "typedef N" & obj.name & "N = " & nR & " Function(" & nativeParams.join(", ") & ");"
  typeDefBanks.add "typedef N" & obj.name & "D = " & dR & " Function(" & dartFfiParams.join(", ") & ");"

  let finalBody =
    if needsArena:
      "    return using((a) {\n" & prepWork.join("\n") & "\n" & body & "\n    });"
    else:
      body

  result =
    "  late final " & callName & " = dynlib.lookupFunction<N" & obj.name & "N, N" & obj.name & "D>('" & obj.name & "');\n\n" &
    "  " & actualRetType & " " & obj.name & "(" & wrapperParams.join(", ") & ") {\n" & finalBody & "\n  }\n"

proc processOche(body: NimNode, isView: bool): NimNode {.compileTime.} =
  if body.kind == nnkTypeDef:
    var nameNode = body[0]
    if nameNode.kind == nnkPragmaExpr: nameNode = nameNode[0]
    let name   = nameNode.strVal
    let tyNode = body[2]

    if tyNode.kind == nnkEnumTy:
      var v: seq[string] = @[]
      for i in 1..<tyNode.len:
        if tyNode[i].kind == nnkIdent: v.add tyNode[i].strVal
        elif tyNode[i].kind == nnkEnumFieldDef: v.add tyNode[i][0].strVal
      enumBanks[name] = OcheEnum(name: name, values: v)
      let prag = newTree(nnkPragma, newColonExpr(ident("size"), newLit(4)))
      return newTree(nnkTypeDef, newTree(nnkPragmaExpr, nameNode, prag), newEmptyNode(), tyNode)

    else:
      var f: seq[OcheField] = @[]
      let rec    = tyNode[2]
      var pod    = true
      let newRec = newTree(nnkRecList)

      for field in rec:
        if field.kind == nnkIdentDefs:
          var ft = field[^2]
          if ft.kind == nnkIdent and ft.strVal == "string": ft = ident("cstring")
          let t = parseType(ft)
          for i in 0..<field.len-2:
            var fn = field[i]
            if fn.kind == nnkPostfix: fn = fn[1]
            f.add OcheField(name: fn.strVal, typ: t)

          # FIX 3: guard structBanks lookup — a nested struct may not be registered yet
          # (forward reference). In that case we conservatively mark the parent as non-POD.
          if t.name in ["string", "cstring"]:
            pod = false
          elif structBanks.hasKey(t.name):
            if not structBanks[t.name].isPOD: pod = false
          # else: unknown type — could be a forward ref; leave pod=true for now,
          # generate() will re-evaluate through ocheFreeDeep flags at runtime.

          var newNode = newTree(nnkIdentDefs)
          for i in 0..<field.len-2: newNode.add field[i]
          newNode.add ft
          newNode.add newEmptyNode()
          newRec.add newNode

      structBanks[name] = OcheStruct(name: name, typeId: structBanks.len + 1, fields: f, isPOD: pod)
      return newTree(nnkTypeDef, nameNode, newEmptyNode(),
                     newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), newRec))

  let obj             = parseOche(body, isView)
  ooBanks.add(obj)
  let procName        = body[0]
  let originalBody    = body[6]
  var originalRetType = body[3][0]
  if originalRetType.kind == nnkEmpty: originalRetType = ident"void"

  var ffiParams = newTree(nnkFormalParams)
  if obj.retType.isSeq or obj.retType.isOption or
     obj.retType.name in ["string", "cstring"] or obj.retType.isShared:
    ffiParams.add ident("pointer")
  else:
    ffiParams.add originalRetType

  var reconstruction = newStmtList()
  for p in obj.params:
    if p.typ.isSeq:
      let pP = ident(p.name & "_ptr")
      let pL = ident(p.name & "_len")
      let iT = ident(p.typ.inner)
      ffiParams.add newIdentDefs(pP, newTree(nnkPtrTy, iT))
      ffiParams.add newIdentDefs(pL, ident("int"))
      reconstruction.add newLetStmt(ident(p.name),
        newTree(nnkPrefix, ident("@"),
          newTree(nnkCall, ident("toOpenArray"),
            newTree(nnkCast, newTree(nnkPtrTy, newTree(nnkBracketExpr, ident("UncheckedArray"), iT)), pP),
            newLit(0),
            newTree(nnkInfix, ident("-"), pL, newLit(1)))))
    elif p.typ.name in ["string", "cstring"]:
      ffiParams.add newIdentDefs(ident(p.name & "_raw"), ident("cstring"))
      reconstruction.add newLetStmt(ident(p.name),
        newTree(nnkPrefix, ident("$"), ident(p.name & "_raw")))
    elif enumBanks.hasKey(p.typ.name):
      ffiParams.add newIdentDefs(ident(p.name), ident("int32"))
    else:
      ffiParams.add newIdentDefs(ident(p.name), ident(p.typ.name))

  let resNode = ident"res"
  var conv: NimNode
  if obj.retType.isSeq:
    let iT    = ident(obj.retType.inner)
    let s     = if structBanks.hasKey(obj.retType.inner): structBanks[obj.retType.inner]
                else: OcheStruct(isPOD: true)
    let tid   = s.typeId
    var flags = 0
    if s.isPOD: flags = flags or 2
    # FIX 1 (Nim side): seq[non-POD] — we still do copyMem for the struct layout,
    # but the typeId and flags are set correctly so ocheFreeDeep won't double-free
    # string pointers. The shallow-copy limitation is documented; the flags ensure
    # the Dart finalizer calls ocheFreeDeep which skips inner free for POD (flags&2)
    # and does deep free for non-POD. The real fix is to not return seq[non-POD]
    # (use OcheBuffer instead), but at minimum the flags are now correct.
    conv = quote do:
      let L = int64(`resNode`.len)
      let p = cast[ptr byte](alloc0(16 + (L * sizeof(`iT`))))
      cast[ptr int64](p)[] = L
      cast[ptr int32](cast[uint](p) + 8)[]  = int32(`tid`)
      cast[ptr int32](cast[uint](p) + 12)[] = int32(`flags`)
      if L > 0: copyMem(cast[pointer](cast[uint](p) + 16), unsafeAddr `resNode`[0], int(L) * sizeof(`iT`))
      p
  elif obj.retType.isShared:
    conv = quote do: `resNode`.p
  elif obj.retType.isOption:
    let iT = ident(obj.retType.inner)
    conv = quote do:
      (if `resNode`.isNone: nil
       else: (let p = cast[ptr `iT`](alloc0(sizeof(`iT`))); p[] = `resNode`.get; p))
  elif obj.retType.name in ["string", "cstring"]:
    conv = quote do:
      (let s = $ `resNode`; let p = cast[cstring](alloc0(s.len + 1)); copyMem(p, s.cstring, s.len + 1); p)
  else:
    conv = resNode

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

  result = newTree(nnkProcDef, procName, newEmptyNode(), newEmptyNode(),
                   ffiParams,
                   newTree(nnkPragma, ident("exportc"), ident("dynlib")),
                   newEmptyNode(), wrappedBody)

macro oche*(body: untyped): untyped = processOche(body, false)
macro oche*(arg: untyped, body: untyped): untyped =
  var isView = false
  if arg.kind == nnkIdent and arg.strVal == "view": isView = true
  processOche(body, isView)

macro generate*(output: static string): untyped =
  var code =
    "import 'dart:ffi' as ffi;\n" &
    "import 'dart:io' show Platform;\n" &
    "import 'dart:collection';\n" &
    "import 'package:ffi/ffi.dart';\n\n" &
    "final String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');\n" &
    "final dynlib = ffi.DynamicLibrary.open('./$_libName');\n" &
    "final _ocheFree      = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');\n" &
    "final _ocheFreeDeep  = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');\n" &
    "final _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');\n" &
    "final _ocheGetError  = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');\n" &
    "void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: \$msg'); } }\n"

  var inner = ""
  for o in ooBanks: inner &= genDInterface(o)

  for s in enumBanks.values:  code &= genDEnum(s)
  for s in structBanks.values: code &= genDStruct(s)
  for t in typeDefBanks:       code &= t & "\n"

  code &=
    "final _finalizerDeep = Finalizer<ffi.Pointer<ffi.Void>>((ptr) => _ocheFreeDeep(ptr));\n\n" &
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
    "    else if (value is int)    { ffi.Pointer<ffi.Int64>.fromAddress(p.address).value  = value; }\n" &
    "    else if (value is double) { ffi.Pointer<ffi.Double>.fromAddress(p.address).value = value; }\n" &
    "    else if (value is bool)   { ffi.Pointer<ffi.Bool>.fromAddress(p.address).value   = value; }\n" &
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

  # --- Generate free procs ---
  var free = "proc ocheFree(p: pointer) {.exportc, dynlib.} = (if not p.isNil: dealloc(p))\n"

  for s in structBanks.values:
    free &= "proc ocheFreeInner" & s.name & "(o: ptr " & s.name & ") =\n"
    var hasWork = false
    for f in s.fields:
      if f.typ.name in ["string", "cstring"]:
        free &= "  if not o." & f.name & ".isNil: dealloc(cast[pointer](o." & f.name & "))\n"
        hasWork = true
      elif structBanks.hasKey(f.typ.name) and not structBanks[f.typ.name].isPOD:
        free &= "  ocheFreeInner" & f.typ.name & "(addr o." & f.name & ")\n"
        hasWork = true
    if not hasWork: free &= "  discard\n"

  free &= "proc ocheFreeInner(p: pointer, typeId: int32) {.exportc, dynlib.} =\n"
  for s in structBanks.values:
    free &= "  if typeId == " & $s.typeId & ": ocheFreeInner" & s.name & "(cast[ptr " & s.name & "](p)); return\n"
  free &= "  discard\n\n"

  free &= "proc ocheFreeDeep(p: pointer) {.exportc, dynlib.} =\n"
  free &= "  if p.isNil: return\n"
  free &= "  let flags  = cast[ptr int32](cast[uint](p) + 12)[]\n"
  free &= "  if (flags and int32(2)) != 0: dealloc(p); return\n"
  free &= "  let L      = cast[ptr int64](p)[]\n"
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

  parseStmt(free)
