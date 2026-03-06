import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:ffi/ffi.dart';

final String _libName = Platform.isWindows ? 'libmain.dll' : (Platform.isMacOS ? 'libmain.dylib' : 'libmain.so');
final dynlib = ffi.DynamicLibrary.open('./$_libName');
final _ocheFree = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFree');
final _ocheFreeDeep = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer), void Function(ffi.Pointer)>('ocheFreeDeep');
final _ocheFreeInner = dynlib.lookupFunction<ffi.Void Function(ffi.Pointer, ffi.Int32), void Function(ffi.Pointer, int)>('ocheFreeInner');
final _ocheGetError = dynlib.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('ocheGetError');
void _checkError() { final ptr = _ocheGetError(); if (ptr.address != 0) { final msg = ptr.toDartString(); _ocheFree(ptr); throw Exception('NimError: $msg'); } }

enum Status {
  Active,
  Inactive,
  Pending,
}
final class NPoint extends ffi.Struct {
  @ffi.Double() external double x;
  @ffi.Double() external double y;
}

extension type PointView(NPoint _ref) {
  double get x => _ref.x;
  set x(double v) => _ref.x = v;
  double get y => _ref.y;
  set y(double v) => _ref.y = v;
  void _packInto(ffi.Pointer<NPoint> p) {
    p.ref.x = _ref.x;
    p.ref.y = _ref.y;
  }
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

