## Python ctypes emitter for Porche.
## Supports all 3 Oche modes with correct semantics:
##   Copy  (seq[T])          → returns List[dict]  — deep copy, Python owns
##   View  (seq[T] {.view.}) → returns NativeListView[XxxView]  — zero-copy, read-only, Nim owns
##   Share (OcheBuffer[T])   → returns SharedListView[XxxView]  — zero-copy, read-write, Nim owns
##
## XxxView is a generated per-struct class that wraps a single int (raw address)
## and reads/writes each field directly in native memory.  No dict is allocated
## until the caller explicitly calls .to_dict().
import std/[sequtils, strutils, tables]
import oche_core

# ---------------------------------------------------------------------------
# Type helpers
# ---------------------------------------------------------------------------

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
  if t.startsWith("OcheBuffer["): return "'SharedListView'"
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
  if obj.retType.isSeq:
    if obj.isView: return "'NativeListView'"
    else: return "List[Any]"
  if obj.retType.isShared: return "'SharedListView'"
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

# ---------------------------------------------------------------------------
# genPStruct
# Emits:
#   1. XxxName_t   — ctypes.Structure (correct layout, used for sizeof + copy)
#   2. _struct_field_meta  — per-field type tag for copy-mode decode
#   3. _OFF_Xxx_field      — byte-offset constants (read at module load)
#   4. XxxView class       — zero-copy view; reads/writes native memory directly
# ---------------------------------------------------------------------------

proc genPStruct*(s: OcheStruct): string =
  # ── 1. ctypes.Structure ──────────────────────────────────────────────────
  result = "class " & s.name & "_t(ctypes.Structure):\n"
  result &= "  _fields_ = [\n"
  for f in s.fields:
    if f.typ.name in ["string", "cstring"]:
      result &= "    ('" & f.name & "', ctypes.c_void_p),\n"
    elif structBanks.hasKey(f.typ.name):
      # inline embedded struct — use real type so sizeof/offset are correct
      result &= "    ('" & f.name & "', " & f.typ.name & "_t),\n"
    else:
      result &= "    ('" & f.name & "', ctypes." & toCType(f.typ.name) & "),\n"
  result &= "  ]\n"
  result &= "_struct_size_cache['" & s.name & "'] = ctypes.sizeof(" & s.name & "_t)\n"
  result &= "_struct_types['" & s.name & "'] = " & s.name & "_t\n"

  # ── 2. Field metadata (copy-mode decode) ─────────────────────────────────
  result &= "_struct_field_meta['" & s.name & "'] = {\n"
  for f in s.fields:
    if f.typ.name in ["string", "cstring"]:
      result &= "  '" & f.name & "': ('string', None),\n"
    elif structBanks.hasKey(f.typ.name):
      result &= "  '" & f.name & "': ('struct', '" & f.typ.name & "'),\n"
    else:
      result &= "  '" & f.name & "': ('pod', None),\n"
  result &= "}\n"

  # ── 3. Byte-offset constants via ctypes descriptor ────────────────────────
  for f in s.fields:
    result &= "_OFF_" & s.name & "_" & f.name &
              " = " & s.name & "_t." & f.name & ".offset\n"

  # ── 4. XxxView: zero-copy view class ─────────────────────────────────────
  result &= "class " & s.name & "View:\n"
  result &= "  \"\"\"Zero-copy view into a " & s.name &
            " in Nim memory. No dict allocated until .to_dict().\"\"\"\n"
  result &= "  __slots__ = ('_addr',)\n"
  result &= "  def __init__(self, addr: int):\n"
  result &= "    self._addr = addr\n"

  for f in s.fields:
    let offExpr = "_OFF_" & s.name & "_" & f.name
    if f.typ.name in ["string", "cstring"]:
      # Read: dereference pointer → decode UTF-8 (one Python str allocation)
      result &= "  @property\n"
      result &= "  def " & f.name & "(self) -> Optional[str]:\n"
      result &= "    p = ctypes.c_void_p.from_address(self._addr + " & offExpr & ").value\n"
      result &= "    return ctypes.string_at(p).decode('utf-8') if p else None\n"
    elif structBanks.hasKey(f.typ.name):
      # Nested inline struct → another StructView at the correct sub-offset
      result &= "  @property\n"
      result &= "  def " & f.name & "(self) -> '" & f.typ.name & "View':\n"
      result &= "    return " & f.typ.name & "View(self._addr + " & offExpr & ")\n"
    elif enumBanks.hasKey(f.typ.name):
      result &= "  @property\n"
      result &= "  def " & f.name & "(self) -> int:\n"
      result &= "    return ctypes.c_int32.from_address(self._addr + " & offExpr & ").value\n"
      result &= "  @" & f.name & ".setter\n"
      result &= "  def " & f.name & "(self, v: int):\n"
      result &= "    ctypes.c_int32.from_address(self._addr + " & offExpr & ").value = int(v)\n"
    else:
      let ct = "ctypes." & toCType(f.typ.name)
      let pt = toPythonType(f.typ.name)
      result &= "  @property\n"
      result &= "  def " & f.name & "(self) -> " & pt & ":\n"
      result &= "    return " & ct & ".from_address(self._addr + " & offExpr & ").value\n"
      result &= "  @" & f.name & ".setter\n"
      result &= "  def " & f.name & "(self, v: " & pt & "):\n"
      result &= "    " & ct & ".from_address(self._addr + " & offExpr & ").value = v\n"

  result &= "  def to_dict(self) -> dict:\n"
  result &= "    \"\"\"Materialise to a plain dict (triggers copy — use sparingly).\"\"\"\n"
  result &= "    return _struct_from_ctypes('" & s.name &
            "', " & s.name & "_t.from_address(self._addr))\n"
  result &= "  def __repr__(self):\n"
  result &= "    return '" & s.name & "View(' + str(self.to_dict()) + ')'\n"
  result &= "\n"

