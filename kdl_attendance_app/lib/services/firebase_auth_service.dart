import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in an admin user using email and password
  /// Returns the UserCredential if successful
  static Future<UserCredential> signInAdmin({
    required String email,
    required String password,
  }) async {
    try {
      // First, sign in with Firebase Auth
      final UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Then verify if the user is an admin
      final adminDoc = await _firestore
          .collection('admins')
          .doc(userCredential.user!.uid)
          .get();

      if (!adminDoc.exists) {
        // If not an admin, sign out and throw error
        await _auth.signOut();
        throw Exception('User is not an admin');
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No admin found with this email');
        case 'wrong-password':
          throw Exception('Wrong password provided');
        case 'invalid-email':
          throw Exception('Invalid email address');
        case 'user-disabled':
          throw Exception('This account has been disabled');
        default:
          throw Exception('Authentication failed: ${e.message}');
      }
    }
  }

  /// Sign out the current user
  static Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Get the current user
  static User? get currentUser => _auth.currentUser;

  /// Check if the current user is an admin
  static Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final adminDoc = await _firestore.collection('admins').doc(user.uid).get();
    return adminDoc.exists;
  }

  /// Change admin password
  static Future<void> changeAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user is signed in');

      // Reauthenticate user before changing password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Change password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          throw Exception('Current password is incorrect');
        case 'weak-password':
          throw Exception('New password is too weak');
        default:
          throw Exception('Failed to change password: ${e.message}');
      }
    }
  }
}
