import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
final class NPoint extends ffi.Struct {
  @ffi.Double() external double x;
  @ffi.Double() external double y;
}

extension type PointView(ffi.Pointer<NPoint> _ptr) {
  double get x => _ptr.ref.x;
  set x(double v) => _ptr.ref.x = v;
  double get y => _ptr.ref.y;
  set y(double v) => _ptr.ref.y = v;
}

class Point {
  final double x;
  final double y;
  const Point({
    required this.x,
    required this.y
  });

  void _pack(NPoint target, ffi.Allocator a) {
    target.x = x;
    target.y = y;
  }

  static Point _unpack(NPoint source) {
    return Point(
    x: source.x,
    y: source.y,
    );
  }
}
typedef NgetPointsCopyN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgetPointsCopyD = ffi.Pointer<ffi.Void> Function(int);
typedef NgetPointsViewN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgetPointsViewD = ffi.Pointer<ffi.Void> Function(int);
typedef NgetPointsSharedN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgetPointsSharedD = ffi.Pointer<ffi.Void> Function(int);
typedef NupdatePointFastN = ffi.Void Function(ffi.Int64, ffi.Double);
typedef NupdatePointFastD = void Function(int, double);
typedef NprintSharedPointN = ffi.Void Function(ffi.Int64);
typedef NprintSharedPointD = void Function(int);
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
  final void Function(ffi.Pointer<ffi.Void> ptr, dynamic value, ffi.Allocator a)? _packer;
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
    if (_packer != null) { using((a) => _packer!(p, value, a)); }
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
  late final ngetPointsCopyCall = dynlib.lookupFunction<NgetPointsCopyN, NgetPointsCopyD>('getPointsCopy');

  List<Point> getPointsCopy(final int v_n) {
      final p = ngetPointsCopyCall(v_n); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<NPoint>.fromAddress(p.address + 16);
        return List<Point>.generate(L, (i) => Point._unpack(d[i]));
      } finally { _ocheFreeDeep(p); }
  }
  late final ngetPointsViewCall = dynlib.lookupFunction<NgetPointsViewN, NgetPointsViewD>('getPointsView');

  NativeListView<PointView> getPointsView(final int v_n) {
      final p = ngetPointsViewCall(v_n); _checkError();
      return NativeListView<PointView>(p, (ptr) => PointView(ptr.cast<NPoint>()), ffi.sizeOf<NPoint>());
  }
  late final ngetPointsSharedCall = dynlib.lookupFunction<NgetPointsSharedN, NgetPointsSharedD>('getPointsShared');

  SharedListView<PointView> getPointsShared(final int v_n) {
      final p = ngetPointsSharedCall(v_n); _checkError();
      return SharedListView<PointView>(p, (ptr) => PointView(ptr.cast<NPoint>()), (p, v, a) { if (v is Point) v._pack(p.cast<NPoint>().ref, a); else if (v is PointView) { for(int j=0; j<ffi.sizeOf<NPoint>(); j++) p.cast<ffi.Uint8>()[j] = v._ptr.cast<ffi.Uint8>()[j]; } }, ffi.sizeOf<NPoint>());
  }
  late final nupdatePointFastCall = dynlib.lookupFunction<NupdatePointFastN, NupdatePointFastD>('updatePointFast');

  void updatePointFast(final int v_idx, final double v_x) {
      nupdatePointFastCall(v_idx, v_x); _checkError();
  }
  late final nprintSharedPointCall = dynlib.lookupFunction<NprintSharedPointN, NprintSharedPointD>('printSharedPoint');

  void printSharedPoint(final int v_idx) {
      nprintSharedPointCall(v_idx); _checkError();
  }

}
final oche = Oche();