# ---------------------------------------------------------------------------

proc genPEnum*(e: OcheEnum): string =
  result = "class " & e.name & ":\n"
  for i, v in e.values:
    result &= "  " & v & " = " & $i & "\n"
  result &= "\n"

# ---------------------------------------------------------------------------
# genPInterface
# ---------------------------------------------------------------------------

proc genPInterface*(obj: OcheObject): string =
  let callName = "_" & obj.name
  var cParams, pyArgList: seq[string]
  for p in obj.params:
    if p.typ.isSeq:
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p"
               else: "ctypes." & toCType(inner)
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

  let sR = obj.retType.isSeq or obj.retType.isOption or
           obj.retType.name in ["string", "cstring"] or obj.retType.isShared
  let cRet = if sR: "ctypes.c_void_p"
             elif obj.retType.name in ["void", ""]: "None"
             else: "ctypes." & toCType(obj.retType.name)
  let setRestype = if cRet == "None": "None" else: cRet

  result = "  " & callName & " = _lib." & obj.name & "\n"
  result &= "  " & callName & ".argtypes = [" & cParams.join(", ") & "]\n"
  result &= "  " & callName & ".restype = " & setRestype & "\n"
  let retHint = toPythonReturnType(obj)
  result &= "  def " & obj.name & "(self, " &
            obj.params.mapIt(it.name & ": " & toPythonType(it.typ.name)).join(", ") &
            ") -> " & retHint & ":\n"

  for p in obj.params:
    if p.typ.isSeq:
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p"
               else: "ctypes." & toCType(inner)
      result &= "    " & p.name & "_arr = (" & cT & " * len(" & p.name & "))(); "
      result &= "for i, x in enumerate(" & p.name & "): " & p.name & "_arr[i] = x\n"
    elif structBanks.hasKey(p.typ.name):
      result &= "    " & p.name & "_buf = _pack_struct('" & p.typ.name & "', " & p.name & ") if " & p.name & " is not None else None\n"

  result &= "    r = self." & callName & "(" & pyArgList.join(", ") & ")\n"
  result &= "    _check_error()\n"

  if obj.retType.name in ["void", ""]:
    result &= "    return None\n"

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
    if obj.isView:
      # ── VIEW MODE ─────────────────────────────────────────────────────────
      if isStruct:
        result &= "    return NativeListView(r, lambda addr: " & inner & "View(addr), " & sz & ", _lib.ocheFreeDeep)\n"
      else:
        result &= "    return NativeListView(r, None, " & sz & ", _lib.ocheFreeDeep, '" & toCType(inner) & "')\n"
    else:
      # ── COPY MODE ─────────────────────────────────────────────────────────
      if isStruct:
        result &= "    out = [_struct_copy('" & inner & "', r, 16, " & sz & ", i) for i in range(n)]\n"
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
      result &= "    out = _struct_copy('" & inner & "', r, 0, sz, 0); _lib.ocheFree(r); return out\n"
    else:
      result &= "    out = ctypes.cast(r, ctypes.POINTER(" & toCType(inner) & ")).contents.value\n"
      result &= "    _lib.ocheFree(r); return out\n"

  elif obj.retType.isShared:
    # ── SHARE MODE ────────────────────────────────────────────────────────
    let inner = obj.retType.inner
    let (sz, _) = elemSizeAndDtype(inner)
    let isStruct = structBanks.hasKey(inner)
    result &= "    if r is None: return []\n"
    result &= "    n = ctypes.cast(r, ctypes.POINTER(ctypes.c_int64)).contents.value\n"
    result &= "    if n <= 0: return []\n"
    if isStruct:
      let s = structBanks[inner]
      result &= "    return SharedListView(r, n, " & sz &
                ", lambda addr: " & inner & "View(addr)" &
                ", " & $s.typeId &
                ", " & (if s.isPOD: "True" else: "False") & ")\n"
    else:
      result &= "    return SharedListView(r, n, " & sz & ", None, 0, True, '" & toCType(inner) & "')\n"

  elif structBanks.hasKey(obj.retType.name):
    # single-struct return — copy mode (Nim allocated, we copy then free)
    result &= "    if r is None: return None\n"
    result &= "    sz = _struct_size('" & obj.retType.name & "')\n"
    result &= "    out = _struct_copy('" & obj.retType.name & "', r, 0, sz, 0)\n"
    result &= "    _lib.ocheFree(r); return out\n"

  elif enumBanks.hasKey(obj.retType.name):
    result &= "    return r\n"
  else:
    result &= "    return r\n"
  result &= "\n"

