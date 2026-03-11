## Dart FFI emitter: genD* and type mapping for Dart.
import std/[sequtils, strutils, tables]
import oche_core

proc toNativeType*(t: string): string =
  case t
  of "int", "int64": return "ffi.Int64"
  of "float", "float64": return "ffi.Double"
  of "float32": return "ffi.Float"
  of "uint8": return "ffi.Uint8"
  of "bool": return "ffi.Bool"
  of "cstring", "string": return "ffi.Pointer<Utf8>"
  else:
    if enumBanks.hasKey(t): return "ffi.Int32"
    elif structBanks.hasKey(t): return "N" & t
    else: return "ffi.Void"

proc toDartType*(t: string): string =
  if t.startsWith("seq["): return "List<" & toDartType(t[4..^2]) & ">"
  if t.startsWith("OcheArray["):
    ## OcheArray in Dart = typed data view (Int64List, Float64List, etc.)
    let inner = t[10..^2]
    case inner
    of "int", "int64": return "typed_data.Int64List"
    of "float", "float64": return "typed_data.Float64List"
    of "float32": return "typed_data.Float32List"
    of "uint8": return "typed_data.Uint8List"
    else: return "List<" & toDartType(inner) & ">"
  if t.startsWith("OchePtr["):
    ## OchePtr in Dart = ffi.Pointer<T> — caller-owned native memory, true zero-copy
    let inner = t[8..^2]
    let nT = case inner
      of "int", "int64": "ffi.Int64"
      of "float", "float64": "ffi.Double"
      of "float32": "ffi.Float"
      of "uint8": "ffi.Uint8"
      of "int32": "ffi.Int32"
      else: "ffi.Void"
    return "ffi.Pointer<" & nT & ">"
  if t.startsWith("Option["): return toDartType(t[7..^2]) & "?"
  if t.startsWith("OcheBuffer["):
    let innerName = t[11..^2]
    let innerV = if structBanks.hasKey(innerName): innerName & "View" else: toDartType(innerName)
    return "SharedListView<" & innerV & ">"
  case t
  of "int", "int64", "uint8": return "int"
  of "float", "float64", "float32": return "double"
  of "bool": return "bool"
  of "cstring", "string": return "String"
  else: return t

proc genDEnum*(e: OcheEnum): string =
  var lines: seq[string] = @[]
  for v in e.values: lines.add "  " & v & ","
  result = "\nenum " & e.name & " {\n" & lines.join("\n") & "\n}\n"

