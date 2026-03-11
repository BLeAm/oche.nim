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
  if t.startsWith("OcheArray["): return "Any"   ## numpy array, list, or buffer — detected at runtime
  if t.startsWith("OchePtr["):   return "Any"   ## numpy array or ctypes pointer — zero-copy, caller owns
  if t.startsWith("Option["): return "Optional[" & toPythonType(t[7..^2]) & "]"
  if t.startsWith("OcheBuffer["): return "'SharedListView'"  ## as param: pass existing SharedListView
  if structBanks.hasKey(t): return "Union['" & t & "', '" & t & "View']"
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
    else:
      let inner = obj.retType.inner
      if structBanks.hasKey(inner): return "List['" & inner & "']"  # plain Xxx
      else: return "List[Any]"
  if obj.retType.isShared: return "'SharedListView'"
  if structBanks.hasKey(obj.retType.name):
    # copy mode → Xxx plain class; view mode on single struct → also Xxx (fallback)
    return "'" & obj.retType.name & "'"
  if enumBanks.hasKey(obj.retType.name): return "int"
  return toPythonType(obj.retType.name)

proc elemSizeAndDtype(inner: string): (string, string) =
  if structBanks.hasKey(inner):
    let s = structBanks[inner]
    if s.isPOD: return ("_struct_size('" & inner & "')", "_NUMPY_DTYPE_" & inner)
    else: return ("_struct_size('" & inner & "')", "None")
  case inner
  of "int", "int64": return ("ctypes.sizeof(ctypes.c_int64)", "'i8'")
  of "float", "float64": return ("ctypes.sizeof(ctypes.c_double)", "'f8'")
  of "float32": return ("ctypes.sizeof(ctypes.c_float)", "'f4'")
  of "uint8": return ("ctypes.sizeof(ctypes.c_uint8)", "'u1'")
  of "bool": return ("ctypes.sizeof(ctypes.c_bool)", "'?'")
  else:
    if enumBanks.hasKey(inner): return ("ctypes.sizeof(ctypes.c_int32)", "'i4'")
    return ("1", "'u1'")

