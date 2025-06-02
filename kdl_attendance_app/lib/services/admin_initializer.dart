import 'package:cloud_firestore/cloud_firestore.dart';

class AdminInitializer {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initializes the admin user in both users and admins collections
  /// Returns true if initialization was successful, false otherwise
  static Future<bool> initializeAdmin({
    required String uid,
    required String email,
    required String fullName,
    required String username,
  }) async {
    try {
      // Create user data
      final Map<String, dynamic> userData = {
        "email": email,
        "fullName": fullName,
        "role": "admin",
        "createdAt": FieldValue.serverTimestamp(),
      };

      // Create admin data
      final Map<String, dynamic> adminData = {
        "email": email,
        "fullName": fullName,
        "username": username,
        "createdAt": FieldValue.serverTimestamp(),
      };

      // Write to both collections
      await Future.wait([
        _firestore.collection("users").doc(uid).set(userData),
        _firestore.collection("admins").doc(uid).set(adminData),
      ]);

      return true;
    } catch (e) {
      print('Error initializing admin: $e');
      return false;
    }
  }
}
