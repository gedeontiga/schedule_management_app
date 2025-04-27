import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static const String _supabaseUrl = 'https://jyuopqgpefhlsileslde.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp5dW9wcWdwZWZobHNpbGVzbGRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDA1MDQ3MjksImV4cCI6MjA1NjA4MDcyOX0.TjylXsumZEofBtNfZcnTf235fdoxme1pXDpPtQb6WNM';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static String? getCurrentUserId() {
    return client.auth.currentUser?.id;
  }
}
