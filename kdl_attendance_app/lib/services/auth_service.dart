import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;
  
  // Get current user
  User? get currentUser => _supabase.auth.currentUser;
  
  // Check if user is logged in
  bool get isAuthenticated => currentUser != null;

  // Sign in with email
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user;
    } catch (e) {
      debugPrint('Sign in error: $e');
      throw Exception('Invalid credentials - Please check your email and password');
    }
  }

  // Sign up with email
  Future<User?> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      debugPrint('Starting sign up process...');
      
      // Create the auth user with email confirmation disabled
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName}, // Store name in auth metadata
        emailRedirectTo: null, // Disable email confirmation for now
      );

      debugPrint('Auth user created: ${response.user?.id}');

      if (response.user != null) {
        try {
          // Create the profile immediately after signup while session is active
          final profileData = {
            'id': response.user!.id,
            'full_name': fullName,
            'role': 'employee',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
          
          debugPrint('Attempting to create profile with data: $profileData');

          final result = await _supabase
              .from('profiles')
              .insert(profileData)
              .select()
              .single();
          
          debugPrint('Profile created successfully: $result');
          
          // Sign out and inform user to check email
          await signOut();
          return response.user;
        } catch (profileError) {
          debugPrint('Profile creation error details: $profileError');
          // Sign out the user if profile creation fails
          await signOut();
          throw Exception('Failed to create user profile. Please try again.');
        }
      } else {
        throw Exception('Failed to create user account');
      }
    } catch (e) {
      debugPrint('Sign up error: $e');
      if (e.toString().contains('User already registered')) {
        throw Exception('This email is already registered. Please try logging in instead.');
      }
      throw Exception('Error during sign up. Please check your information and try again.');
    }
  }

  // Admin sign in
  Future<User?> adminSignIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Check if user is admin
        final profile = await _supabase
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .single();

        if (profile['role'] != 'admin') {
          await signOut();
          throw Exception('User is not an admin');
        }
      }

      return response.user;
    } catch (e) {
      debugPrint('Admin sign in error: $e');
      throw Exception('Invalid admin credentials');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (!isAuthenticated) return null;
    
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', currentUser!.id)
          .single();
      return response;
    } catch (e) {
      debugPrint('Get profile error: $e');
      return null;
    }
  }

  // Update user profile
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    if (!isAuthenticated) return;

    try {
      await _supabase
          .from('profiles')
          .update(data)
          .eq('id', currentUser!.id);
    } catch (e) {
      debugPrint('Update profile error: $e');
      throw Exception('Failed to update profile');
    }
  }

  // Reset password
  Future<void> resetPassword({required String email}) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      debugPrint('Reset password error: $e');
      throw Exception('Failed to send reset password instructions');
    }
  }
} 