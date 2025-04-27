import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/supabase_manager.dart';

class AuthService {
  final _supabase = SupabaseManager.client;

  Future<void> signUp(String email, String password, String username) async {
    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
      );
    } catch (e) {
      throw Exception('Sign-up failed: $e');
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw Exception('Sign-in failed: $e');
    }
  }

  Future<void> resetPasswordForEmail(String email) async {
    try {
      await SupabaseManager.client.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  User? get currentUser => _supabase.auth.currentUser;
}
