import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libbench.dll' : (Platform.isMacOS ? 'libbench.dylib' : 'libbench.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
  typedef NmonteCarloPiNimN = ffi.Double Function(ffi.Int64);
  typedef NmonteCarloPiNimD = double Function(int);
  final nmonteCarloPiNimCall = dynlib.lookupFunction<NmonteCarloPiNimN, NmonteCarloPiNimD>('monteCarloPiNim');

  double monteCarloPiNim(final int v_iterations) {
    return using((a) {

      final r = nmonteCarloPiNimCall(v_iterations); _checkError();
      return r;
    });
  }

  Future<double> monteCarloPiNimAsync(final int v_iterations) => Isolate.run(() => monteCarloPiNim(v_iterations));
  typedef NmandelbrotNimN = ffi.Pointer<ffi.Void> Function(ffi.Int64, ffi.Int64, ffi.Int64);
  typedef NmandelbrotNimD = ffi.Pointer<ffi.Void> Function(int, int, int);
  final nmandelbrotNimCall = dynlib.lookupFunction<NmandelbrotNimN, NmandelbrotNimD>('mandelbrotNim');

  List<int> mandelbrotNim(final int v_width, final int v_height, final int v_maxIter) {
    return using((a) {

      final p = nmandelbrotNimCall(v_width, v_height, v_maxIter); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<ffi.Int64>.fromAddress(p.address + 8);
        return d.asTypedList(L).toList();
      } finally { _ocheFree(p); }
    });
  }

  Future<List<int>> mandelbrotNimAsync(final int v_width, final int v_height, final int v_maxIter) => Isolate.run(() => mandelbrotNim(v_width, v_height, v_maxIter));
