import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libbench2.dll' : (Platform.isMacOS ? 'libbench2.dylib' : 'libbench2.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');
final _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
final class NPixel extends ffi.Struct {
  @ffi.Uint8() external int r;
  @ffi.Uint8() external int g;
  @ffi.Uint8() external int b;
  @ffi.Uint8() external int a;
}

extension type PixelView(NPixel _ref) {
  int get r => _ref.r;
  set r(int v) => _ref.r = v;
  int get g => _ref.g;
  set g(int v) => _ref.g = v;
  int get b => _ref.b;
  set b(int v) => _ref.b = v;
  int get a => _ref.a;
  set a(int v) => _ref.a = v;
  void _packInto(ffi.Pointer<NPixel> p) {
    p.ref.r = _ref.r;
    p.ref.g = _ref.g;
    p.ref.b = _ref.b;
    p.ref.a = _ref.a;
  }
}

class Pixel {
  final int r;
  final int g;
  final int b;
  final int a;
  const Pixel({
    required this.r,
    required this.g,
    required this.b,
    required this.a
  });

  void _pack(NPixel target, ffi.Allocator alloc) {
    target.r = r;
    target.g = g;
    target.b = b;
    target.a = a;
  }

  void _packManual(NPixel target) {
    target.r = r;
    target.g = g;
    target.b = b;
    target.a = a;
  }

  static Pixel _unpack(NPixel source) {
    return Pixel(
    r: source.r,
    g: source.g,
    b: source.b,
    a: source.a,
    );
  }
}
final class NEntity extends ffi.Struct {
  @ffi.Float() external double x;
  @ffi.Float() external double y;
  @ffi.Float() external double radius;
  @ffi.Bool() external bool colliding;
}

extension type EntityView(NEntity _ref) {
  double get x => _ref.x;
  set x(double v) => _ref.x = v;
  double get y => _ref.y;
  set y(double v) => _ref.y = v;
  double get radius => _ref.radius;
  set radius(double v) => _ref.radius = v;
  bool get colliding => _ref.colliding;
  set colliding(bool v) => _ref.colliding = v;
  void _packInto(ffi.Pointer<NEntity> p) {
    p.ref.x = _ref.x;
    p.ref.y = _ref.y;
    p.ref.radius = _ref.radius;
    p.ref.colliding = _ref.colliding;
  }
}

class Entity {
  final double x;
  final double y;
  final double radius;
  final bool colliding;
  const Entity({
    required this.x,
    required this.y,
    required this.radius,
    required this.colliding
  });

  void _pack(NEntity target, ffi.Allocator alloc) {
    target.x = x;
    target.y = y;
    target.radius = radius;
    target.colliding = colliding;
  }

  void _packManual(NEntity target) {
    target.x = x;
    target.y = y;
    target.radius = radius;
    target.colliding = colliding;
  }

  static Entity _unpack(NEntity source) {
    return Entity(
    x: source.x,
    y: source.y,
    radius: source.radius,
    colliding: source.colliding,
    );
  }
}
typedef NnbodyNimN = ffi.Double Function(ffi.Int64);
typedef NnbodyNimD = double Function(int);
typedef NfannkuchNimN = ffi.Int64 Function(ffi.Int64);
typedef NfannkuchNimD = int Function(int);
typedef NinitImageN = ffi.Pointer<ffi.Void> Function(ffi.Int64, ffi.Int64);
typedef NinitImageD = ffi.Pointer<ffi.Void> Function(int, int);
typedef NprocessImageGrayscaleN = ffi.Void Function();
typedef NprocessImageGrayscaleD = void Function();
typedef NinitEntitiesN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NinitEntitiesD = ffi.Pointer<ffi.Void> Function(int);
typedef NdetectCollisionsN = ffi.Void Function();
typedef NdetectCollisionsD = void Function();
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
  late final nnbodyNimCall = dynlib.lookupFunction<NnbodyNimN, NnbodyNimD>('nbodyNim');

  double nbodyNim(final int v_iterations) {
      final r = nnbodyNimCall(v_iterations); _checkError();
      return r;
  }
  late final nfannkuchNimCall = dynlib.lookupFunction<NfannkuchNimN, NfannkuchNimD>('fannkuchNim');

  int fannkuchNim(final int v_n) {
      final r = nfannkuchNimCall(v_n); _checkError();
      return r;
  }
  late final ninitImageCall = dynlib.lookupFunction<NinitImageN, NinitImageD>('initImage');

  SharedListView<PixelView> initImage(final int v_w, final int v_h) {
      final p = ninitImageCall(v_w, v_h); _checkError();
      return SharedListView<PixelView>(p, (ptr) => PixelView(ptr.cast<NPixel>().ref), (p, v) { if (v is Pixel) { v._packManual(p.cast<NPixel>().ref); } else if (v is PixelView) { v._packInto(p.cast<NPixel>()); } }, ffi.sizeOf<NPixel>());
  }
  late final nprocessImageGrayscaleCall = dynlib.lookupFunction<NprocessImageGrayscaleN, NprocessImageGrayscaleD>('processImageGrayscale');

  void processImageGrayscale() {
      nprocessImageGrayscaleCall(); _checkError();
  }
  late final ninitEntitiesCall = dynlib.lookupFunction<NinitEntitiesN, NinitEntitiesD>('initEntities');

  SharedListView<EntityView> initEntities(final int v_n) {
      final p = ninitEntitiesCall(v_n); _checkError();
      return SharedListView<EntityView>(p, (ptr) => EntityView(ptr.cast<NEntity>().ref), (p, v) { if (v is Entity) { v._packManual(p.cast<NEntity>().ref); } else if (v is EntityView) { v._packInto(p.cast<NEntity>()); } }, ffi.sizeOf<NEntity>());
  }
  late final ndetectCollisionsCall = dynlib.lookupFunction<NdetectCollisionsN, NdetectCollisionsD>('detectCollisions');

  void detectCollisions() {
      ndetectCollisionsCall(); _checkError();
  }

}
final oche = Oche();
