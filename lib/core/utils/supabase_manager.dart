import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static final String _supabaseUrl = dotenv.env['SUPABASE_URL']!;
  static final String _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

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
