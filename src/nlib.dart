    import 'dart:ffi' as ffi;
    import 'package:ffi/ffi.dart';

    final dynlib = ffi.DynamicLibrary.open("./libmain.so");
      typedef NAddNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, );
  typedef NAddDart = int Function(int, int, );
  final naddCall = dynlib.lookupFunction<NAddNative, NAddDart>("add");
  int add(int a, int b, ) {
    return naddCall(a, b, );
  }
    typedef NMulNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, );
  typedef NMulDart = int Function(int, int, );
  final nmulCall = dynlib.lookupFunction<NMulNative, NMulDart>("mul");
  int mul(int a, int b, ) {
    return nmulCall(a, b, );
  }
    typedef NTdivNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32, );
  typedef NTdivDart = int Function(int, int, int, );
  final ntdivCall = dynlib.lookupFunction<NTdivNative, NTdivDart>("tdiv");
  int tdiv(int a, int b, int c, ) {
    return ntdivCall(a, b, c, );
  }
  