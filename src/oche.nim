import std/[
  macros,
  os,
  strutils,
  strformat,
  sequtils
]

type
  OcheParam = object
    name: string
    typ:  string
  OcheObject = object
    name:    string
    retType: string
    params:  seq[OcheParam]

var ooBanks {.compileTime.}: seq[OcheObject] = @[]

proc parseOche(body: NimNode): OcheObject =
  var o: OcheObject
  o.name    = body[0].strVal
  o.retType = body[3][0].strVal
  for i in 1 ..< body[3].len:
    let node = body[3][i]
    if node.kind != nnkIdentDefs: continue
    let typ = node[^2].strVal
    for n in node[0 ..< node.len - 2]:
      o.params.add OcheParam(name: n.strVal, typ: typ)
  o

macro oche*(body: untyped): untyped =
  body[4] = nnkPragma.newTree(
    ident("exportc"),
    ident("dynlib")
  )
  ooBanks.add(parseOche(body))
  body

# ─── Type Mapping ─────────────────────────────────────────────────────────────

proc toNativeFfi(t: string): string =
  ## Nim type → raw C FFI type (used in the Native typedef)
  case t
  of "int":               "ffi.Int64"
  of "int8":              "ffi.Int8"
  of "int16":             "ffi.Int16"
  of "int32":             "ffi.Int32"
  of "int64":             "ffi.Int64"
  of "uint", "uint64":    "ffi.Uint64"
  of "uint8":             "ffi.Uint8"
  of "uint16":            "ffi.Uint16"
  of "uint32":            "ffi.Uint32"
  of "float", "float64":  "ffi.Double"
  of "float32":           "ffi.Float"
  of "bool":              "ffi.Bool"
  of "cstring", "string": "ffi.Pointer<Utf8>"
  of "void", "":          "ffi.Void"
  else:                   "ffi.Void"

proc toDartFfi(t: string): string =
  ## Nim type → Dart-compatible FFI type (used in the Dart typedef).
  ## Dart FFI requires scalar Dart types here (int/double/bool),
  ## but Pointer types stay as-is.
  case t
  of "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64": "int"
  of "float", "float64", "float32": "double"
  of "bool":              "bool"
  of "cstring", "string": "ffi.Pointer<Utf8>"
  of "void", "":          "void"
  else:                   "void"

proc toDart(t: string): string =
  ## Nim type → user-facing Dart type (wrapper function signatures)
  case t
  of "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64": "int"
  of "float", "float64", "float32": "double"
  of "bool":              "bool"
  of "cstring", "string": "String"
  of "void", "":          "void"
  else:                   "void"

proc isStringType(t: string): bool =
  t in ["string", "cstring"]

proc toFfiArg(name, typ: string): string =
  ## Converts a wrapper arg to what the FFI call expects.
  ## String args get .toNativeUtf8(allocator: arena) — requires a
  ## surrounding using() block in the generated code.
  if isStringType(typ): fmt"{name}.toNativeUtf8(allocator: arena)"
  else: name

# ─── Code Generation ──────────────────────────────────────────────────────────

proc genDInterface(obj: OcheObject): string =
  let
    capName    = obj.name[0].toUpperAscii & obj.name[1 .. ^1]
    nativeName = "N" & capName & "Native"
    dartName   = "N" & capName & "Dart"
    callName   = "n" & obj.name & "Call"

    nativeRetType  = toNativeFfi(obj.retType)
    dartFfiRetType = toDartFfi(obj.retType)
    dartRetType    = toDart(obj.retType)

    # Native typedef: raw C types
    nativeParams  = obj.params.mapIt(toNativeFfi(it.typ)).join(", ")
    # Dart typedef: Dart-native scalar types (int/double/bool/Pointer)
    dartFfiParams = obj.params.mapIt(toDartFfi(it.typ)).join(", ")
    # Wrapper signature: user-friendly types (int/double/bool/String)
    wrapperParams = obj.params.mapIt(fmt"{toDart(it.typ)} {it.name}").join(", ")

    hasStringParam  = obj.params.anyIt(isStringType(it.typ))
    hasStringReturn = isStringType(obj.retType)
    isVoidReturn    = obj.retType in ["void", ""]

    callArgs = obj.params.mapIt(toFfiArg(it.name, it.typ)).join(", ")
    rawCall  = fmt"{callName}({callArgs})"

  # ── Build the inner body lines (go inside function or using-block) ──────────
  var inner: seq[string]
  if hasStringReturn:
    # Get the raw pointer, copy to Dart string, then free the Nim allocation
    inner.add fmt"final _ret = {rawCall};"
    inner.add "final _dartStr = _ret.toDartString();"
    inner.add "_ocheFreeCString(_ret);"
    inner.add "return _dartStr;"
  elif isVoidReturn:
    inner.add fmt"{rawCall};"
  else:
    inner.add fmt"return {rawCall};"

  # ── Assemble the full function ──────────────────────────────────────────────
  var lines: seq[string]
  lines.add fmt"  // --- {obj.name} ---"
  lines.add fmt"  typedef {nativeName} = {nativeRetType} Function({nativeParams});"
  lines.add fmt"  typedef {dartName} = {dartFfiRetType} Function({dartFfiParams});"
  lines.add fmt"  final {callName} = dynlib.lookupFunction<{nativeName}, {dartName}>('{obj.name}');"
  lines.add fmt"  {dartRetType} {obj.name}({wrapperParams}) {{"

  if hasStringParam:
    # Wrap in using() so the Arena frees toNativeUtf8() allocations on exit
    let retKw = if isVoidReturn and not hasStringReturn: "" else: "return "
    lines.add fmt"    {retKw}using((arena) {{"
    for ln in inner:
      lines.add "      " & ln          # 6 spaces inside using block
    lines.add "    });"
  else:
    for ln in inner:
      lines.add "    " & ln            # 4 spaces inside plain function body

  lines.add "  }"
  lines.add ""
  lines.join("\n")

macro generate*(output: varargs[untyped]): untyped =
  let
    info    = output[0].lineInfoObj
    libname = "lib" & info.filename.splitFile.name & ".so"

  var code = fmt"""import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

final dynlib = ffi.DynamicLibrary.open('./{libname}');

// --- Memory: free Nim-allocated C strings ---
typedef _OcheFreeCStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _OcheFreeCStringDart = void Function(ffi.Pointer<Utf8>);
final _ocheFreeCString = dynlib.lookupFunction<_OcheFreeCStringNative, _OcheFreeCStringDart>('ocheFreeCString');

"""
  for obj in ooBanks:
    code &= genDInterface(obj)

  writeFile(output[0].strVal, code)

  # Auto-inject ocheFreeCString into the compiled shared library.
  # Users don't need to write this themselves.
  result = quote do:
    proc ocheFreeCString(p: pointer) {.exportc, dynlib.} =
      if not p.isNil:
        dealloc(p)