import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Stub — should never be called (overridden by native or web impl).
Future<void> printNative(BuildContext context, Uint8List imageBytes, dynamic ref) async {}

void printWeb(Uint8List imageBytes) {}

Future<void> saveToFile(Uint8List imageBytes, String fileName) async {}
