## Python ctypes emitter: genP* and type mapping. Supports seq/Option/OcheBuffer, structs, memoryview/numpy.
import std/[sequtils, strutils, tables]
import oche_core

proc toCType*(t: string): string =
  case t
  of "int", "int64": return "c_int64"
  of "float", "float64": return "c_double"
  of "float32": return "c_float"
  of "uint8": return "c_uint8"
  of "bool": return "c_bool"
  of "cstring", "string": return "c_void_p"
  else:
    if enumBanks.hasKey(t): return "c_int32"
    elif structBanks.hasKey(t): return "c_void_p"
    else: return "c_void_p"

proc toPythonType*(t: string): string =
  if t.startsWith("seq["): return "List[Any]"
  if t.startsWith("Option["): return "Optional[" & toPythonType(t[7..^2]) & "]"
  if t.startsWith("OcheBuffer["): return "List[Any]"
  case t
  of "int", "int64", "uint8": return "int"
  of "float", "float64", "float32": return "float"
  of "bool": return "bool"
  of "cstring", "string": return "str"
  of "void", "": return "None"
  else: return "Any"

proc toPythonReturnType*(obj: OcheObject): string =
  if obj.retType.name in ["void", ""]: return "None"
  if obj.retType.name in ["string", "cstring"]: return "str"
  if obj.retType.isOption: return "Optional[" & toPythonType(obj.retType.inner) & "]"
  if obj.retType.isSeq or obj.retType.isShared: return "List[Any]"
  if structBanks.hasKey(obj.retType.name): return "Any"
  if enumBanks.hasKey(obj.retType.name): return "int"
  return toPythonType(obj.retType.name)

proc elemSizeAndDtype(inner: string): (string, string) =
  if structBanks.hasKey(inner): return ("_struct_size('" & inner & "')", "None")
  case inner
  of "int", "int64": return ("ctypes.sizeof(ctypes.c_int64)", "'i8'")
  of "float", "float64": return ("ctypes.sizeof(ctypes.c_double)", "'f8'")
  of "float32": return ("ctypes.sizeof(ctypes.c_float)", "'f4'")
  of "uint8": return ("ctypes.sizeof(ctypes.c_uint8)", "'u1'")
  of "bool": return ("ctypes.sizeof(ctypes.c_bool)", "'?'")
  else:
    if enumBanks.hasKey(inner): return ("ctypes.sizeof(ctypes.c_int32)", "'i4'")
    return ("1", "'u1'")

proc genPStruct*(s: OcheStruct): string =
  result = "class " & s.name & "_t(ctypes.Structure):\n"
  result &= "  _fields_ = [\n"
  for f in s.fields:
    let cT = toCType(f.typ.name)
    let cTFull = "ctypes." & cT
    if f.typ.name in ["string", "cstring"]: result &= "    ('" & f.name & "', ctypes.c_void_p),\n"
    elif structBanks.hasKey(f.typ.name): result &= "    ('" & f.name & "', ctypes.c_void_p),\n"
    else: result &= "    ('" & f.name & "', " & cTFull & "),\n"
  result &= "  ]\n"
  result &= "_struct_size_cache['" & s.name & "'] = ctypes.sizeof(" & s.name & "_t)\n"
  result &= "_struct_types['" & s.name & "'] = " & s.name & "_t\n\n"

proc genPEnum*(e: OcheEnum): string =
  result = "class " & e.name & ":\n"
  for i, v in e.values:
    result &= "  " & v & " = " & $i & "\n"
  result &= "\n"