  void _packManual(NPoint target) {
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
final class NTag extends ffi.Struct {
  external ffi.Pointer<Utf8> name;
  @ffi.Int64() external int id;
}

extension type TagView(NTag _ref) {
  String get name => (_ref.name.address == 0) ? '' : _ref.name.toDartString();
  int get id => _ref.id;
  set id(int v) => _ref.id = v;
  void _packInto(ffi.Pointer<NTag> p) {
    p.ref.name = _ref.name;
    p.ref.id = _ref.id;
  }
}

class Tag {
  final String name;
  final int id;
  const Tag({
    required this.name,
    required this.id
  });

  void _pack(NTag target, ffi.Allocator a) {
    target.name = name.toNativeUtf8(allocator: a);
    target.id = id;
  }

  void _packManual(NTag target) {
    target.name = name.toNativeUtf8(allocator: malloc);
    target.id = id;
  }

  static Tag _unpack(NTag source) {
    return Tag(
    name: (source.name.address == 0) ? '' : source.name.toDartString(),
    id: source.id,
    );
  }
}
final class NUser extends ffi.Struct {
  external ffi.Pointer<Utf8> username;
  @ffi.Int32() external int status;
  external NTag primaryTag;
}

extension type UserView(NUser _ref) {
  String get username => (_ref.username.address == 0) ? '' : _ref.username.toDartString();
  Status get status => Status.values[_ref.status];
  set status(Status v) => _ref.status = v.index;
  TagView get primaryTag => TagView(_ref.primaryTag);
  void _packInto(ffi.Pointer<NUser> p) {
    p.ref.username = _ref.username;
    p.ref.status = _ref.status;
    p.ref.primaryTag = _ref.primaryTag;
  }
}

class User {
  final String username;
  final Status status;
  final Tag primaryTag;
  const User({
    required this.username,
    required this.status,
    required this.primaryTag
  });

  void _pack(NUser target, ffi.Allocator a) {
    target.username = username.toNativeUtf8(allocator: a);
    target.status = status.index;
    this.primaryTag._pack(target.primaryTag, a);
  }

  void _packManual(NUser target) {
    target.username = username.toNativeUtf8(allocator: malloc);
    target.status = status.index;
    this.primaryTag._pack(target.primaryTag, malloc);
  }

  static User _unpack(NUser source) {
    return User(
    username: (source.username.address == 0) ? '' : source.username.toDartString(),
    status: Status.values[source.status],
    primaryTag: Tag._unpack(source.primaryTag),
    );
  }
}
typedef NaddNumbersN = ffi.Int64 Function(ffi.Int64, ffi.Int64);
typedef NaddNumbersD = int Function(int, int);
typedef NgreetN = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
typedef NgreetD = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
typedef NcreateUserN = NUser Function(ffi.Pointer<Utf8>, ffi.Int64);
typedef NcreateUserD = NUser Function(ffi.Pointer<Utf8>, int);
typedef NsumPointsN = ffi.Double Function(ffi.Pointer<NPoint>, ffi.Int64);
typedef NsumPointsD = double Function(ffi.Pointer<NPoint>, int);
typedef NgetPointsCopyN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgetPointsCopyD = ffi.Pointer<ffi.Void> Function(int);
typedef NgetPointsViewN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NgetPointsViewD = ffi.Pointer<ffi.Void> Function(int);
typedef NinitSharedPointsN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NinitSharedPointsD = ffi.Pointer<ffi.Void> Function(int);
typedef NprintSharedPointN = ffi.Void Function(ffi.Int64);
typedef NprintSharedPointD = void Function(int);
typedef NinitSharedUsersN = ffi.Pointer<ffi.Void> Function(ffi.Int64);
typedef NinitSharedUsersD = ffi.Pointer<ffi.Void> Function(int);
typedef NprintSharedUserN = ffi.Void Function(ffi.Int64);
typedef NprintSharedUserD = void Function(int);
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
  late final naddNumbersCall = dynlib.lookupFunction<NaddNumbersN, NaddNumbersD>('addNumbers');

  int addNumbers(final int v_a, final int v_b) {
      final r = naddNumbersCall(v_a, v_b); _checkError();
      return r;
  }
  late final ngreetCall = dynlib.lookupFunction<NgreetN, NgreetD>('greet');

  String greet(final String v_name) {
    return using((a) {

      final p = ngreetCall(v_name.toNativeUtf8(allocator: a)); _checkError();
      if (p.address == 0) return ''; try { return p.cast<Utf8>().toDartString(); } finally { _ocheFree(p); }
    });
  }
  late final ncreateUserCall = dynlib.lookupFunction<NcreateUserN, NcreateUserD>('createUser');

  User createUser(final String v_name, final int v_tagId) {
    return using((a) {

      final r = ncreateUserCall(v_name.toNativeUtf8(allocator: a), v_tagId); _checkError();
      return User._unpack(r);
    });
  }
  late final nsumPointsCall = dynlib.lookupFunction<NsumPointsN, NsumPointsD>('sumPoints');

  double sumPoints(final List<Point> v_points) {
    return using((a) {
    final _v_pointsPtr = a.allocate<NPoint>(v_points.length * ffi.sizeOf<NPoint>());
    for (var i = 0; i < v_points.length; i++) { v_points[i]._pack(_v_pointsPtr[i], a); }
      final r = nsumPointsCall(_v_pointsPtr, v_points.length); _checkError();
      return r;
    });
  }
  late final ngetPointsCopyCall = dynlib.lookupFunction<NgetPointsCopyN, NgetPointsCopyD>('getPointsCopy');

  List<Point> getPointsCopy(final int v_n) {
      final p = ngetPointsCopyCall(v_n); _checkError();
      if (p.address == 0) return []; try {
        final L = ffi.Pointer<ffi.Int64>.fromAddress(p.address).value; final d = ffi.Pointer<NPoint>.fromAddress(p.address + 16);
        return List<Point>.generate(L, (i) => Point._unpack(d[i]));
      } finally { _ocheFreeDeep(p); }
  }
  late final ngetPointsViewCall = dynlib.lookupFunction<NgetPointsViewN, NgetPointsViewD>('getPointsView');

  NativeListView<PointView> getPointsView(final int v_n) {
      final p = ngetPointsViewCall(v_n); _checkError();
      return NativeListView<PointView>(p, (ptr) => PointView(ptr.cast<NPoint>().ref), ffi.sizeOf<NPoint>());
  }
  late final ninitSharedPointsCall = dynlib.lookupFunction<NinitSharedPointsN, NinitSharedPointsD>('initSharedPoints');

  SharedListView<PointView> initSharedPoints(final int v_n) {
      final p = ninitSharedPointsCall(v_n); _checkError();
      return SharedListView<PointView>(p, (ptr) => PointView(ptr.cast<NPoint>().ref), (p, v) { if (v is Point) { v._packManual(p.cast<NPoint>().ref); } else if (v is PointView) { v._packInto(p.cast<NPoint>()); } }, ffi.sizeOf<NPoint>());
  }
  late final nprintSharedPointCall = dynlib.lookupFunction<NprintSharedPointN, NprintSharedPointD>('printSharedPoint');

  void printSharedPoint(final int v_idx) {
      nprintSharedPointCall(v_idx); _checkError();
  }
  late final ninitSharedUsersCall = dynlib.lookupFunction<NinitSharedUsersN, NinitSharedUsersD>('initSharedUsers');

  SharedListView<UserView> initSharedUsers(final int v_n) {
      final p = ninitSharedUsersCall(v_n); _checkError();
      return SharedListView<UserView>(p, (ptr) => UserView(ptr.cast<NUser>().ref), (p, v) { if (v is User) { _ocheFreeInner(p, 3); v._packManual(p.cast<NUser>().ref); } else if (v is UserView) { v._packInto(p.cast<NUser>()); } }, ffi.sizeOf<NUser>());
  }
  late final nprintSharedUserCall = dynlib.lookupFunction<NprintSharedUserN, NprintSharedUserD>('printSharedUser');

  void printSharedUser(final int v_idx) {
      nprintSharedUserCall(v_idx); _checkError();
  }

}
final oche = Oche();
