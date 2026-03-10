## Core IR and parsing shared by Dart and Python emitters.
import std/[macros, tables]

type
  OcheType* = object
    name*:  string
    isSeq*: bool
    isOption*: bool
    isShared*: bool
    isArray*: bool   ## OcheArray[T] — zero-copy view, caller owns buffer, Dart uses memcpy
    isPtr*:  bool    ## OchePtr[T]   — true zero-copy raw pointer, caller manages lifetime
    inner*: string
  OcheField* = object
    name*: string
    typ*:  OcheType
  OcheStruct* = object
    name*:   string
    typeId*: int
    fields*: seq[OcheField]
    isPOD*:  bool
  OcheEnum* = object
    name*:   string
    values*: seq[string]
  OcheParam* = object
    name*: string
    typ*:  OcheType
  OcheObject* = object
    name*:    string
    retType*: OcheType
    params*:  seq[OcheParam]
    isView*:  bool
  Backend* = enum
    bDart
    bPython

var ooBanks* {.compileTime.}: seq[OcheObject] = @[]
var ooBanksPython* {.compileTime.}: seq[OcheObject] = @[]
var structBanks* {.compileTime.}: Table[string, OcheStruct]
var enumBanks* {.compileTime.}: Table[string, OcheEnum]
var typeDefBanks* {.compileTime.}: seq[string] = @[]

proc parseType*(node: NimNode): OcheType =
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
    elif base == "OcheArray":
      return OcheType(name: node.repr, isArray: true, inner: node[1].repr)
    elif base == "OchePtr":
      return OcheType(name: node.repr, isPtr: true, inner: node[1].repr)
    return OcheType(name: node.repr)
  else:
    return OcheType(name: node.repr)

proc parseOche*(body: NimNode, isView: bool): OcheObject =
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