proc genDStruct*(s: OcheStruct): string =
  var ffiFields, toFfi, fromFfi, dartFields, toFfiManual: seq[string]
  for f in s.fields:
    let nT = toNativeType(f.typ.name)
    let dT = toDartType(f.typ.name)
    if structBanks.hasKey(f.typ.name):
      ffiFields.add "  external N" & f.typ.name & " " & f.name & ";"
      toFfi.add "    this." & f.name & "._pack(target." & f.name & ", alloc);"
      toFfiManual.add "    this." & f.name & "._pack(target." & f.name & ", malloc);"
      fromFfi.add "    " & f.name & ": " & f.typ.name & "._unpack(source." & f.name & "),"
    elif f.typ.name in ["string", "cstring"]:
      ffiFields.add "  external ffi.Pointer<Utf8> " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ".toNativeUtf8(allocator: alloc);"
      toFfiManual.add "    target." & f.name & " = " & f.name & ".toNativeUtf8(allocator: malloc);"
      fromFfi.add "    " & f.name & ": (source." & f.name & ".address == 0) ? '' : source." & f.name & ".toDartString(),"
    elif enumBanks.hasKey(f.typ.name):
      ffiFields.add "  @ffi.Int32() external int " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ".index;"
      toFfiManual.add "    target." & f.name & " = " & f.name & ".index;"
      fromFfi.add "    " & f.name & ": " & f.typ.name & ".values[source." & f.name & "],"
    else:
      ffiFields.add "  @" & nT & "() external " & dT & " " & f.name & ";"
      toFfi.add "    target." & f.name & " = " & f.name & ";"
      toFfiManual.add "    target." & f.name & " = " & f.name & ";"
      fromFfi.add "    " & f.name & ": source." & f.name & ","
    dartFields.add "  final " & dT & " " & f.name & ";"

  let ffiStruct = "final class N" & s.name & " extends ffi.Struct {\n" & ffiFields.join("\n") & "\n}\n"
  var extType = "\nextension type " & s.name & "View(N" & s.name & " _ref) {\n"
  var packIntoLines: seq[string] = @[]
  for f in s.fields:
    let dT = toDartType(f.typ.name)
    if f.typ.name in ["string", "cstring"]:
      extType &= "  " & dT & " get " & f.name & " => (_ref." & f.name & ".address == 0) ? '' : _ref." & f.name & ".toDartString();\n"
      extType &= "  set " & f.name & "(String v) {\n"
      extType &= "    if (_ref." & f.name & ".address != 0) _ocheStrFree(_ref." & f.name & ".cast());\n"
      extType &= "    _ref." & f.name & " = v.isEmpty ? ffi.nullptr : _ocheStrAlloc(v.toNativeUtf8(allocator: malloc)).cast();\n"
      extType &= "  }\n"
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
  extType &= "  void _packInto(ffi.Pointer<N" & s.name & "> p) {\n" & packIntoLines.join("\n") & "\n  }\n"

  # User class: mutable fields, Dart-owned strings (no ocheStr* involved)
  var mutableFields: seq[string]
  for f in s.fields:
    let dT = toDartType(f.typ.name)
    mutableFields.add "  " & dT & " " & f.name & ";"
  let dartClass = "class " & s.name & " {\n" & mutableFields.join("\n") & "\n" &
                  "  " & s.name & "({\n" & s.fields.mapIt("    required this." & it.name).join(",\n") & "\n  });\n\n" &
                  "  void _pack(N" & s.name & " target, ffi.Allocator alloc) {\n" & toFfi.join("\n") & "\n  }\n\n" &
                  "  void _packManual(N" & s.name & " target) {\n" & toFfiManual.join("\n") & "\n  }\n\n" &
                  "  static " & s.name & " _unpack(N" & s.name & " source) {\n" &
                  "    return " & s.name & "(\n" & fromFfi.join("\n") & "\n    );\n  }\n" &
                  "}\n"

  # freeze() on XxxView: deep copy into a Dart-owned User
  var freezeLines: seq[string]
  for f in s.fields:
    if f.typ.name in ["string", "cstring"]:
      freezeLines.add "      " & f.name & ": (_ref." & f.name & ".address == 0) ? \'\' : _ref." & f.name & ".toDartString(),"
    elif structBanks.hasKey(f.typ.name):
      freezeLines.add "      " & f.name & ": " & f.typ.name & "View(_ref." & f.name & ").freeze(),"
    elif enumBanks.hasKey(f.typ.name):
      freezeLines.add "      " & f.name & ": " & f.typ.name & ".values[_ref." & f.name & "],"
    else:
      freezeLines.add "      " & f.name & ": _ref." & f.name & ","
  extType &= "  " & s.name & " freeze() => " & s.name & "(\n" & freezeLines.join("\n") & "\n    );\n}\n"

  result = ffiStruct & extType & "\n" & dartClass

