import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Pointer<Utf8>), void Function(ffi.Pointer, ffi.Pointer<Utf8>)>('ocheFreeDeep');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
class NativeListView<T> {
  final ffi.Pointer<ffi.Void> _ptr;
  final String _typeName;
  final T Function(ffi.Pointer<ffi.Void> ptr) _unpacker;
  final int _elemSize;
  late final int length;
  NativeListView(this._ptr, this._typeName, this._unpacker, this._elemSize) { length = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address).value; }
  T operator [](int index) { if (index < 0 || index >= length) throw RangeError.index(index, this); return _unpacker(ffi.Pointer<ffi.Void>.fromAddress(_ptr.address + ffi.sizeOf<ffi.Int64>() + (index * _elemSize))); }
  void dispose() { using((Arena a) => _ocheFreeDeep(_ptr, _typeName.toNativeUtf8(allocator: a))); }
}
final class NPoint extends ffi.Struct {
  @ffi.Double() external double x;
  @ffi.Double() external double y;
}

extension type PointView(ffi.Pointer<NPoint> _ptr) {
  double get x => _ptr.ref.x;
  double get y => _ptr.ref.y;
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
class Oche {
  late final ngetPointsCopyCall = dynlib.lookupFunction<NgetPointsCopyN, NgetPointsCopyD>('getPointsCopy');

  List<Point> getPointsCopy(final int v_n) {
    return using((a) {

      final p = ngetPointsCopyCall(v_n); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<NPoint>.fromAddress(p.address + ffi.sizeOf<ffi.Int64>());
        return List<Point>.generate(L, (i) => Point._unpack(d[i]));
      } finally { using((Arena a) => _ocheFreeDeep(p, 'seq[Point]'.toNativeUtf8(allocator: a))); }
    });
  }
  late final ngetPointsViewCall = dynlib.lookupFunction<NgetPointsViewN, NgetPointsViewD>('getPointsView');

  NativeListView<PointView> getPointsView(final int v_n) {
    return using((a) {

      final p = ngetPointsViewCall(v_n); _checkError();
      return NativeListView<PointView>(p, 'Point', (ptr) => PointView(ptr.cast<NPoint>()), ffi.sizeOf<NPoint>());
    });
  }

}
final oche = Oche();
