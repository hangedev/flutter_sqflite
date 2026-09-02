import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/src/sql_builder.dart';
import 'package:sqflite_common/src/logger/sqflite_logger.dart'
    show logTruncate, logTruncateAny;
import 'package:sqflite_common/src/sql_command.dart';

void main() {
  group('escapeEntityName', () {
    test('should escape sql keywords', () {
      expect(escapeEntityName('order'), '"order"');
      expect(escapeEntityName('GROUP'), '"GROUP"');
      expect(escapeEntityName('index'), '"index"');
    });

    test('should keep regular identifiers untouched', () {
      expect(escapeEntityName('name'), 'name');
      expect(escapeEntityName('user_name'), 'user_name');
      expect(escapeEntityName('column1'), 'column1');
    });

    test('should escape invalid identifiers', () {
      expect(escapeEntityName('1abc'), '"1abc"');
      expect(escapeEntityName('a-b'), '"a-b"');
      expect(escapeEntityName('a b'), '"a b"');
    });
  });

  group('unescapeValueKeyName', () {
    test('should remove the surrounding quotes of escaped names', () {
      expect(unescapeValueKeyName('"weird name"'), 'weird name');
      expect(unescapeValueKeyName('`weird name`'), 'weird name');
      expect(unescapeValueKeyName('"order"'), 'order');
    });

    test('should keep plain names untouched', () {
      expect(unescapeValueKeyName('name'), 'name');
      expect(unescapeValueKeyName("'name'"), "'name'");
      expect(unescapeValueKeyName('"name'), '"name');
    });
  });

  group('isEscapedName', () {
    test('should detect escaped keywords only', () {
      expect(isEscapedName('"order"'), isTrue);
      expect(isEscapedName('`group`'), isTrue);
      expect(isEscapedName('"name"'), isFalse);
      expect(isEscapedName('order'), isFalse);
      expect(isEscapedName('o'), isFalse);
    });
  });

  group('logTruncate', () {
    test('should keep short texts untouched and truncate long ones', () {
      expect(logTruncate('short'), 'short');
      final long = 'a' * 300;
      expect(logTruncate(long), 'a' * 256);
      expect(logTruncate(long, len: 10), 'a' * 10);
    });

    test('should format any value and render null explicitly', () {
      expect(logTruncateAny(null), '<null>');
      expect(logTruncateAny(12), '12');
      expect(logTruncateAny(<Object?>['a', 'b']), '[a, b]');
    });
  });

  group('SqfliteSqlCommand', () {
    test('should expose its type, sql and arguments', () {
      final command = SqfliteSqlCommand(
          SqliteSqlCommandType.insert, 'INSERT INTO test VALUES (?)',
          <Object?>[1]);
      expect(command.type, SqliteSqlCommandType.insert);
      expect(command.sql, 'INSERT INTO test VALUES (?)');
      expect(command.arguments, <Object?>[1]);

      expect(
          SqfliteSqlCommand(SqliteSqlCommandType.execute, 'BEGIN', null).type,
          SqliteSqlCommandType.execute);
      expect(
          SqfliteSqlCommand(SqliteSqlCommandType.query, 'SELECT 1', null).type,
          SqliteSqlCommandType.query);
      expect(
          SqfliteSqlCommand(
                  SqliteSqlCommandType.update, 'UPDATE t SET a = 1', null)
              .type,
          SqliteSqlCommandType.update);
      expect(
          SqfliteSqlCommand(SqliteSqlCommandType.delete, 'DELETE FROM t', null)
              .type,
          SqliteSqlCommandType.delete);
    });
  });
}