proc genPInterface*(obj: OcheObject): string =
  let callName = "_" & obj.name
  var cParams, pyArgList: seq[string]
  for p in obj.params:
    if p.typ.isSeq:
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p" else: "ctypes." & toCType(inner)
      cParams.add "ctypes.POINTER(" & cT & ")"
      cParams.add "ctypes.c_int64"
      pyArgList.add p.name & "_arr"
      pyArgList.add "len(" & p.name & ")"
    elif p.typ.name in ["string", "cstring"]:
      cParams.add "ctypes.c_char_p"
      pyArgList.add p.name & ".encode('utf-8') if " & p.name & " else None"
    elif enumBanks.hasKey(p.typ.name):
      cParams.add "ctypes.c_int32"
      pyArgList.add "int(" & p.name & ")"
    elif structBanks.hasKey(p.typ.name):
      cParams.add "ctypes.c_void_p"
      pyArgList.add "ctypes.byref(" & p.name & "_buf) if " & p.name & "_buf is not None else None"
    else:
      cParams.add "ctypes." & toCType(p.typ.name)
      pyArgList.add p.name

  let sR = obj.retType.isSeq or obj.retType.isOption or obj.retType.name in ["string", "cstring"] or obj.retType.isShared
  let cRet = if sR: "ctypes.c_void_p" elif obj.retType.name in ["void", ""]: "None" else: "ctypes." & toCType(obj.retType.name)
  let setRestype = if cRet == "None": "None" else: cRet

  result = "  " & callName & " = _lib." & obj.name & "\n"
  result &= "  " & callName & ".argtypes = [" & cParams.join(", ") & "]\n"
  result &= "  " & callName & ".restype = " & setRestype & "\n"
  let retHint = toPythonReturnType(obj)
  result &= "  def " & obj.name & "(self, " & obj.params.mapIt(it.name & ": " & toPythonType(it.typ.name)).join(", ") & ") -> " & retHint & ":\n"

  for p in obj.params:
    if p.typ.isSeq:
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p" else: "ctypes." & toCType(inner)
      result &= "    " & p.name & "_arr = (" & cT & " * len(" & p.name & "))(); "
      result &= "for i, x in enumerate(" & p.name & "): " & p.name & "_arr[i] = x\n"
    elif structBanks.hasKey(p.typ.name):
      result &= "    " & p.name & "_buf = _pack_struct('" & p.typ.name & "', " & p.name & ") if " & p.name & " is not None else None\n"

  result &= "    r = self." & callName & "(" & pyArgList.join(", ") & ")\n"
  result &= "    _check_error()\n"

  if obj.retType.name in ["void", ""]: result &= "    return None\n"
  elif obj.retType.name in ["string", "cstring"]:
    result &= "    if r is None: return ''\n"
    result &= "    s = ctypes.string_at(r).decode('utf-8'); _lib.ocheFree(r); return s\n"
  elif obj.retType.isSeq:
    let inner = obj.retType.inner
    let (sz, dtype) = elemSizeAndDtype(inner)
    let isStruct = structBanks.hasKey(inner)
    result &= "    if r is None: return []\n"
    result &= "    n = ctypes.cast(r, ctypes.POINTER(ctypes.c_int64)).contents.value\n"
    result &= "    if n <= 0: _lib.ocheFreeDeep(r); return []\n"
    if isStruct:
      result &= "    out = [_unpack_struct('" & inner & "', r, 16, " & sz & ", i) for i in range(n)]\n"
      result &= "    _lib.ocheFreeDeep(r); return out\n"
    else:
      result &= "    data_addr = ctypes.cast(r, ctypes.c_void_p).value + 16\n"
      result &= "    try:\n"
      result &= "      import numpy as np\n"
      result &= "      arr = np.frombuffer((ctypes.c_char * (n * " & sz & ")).from_address(data_addr), dtype=" & dtype & ", count=n).copy()\n"
      result &= "      _lib.ocheFreeDeep(r); return arr\n"
      result &= "    except ImportError:\n"
      result &= "      arr = [ctypes.cast(data_addr + i * " & sz & ", ctypes.POINTER(" & toCType(inner) & ")).contents.value for i in range(n)]\n"
      result &= "      _lib.ocheFreeDeep(r); return arr\n"
      result &= "    except Exception:\n"
      result &= "      _lib.ocheFreeDeep(r); raise\n"
  elif obj.retType.isOption:
    let inner = obj.retType.inner
    let isStruct = structBanks.hasKey(inner)
    result &= "    if r is None: return None\n"
    if isStruct:
      result &= "    sz = _struct_size('" & inner & "')\n"
      result &= "    out = _unpack_struct('" & inner & "', r, 0, sz, 0); _lib.ocheFree(r); return out\n"
    else:
      result &= "    out = ctypes.cast(r, ctypes.POINTER(" & toCType(inner) & ")).contents.value\n"
      result &= "    _lib.ocheFree(r); return out\n"
  elif obj.retType.isShared:
    let inner = obj.retType.inner
    let (sz, dtype) = elemSizeAndDtype(inner)
    let isStruct = structBanks.hasKey(inner)
    result &= "    if r is None: return []\n"
    result &= "    n = ctypes.cast(r, ctypes.POINTER(ctypes.c_int64)).contents.value\n"
    result &= "    if n <= 0: return []\n"
    if isStruct:
      result &= "    return _SharedView(r, n, " & sz & ", '" & inner & "', None)\n"
    else:
      result &= "    data_addr = ctypes.cast(r, ctypes.c_void_p).value + 16\n"
      result &= "    try:\n"
      result &= "      import numpy as np\n"
      result &= "      return np.frombuffer((ctypes.c_char * (n * " & sz & ")).from_address(data_addr), dtype=" & dtype & ", count=n)\n"
      result &= "    except ImportError:\n"
      result &= "      return _SharedView(r, n, " & sz & ", None, None, '" & toCType(inner) & "')\n"
  elif structBanks.hasKey(obj.retType.name):
    result &= "    if r is None: return None\n"
    result &= "    sz = _struct_size('" & obj.retType.name & "')\n"
    result &= "    return _unpack_struct('" & obj.retType.name & "', r, 0, sz, 0)\n"
  elif enumBanks.hasKey(obj.retType.name):
    result &= "    return r\n"
  else:
    result &= "    return r\n"
  result &= "\n"