proc genDInterface*(obj: OcheObject): string =
  let callName = "n" & obj.name & "Call"
  var nativeParams, dartFfiParams, wrapperParams, callArgs, prepWork: seq[string]
  var needsArena = false
  for p in obj.params:
    let dT = toDartType(p.typ.name)
    let pN = "v_" & p.name
    wrapperParams.add "final " & dT & " " & pN
    if p.typ.isSeq:
      needsArena = true
      let iI = p.typ.inner; let isC = structBanks.hasKey(iI)
      let nT = if isC: "N" & iI else: toNativeType(iI)
      let sz = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      prepWork.add "    final _" & pN & "Ptr = alloc.allocate<" & nT & ">(" & pN & ".length * " & sz & ");"
      if isC: prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { " & pN & "[i]._pack(_" & pN & "Ptr[i], alloc); }"
      elif enumBanks.hasKey(iI): prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i].index; }"
      else: prepWork.add "    for (var i = 0; i < " & pN & ".length; i++) { _" & pN & "Ptr[i] = " & pN & "[i]; }"
      callArgs.add "_" & pN & "Ptr, " & pN & ".length"
    elif p.typ.isArray:
      # OcheArray in Dart: Dart VM GC may move managed TypedData, so true zero-copy
      # into VM heap is unsafe. Instead we accept a malloc-pinned buffer (NativeArray<T>)
      # OR a TypedData — TypedData gets a single fast C-level memcpy before the call.
      needsArena = true
      let iI = p.typ.inner
      let nT = toNativeType(iI)
      let sz = "ffi.sizeOf<" & nT & ">()"
      let dartTypedListType = case iI
        of "int", "int64": "typed_data.Int64List"
        of "float", "float64": "typed_data.Float64List"
        of "float32": "typed_data.Float32List"
        of "uint8": "typed_data.Uint8List"
        of "int32": "typed_data.Int32List"
        of "uint16": "typed_data.Uint16List"
        of "uint32": "typed_data.Uint32List"
        else: "typed_data.ByteBuffer"
      wrapperParams[wrapperParams.len - 1] = "final " & dartTypedListType & " " & pN
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      # Fast path: single memcpy via allocate + setAll (C-level, avoids Dart loop)
      prepWork.add "    final _" & pN & "Ptr = alloc.allocate<" & nT & ">(" & pN & ".length * " & sz & ");"
      prepWork.add "    _" & pN & "Ptr.asTypedList(" & pN & ".length).setAll(0, " & pN & ");"
      callArgs.add "_" & pN & "Ptr, " & pN & ".length"
    elif p.typ.isPtr:
      # OchePtr in Dart: TRUE zero-copy — caller passes ffi.Pointer<T> directly.
      # Memory must live outside Dart VM heap (allocated via calloc/malloc).
      # No arena, no memcpy, no allocation — pointer goes straight to Nim.
      let iI = p.typ.inner
      let nT = toNativeType(iI)
      wrapperParams[wrapperParams.len - 1] = "final ffi.Pointer<" & nT & "> " & pN & ", final int " & pN & "_len"
      nativeParams.add "ffi.Pointer<" & nT & ">, ffi.Int64"
      dartFfiParams.add "ffi.Pointer<" & nT & ">, int"
      callArgs.add pN & ", " & pN & "_len"
    elif p.typ.isShared:
      # OcheBuffer[T] as input — wire: single void* (the buffer header pointer already in Nim RAM)
      # Dart passes the _nativePtr of a SharedListView directly — no copy, no arena.
      let iI = p.typ.inner
      let innerV = if structBanks.hasKey(iI): iI & "View" else: toDartType(iI)
      wrapperParams[wrapperParams.len - 1] = "final SharedListView<" & innerV & "> " & pN
      nativeParams.add "ffi.Pointer<ffi.Void>"
      dartFfiParams.add "ffi.Pointer<ffi.Void>"
      callArgs.add pN & "._nativePtr"
    elif structBanks.hasKey(p.typ.name):
      needsArena = true
      nativeParams.add "ffi.Pointer<N" & p.typ.name & ">"
      dartFfiParams.add "ffi.Pointer<N" & p.typ.name & ">"
      # accept both User and UserView — override param type to dynamic
      wrapperParams[wrapperParams.len - 1] = "final dynamic " & pN
      prepWork.add "    final _" & pN & "Ptr = alloc.allocate<N" & p.typ.name & ">(ffi.sizeOf<N" & p.typ.name & ">());"
      prepWork.add "    if (" & pN & " is " & p.typ.name & "View) { " & pN & "._packInto(_" & pN & "Ptr); } else { (" & pN & " as " & p.typ.name & ")._pack(_" & pN & "Ptr.ref, alloc); }"
      callArgs.add "_" & pN & "Ptr"
    else:
      let nT = toNativeType(p.typ.name)
      nativeParams.add nT
      dartFfiParams.add (if enumBanks.hasKey(p.typ.name): "int" elif nT.contains("Int") or nT.contains("Double") or nT.contains("Bool"): toDartType(p.typ.name) else: nT)
      if p.typ.name in ["string", "cstring"]:
         needsArena = true
         callArgs.add pN & ".toNativeUtf8(allocator: alloc)"
      elif enumBanks.hasKey(p.typ.name): callArgs.add pN & ".index"
      else: callArgs.add pN

  let sR = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"] or obj.retType.isShared or structBanks.hasKey(obj.retType.name)
  let nR = if sR: (if structBanks.hasKey(obj.retType.name): "ffi.Pointer<N" & obj.retType.name & ">" else: "ffi.Pointer<ffi.Void>") else: toNativeType(obj.retType.name)
  let dT_ret = toDartType(obj.retType.name)
  let isVoid = obj.retType.name == "void" or obj.retType.name == ""

  var actualRetType = dT_ret
  if isVoid: actualRetType = "void"
  elif obj.retType.isShared:
    let innerName = obj.retType.inner
    let innerV = if structBanks.hasKey(innerName): innerName & "View" else: toDartType(innerName)
    actualRetType = "SharedListView<" & innerV & ">"
  elif obj.isView:
    if obj.retType.isSeq:
      let innerName = obj.retType.inner
      let innerV = if structBanks.hasKey(innerName): innerName & "View" else: toDartType(innerName)
      actualRetType = "NativeListView<" & innerV & ">"
    elif structBanks.hasKey(obj.retType.name):
      # single struct {.view.} is meaningless — Nim returns by value (stack copy)
      # so there's no persistent buffer to borrow from. Fall back to copy mode silently.
      discard  # actualRetType stays as dT_ret = "User"
  # copy mode single struct: actualRetType stays as dT_ret = "User" (Dart class)

  let dR = if sR: nR else: (if isVoid: "void" elif enumBanks.hasKey(obj.retType.name): "int" else: (if nR.contains("Int") or nR.contains("Double") or nR.contains("Bool"): dT_ret else: nR))

  var body: string
  if obj.retType.isShared:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI); let nT = if isC: "N" & iI else: toNativeType(iI)
    let sz = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
    let packerBody =
      if isC:
        let innerStruct = structBanks[iI]
        let freeCall = if not innerStruct.isPOD: "_ocheFreeInner(p, " & $innerStruct.typeId & "); " else: ""
        "if (v is " & iI & ") { " & freeCall & "v._packManual(p.cast<N" & iI & ">().ref); } " &
        "else if (v is " & iI & "View) { v._packInto(p.cast<N" & iI & ">()); }"
      else:
        "p.cast<" & nT & ">().value = v as " & toDartType(iI) & ";"
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      return SharedListView<" & (if isC: iI & "View" else: toDartType(iI)) & ">(p, (ptr) => " & (if isC: iI & "View(ptr.cast<N" & iI & ">().ref)" else: "ptr.cast<" & nT & ">().value") & ", (p, v) { " & packerBody & " }, " & sz & ");"
  elif obj.retType.isSeq:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI); let nT = if isC: "N" & iI else: toNativeType(iI)
    if obj.isView:
      let sz = if isC: "ffi.sizeOf<N" & iI & ">()" else: "ffi.sizeOf<" & nT & ">()"
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      return NativeListView<" & (if isC: iI & "View" else: toDartType(iI)) & ">(p, (ptr) => " & (if isC: iI & "View(ptr.cast<N" & iI & ">().ref)" else: "ptr.cast<" & nT & ">().value") & ", " & sz & ");"
    else:
      body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
             "      if (p.address == 0) return []; try {\n" &
             "        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<" & nT & ">.fromAddress(p.address + 16);\n" &
             (if isC: "        return List<" & iI & ">.generate(L, (i) => " & iI & "._unpack(d[i]));" else: "        return d.asTypedList(L).toList();") & "\n" &
             "      } finally { _ocheFreeDeep(p); }"
  elif obj.retType.isOption:
    let iI = obj.retType.inner; let isC = structBanks.hasKey(iI); let nTI = if isC: "N" & iI else: toNativeType(iI)
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
  elif structBanks.hasKey(obj.retType.name):
    let sn = obj.retType.name
    # copy mode: _unpack into Dart-owned User, then free Nim allocation
    body = "      final p = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      try { return " & sn & "._unpack(p.ref); } finally { _ocheFree(p); }"
  elif isVoid:
    body = "      " & callName & "(" & callArgs.join(", ") & "); _checkError();"
  else:
    body = "      final r = " & callName & "(" & callArgs.join(", ") & "); _checkError();\n" &
           "      return " & (if enumBanks.hasKey(obj.retType.name): dT_ret & ".values[r];" else: "r;")

  typeDefBanks.add "typedef N" & obj.name & "N = " & nR & " Function(" & nativeParams.join(", ") & ");"
  typeDefBanks.add "typedef N" & obj.name & "D = " & dR & " Function(" & dartFfiParams.join(", ") & ");"

  let finalBody = if needsArena:
      # has arena allocations — wrap everything in using()
      "    return using((alloc) {\n" & prepWork.join("\n") & "\n" & body & "\n    });"
    elif prepWork.len > 0:
      # has prepWork (e.g. OcheArray pointer setup) but no arena needed
      "    " & prepWork.join("\n    ") & "\n" & body
    else: body

  result = "  late final " & callName & " = dynlib.lookupFunction<N" & obj.name & "N, N" & obj.name & "D>('" & obj.name & "');\n\n" &
           "  " & actualRetType & " " & obj.name & "(" & wrapperParams.join(", ") & ") {\n" & finalBody & "\n  }\n"