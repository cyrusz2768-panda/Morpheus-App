import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/app/app.dart';

/// The process entry point of the application.
///
/// A Flutter program starts here in the same way that a C++ program starts in
/// `int main()`. Keep this function intentionally small: configuration and UI
/// belong in separate files so they can be tested independently.
void main() {
  // Flutter bindings connect Dart code to the host platform. `runApp` would
  // initialize them automatically, but doing it explicitly makes this entry
  // point ready for future asynchronous startup work such as opening SQLite.
  WidgetsFlutterBinding.ensureInitialized();

  // ProviderScope is Riverpod's root container. Every provider below this
  // widget shares a lifecycle and can be replaced with a fake during tests.
  runApp(const ProviderScope(child: MorpheusApp()));
}
