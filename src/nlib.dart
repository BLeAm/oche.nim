import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

final dynlib = ffi.DynamicLibrary.open('./libmain.so');
  // --- add ---
  typedef NAddNative = ffi.Int64 Function(ffi.Int64, ffi.Int64);
  typedef NAddDart = int Function(int, int);
  final naddCall = dynlib.lookupFunction<NAddNative, NAddDart>('add');
  int add(int a, int b) {
    return naddCall(a, b);
  }
  // --- mul ---
  typedef NMulNative = ffi.Int64 Function(ffi.Int64, ffi.Int64);
  typedef NMulDart = int Function(int, int);
  final nmulCall = dynlib.lookupFunction<NMulNative, NMulDart>('mul');
  int mul(int a, int b) {
    return nmulCall(a, b);
  }
  // --- tdiv ---
  typedef NTdivNative = ffi.Int64 Function(ffi.Int64, ffi.Int64, ffi.Int64);
  typedef NTdivDart = int Function(int, int, int);
  final ntdivCall = dynlib.lookupFunction<NTdivNative, NTdivDart>('tdiv');
  int tdiv(int a, int b, int c) {
    return ntdivCall(a, b, c);
  }
  // --- addFloat ---
  typedef NAddFloatNative = ffi.Double Function(ffi.Double, ffi.Double);
  typedef NAddFloatDart = double Function(double, double);
  final naddFloatCall = dynlib.lookupFunction<NAddFloatNative, NAddFloatDart>('addFloat');
  double addFloat(double a, double b) {
    return naddFloatCall(a, b);
  }
  // --- isEven ---
  typedef NIsEvenNative = ffi.Bool Function(ffi.Int64);
  typedef NIsEvenDart = bool Function(int);
  final nisEvenCall = dynlib.lookupFunction<NIsEvenNative, NIsEvenDart>('isEven');
  bool isEven(int n) {
    return nisEvenCall(n);
  }
  // --- greet ---
  typedef NGreetNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
  typedef NGreetDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
  final ngreetCall = dynlib.lookupFunction<NGreetNative, NGreetDart>('greet');
  String greet(String name) {
    return ngreetCall(name.toNativeUtf8()).toDartString();
  }
