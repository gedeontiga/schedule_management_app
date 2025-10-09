import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DbManagerService {
  static const String _localDbName = 'scheduling_app.db';
  static const int _databaseVersion = 3;

  Database? _localDb;

  static final DbManagerService _instance = DbManagerService._internal();

  factory DbManagerService() {
    return _instance;
  }

  DbManagerService._internal();

  /// Initialize local SQLite database
  Future<void> initializeLocalDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _localDbName);

      _localDb = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      _localDb = null;

      throw Exception('Failed to initialize local database: $e');
    }
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    const schemas = [
      // Schedules table
      '''CREATE TABLE IF NOT EXISTS schedules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        available_days TEXT NOT NULL,
        duration TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        participants TEXT,
        is_fully_set INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        start_date TEXT NOT NULL,
        updated_at TEXT,
        synced INTEGER DEFAULT 0
      )''',

      // Participants table
      '''CREATE TABLE IF NOT EXISTS participants (
        id TEXT PRIMARY KEY,
        schedule_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        roles TEXT NOT NULL,
        free_days TEXT DEFAULT '[]',
        created_at TEXT,
        updated_at TEXT,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (schedule_id) REFERENCES schedules(id) ON DELETE CASCADE
      )''',

      // Notifications table
      '''CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL,
        data TEXT NOT NULL,
        creator_id TEXT,
        created_at TEXT NOT NULL,
        read INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0
      )''',

      // Permutation requests table
      '''CREATE TABLE IF NOT EXISTS permutation_requests (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        schedule_id TEXT NOT NULL,
        sender_day TEXT NOT NULL,
        receiver_day TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        created_at TEXT,
        synced INTEGER DEFAULT 0
      )''',

      // User cache table
      '''CREATE TABLE IF NOT EXISTS user_cache (
        user_id TEXT PRIMARY KEY,
        email TEXT,
        username TEXT,
        photo_url TEXT,
        cached_at TEXT NOT NULL
      )''',
    ];

    for (var schema in schemas) {
      await db.execute(schema);
    }

    // Create indexes for better performance
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_schedules_owner ON schedules(owner_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_participants_schedule ON participants(schedule_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_participants_user ON participants(user_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id)');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add start_date column
      try {
        await db.execute('ALTER TABLE schedules ADD COLUMN start_date TEXT');
      } catch (e) {
        // Ignore
      }

      // Add free_days column
      try {
        await db.execute(
            'ALTER TABLE participants ADD COLUMN free_days TEXT DEFAULT "[]"');
      } catch (e) {
        // Ignore
      }
    }

    if (oldVersion < 3) {
      // Add synced columns for offline sync tracking
      try {
        await db.execute(
            'ALTER TABLE schedules ADD COLUMN synced INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE schedules ADD COLUMN updated_at TEXT');
        await db.execute(
            'ALTER TABLE participants ADD COLUMN synced INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE participants ADD COLUMN created_at TEXT');
        await db.execute('ALTER TABLE participants ADD COLUMN updated_at TEXT');
        await db.execute(
            'ALTER TABLE notifications ADD COLUMN synced INTEGER DEFAULT 0');
        await db.execute(
            'ALTER TABLE permutation_requests ADD COLUMN synced INTEGER DEFAULT 0');
        await db.execute(
            'ALTER TABLE permutation_requests ADD COLUMN created_at TEXT');
      } catch (e) {
        // Ignore
      }

      // Create user cache table
      try {
        await db.execute('''CREATE TABLE IF NOT EXISTS user_cache (
          user_id TEXT PRIMARY KEY,
          email TEXT,
          username TEXT,
          photo_url TEXT,
          cached_at TEXT NOT NULL
        )''');
      } catch (e) {
        // Ignore
      }
    }
  }

  /// Initialize database (backward compatibility)
  Future<void> initializeDatabases({bool isLocalOnly = false}) async {
    if (_localDb == null) {
      await initializeLocalDatabase();
    }
  }

  /// Get local database instance
  Database get localDatabase {
    if (_localDb == null) {
      throw Exception(
          'Local database not initialized. Call initializeLocalDatabase() first.');
    }
    return _localDb!;
  }

  /// Check if local database is initialized
  Future<bool> isLocalDatabaseInitialized() async {
    return _localDb != null;
  }

  /// Clear all data from local database
  Future<void> clearAllData() async {
    try {
      final db = localDatabase;
      await db.delete('schedules');
      await db.delete('participants');
      await db.delete('notifications');
      await db.delete('permutation_requests');
      await db.delete('user_cache');
    } catch (e) {
      rethrow;
    }
  }

  /// Mark records as synced
  Future<void> markAsSynced(String table, String id) async {
    try {
      final db = localDatabase;
      await db.update(
        table,
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      // Ignore
    }
  }

  /// Get unsynced records
  Future<List<Map<String, dynamic>>> getUnsyncedRecords(String table) async {
    try {
      final db = localDatabase;
      return await db.query(
        table,
        where: 'synced = ?',
        whereArgs: [0],
      );
    } catch (e) {
      return [];
    }
  }

  /// Get database size in bytes
  Future<int> getDatabaseSize() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _localDbName);
      final file = await databaseFactory.databaseExists(path);
      if (file) {
        // This is a simplified version - actual size would require file system access
        return 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Close local database
  Future<void> closeLocalDatabase() async {
    if (_localDb != null) {
      await _localDb!.close();
      _localDb = null;
    }
  }

  /// Delete database file
  Future<void> deleteDatabase() async {
    try {
      await closeLocalDatabase();
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _localDbName);
      await databaseFactory.deleteDatabase(path);
    } catch (e) {
      rethrow;
    }
  }
}
