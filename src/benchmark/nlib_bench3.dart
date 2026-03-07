import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libbench3.dll' : (Platform.isMacOS ? 'libbench3.dylib' : 'libbench3.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');
final _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
final class NVec3 extends ffi.Struct {
  @ffi.Double() external double x;
  @ffi.Double() external double y;
  @ffi.Double() external double z;
}

extension type Vec3View(NVec3 _ref) {
  double get x => _ref.x;
  set x(double v) => _ref.x = v;
  double get y => _ref.y;
  set y(double v) => _ref.y = v;
  double get z => _ref.z;
  set z(double v) => _ref.z = v;
  void _packInto(ffi.Pointer<NVec3> p) {
    p.ref.x = _ref.x;
    p.ref.y = _ref.y;
    p.ref.z = _ref.z;
  }
}

class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3({
    required this.x,
    required this.y,
    required this.z
  });

  void _pack(NVec3 target, ffi.Allocator alloc) {
    target.x = x;
    target.y = y;
    target.z = z;
  }

  void _packManual(NVec3 target) {
    target.x = x;
    target.y = y;
    target.z = z;
  }

  static Vec3 _unpack(NVec3 source) {
    return Vec3(
    x: source.x,
    y: source.y,
    z: source.z,
    );
  }
}
typedef NgenerateLargeArrayCopyN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgenerateLargeArrayCopyD = ffi.Pointer<ffi.Void> Function(int);
typedef NgenerateLargeArrayViewN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgenerateLargeArrayViewD = ffi.Pointer<ffi.Void> Function(int);
typedef NinitParticlesN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NinitParticlesD = ffi.Pointer<ffi.Void> Function(int);
typedef NnimUpdateParticlesN = ffi.Void Function(ffi.Double);
typedef NnimUpdateParticlesD = void Function(double);
final _finalizerDeep = Finalizer<ffi.Pointer<ffi.Void>>((ptr) => _ocheFreeDeep(ptr));

abstract class OcheView<T> extends ListBase<T> {
  ffi.Pointer<ffi.Void> get _nativePtr;
  @override int get length;
  @override set length(int value) => throw UnsupportedError('Cannot resize native buffer');
  @override Iterator<T> get iterator => _NativeListIterator<T>(this);
}

class NativeListView<T> extends OcheView<T> {
  ffi.Pointer<ffi.Void> _ptr;
  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;
  final int _elemSize;
  @override late final int length;
  NativeListView(this._ptr, this._unpacker, this._elemSize) {
    if (_ptr.address == 0) { length = 0; return; }
    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;
    _finalizerDeep.attach(this, _ptr, detach: this);
  }
  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;
  @override T operator [](int index) {
    if (_ptr.address == 0) throw StateError('NativeListView has been disposed');
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize)));
  }
  @override void operator []=(int index, T value) => throw UnsupportedError('View mode is read-only. Use Buffer mode for mutation.');
  void dispose() {
    if (_ptr.address == 0) return;
    _finalizerDeep.detach(this);
    _ocheFreeDeep(_ptr);
    _ptr = ffi.Pointer.fromAddress(0);
  }
}

class SharedListView<T> extends OcheView<T> {
  final ffi.Pointer<ffi.Void> _ptr;
  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;
  final void Function(ffi.Pointer<ffi.Void> ptr, dynamic value)? _packer;
  final int _elemSize;
  @override late final int length;
  SharedListView(this._ptr, this._unpacker, this._packer, this._elemSize) {
    if (_ptr.address == 0) { length = 0; return; }
    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;
  }
  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;
  @override T operator [](int index) {
    if (_ptr.address == 0) throw StateError('SharedListView has been disposed');
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize)));
  }
  @override void operator []=(int index, dynamic value) {
    if (_ptr.address == 0) throw StateError('SharedListView has been disposed');
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    final flags = ffi.Pointer<ffi.Int32>.fromAddress(_ptr.address + 12).value;
    if ((flags & 1) != 0) throw StateError('Buffer is frozen (READ-ONLY)');
    final p = ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 16 + (index * _elemSize));
    if (_packer != null) { _packer!(p, value); }
    else if (value is int) { ffi.Pointer<ffi.Int64>.fromAddress(p.address).value = value; }
    else if (value is double) { ffi.Pointer<ffi.Double>.fromAddress(p.address).value = value; }
    else if (value is bool) { ffi.Pointer<ffi.Bool>.fromAddress(p.address).value = value; }
    else { throw UnsupportedError('Mutation via []= not supported for this type.'); }
  }
}

class _NativeListIterator<T> implements Iterator<T> {
  final OcheView<T> _view; int _index = -1;
  _NativeListIterator(this._view);
  @override T get current => _view[_index];
  @override bool moveNext() => ++_index < _view.length;
}
class Oche {
  late final ngenerateLargeArrayCopyCall = dynlib.lookupFunction<NgenerateLargeArrayCopyN, NgenerateLargeArrayCopyD>('generateLargeArrayCopy');

  List<Vec3> generateLargeArrayCopy(final int v_n) {
      final p = ngenerateLargeArrayCopyCall(v_n); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<NVec3>.fromAddress(p.address + 16);
        return List<Vec3>.generate(L, (i) => Vec3._unpack(d[i]));
      } finally { _ocheFreeDeep(p); }
  }
  late final ngenerateLargeArrayViewCall = dynlib.lookupFunction<NgenerateLargeArrayViewN, NgenerateLargeArrayViewD>('generateLargeArrayView');

  NativeListView<Vec3View> generateLargeArrayView(final int v_n) {
      final p = ngenerateLargeArrayViewCall(v_n); _checkError();
      return NativeListView<Vec3View>(p, (ptr) => Vec3View(ptr.cast<NVec3>().ref), ffi.sizeOf<NVec3>());
  }
  late final ninitParticlesCall = dynlib.lookupFunction<NinitParticlesN, NinitParticlesD>('initParticles');

  SharedListView<Vec3View> initParticles(final int v_n) {
      final p = ninitParticlesCall(v_n); _checkError();
      return SharedListView<Vec3View>(p, (ptr) => Vec3View(ptr.cast<NVec3>().ref), (p, v) { if (v is Vec3) { v._packManual(p.cast<NVec3>().ref); } else if (v is Vec3View) { v._packInto(p.cast<NVec3>()); } }, ffi.sizeOf<NVec3>());
  }
  late final nnimUpdateParticlesCall = dynlib.lookupFunction<NnimUpdateParticlesN, NnimUpdateParticlesD>('nimUpdateParticles');

  void nimUpdateParticles(final double v_dt) {
      nnimUpdateParticlesCall(v_dt); _checkError();
  }

}
final oche = Oche();
