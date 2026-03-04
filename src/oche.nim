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
  ## Nim type → C FFI type (used in the Native typedef)
  case t
  of "int":             "ffi.Int64"
  of "int8":            "ffi.Int8"
  of "int16":           "ffi.Int16"
  of "int32":           "ffi.Int32"
  of "int64":           "ffi.Int64"
  of "uint", "uint64":  "ffi.Uint64"
  of "uint8":           "ffi.Uint8"
  of "uint16":          "ffi.Uint16"
  of "uint32":          "ffi.Uint32"
  of "float", "float64":"ffi.Double"
  of "float32":         "ffi.Float"
  of "bool":            "ffi.Bool"
  of "cstring", "string": "ffi.Pointer<Utf8>"
  of "void", "":        "ffi.Void"
  else:                 "ffi.Void"

proc toDartFfi(t: string): string =
  ## Nim type → Dart FFI type used inside the Dart typedef.
  ## Dart FFI requires Dart-native scalar types (int/double/bool) here,
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

proc toFfiArg(name, typ: string): string =
  ## Converts a user-facing Dart argument to the raw FFI value the native fn expects
  case typ
  of "cstring", "string": fmt"{name}.toNativeUtf8()"
  else:                   name

proc wrapReturn(call, retType: string): string =
  ## Wraps the raw FFI call into a user-friendly Dart return statement
  case retType
  of "cstring", "string": fmt"return {call}.toDartString();"
  of "void", "":          fmt"{call};"
  else:                   fmt"return {call};"

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

    # Native typedef — raw C types (ffi.Int64, ffi.Double, ffi.Bool, ...)
    nativeParams   = obj.params.mapIt(toNativeFfi(it.typ)).join(", ")
    # Dart typedef  — Dart-compatible FFI types (int, double, bool, Pointer<Utf8>)
    dartFfiParams  = obj.params.mapIt(toDartFfi(it.typ)).join(", ")

    # wrapper function: user-friendly param list ("int x, String s, ...")
    wrapperParams  = obj.params.mapIt(fmt"{toDart(it.typ)} {it.name}").join(", ")

    # args forwarded to the underlying FFI call (with conversions where needed)
    callArgs = obj.params.mapIt(toFfiArg(it.name, it.typ)).join(", ")

  let
    call = fmt"{callName}({callArgs})"
    body = wrapReturn(call, obj.retType)

  fmt"""
  // --- {obj.name} ---
  typedef {nativeName} = {nativeRetType} Function({nativeParams});
  typedef {dartName} = {dartFfiRetType} Function({dartFfiParams});
  final {callName} = dynlib.lookupFunction<{nativeName}, {dartName}>('{obj.name}');
  {dartRetType} {obj.name}({wrapperParams}) {{
    {body}
  }}
"""

macro generate*(output: varargs[untyped]): untyped =
  let
    info    = output[0].lineInfoObj
    libname = "lib" & info.filename.splitFile.name & ".so"

  var code = fmt"""import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

final dynlib = ffi.DynamicLibrary.open('./{libname}');
"""
  for obj in ooBanks:
    code &= genDInterface(obj)

  writeFile(output[0].strVal, code)