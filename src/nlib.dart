import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
final dynlib = ffi.DynamicLibrary.open('./libmain.so');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final class Employer extends ffi.Struct {
  external People secretary;
}

final class People extends ffi.Struct {
  @ffi.Int64() external int id;
  @ffi.Int64() external int age;
}

final class User extends ffi.Struct {
  @ffi.Int64() external int id;
  @ffi.Double() external double score;
}

  typedef NAddNative = ffi.Int64 Function(ffi.Int64, ffi.Int64);
  typedef NAddDart = int Function(int, int);
  final naddCall = dynlib.lookupFunction<NAddNative, NAddDart>('add');
  int add(int a, int b) {
    return using((arena) {
  
    return naddCall(a, b);
    });
  }
  typedef NSumNative = ffi.Int64 Function(ffi.Pointer<ffi.Int64>, ffi.Int64);
  typedef NSumDart = int Function(ffi.Pointer<ffi.Int64>, int);
  final nsumCall = dynlib.lookupFunction<NSumNative, NSumDart>('sum');
  int sum(List<int> vals) {
    return using((arena) {
      final _valsPtr = arena.allocate<ffi.Int64>(vals.length * 8);
    for (var i = 0; i < vals.length; i++) { _valsPtr[i] = vals[i]; }
    return nsumCall(_valsPtr, vals.length);
    });
  }
  typedef NGetRangeNative = ffi.Pointer<ffi.Void> Function(ffi.Int64);
  typedef NGetRangeDart = ffi.Pointer<ffi.Void> Function(int);
  final ngetRangeCall = dynlib.lookupFunction<NGetRangeNative, NGetRangeDart>('getRange');
  List<int> getRange(int n) {
    return using((arena) {
  
    final _ptr = ngetRangeCall(n);
    if (_ptr.address == 0) return [];
    try { final _len = _ptr.cast<ffi.Int64>().value; final _view = ffi.Pointer<ffi.Int64>.fromAddress(_ptr.address + 8).asTypedList(_len); return _view.toList(); } finally { _ocheFree(_ptr); }
    });
  }
  typedef NGetTopPlayersNative = ffi.Pointer<ffi.Void> Function();
  typedef NGetTopPlayersDart = ffi.Pointer<ffi.Void> Function();
  final ngetTopPlayersCall = dynlib.lookupFunction<NGetTopPlayersNative, NGetTopPlayersDart>('getTopPlayers');
  List<User> getTopPlayers() {
    return using((arena) {
  
    final _ptr = ngetTopPlayersCall();
    if (_ptr.address == 0) return [];
    try { final _len = _ptr.cast<ffi.Int64>().value; final _dataPtr = ffi.Pointer<User>.fromAddress(_ptr.address + 8); return List<User>.generate(_len, (i) => _dataPtr[i]); } finally { _ocheFree(_ptr); }
    });
  }
  typedef NCreateEmployerNative = Employer Function(ffi.Int64, ffi.Int64);
  typedef NCreateEmployerDart = Employer Function(int, int);
  final ncreateEmployerCall = dynlib.lookupFunction<NCreateEmployerNative, NCreateEmployerDart>('createEmployer');
  Employer createEmployer(int id, int age) {
    return using((arena) {
  
    return ncreateEmployerCall(id, age);
    });
  }
  typedef NGreetNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  typedef NGreetDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  final ngreetCall = dynlib.lookupFunction<NGreetNative, NGreetDart>('greet');
  String greet(String name) {
    return using((arena) {
  
    final _ptr = ngreetCall(name.toNativeUtf8(allocator: arena));
    if (_ptr.address == 0) return '';
    try { return _ptr.cast<Utf8>().toDartString(); } finally { _ocheFree(_ptr); }
    });
  }