# ---------------------------------------------------------------------------
# genPythonPrelude  — runtime helpers emitted verbatim into nlib.py
# ---------------------------------------------------------------------------

proc genPythonPrelude*(): string =
  result = ""
  result &= "try:\n"
  result &= "  import numpy as np\n"
  result &= "  _HAS_NUMPY = True\n"
  result &= "except ImportError:\n"
  result &= "  _HAS_NUMPY = False\n"
  result &= "\n"
  result &= "_struct_size_cache: dict = {}\n"
  result &= "_struct_types: dict = {}\n"
  result &= "_struct_field_meta: dict = {}\n"
  result &= "\n"
  result &= "def _struct_size(name: str) -> int:\n"
  result &= "  return _struct_size_cache.get(name, 8)\n"
  result &= "\n"
  result &= "# -- Copy-mode helpers --\n"
  result &= "\n"
  result &= "def _pack_struct(name: str, obj):\n"
  result &= "  if obj is None: return None\n"
  result &= "  t = _struct_types[name]\n"
  result &= "  if hasattr(obj, '_as_buffer'): return obj\n"
  result &= "  buf = t()\n"
  result &= "  for (k, v) in (obj.items() if hasattr(obj, 'items') else obj):\n"
  result &= "    setattr(buf, k, v)\n"
  result &= "  return buf\n"
  result &= "\n"
  result &= "def _struct_copy(name: str, ptr, offset: int, elem_size: int, index: int) -> dict:\n"
  result &= "  addr = ctypes.cast(ptr, ctypes.c_void_p).value + offset + index * elem_size\n"
  result &= "  return _struct_from_ctypes(name, _struct_types[name].from_address(addr))\n"
  result &= "\n"
  result &= "def _struct_from_ctypes(name: str, c) -> dict:\n"
  result &= "  d = {}\n"
  result &= "  meta = _struct_field_meta.get(name, {})\n"
  result &= "  for (fname, _) in c._fields_:\n"
  result &= "    raw = getattr(c, fname)\n"
  result &= "    kind, extra = meta.get(fname, ('pod', None))\n"
  result &= "    if kind == 'string':\n"
  result &= "      d[fname] = ctypes.string_at(raw).decode('utf-8') if raw else None\n"
  result &= "    elif kind == 'struct':\n"
  result &= "      d[fname] = _struct_from_ctypes(extra, raw)\n"
  result &= "    else:\n"
  result &= "      d[fname] = raw\n"
  result &= "  return d\n"
  result &= "\n"
  result &= "# -- NativeListView (view mode: zero-copy, read-only) --\n"
  result &= "\n"
  result &= "class NativeListView:\n"
  result &= "  __slots__ = ('_ptr', '_n', '_elem_size', '_unpacker', '_free_fn', '_elem_ctype')\n"
  result &= "  def __init__(self, ptr, unpacker, elem_size: int, free_fn, elem_ctype=None):\n"
  result &= "    self._ptr = ptr\n"
  result &= "    self._n = ctypes.cast(ptr, ctypes.POINTER(ctypes.c_int64)).contents.value if ptr else 0\n"
  result &= "    self._elem_size = elem_size\n"
  result &= "    self._unpacker = unpacker\n"
  result &= "    self._free_fn = free_fn\n"
  result &= "    self._elem_ctype = getattr(ctypes, elem_ctype) if isinstance(elem_ctype, str) else elem_ctype\n"
  result &= "  def __len__(self): return self._n\n"
  result &= "  def __getitem__(self, i):\n"
  result &= "    if i < 0 or i >= self._n: raise IndexError('index out of range')\n"
  result &= "    addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16 + i * self._elem_size\n"
  result &= "    if self._unpacker: return self._unpacker(addr)\n"
  result &= "    return ctypes.cast(addr, ctypes.POINTER(self._elem_ctype)).contents.value\n"
  result &= "  def __setitem__(self, i, v):\n"
  result &= "    raise TypeError('NativeListView is read-only. Use SharedListView for mutation.')\n"
  result &= "  def __iter__(self):\n"
  result &= "    for i in range(self._n): yield self[i]\n"
  result &= "  def __del__(self):\n"
  result &= "    if self._ptr and self._free_fn: self._free_fn(self._ptr)\n"
  result &= "  def to_list(self) -> list:\n"
  result &= "    return [self[i] for i in range(self._n)]\n"
  result &= "  def to_numpy(self):\n"
  result &= "    if not _HAS_NUMPY or self._unpacker: return None\n"
  result &= "    data_addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16\n"
  result &= "    dt = np.dtype(self._elem_ctype)\n"
  result &= "    return np.frombuffer(\n"
  result &= "      (ctypes.c_char * (self._n * self._elem_size)).from_address(data_addr),\n"
  result &= "      dtype=dt, count=self._n).copy()\n"
  result &= "\n"
  result &= "# -- SharedListView (share mode: zero-copy, read-write) --\n"
  result &= "\n"
  result &= "class SharedListView:\n"
  result &= "  __slots__ = ('_ptr', '_n', '_elem_size', '_unpacker', '_type_id', '_is_pod', '_elem_ctype')\n"
  result &= "  def __init__(self, ptr, n: int, elem_size: int, unpacker, type_id: int = 0,\n"
  result &= "               is_pod: bool = True, elem_ctype=None):\n"
  result &= "    self._ptr = ptr\n"
  result &= "    self._n = n\n"
  result &= "    self._elem_size = elem_size\n"
  result &= "    self._unpacker = unpacker\n"
  result &= "    self._type_id = type_id\n"
  result &= "    self._is_pod = is_pod\n"
  result &= "    self._elem_ctype = getattr(ctypes, elem_ctype) if isinstance(elem_ctype, str) else elem_ctype\n"
  result &= "  def __len__(self): return self._n\n"
  result &= "  def __getitem__(self, i):\n"
  result &= "    if i < 0 or i >= self._n: raise IndexError('index out of range')\n"
  result &= "    addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16 + i * self._elem_size\n"
  result &= "    if self._unpacker: return self._unpacker(addr)\n"
  result &= "    return ctypes.cast(addr, ctypes.POINTER(self._elem_ctype)).contents.value\n"
  result &= "  def __setitem__(self, i, v):\n"
  result &= "    if i < 0 or i >= self._n: raise IndexError('index out of range')\n"
  result &= "    addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16 + i * self._elem_size\n"
  result &= "    if self._unpacker:\n"
  result &= "      if not self._is_pod: _ocheFreeInner(ctypes.c_void_p(addr), self._type_id)\n"
  result &= "      if hasattr(v, '_addr'):\n"
  result &= "        ctypes.memmove(addr, v._addr, self._elem_size)\n"
  result &= "      else:\n"
  result &= "        struct_name = None\n"
  result &= "        for sn, st in _struct_types.items():\n"
  result &= "          if ctypes.sizeof(st) == self._elem_size: struct_name = sn; break\n"
  result &= "        if struct_name is None:\n"
  result &= "          raise TypeError(f'Cannot infer struct type for SharedListView elem_size={self._elem_size}')\n"
  result &= "        buf = _pack_struct(struct_name, v)\n"
  result &= "        ctypes.memmove(addr, ctypes.addressof(buf), self._elem_size)\n"
  result &= "    else:\n"
  result &= "      ctypes.cast(addr, ctypes.POINTER(self._elem_ctype)).contents.value = v\n"
  result &= "  def __iter__(self):\n"
  result &= "    for i in range(self._n): yield self[i]\n"
  result &= "  def to_list(self) -> list:\n"
  result &= "    return [self[i] for i in range(self._n)]\n"
  result &= "  def to_numpy(self):\n"
  result &= "    if not _HAS_NUMPY or self._unpacker: return None\n"
  result &= "    data_addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16\n"
  result &= "    dt = np.dtype(self._elem_ctype)\n"
  result &= "    return np.frombuffer(\n"
  result &= "      (ctypes.c_char * (self._n * self._elem_size)).from_address(data_addr),\n"
  result &= "      dtype=dt, count=self._n)\n"
  result &= "\n"