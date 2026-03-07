import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libbench_suite.dll' : (Platform.isMacOS ? 'libbench_suite.dylib' : 'libbench_suite.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');
final _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
typedef NnbodyNimN = ffi.Double Function(ffi.Int64);
typedef NnbodyNimD = double Function(int);
typedef NfannkuchNimN = ffi.Int64 Function(ffi.Int64);
typedef NfannkuchNimD = int Function(int);
typedef NspectralNormNimN = ffi.Double Function(ffi.Int64);
typedef NspectralNormNimD = double Function(int);
typedef NbinaryTreesNimN = ffi.Int64 Function(ffi.Int64);
typedef NbinaryTreesNimD = int Function(int);
typedef NmandelbrotNimN = ffi.Int64 Function(ffi.Int64);
typedef NmandelbrotNimD = int Function(int);
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

  double nbodyNim(final int v_n) {
      final r = nnbodyNimCall(v_n); _checkError();
      return r;
  }
  late final nfannkuchNimCall = dynlib.lookupFunction<NfannkuchNimN, NfannkuchNimD>('fannkuchNim');

  int fannkuchNim(final int v_n) {
      final r = nfannkuchNimCall(v_n); _checkError();
      return r;
  }
  late final nspectralNormNimCall = dynlib.lookupFunction<NspectralNormNimN, NspectralNormNimD>('spectralNormNim');

  double spectralNormNim(final int v_n) {
      final r = nspectralNormNimCall(v_n); _checkError();
      return r;
  }
  late final nbinaryTreesNimCall = dynlib.lookupFunction<NbinaryTreesNimN, NbinaryTreesNimD>('binaryTreesNim');

  int binaryTreesNim(final int v_depth) {
      final r = nbinaryTreesNimCall(v_depth); _checkError();
      return r;
  }
  late final nmandelbrotNimCall = dynlib.lookupFunction<NmandelbrotNimN, NmandelbrotNimD>('mandelbrotNim');

  int mandelbrotNim(final int v_n) {
      final r = nmandelbrotNimCall(v_n); _checkError();
      return r;
  }

}
final oche = Oche();
