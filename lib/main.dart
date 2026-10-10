import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/input/stylus_side_button.dart';
import 'src/storage/vault.dart';
import 'src/ui/library_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  stylusSideButton.attachPlatform();
  runApp(const YetAnotherPageApp());
}

class YetAnotherPageApp extends StatelessWidget {
  const YetAnotherPageApp({this.vault, super.key});

  final Vault? vault;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YetAnotherPage',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5A4C),
        useMaterial3: true,
      ),
      home: vault == null
          ? const _DefaultLibrary()
          : LibraryPage(vault: vault!),
    );
  }
}

class _DefaultLibrary extends StatelessWidget {
  const _DefaultLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: _vaultDirectory(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('无法打开笔记库：${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return LibraryPage(vault: Vault(snapshot.data!));
      },
    );
  }
}

Future<Directory> _vaultDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/vault');
}
