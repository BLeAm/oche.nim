import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libbench_suite.dll' : (Platform.isMacOS ? 'libbench_suite.dylib' : 'libbench_suite.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
  typedef NnbodyNimN = ffi.Double Function(ffi.Int64);
  typedef NnbodyNimD = double Function(int);
  final nnbodyNimCall = dynlib.lookupFunction<NnbodyNimN, NnbodyNimD>('nbodyNim');

  double nbodyNim(final int v_n) {
    return using((a) {

      final r = nnbodyNimCall(v_n); _checkError();
      return r;
    });
  }

  Future<double> nbodyNimAsync(final int v_n) => Isolate.run(() => nbodyNim(v_n));
  typedef NfannkuchNimN = ffi.Int64 Function(ffi.Int64);
  typedef NfannkuchNimD = int Function(int);
  final nfannkuchNimCall = dynlib.lookupFunction<NfannkuchNimN, NfannkuchNimD>('fannkuchNim');

  int fannkuchNim(final int v_n) {
    return using((a) {

      final r = nfannkuchNimCall(v_n); _checkError();
      return r;
    });
  }

  Future<int> fannkuchNimAsync(final int v_n) => Isolate.run(() => fannkuchNim(v_n));
  typedef NspectralNormNimN = ffi.Double Function(ffi.Int64);
  typedef NspectralNormNimD = double Function(int);
  final nspectralNormNimCall = dynlib.lookupFunction<NspectralNormNimN, NspectralNormNimD>('spectralNormNim');

  double spectralNormNim(final int v_n) {
    return using((a) {

      final r = nspectralNormNimCall(v_n); _checkError();
      return r;
    });
  }

  Future<double> spectralNormNimAsync(final int v_n) => Isolate.run(() => spectralNormNim(v_n));
  typedef NbinaryTreesNimN = ffi.Int64 Function(ffi.Int64);
  typedef NbinaryTreesNimD = int Function(int);
  final nbinaryTreesNimCall = dynlib.lookupFunction<NbinaryTreesNimN, NbinaryTreesNimD>('binaryTreesNim');

  int binaryTreesNim(final int v_depth) {
    return using((a) {

      final r = nbinaryTreesNimCall(v_depth); _checkError();
      return r;
    });
  }

  Future<int> binaryTreesNimAsync(final int v_depth) => Isolate.run(() => binaryTreesNim(v_depth));
  typedef NmandelbrotNimN = ffi.Int64 Function(ffi.Int64);
  typedef NmandelbrotNimD = int Function(int);
  final nmandelbrotNimCall = dynlib.lookupFunction<NmandelbrotNimN, NmandelbrotNimD>('mandelbrotNim');

  int mandelbrotNim(final int v_n) {
    return using((a) {

      final r = nmandelbrotNimCall(v_n); _checkError();
      return r;
    });
  }

  Future<int> mandelbrotNimAsync(final int v_n) => Isolate.run(() => mandelbrotNim(v_n));
