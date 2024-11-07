import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/utils/utils.dart';
import 'package:sqflite_example/utils.dart';

import 'src/common_import.dart';
import 'test_page.dart';

// ignore_for_file: avoid_print

/// Raw test page.
class RawTestPage extends TestPage {
  /// Raw test page.
  RawTestPage({Key? key}) : super('Raw tests', key: key) {
    test('Simple', () async {
      // await Sqflite.devSetDebugModeOn(true);

      final path = await initDeleteDb('raw_simple.db');
      final db = await openDatabase(path);
      try {
        await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
        expect(await db.rawInsert('INSERT INTO Test (name) VALUES (?)', ['test']), 1);

        final result = await db.query('Test');
        final expected = [
          {'id': 1, 'name': 'test'}
        ];
        expect(result, expected);
      } finally {
        await db.close();
      }
    });
  }
}
