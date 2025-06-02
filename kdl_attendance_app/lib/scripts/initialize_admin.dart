import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import '../services/admin_initializer.dart';

Future<void> main() async {
  // Initialize Firebase
  await Firebase.initializeApp();

  // Admin user details
  const String uid = "7a5STWxs5th1z5MMT7K8FZOggiB3";
  const String email = "info@kalamdreamlabs.com";
  const String fullName = "System Administrator";
  const String username = "admin";

  // Initialize admin
  final bool success = await AdminInitializer.initializeAdmin(
    uid: uid,
    email: email,
    fullName: fullName,
    username: username,
  );

  if (success) {
    print('Admin user initialized successfully!');
  } else {
    print('Failed to initialize admin user.');
  }

  // Exit the script
  exit(0);
}
