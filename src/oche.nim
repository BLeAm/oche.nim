import std/[
  macros, 
  os,
  strutils,
  strformat
]

type
  OcheParam = object
    name:string
    typ: string
  OcheObject = object
    name:string
    retType: string
    params: seq[OcheParam]

var ooBanks {.compileTime.}:seq[OcheObject] = @[]

proc parseOche(body: NimNode): OcheObject = 
  var ocheObject: OcheObject
  ocheObject.name = body[0].strVal
  ocheObject.retType = body[3][0].strVal
  for i in 1..body[3].len-1:
    var node = body[3][i]
    if node.kind != nnkIdentDefs:
      continue
    var typ = node[^2].strVal
    for n in node[0..<node.len-2]:
      ocheObject.params.add(OcheParam(name:n.strVal, typ:typ))

  ocheObject  

macro oche*(body: untyped): untyped = 
  body[4] = nnkPragma.newTree(
    ident("exportc"),
    ident("dynlib")
  )
  ooBanks.add(parseOche(body))
  echo body.repr
  body

proc genDInterace(obj: OcheObject): string = 
  let
    capName = block:
      var res = obj.name
      res[0] = res[0].toUpperAscii
      res
    nativeName = "N" & capName & "Native"
    dartName = "N" & capName & "Dart"
    callName = "n" & obj.name & "Call"

    nativeRetType = case obj.retType:
      of "int": "ffi.Int32"
      of "string": "ffi.Pointer<Utf8>"
      else: "ffi.Void"
    dartRetType = case obj.retType:
      of "int": "int"
      of "string": "String"
      else: "void"
    
    callRetType = case obj.retType:
      of "int": "int"
      of "string": "String"
      else: "void"
    
    nativeParams = block:
      var res = ""
      for param in obj.params:
        case param.typ:
          of "int": res &= "ffi.Int32, "
          of "string": res &= "ffi.Pointer<Utf8>, "
          else: res &= "ffi.Void, "
      res
    
    callBody = block:
      var res = ""
      for param in obj.params:
        res &= fmt"{param.name}, "
      res = fmt"return {callName}({res});"
      res

    dartParams = block:
      var res = ""
      for param in obj.params:
        case param.typ:
          of "int": res &= "int, "
          of "string": res &= "String, "
          else: res &= "void, "
      res
    
    dartCallParams = block:
      var res = ""
      for param in obj.params:
        case param.typ:
          of "int": res &= "int, "
          of "string": res &= "String, "
          else: res &= "void, "
      res 
    
    nativeCallParams = block:
      var res = ""
      for param in obj.params:
        case param.typ:
          of "int": res &= fmt"int {param.name}, "
          of "string": res &= fmt"String {param.name}, "
          else: res &= fmt"void {param.name}, "
      res 
  var 
    code = ""
  
  code &= fmt"""
  typedef {nativeName} = {nativeRetType} Function({nativeParams});
  typedef {dartName} = {dartRetType} Function({dartParams});
  final {callName} = dynlib.lookupFunction<{nativeName}, {dartName}>("{obj.name}");
  {callRetType} {obj.name}({nativeCallParams}) {{
    {callBody}
  }}
  """
  code

macro generate*(output: string): untyped = 
  let
    info = lineInfoObj(callsite())
    libname = "lib" & info.filename.splitFile.name & ".so"
  
  var
    code = fmt"""
    import 'dart:ffi' as ffi;
    import 'package:ffi/ffi.dart';

    final dynlib = ffi.DynamicLibrary.open("./{libname}");
    """
  for obj in ooBanks:
    code &= genDInterace(obj)

  writeFile(output.strVal, code)