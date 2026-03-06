import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeDeep');
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
typedef NprintSharedPointN = ffi.Void Function(ffi.Int64);
typedef NprintSharedPointD = void Function(int);
final _finalizer = Finalizer<ffi.Pointer<ffi.Void>>((ptr) => _ocheFree(ptr));
final _finalizerDeep = Finalizer<(ffi.Pointer<ffi.Void>, int)>((msg) => _ocheFreeDeep(msg.$1, msg.$2));

abstract class OcheView<T> with IterableMixin<T> {
  ffi.Pointer<ffi.Void> get _nativePtr;
  int get length;
  @override Iterator<T> get iterator => _NativeListIterator<T>(this);
  T operator [](int index);
}

class NativeListView<T> extends OcheView<T> {
  ffi.Pointer<ffi.Void> _ptr;
  final int _typeId;
  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;
  final int _elemSize;
  @override late final int length;
  NativeListView(this._ptr, this._typeId, this._unpacker, this._elemSize) {
    if (_ptr.address == 0) { length = 0; return; }
    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;
    _finalizerDeep.attach(this, (_ptr, _typeId), detach: this);
  }
  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;
  @override T operator [](int index) {
    if (_ptr.address == 0) throw StateError('NativeListView has been disposed');
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 8 + (index * _elemSize)));
  }
  void dispose() {
    if (_ptr.address == 0) return;
    _finalizerDeep.detach(this);
    _ocheFreeDeep(_ptr, _typeId);
    _ptr = ffi.Pointer.fromAddress(0);
  }
}

class SharedListView<T> extends OcheView<T> {
  final ffi.Pointer<ffi.Void> _ptr;
  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;
  final int _elemSize;
  @override late final int length;
  SharedListView(this._ptr, this._unpacker, this._elemSize) {
    if (_ptr.address == 0) { length = 0; return; }
    length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value;
  }
  @override ffi.Pointer<ffi.Void> get _nativePtr => _ptr;
  @override T operator [](int index) {
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + 8 + (index * _elemSize)));
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
    return using((a) {

      final p = ngetPointsCopyCall(v_n); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<NPoint>.fromAddress(p.address + 8);
        return List<Point>.generate(L, (i) => Point._unpack(d[i]));
      } finally { _ocheFreeDeep(p, 1); }
    });
  }
  late final ngetPointsViewCall = dynlib.lookupFunction<NgetPointsViewN, NgetPointsViewD>('getPointsView');

  NativeListView<PointView> getPointsView(final int v_n) {
    return using((a) {

      final p = ngetPointsViewCall(v_n); _checkError();
      return NativeListView<PointView>(p, 1, (ptr) => PointView(ptr.cast<NPoint>()), ffi.sizeOf<NPoint>());
    });
  }
  late final ngetPointsSharedCall = dynlib.lookupFunction<NgetPointsSharedN, NgetPointsSharedD>('getPointsShared');

  SharedListView<PointView> getPointsShared(final int v_n) {
    return using((a) {

      final p = ngetPointsSharedCall(v_n); _checkError();
      return SharedListView<PointView>(p, (ptr) => PointView(ptr.cast<NPoint>()), ffi.sizeOf<NPoint>());
    });
  }
  late final nprintSharedPointCall = dynlib.lookupFunction<NprintSharedPointN, NprintSharedPointD>('printSharedPoint');

  void printSharedPoint(final int v_idx) {
    return using((a) {

      nprintSharedPointCall(v_idx); _checkError();
    });
  }

}
final oche = Oche();
