import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'package:ffi/ffi.dart';
final dynlib = ffi.DynamicLibrary.open('./libmain.so');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }
enum UserRole {
  Admin,
  Editor,
  Viewer,
}

final class User extends ffi.Struct {
  @ffi.Int64() external int id;
  @ffi.Int32() external int role;
}

  typedef NgreetNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  typedef NgreetDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  final ngreetCall = dynlib.lookupFunction<NgreetNative, NgreetDart>('greet');
  String greet(String name) {
    return using((a) {

      final p = ngreetCall(name.toNativeUtf8(allocator: a)); _checkError();
      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }
    });
  }
  Future<String> greetAsync(String name) => Isolate.run(() => greet(name));
  typedef NcheckAccessNative = ffi.Pointer<ffi.Void> Function(User);
  typedef NcheckAccessDart = ffi.Pointer<ffi.Void> Function(User);
  final ncheckAccessCall = dynlib.lookupFunction<NcheckAccessNative, NcheckAccessDart>('checkAccess');
  String checkAccess(User user) {
    return using((a) {

      final p = ncheckAccessCall(user); _checkError();
      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }
    });
  }
  Future<String> checkAccessAsync(User user) => Isolate.run(() => checkAccess(user));
  typedef NslowComputeNative = ffi.Int64 Function(ffi.Int64);
  typedef NslowComputeDart = int Function(int);
  final nslowComputeCall = dynlib.lookupFunction<NslowComputeNative, NslowComputeDart>('slowCompute');
  int slowCompute(int n) {
    return using((a) {

      final r = nslowComputeCall(n); 
      _checkError();
    return r;
    });
  }
  Future<int> slowComputeAsync(int n) => Isolate.run(() => slowCompute(n));
  typedef NgetScoreNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  typedef NgetScoreDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  final ngetScoreCall = dynlib.lookupFunction<NgetScoreNative, NgetScoreDart>('getScore');
  double? getScore(String name) {
    return using((a) {

      final p = ngetScoreCall(name.toNativeUtf8(allocator: a)); _checkError();
      if (p.address == 0) return null; try {
        return p.cast<ffi.Double>().value;
      } finally { _ocheFree(p); }
    });
  }
  Future<double?> getScoreAsync(String name) => Isolate.run(() => getScore(name));
  typedef NfindUserIdNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  typedef NfindUserIdDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  final nfindUserIdCall = dynlib.lookupFunction<NfindUserIdNative, NfindUserIdDart>('findUserId');
  int? findUserId(String name) {
    return using((a) {

      final p = nfindUserIdCall(name.toNativeUtf8(allocator: a)); _checkError();
      if (p.address == 0) return null; try {
        return p.cast<ffi.Int64>().value;
      } finally { _ocheFree(p); }
    });
  }
  Future<int?> findUserIdAsync(String name) => Isolate.run(() => findUserId(name));