proc toNumpyDtypeChar*(t: string): string =
  ## Map a primitive Nim type to numpy dtype char string
  case t
  of "int", "int64":    return "'i8'"
  of "float", "float64": return "'f8'"
  of "float32":          return "'f4'"
  of "uint8":            return "'u1'"
  of "bool":             return "'?'"
  else:
    if enumBanks.hasKey(t): return "'i4'"
    return ""  # non-primitive — not numpy compatible

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
    elif enumBanks.hasKey(f.typ.name):
      result &= "  '" & f.name & "': ('enum', None),\n"
    else:
      result &= "  '" & f.name & "': ('pod', None),\n"
  result &= "}\n"

  # ── 3. Byte-offset constants via ctypes descriptor ────────────────────────
  for f in s.fields:
    result &= "_OFF_" & s.name & "_" & f.name &
              " = " & s.name & "_t." & f.name & ".offset\n"

  # ── 4. XxxView: unified view class used by ALL modes ─────────────────────
  # _owned=True  → copy mode: Python allocated, __del__ calls ocheFree
  # _owned=False → view/share mode: Nim owns, Python must not free
  result &= "class " & s.name & "View:\n"
  result &= "  __slots__ = ('_addr', '_owned')\n"
  result &= "  def __init__(self, addr: int, owned: bool = False):\n"
  result &= "    self._addr = addr\n"
  result &= "    self._owned = owned\n"
  result &= "  def __del__(self):\n"
  result &= "    if self._owned and self._addr:\n"
  for f in s.fields:
    if f.typ.name in ["string", "cstring"]:
      result &= "      _p = ctypes.c_void_p.from_address(self._addr + _OFF_" & s.name & "_" & f.name & ").value\n"
      result &= "      if _p: _lib.ocheStrFree(ctypes.c_void_p(_p))\n"
  result &= "      _lib.ocheFree(ctypes.c_void_p(self._addr))\n"
  result &= "      self._addr = 0\n"

  for f in s.fields:
    let offExpr = "_OFF_" & s.name & "_" & f.name
    if f.typ.name in ["string", "cstring"]:
      result &= "  @property\n"
      result &= "  def " & f.name & "(self) -> Optional[str]:\n"
      result &= "    p = ctypes.c_void_p.from_address(self._addr + " & offExpr & ").value\n"
      result &= "    return ctypes.string_at(p).decode('utf-8') if p else None\n"
      result &= "  @" & f.name & ".setter\n"
      result &= "  def " & f.name & "(self, v: Optional[str]):\n"
      result &= "    old = ctypes.c_void_p.from_address(self._addr + " & offExpr & ").value\n"
      result &= "    if old: _lib.ocheStrFree(ctypes.c_void_p(old))\n"
      result &= "    new_p = _lib.ocheStrAlloc(v.encode('utf-8')) if v is not None else 0\n"
      result &= "    ctypes.c_void_p.from_address(self._addr + " & offExpr & ").value = new_p\n"
    elif structBanks.hasKey(f.typ.name):
      # nested inline struct: always owned=False — parent controls the memory
      result &= "  @property\n"
      result &= "  def " & f.name & "(self) -> '" & f.typ.name & "View':\n"
      result &= "    return " & f.typ.name & "View(self._addr + " & offExpr & ", owned=False)\n"
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

  result &= "  def __eq__(self, other) -> bool:\n"
  result &= "    if isinstance(other, " & s.name & "View): return self._addr == other._addr or self.to_dict() == other.to_dict()\n"
  result &= "    if isinstance(other, " & s.name & "): return self.to_dict() == other.__dict__ if hasattr(other, '__dict__') else all(getattr(other, k, None) == v for k, v in self.to_dict().items())\n"
  result &= "    return NotImplemented\n"
  result &= "  def __hash__(self): return hash(tuple(self.to_dict().values()))\n"
  result &= "  def to_dict(self) -> dict:\n"
  result &= "    return _struct_from_ctypes('" & s.name &
            "', " & s.name & "_t.from_address(self._addr))\n"
  result &= "  def freeze(self) -> '" & s.name & "':\n"
  result &= "    return " & s.name & "._from_view(self)\n"
  result &= "  def __repr__(self):\n"
  result &= "    return '" & s.name & "View(' + str(self.to_dict()) + ')'\n"
  result &= "_struct_view_types['" & s.name & "'] = " & s.name & "View\n"
  # ── Xxx plain Python class (mutable, GC-owned, equivalent to Dart's User) ──
  result &= "class " & s.name & ":\n"
  result &= "  __slots__ = ("
  for i, f in s.fields:
    result &= "'" & f.name & "'"
    if i < s.fields.len - 1: result &= ", "
  result &= ")\n"
  result &= "  def __init__(self, "
  for i, f in s.fields:
    result &= f.name & "=None"
    if i < s.fields.len - 1: result &= ", "
  result &= "):\n"
  for f in s.fields:
    result &= "    self." & f.name & " = " & f.name & "\n"
  result &= "  @staticmethod\n"
  result &= "  def _from_view(v: '" & s.name & "View') -> '" & s.name & "':\n"
  result &= "    return " & s.name & "("
  for i, f in s.fields:
    if f.typ.name in ["string", "cstring"]:
      result &= f.name & "=v." & f.name
    elif structBanks.hasKey(f.typ.name):
      result &= f.name & "=" & f.typ.name & "._from_view(v." & f.name & ")"
    else:
      result &= f.name & "=v." & f.name
    if i < s.fields.len - 1: result &= ", "
  result &= ")\n"
  result &= "  def __repr__(self):\n"
  result &= "    return '" & s.name & "(' + ', '.join(f'{k}={getattr(self,k)!r}' for k in self.__slots__) + ')'\n"
  result &= "_struct_plain_types['" & s.name & "'] = " & s.name & "\n"

  # ── 5. numpy structured dtype (POD structs only) ──────────────────────────
  if s.isPOD:
    result &= "_NUMPY_DTYPE_" & s.name & " = np.dtype([\n"
    for f in s.fields:
      let dc = toNumpyDtypeChar(f.typ.name)
      if dc != "":
        result &= "  ('" & f.name & "', " & dc & "),\n"
    result &= "]) if _HAS_NUMPY else None\n"
  else:
    result &= "_NUMPY_DTYPE_" & s.name & " = None  # not POD (has strings/pointers)\n"
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
      pyArgList.add p.name & "_ptr"
      pyArgList.add p.name & "_len"
    elif p.typ.isArray:
      # OcheArray — same wire format as seq (ptr + len) but zero-copy fast path
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p"
               else: "ctypes." & toCType(inner)
      cParams.add "ctypes.POINTER(" & cT & ")"
      cParams.add "ctypes.c_int64"
      pyArgList.add p.name & "_ptr"
      pyArgList.add p.name & "_len"
    elif p.typ.isPtr:
      # OchePtr — true zero-copy: numpy array or raw ctypes pointer
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p"
               else: "ctypes." & toCType(inner)
      cParams.add "ctypes.POINTER(" & cT & ")"
      cParams.add "ctypes.c_int64"
      pyArgList.add p.name & "_ptr"
      pyArgList.add p.name & "_len"
    elif p.typ.isShared:
      # OcheBuffer[T] as input — wire: single void* (the buffer header pointer)
      # Accepts SharedListView (pass ._ptr), or raw int pointer
      cParams.add "ctypes.c_void_p"
      pyArgList.add p.name & "._ptr if hasattr(" & p.name & ", '_ptr') else int(" & p.name & ")"
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
      let npDtype = toNumpyDtypeChar(inner)
      # Fast path 1: numpy array with matching dtype — zero-copy, just grab pointer
      # Fast path 2: any object with buffer protocol (array.array, memoryview, etc.)
      # Slow path: generic Python iterable — ctypes unpack (C-level, still faster than enumerate loop)
      result &= "    if _HAS_NUMPY and isinstance(" & p.name & ", np.ndarray) and " & p.name & ".dtype == np.dtype(" & npDtype & ") and " & p.name & ".data.contiguous:\n"
      result &= "      " & p.name & "_ptr = " & p.name & ".ctypes.data_as(ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = len(" & p.name & ")\n"
      result &= "    elif hasattr(" & p.name & ", 'buffer_info'):\n"
      result &= "      _buf_ptr, _buf_len = " & p.name & ".buffer_info()\n"
      result &= "      " & p.name & "_ptr = ctypes.cast(_buf_ptr, ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = _buf_len\n"
      result &= "    else:\n"
      result &= "      " & p.name & "_arr = (" & cT & " * len(" & p.name & "))(*" & p.name & ")\n"
      result &= "      " & p.name & "_ptr = " & p.name & "_arr\n"
      result &= "      " & p.name & "_len = len(" & p.name & ")\n"
    elif p.typ.isArray:
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p"
               else: "ctypes." & toCType(inner)
      let npDtype = toNumpyDtypeChar(inner)
      # OcheArray: always zero-copy — require contiguous numeric buffer
      result &= "    if _HAS_NUMPY and isinstance(" & p.name & ", np.ndarray):\n"
      result &= "      if not " & p.name & ".data.contiguous: " & p.name & " = np.ascontiguousarray(" & p.name & ", dtype=np.dtype(" & npDtype & "))\n"
      result &= "      " & p.name & "_ptr = " & p.name & ".ctypes.data_as(ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = len(" & p.name & ")\n"
      result &= "    elif hasattr(" & p.name & ", 'buffer_info'):\n"
      result &= "      _buf_ptr, _buf_len = " & p.name & ".buffer_info()\n"
      result &= "      " & p.name & "_ptr = ctypes.cast(_buf_ptr, ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = _buf_len\n"
      result &= "    else:\n"
      result &= "      raise TypeError('OcheArray parameter \\'" & p.name & "\\' requires a contiguous buffer (numpy array or array.array). Got: ' + type(" & p.name & ").__name__)\n"
    elif p.typ.isPtr:
      let inner = p.typ.inner
      let cT = if structBanks.hasKey(inner): "ctypes.c_void_p"
               else: "ctypes." & toCType(inner)
      let npDtype = toNumpyDtypeChar(inner)
      # OchePtr: same zero-copy paths as OcheArray + accepts raw ctypes pointer directly
      result &= "    if isinstance(" & p.name & ", ctypes.POINTER(" & cT & ")) or isinstance(" & p.name & ", ctypes.Array):\n"
      result &= "      " & p.name & "_ptr = ctypes.cast(" & p.name & ", ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = " & p.name & "._length_ if hasattr(" & p.name & ", '_length_') else ctypes.sizeof(" & p.name & ") // ctypes.sizeof(" & cT & ")\n"
      result &= "    elif _HAS_NUMPY and isinstance(" & p.name & ", np.ndarray):\n"
      result &= "      if not " & p.name & ".data.contiguous: " & p.name & " = np.ascontiguousarray(" & p.name & ", dtype=np.dtype(" & npDtype & "))\n"
      result &= "      " & p.name & "_ptr = " & p.name & ".ctypes.data_as(ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = len(" & p.name & ")\n"
      result &= "    elif hasattr(" & p.name & ", 'buffer_info'):\n"
      result &= "      _buf_ptr, _buf_len = " & p.name & ".buffer_info()\n"
      result &= "      " & p.name & "_ptr = ctypes.cast(_buf_ptr, ctypes.POINTER(" & cT & "))\n"
      result &= "      " & p.name & "_len = _buf_len\n"
      result &= "    else:\n"
      result &= "      raise TypeError('OchePtr parameter \\'" & p.name & "\\' requires a ctypes pointer, numpy array, or array.array. Got: ' + type(" & p.name & ").__name__)\n"
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
      # ── VIEW MODE: NativeListView of XxxView(owned=False) ─────────────────
      if isStruct:
        let isPOD = structBanks[inner].isPOD
        let ndt = if isPOD: "_NUMPY_DTYPE_" & inner else: "None"
        result &= "    return NativeListView(r, lambda addr: " & inner & "View(addr, owned=False), " & sz & ", _lib.ocheFreeDeep, numpy_dtype=" & ndt & ")\n"
      else:
        result &= "    return NativeListView(r, None, " & sz & ", _lib.ocheFreeDeep, '" & toCType(inner) & "')\n"
    else:
      # ── COPY MODE: each element copied into a Python-owned XxxView ────────
      if isStruct:
        result &= "    out = [_struct_unpack_plain('" & inner & "', r, 16, " & sz & ", i) for i in range(n)]\n"
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
      result &= "    out = _struct_unpack_plain('" & inner & "', r, 0, sz, 0); _lib.ocheFree(r); return out\n"
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
      let ndt = if s.isPOD: "_NUMPY_DTYPE_" & inner else: "None"
      result &= "    return SharedListView(r, n, " & sz &
                ", lambda addr: " & inner & "View(addr)" &
                ", " & $s.typeId &
                ", " & (if s.isPOD: "True" else: "False") &
                ", numpy_dtype=" & ndt & ")\n"
    else:
      result &= "    return SharedListView(r, n, " & sz & ", None, 0, True, '" & toCType(inner) & "')\n"

  elif structBanks.hasKey(obj.retType.name):
    let sn = obj.retType.name
    if obj.isView:
      result &= "    # NOTE: {.porche:view.} ignored for single-struct return — copy mode used\n"
    result &= "    if r is None: return None\n"
    # Unpack into a plain Xxx Python object (GC-owned, no manual free needed)
    # String fields: toDartString equivalent — just decode the pointer value
    result &= "    _plain_cls = _struct_plain_types['" & sn & "']\n"
    result &= "    _ct = _struct_types['" & sn & "'].from_address(ctypes.cast(r, ctypes.c_void_p).value)\n"
    result &= "    _meta = _struct_field_meta['" & sn & "']\n"
    result &= "    _kwargs = {}\n"
    result &= "    for _fn, _ft in _ct._fields_:\n"
    result &= "      _raw = getattr(_ct, _fn)\n"
    result &= "      _kind, _extra = _meta.get(_fn, ('pod', None))\n"
    result &= "      if _kind == 'string':\n"
    result &= "        _kwargs[_fn] = ctypes.string_at(_raw).decode('utf-8') if _raw else None\n"
    result &= "      elif _kind == 'struct':\n"
    result &= "        _sv = _struct_view_types[_extra](ctypes.addressof(getattr(_ct, _fn)), owned=False)\n"
    result &= "        _kwargs[_fn] = _struct_plain_types[_extra]._from_view(_sv)\n"
    result &= "      else:\n"
    result &= "        _kwargs[_fn] = _raw\n"
    result &= "    _lib.ocheFree(r)\n"
    result &= "    return _plain_cls(**_kwargs)\n"

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
  result &= "  # XxxView — memcpy entire struct buffer directly (fast path)\n"
  result &= "  if hasattr(obj, '_addr'):\n"
  result &= "    ctypes.memmove(ctypes.addressof(buf), obj._addr, ctypes.sizeof(t))\n"
  result &= "    return buf\n"
  result &= "  meta = _struct_field_meta.get(name, {})\n"
  result &= "  # Xxx plain class or dict — iterate fields\n"
  result &= "  pairs = list(obj.items()) if hasattr(obj, 'items') else [(k, getattr(obj,k)) for k in getattr(obj, '__slots__', [])]\n"
  result &= "  for (k, v) in pairs:\n"
  result &= "    kind, extra = meta.get(k, ('pod', None))\n"
  result &= "    if kind == 'struct':\n"
  result &= "      if v is None:\n"
  result &= "        pass  # leave zeroed\n"
  result &= "      elif hasattr(v, '_addr'):\n"
  result &= "        # XxxView — memcpy into the nested field slot\n"
  result &= "        sub_t = _struct_types[extra]\n"
  result &= "        ctypes.memmove(ctypes.addressof(getattr(buf, k)), v._addr, ctypes.sizeof(sub_t))\n"
  result &= "      elif isinstance(v, dict):\n"
  result &= "        setattr(buf, k, _pack_struct(extra, v))\n"
  result &= "      else:\n"
  result &= "        setattr(buf, k, v)  # already a ctypes struct instance\n"
  result &= "    elif kind == 'string':\n"
  result &= "      setattr(buf, k, _lib.ocheStrAlloc(v.encode('utf-8')) if v else 0)\n"
  result &= "    elif kind == 'enum':\n"
  result &= "      setattr(buf, k, int(v))\n"
  result &= "    else:\n"
  result &= "      setattr(buf, k, v)\n"
  result &= "  return buf\n"
  result &= "\n"
  result &= "def _struct_copy(name: str, ptr, offset: int, elem_size: int, index: int) -> dict:\n"
  result &= "  addr = ctypes.cast(ptr, ctypes.c_void_p).value + offset + index * elem_size\n"
  result &= "  return _struct_from_ctypes(name, _struct_types[name].from_address(addr))\n"
  result &= "\n"
  result &= "_struct_view_types: dict = {}\n"
  result &= "_struct_plain_types: dict = {}\n"
  result &= "\n"
  result &= "def _struct_copy_view(name: str, ptr, offset: int, elem_size: int, index: int):\n"
  result &= "  src = ctypes.cast(ptr, ctypes.c_void_p).value + offset + index * elem_size\n"
  result &= "  dst = _lib.ocheAllocBytes(ctypes.c_size_t(elem_size))\n"
  result &= "  ctypes.memmove(dst, src, elem_size)\n"
  result &= "  view_cls = _struct_view_types.get(name)\n"
  result &= "  return view_cls(dst, owned=True) if view_cls else None\n"
  result &= "\n"
  result &= "def _struct_unpack_plain(name: str, ptr, offset: int, elem_size: int, index: int):\n"
  result &= "  addr = ctypes.cast(ptr, ctypes.c_void_p).value + offset + index * elem_size\n"
  result &= "  ct = _struct_types[name].from_address(addr)\n"
  result &= "  meta = _struct_field_meta[name]\n"
  result &= "  plain_cls = _struct_plain_types[name]\n"
  result &= "  kwargs = {}\n"
  result &= "  for fn, _ in ct._fields_:\n"
  result &= "    raw = getattr(ct, fn)\n"
  result &= "    kind, extra = meta.get(fn, ('pod', None))\n"
  result &= "    if kind == 'string':\n"
  result &= "      kwargs[fn] = ctypes.string_at(raw).decode('utf-8') if raw else None\n"
  result &= "    elif kind == 'struct':\n"
  result &= "      sv = _struct_view_types[extra](ctypes.addressof(getattr(ct, fn)), owned=False)\n"
  result &= "      kwargs[fn] = _struct_plain_types[extra]._from_view(sv)\n"
  result &= "    else:\n"
  result &= "      kwargs[fn] = raw\n"
  result &= "  return plain_cls(**kwargs)\n"
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
  result &= "  __slots__ = ('_ptr', '_n', '_elem_size', '_unpacker', '_free_fn', '_elem_ctype', '_numpy_dtype')\n"
  result &= "  def __init__(self, ptr, unpacker, elem_size: int, free_fn, elem_ctype=None, numpy_dtype=None):\n"
  result &= "    self._ptr = ptr\n"
  result &= "    self._n = ctypes.cast(ptr, ctypes.POINTER(ctypes.c_int64)).contents.value if ptr else 0\n"
  result &= "    self._elem_size = elem_size\n"
  result &= "    self._unpacker = unpacker\n"
  result &= "    self._free_fn = free_fn\n"
  result &= "    self._elem_ctype = getattr(ctypes, elem_ctype) if isinstance(elem_ctype, str) else elem_ctype\n"
  result &= "    self._numpy_dtype = numpy_dtype\n"
  result &= "  def __len__(self): return self._n\n"
  result &= "  def _get_one(self, i: int):\n"
  result &= "    addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16 + i * self._elem_size\n"
  result &= "    if self._unpacker: return self._unpacker(addr)\n"
  result &= "    return ctypes.cast(addr, ctypes.POINTER(self._elem_ctype)).contents.value\n"
  result &= "  def __getitem__(self, key):\n"
  result &= "    if isinstance(key, slice):\n"
  result &= "      return [self._get_one(i) for i in range(*key.indices(self._n))]\n"
  result &= "    i = key if key >= 0 else self._n + key\n"
  result &= "    if i < 0 or i >= self._n: raise IndexError(f'NativeListView index {key} out of range (len={self._n})')\n"
  result &= "    return self._get_one(i)\n"
  result &= "  def __setitem__(self, i, v):\n"
  result &= "    raise TypeError('NativeListView is read-only. Use SharedListView for mutation.')\n"
  result &= "  def __iter__(self):\n"
  result &= "    for i in range(self._n): yield self._get_one(i)\n"
  result &= "  def __reversed__(self):\n"
  result &= "    for i in range(self._n - 1, -1, -1): yield self._get_one(i)\n"
  result &= "  def __contains__(self, v): return any(x == v for x in self)\n"
  result &= "  def __repr__(self): return f'NativeListView(len={self._n})'\n"
  result &= "  def __del__(self):\n"
  result &= "    if self._ptr and self._free_fn: self._free_fn(self._ptr)\n"
  result &= "  def index(self, v, start=0, stop=None):\n"
  result &= "    stop = self._n if stop is None else min(stop, self._n)\n"
  result &= "    for i in range(start, stop):\n"
  result &= "      if self._get_one(i) == v: return i\n"
  result &= "    raise ValueError(f'{v!r} is not in NativeListView')\n"
  result &= "  def count(self, v): return sum(1 for x in self if x == v)\n"
  result &= "  def to_list(self) -> list:\n"
  result &= "    return [self._get_one(i) for i in range(self._n)]\n"
  result &= "  def to_numpy(self):\n"
  result &= "    if not _HAS_NUMPY: return None\n"
  result &= "    data_addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16\n"
  result &= "    raw = (ctypes.c_char * (self._n * self._elem_size)).from_address(data_addr)\n"
  result &= "    if self._numpy_dtype is not None:\n"
  result &= "      # POD struct — read-only copy (Nim may free the buffer anytime)\n"
  result &= "      return np.frombuffer(raw, dtype=self._numpy_dtype, count=self._n).copy()\n"
  result &= "    elif self._elem_ctype is not None:\n"
  result &= "      return np.frombuffer(raw, dtype=np.dtype(self._elem_ctype), count=self._n).copy()\n"
  result &= "    return None\n"
  result &= "\n"
  result &= "# -- SharedListView (share mode: zero-copy, read-write) --\n"
  result &= "\n"
  result &= "class SharedListView:\n"
  result &= "  __slots__ = ('_ptr', '_n', '_elem_size', '_unpacker', '_type_id', '_is_pod', '_elem_ctype', '_numpy_dtype')\n"
  result &= "  def __init__(self, ptr, n: int, elem_size: int, unpacker, type_id: int = 0,\n"
  result &= "               is_pod: bool = True, elem_ctype=None, numpy_dtype=None):\n"
  result &= "    self._ptr = ptr\n"
  result &= "    self._n = n\n"
  result &= "    self._elem_size = elem_size\n"
  result &= "    self._unpacker = unpacker\n"
  result &= "    self._type_id = type_id\n"
  result &= "    self._is_pod = is_pod\n"
  result &= "    self._elem_ctype = getattr(ctypes, elem_ctype) if isinstance(elem_ctype, str) else elem_ctype\n"
  result &= "    self._numpy_dtype = numpy_dtype\n"
  result &= "  def __len__(self): return self._n\n"
  result &= "  def _get_one(self, i: int):\n"
  result &= "    addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16 + i * self._elem_size\n"
  result &= "    if self._unpacker: return self._unpacker(addr)\n"
  result &= "    return ctypes.cast(addr, ctypes.POINTER(self._elem_ctype)).contents.value\n"
  result &= "  def _set_one(self, i: int, v):\n"
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
  result &= "  def __getitem__(self, key):\n"
  result &= "    if isinstance(key, slice):\n"
  result &= "      return [self._get_one(i) for i in range(*key.indices(self._n))]\n"
  result &= "    i = key if key >= 0 else self._n + key\n"
  result &= "    if i < 0 or i >= self._n: raise IndexError(f'SharedListView index {key} out of range (len={self._n})')\n"
  result &= "    return self._get_one(i)\n"
  result &= "  def __setitem__(self, key, v):\n"
  result &= "    if isinstance(key, slice):\n"
  result &= "      indices = range(*key.indices(self._n))\n"
  result &= "      values = list(v)\n"
  result &= "      if len(indices) != len(values): raise ValueError('slice assignment length mismatch')\n"
  result &= "      for i, val in zip(indices, values): self._set_one(i, val)\n"
  result &= "      return\n"
  result &= "    i = key if key >= 0 else self._n + key\n"
  result &= "    if i < 0 or i >= self._n: raise IndexError(f'SharedListView index {key} out of range (len={self._n})')\n"
  result &= "    self._set_one(i, v)\n"
  result &= "  def __iter__(self):\n"
  result &= "    for i in range(self._n): yield self._get_one(i)\n"
  result &= "  def __reversed__(self):\n"
  result &= "    for i in range(self._n - 1, -1, -1): yield self._get_one(i)\n"
  result &= "  def __contains__(self, v): return any(x == v for x in self)\n"
  result &= "  def __repr__(self): return f'SharedListView(len={self._n})'\n"
  result &= "  def index(self, v, start=0, stop=None):\n"
  result &= "    stop = self._n if stop is None else min(stop, self._n)\n"
  result &= "    for i in range(start, stop):\n"
  result &= "      if self._get_one(i) == v: return i\n"
  result &= "    raise ValueError(f'{v!r} is not in SharedListView')\n"
  result &= "  def count(self, v): return sum(1 for x in self if x == v)\n"
  result &= "  def to_list(self) -> list:\n"
  result &= "    return [self._get_one(i) for i in range(self._n)]\n"
  result &= "  def free(self):\n"
  result &= "    if self._ptr:\n"
  result &= "      _lib.ocheFreeDeep(self._ptr)\n"
  result &= "      self._ptr = None\n"
  result &= "      self._n = 0\n"
  result &= "  def __del__(self): self.free()  # GC safety net — explicit .free() preferred\n"
  result &= "  def __enter__(self): return self\n"
  result &= "  def __exit__(self, *_): self.free()\n"
  result &= "  def to_numpy(self):\n"
  result &= "    if not _HAS_NUMPY: return None\n"
  result &= "    data_addr = ctypes.cast(self._ptr, ctypes.c_void_p).value + 16\n"
  result &= "    raw = (ctypes.c_char * (self._n * self._elem_size)).from_address(data_addr)\n"
  result &= "    if self._numpy_dtype is not None:\n"
  result &= "      # POD struct — zero-copy writable view directly into Nim RAM\n"
  result &= "      return np.frombuffer(raw, dtype=self._numpy_dtype, count=self._n)\n"
  result &= "    elif self._elem_ctype is not None:\n"
  result &= "      # primitive — zero-copy writable view directly into Nim RAM\n"
  result &= "      return np.frombuffer(raw, dtype=np.dtype(self._elem_ctype), count=self._n)\n"
  result &= "    return None\n"
  result &= "\n"