proc genPythonPrelude*(): string =
  result = """
try:
  import numpy as np
  _HAS_NUMPY = True
except ImportError:
  _HAS_NUMPY = False

_struct_size_cache = {}
_struct_types = {}
def _struct_size(name):
  return _struct_size_cache.get(name, 8)

def _pack_struct(name, obj):
  if obj is None: return None
  t = _struct_types[name]
  if hasattr(obj, '_as_buffer'): return obj
  buf = t()
  for (k, v) in (obj.items() if hasattr(obj, 'items') else obj):
    setattr(buf, k, v)
  return buf

def _unpack_struct(name, ptr, offset, elem_size, index):
  t = _struct_types[name]
  p = ctypes.cast(ctypes.c_void_p(ctypes.addressof(ctypes.cast(ptr, ctypes.POINTER(ctypes.c_char)).contents) + offset + index * elem_size), ctypes.POINTER(t))
  return _struct_from_ctypes(name, p.contents)

def _struct_from_ctypes(name, c):
  d = {}
  for (fname, _) in c._fields_:
    d[fname] = getattr(c, fname)
  return d

class _SharedView:
  def __init__(self, ptr, n, elem_size, struct_name, free_fn, elem_ctype=None):
    self._ptr = ptr
    self._n = n
    self._elem_size = elem_size
    self._struct_name = struct_name
    self._free_fn = free_fn
    self._elem_ctype = getattr(ctypes, elem_ctype) if isinstance(elem_ctype, str) else elem_ctype
  def __len__(self): return self._n
  def __getitem__(self, i):
    if self._struct_name:
      return _unpack_struct(self._struct_name, self._ptr, 16, self._elem_size, i)
    addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16 + i * self._elem_size
    return ctypes.cast(addr, ctypes.POINTER(self._elem_ctype)).contents.value
  def __del__(self):
    if self._ptr is not None and self._free_fn: self._free_fn(self._ptr)
"""
