import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbManagerService {
  static const String _localDbName = 'scheduling_app.db';
  Database? _localDb;

  static final DbManagerService _instance = DbManagerService._internal();

  factory DbManagerService() {
    return _instance;
  }

  DbManagerService._internal();

  Future<void> initializeLocalDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _localDbName);

      _localDb = await openDatabase(
        path,
        version: 2,
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
              created_at TEXT DEFAULT (datetime('now')),
              start_date TEXT
            );''',
            '''CREATE TABLE IF NOT EXISTS participants (
              id TEXT PRIMARY KEY,
              schedule_id TEXT,
              user_id TEXT,
              roles TEXT,
              free_days TEXT DEFAULT '[]'
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
            await db
                .execute('ALTER TABLE schedules ADD COLUMN start_date TEXT;');
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
    // Check if the database is already initialized
    if (_localDb == null) {
      await initializeLocalDatabase();
    }
  }

  Database get localDatabase {
    if (_localDb == null) {
      throw Exception(
          'Local database not initialized or unavailable. Call initializeDatabases() first.');
    }
    return _localDb!;
  }

  Future<bool> isLocalDatabaseInitialized() async {
    return _localDb != null;
  }

  Future<void> closeLocalDatabase() async {
    if (_localDb != null) {
      await _localDb!.close();
      _localDb = null;
    }
  }
}
