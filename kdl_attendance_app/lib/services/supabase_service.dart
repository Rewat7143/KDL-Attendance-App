import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient? _client;
  
  static Future<void> initialize() async {
    await dotenv.load();
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    _client = Supabase.instance.client;
  }

  static SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase client not initialized');
    }
    return _client!;
  }

  // Authentication methods
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // User profile methods
  Future<void> updateUserProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    await client.from('profiles').upsert([
      {
        'id': userId,
        ...data,
      }
    ]);
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return response;
  }

  // Admin methods
  Future<bool> isAdmin(String userId) async {
    final response = await client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .single();
    return response['role'] == 'admin';
  }

  Future<AuthResponse> adminSignIn({
    required String email,
    required String password,
  }) async {
    final response = await signInWithEmail(
      email: email,
      password: password,
    );
    
    final isUserAdmin = await isAdmin(response.user!.id);
    if (!isUserAdmin) {
      await signOut();
      throw Exception('User is not an admin');
    }
    
    return response;
  }

  // Attendance methods
  Future<void> recordAttendance({
    required String userId,
    required DateTime checkInTime,
    double? latitude,
    double? longitude,
  }) async {
    await client.from('attendance').insert({
      'user_id': userId,
      'check_in': checkInTime.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<void> updateCheckOut({
    required String attendanceId,
    required DateTime checkOutTime,
  }) async {
    await client.from('attendance').update({
      'check_out': checkOutTime.toIso8601String(),
    }).eq('id', attendanceId);
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistory(String userId) async {
    final response = await client
        .from('attendance')
        .select()
        .eq('user_id', userId)
        .order('check_in', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Add this method to test connection
  static Future<bool> testConnection() async {
    try {
      if (_client == null) {
        throw Exception('Supabase client not initialized');
      }
      
      // Try to get the current user session
      final session = _client!.auth.currentSession;
      print('Supabase Connection Test:');
      print('- Client initialized: ${_client != null}');
      print('- Current session: ${session != null}');
      
      // Try to query the profiles table
      final response = await _client!.from('profiles').select().limit(1);
      print('- Database query successful');
      return true;
    } catch (e) {
      print('Supabase Connection Error: $e');
      return false;
    }
  }
} 