import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }

enum UserRole {
  Admin,
  Editor,
  Viewer,
}

final class NPoint extends ffi.Struct {
  @ffi.Double() external double x;
  @ffi.Double() external double y;
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

final class NUser extends ffi.Struct {
  @ffi.Int64() external int id;
  external ffi.Pointer<Utf8> name;
  @ffi.Int32() external int status;
  external NPoint position;
}

class User {
  final int id;
  final String name;
  final UserRole status;
  final Point position;
  const User({
    required this.id,
    required this.name,
    required this.status,
    required this.position
  });

  void _pack(NUser target, ffi.Allocator a) {
    target.id = id;
    target.name = name.toNativeUtf8(allocator: a);
    target.status = status.index;
    position._pack(target.position, a);
  }

  static User _unpack(NUser source) {
    return User(
    id: source.id,
    name: (source.name.address == 0) ? '' : source.name.toDartString(),
    status: UserRole.values[source.status],
    position: Point._unpack(source.position),
    );
  }
}

  typedef NgreetN = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  typedef NgreetD = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
  final ngreetCall = dynlib.lookupFunction<NgreetN, NgreetD>('greet');

  String greet(final String v_name) {
    return using((a) {

      final p = ngreetCall(v_name.toNativeUtf8(allocator: a)); _checkError();
      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }
    });
  }

  Future<String> greetAsync(final String v_name) => Isolate.run(() => greet(v_name));
  typedef NgetMultipliersN = ffi.Pointer<ffi.Void> Function(ffi.Int64, ffi.Int64);
  typedef NgetMultipliersD = ffi.Pointer<ffi.Void> Function(int, int);
  final ngetMultipliersCall = dynlib.lookupFunction<NgetMultipliersN, NgetMultipliersD>('getMultipliers');

  List<int> getMultipliers(final int v_base, final int v_count) {
    return using((a) {

      final p = ngetMultipliersCall(v_base, v_count); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<ffi.Int64>.fromAddress(p.address + 8);
        return d.asTypedList(L).toList();
      } finally { _ocheFree(p); }
    });
  }

  Future<List<int>> getMultipliersAsync(final int v_base, final int v_count) => Isolate.run(() => getMultipliers(v_base, v_count));
  typedef NsumPointsN = ffi.Double Function(ffi.Pointer<NPoint>, ffi.Int64);
  typedef NsumPointsD = double Function(ffi.Pointer<NPoint>, int);
  final nsumPointsCall = dynlib.lookupFunction<NsumPointsN, NsumPointsD>('sumPoints');

  double sumPoints(final List<Point> v_points) {
    return using((a) {
    final _v_pointsPtr = a.allocate<NPoint>(v_points.length * ffi.sizeOf<NPoint>());
    for (var i = 0; i < v_points.length; i++) { v_points[i]._pack(_v_pointsPtr[i], a); }
      final r = nsumPointsCall(_v_pointsPtr, v_points.length); _checkError();
      return r;
    });
  }

  Future<double> sumPointsAsync(final List<Point> v_points) => Isolate.run(() => sumPoints(v_points));
  typedef NfindUserByIdN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
  typedef NfindUserByIdD = ffi.Pointer<ffi.Void> Function(int);
  final nfindUserByIdCall = dynlib.lookupFunction<NfindUserByIdN, NfindUserByIdD>('findUserById');

  User? findUserById(final int v_id) {
    return using((a) {

      final p = nfindUserByIdCall(v_id); _checkError();
      if (p.address == 0) return null; try {
        return User._unpack(p.cast<NUser>().ref);
      } finally { _ocheFree(p); }
    });
  }

  Future<User?> findUserByIdAsync(final int v_id) => Isolate.run(() => findUserById(v_id));
  typedef NisPrimeN = ffi.Bool Function(ffi.Int64);
  typedef NisPrimeD = bool Function(int);
  final nisPrimeCall = dynlib.lookupFunction<NisPrimeN, NisPrimeD>('isPrime');

  bool isPrime(final int v_n) {
    return using((a) {

      final r = nisPrimeCall(v_n); _checkError();
      return r;
    });
  }

  Future<bool> isPrimeAsync(final int v_n) => Isolate.run(() => isPrime(v_n));
  typedef NheavyTaskN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
  typedef NheavyTaskD = ffi.Pointer<ffi.Void> Function(int);
  final nheavyTaskCall = dynlib.lookupFunction<NheavyTaskN, NheavyTaskD>('heavyTask');

  String heavyTask(final int v_seconds) {
    return using((a) {

      final p = nheavyTaskCall(v_seconds); _checkError();
      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }
    });
  }

  Future<String> heavyTaskAsync(final int v_seconds) => Isolate.run(() => heavyTask(v_seconds));
