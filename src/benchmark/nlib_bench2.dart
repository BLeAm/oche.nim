import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libbench2.dll' : (Platform.isMacOS ? 'libbench2.dylib' : 'libbench2.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
  typedef NnbodyNimN = ffi.Double Function(ffi.Int64);
  typedef NnbodyNimD = double Function(int);
  final nnbodyNimCall = dynlib.lookupFunction<NnbodyNimN, NnbodyNimD>('nbodyNim');

  double nbodyNim(final int v_iterations) {
    return using((a) {

      final r = nnbodyNimCall(v_iterations); _checkError();
      return r;
    });
  }

  Future<double> nbodyNimAsync(final int v_iterations) => Isolate.run(() => nbodyNim(v_iterations));
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
