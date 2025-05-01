import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbManagerService {
  static const String _localDbName = 'scheduling_app.db';
  Database? _localDb;

  Future<void> initializeLocalDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _localDbName);

      _localDb = await openDatabase(
        path,
        version: 2, // Increment version for schema migration
        onCreate: (db, version) async {
          const localSchemas = [
            '''CREATE TABLE IF NOT EXISTS schedules (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT,
              available_days TEXT,
              duration TEXT NOT NULL,
              owner_id TEXT,
              participants TEXT,
              is_fully_set INTEGER DEFAULT 0,
              created_at TEXT DEFAULT (datetime('now'))
            );''',
            '''CREATE TABLE IF NOT EXISTS participants (
              id TEXT PRIMARY KEY,
              schedule_id TEXT,
              user_id TEXT,
              roles TEXT,
              free_days TEXT DEFAULT '[]' -- Store as JSON string
            );''',
            '''CREATE TABLE IF NOT EXISTS notifications (
              id TEXT PRIMARY KEY,
              user_id TEXT,
              type TEXT NOT NULL,
              data TEXT,
              created_at TEXT DEFAULT (datetime('now'))
            );''',
            '''CREATE TABLE IF NOT EXISTS permutation_requests (
              id TEXT PRIMARY KEY,
              sender_id TEXT,
              receiver_id TEXT,
              schedule_id TEXT,
              sender_day TEXT,
              receiver_day TEXT,
              status TEXT DEFAULT 'pending'
            );''',
          ];

          for (var schema in localSchemas) {
            await db.execute(schema);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Migration for version 2: Add created_at to schedules and update free_days default
            await db.execute(
                'ALTER TABLE schedules ADD COLUMN created_at TEXT DEFAULT (datetime("now"));');
            await db.execute(
                'ALTER TABLE participants ADD COLUMN free_days TEXT DEFAULT "[]";');
          }
        },
      );
    } catch (e) {
      _localDb = null;
      throw Exception('Failed to initialize local database: $e');
    }
  }

  Future<void> initializeDatabases({bool isLocalOnly = false}) async {
    await initializeLocalDatabase();
  }

  Database get localDatabase {
    if (_localDb == null) {
      throw Exception('Local database not initialized or unavailable');
    }
    return _localDb!;
  }

  Future<void> closeLocalDatabase() async {
    if (_localDb != null) {
      await _localDb!.close();
      _localDb = null;
    }
  }
}
