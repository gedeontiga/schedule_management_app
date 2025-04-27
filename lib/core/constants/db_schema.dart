class DbSchema {
  static const String createSchedulesTable = '''
    CREATE TABLE IF NOT EXISTS schedules (
      id UUID PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      available_days TEXT[] NOT NULL,
      duration TEXT NOT NULL,
      owner_id UUID REFERENCES auth.users(id),
      participants JSONB,
      is_fully_set BOOLEAN DEFAULT FALSE
    );
  ''';

  static const String createParticipantsTable = '''
    CREATE TABLE IF NOT EXISTS participants (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      schedule_id UUID REFERENCES schedules(id),
      user_id UUID REFERENCES auth.users(id),
      roles JSONB,
      free_days TEXT[]
    );
  ''';

  static const String createNotificationsTable = '''
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      user_id UUID REFERENCES auth.users(id),
      type TEXT NOT NULL,
      data JSONB,
      created_at TIMESTAMP DEFAULT NOW()
    );
  ''';

  static const String createPermutationRequestsTable = '''
    CREATE TABLE IF NOT EXISTS permutation_requests (
      id UUID PRIMARY KEY,
      sender_id UUID REFERENCES auth.users(id),
      receiver_id UUID REFERENCES auth.users(id),
      schedule_id UUID REFERENCES schedules(id),
      sender_day TEXT,
      receiver_day TEXT,
      status TEXT DEFAULT 'pending'
    );
  ''';

  static const String enableRlsSchedules = '''
    ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;
    CREATE POLICY schedule_access ON schedules
      FOR ALL
      USING (owner_id = auth.uid() OR participants @> '[{"user_id": "' || auth.uid() || '"}]');
  ''';

  static const String enableRlsParticipants = '''
    ALTER TABLE participants ENABLE ROW LEVEL SECURITY;
    CREATE POLICY participant_access ON participants
      FOR ALL
      USING (user_id = auth.uid() OR EXISTS (
        SELECT 1 FROM schedules
        WHERE schedules.id = participants.schedule_id
        AND schedules.owner_id = auth.uid()
      ));
  ''';

  static const String enableRlsNotifications = '''
    ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
    CREATE POLICY notification_access ON notifications
      FOR ALL
      USING (user_id = auth.uid());
  ''';

  static const String enableRlsPermutationRequests = '''
    ALTER TABLE permutation_requests ENABLE ROW LEVEL SECURITY;
    CREATE POLICY permutation_request_access ON permutation_requests
      FOR ALL
      USING (sender_id = auth.uid() OR receiver_id = auth.uid());
  ''';

  static const List<String> allSchemas = [
    createSchedulesTable,
    createParticipantsTable,
    createNotificationsTable,
    createPermutationRequestsTable,
  ];

  static const List<String> allRlsPolicies = [
    enableRlsSchedules,
    enableRlsParticipants,
    enableRlsNotifications,
    enableRlsPermutationRequests,
  ];
}
