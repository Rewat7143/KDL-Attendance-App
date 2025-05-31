// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// Simple auth service
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Authentication failed');
    }
  }

  Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document in Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': email,
        'fullName': fullName,
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Registration failed');
    }
  }

  Future<Map<String, dynamic>?> adminSignIn({
    required String username,
    required String password,
  }) async {
    try {
      // First, find the admin document by username
      QuerySnapshot adminQuery = await _firestore
          .collection('admins')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (adminQuery.docs.isEmpty) {
        throw Exception('Admin not found');
      }

      // Get the admin document
      DocumentSnapshot adminDoc = adminQuery.docs.first;
      Map<String, dynamic> adminData = adminDoc.data() as Map<String, dynamic>;

      // Sign in with email and password
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: adminData['email'],
        password: password,
      );

      // Verify the user's role in the users collection
      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists ||
          (userDoc.data() as Map<String, dynamic>)['role'] != 'admin') {
        await _auth.signOut();
        throw Exception('Unauthorized access');
      }

      return {
        'uid': userCredential.user!.uid,
        'email': adminData['email'],
        'fullName': adminData['fullName'],
        'username': adminData['username'],
      };
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Authentication failed');
    } catch (e) {
      throw Exception('Admin authentication failed: $e');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

class AttendanceService {
  static const String _attendanceKey = 'attendance_records';
  static const String _checkInStatusKey =
      'check_in_status'; // Key to store check-in status
  static const double _officeLatitude =
      17.724610; // Replace with actual office coordinates
  static const double _officeLongitude =
      83.314066; // Replace with actual office coordinates
  static const double _maxDistance = 200; // Maximum distance in meters
  static const TimeOfDay _defaultShiftEndTime =
      TimeOfDay(hour: 17, minute: 0); // Default shift end time

  final LocalAuthentication _localAuth = LocalAuthentication();
  late SharedPreferences _prefs;

  // Singleton instance
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<Position> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<double> getDistanceFromOffice() async {
    try {
      Position currentPosition = await getCurrentLocation();
      double distanceInMeters = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        _officeLatitude,
        _officeLongitude,
      );
      return distanceInMeters;
    } catch (e) {
      throw Exception('Failed to get distance: $e');
    }
  }

  Future<bool> isWithinOfficeRange() async {
    try {
      double distance = await getDistanceFromOffice();
      return distance <= _maxDistance;
    } catch (e) {
      return false;
    }
  }

  // Renamed to be more general for fingerprint/face ID
  Future<bool> authenticateWithBiometrics() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        throw Exception('Biometric authentication not available');
      }

      List<BiometricType> availableBiometrics =
          await _localAuth.getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        throw Exception('No biometrics available on this device.');
      }

      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to proceed',
        options: const AuthenticationOptions(
          stickyAuth: true,
          // biometricOnly: true, // Allow device authentication if no biometrics set
        ),
      );
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  // Check if the user is currently checked in
  bool isCheckedIn() {
    return _prefs.getBool(_checkInStatusKey) ?? false;
  }

  // Save the check-in status
  Future<void> _setCheckedIn(bool status) async {
    debugPrint('AttendanceService: Saving check-in status: $status');
    await _prefs.setBool(_checkInStatusKey, status);
    await Future.delayed(const Duration(milliseconds: 50)); // Add a small delay
  }

  Future<void> checkIn() async {
    try {
      bool isInRange = await isWithinOfficeRange();
      if (!isInRange) {
        throw Exception('You are not within office range');
      }

      // Biometric authentication is handled before calling this method now

      DateFormat('yyyy-MM-dd').format(DateTime.now());
      DateFormat('HH:mm').format(DateTime.now());

      // Save attendance record

      List<String> records = _prefs.getStringList(_attendanceKey) ?? [];
      records.add(DateTime.now().toIso8601String());
      await _prefs.setStringList(_attendanceKey, records);

      // Set check-in status to true
      await _setCheckedIn(true);
    } catch (e) {
      throw Exception('Check-in failed: $e');
    }
  }

  Future<void> checkOut() async {
    try {
      // Biometric authentication is handled before calling this method now

      // TODO: Implement actual check-out logic (e.g., save check-out time and reason)
      // For now, just focusing on updating the check-in status

      // Set check-in status to false
      await _setCheckedIn(false);
    } catch (e) {
      throw Exception('Check-out failed: $e');
    }
  }

  // Get the date of the first attendance record, used as the effective start date
  DateTime? _getEffectiveStartDate() {
    List<String> records = _prefs.getStringList(_attendanceKey) ?? [];
    if (records.isEmpty) {
      return null;
    }
    // Sort records by date to find the earliest
    records.sort();
    return DateTime.parse(records.first);
  }

  AttendanceStats getAttendanceStats() {
    List<String> records = _prefs.getStringList(_attendanceKey) ?? [];

    // Get effective start date
    DateTime? effectiveStartDate = _getEffectiveStartDate();
    if (effectiveStartDate == null) {
      // No attendance records yet
      return AttendanceStats(
        attendancePercentage: 0,
        presentDays: 0,
        lateDays: 0,
        absentDays: 0,
      );
    }

    // Calculate total calendar days from start date to today
    DateTime today = DateTime.now();
    int totalCalendarDays =
        today.difference(effectiveStartDate).inDays + 1; // +1 to include today

    // Count present and late days from all records (assuming records store full date/time)
    // TODO: Implement late day counting logic based on shift start time
    int presentDays = records
        .length; // For simplicity, assuming all records are 'present' for now
    int lateDays = 0; // Placeholder

    // Calculate absent days: total calendar days minus recorded attendance days
    int recordedAttendanceDays = presentDays + lateDays;
    int absentDays = totalCalendarDays - recordedAttendanceDays;

    // Ensure absentDays is not negative (can happen if records are inconsistent or future dates are present)
    absentDays = absentDays < 0 ? 0 : absentDays;

    // Calculate attendance percentage based on total calendar days
    double attendancePercentage =
        (recordedAttendanceDays / totalCalendarDays) * 100;
    // Ensure percentage is between 0 and 100
    attendancePercentage = attendancePercentage.clamp(0.0, 100.0);

    return AttendanceStats(
      attendancePercentage: attendancePercentage,
      presentDays: presentDays,
      lateDays: lateDays,
      absentDays: absentDays,
    );
  }

  String getWorkingHours() {
    // Implement working hours calculation
    return '0.0';
  }

  // Removed getWorkingDays as its logic is redundant and format incorrect
  // String getWorkingDays() {
  //   List<String> records = _prefs.getStringList(_attendanceKey) ?? [];
  //   int presentDays = records.length;
  //   return '$presentDays/31';
  // }
}

class AttendanceStats {
  final double attendancePercentage;
  final int presentDays;
  final int lateDays;
  final int absentDays;

  AttendanceStats({
    required this.attendancePercentage,
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
  });
}

// Add this at the top level, before MyApp class
class _EmployeeDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> employee;
  const _EmployeeDetailsSheet({required this.employee});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF23242A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Employee Details',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22)),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 28),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: NetworkImage(employee['avatar']),
                          radius: 36,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(employee['name'],
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22)),
                              const SizedBox(height: 4),
                              Text(employee['role'],
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 16)),
                              Text(employee['department'],
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 15)),
                              Text('Started: ${employee['startDate']}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('Contact Information',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    const SizedBox(height: 8),
                    const Text('Email',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                    Text(employee['email'],
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 28),
                    const Text('Shift Information',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    const SizedBox(height: 8),
                    const Text('Working Hours:',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                    Text(employee['workingHours'],
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 28),
                    const Text('Attendance Summary',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    const SizedBox(height: 24),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Text('Present',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            SizedBox(height: 4),
                            Text('20',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('Late',
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            SizedBox(height: 4),
                            Text('2',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('Absent',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            SizedBox(height: 4),
                            Text('1',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Colors.white54, width: 2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Close',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Export Data',
                                style: TextStyle(fontSize: 18)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Theme Provider
class ThemeProvider with ChangeNotifier {
  static const String _themePreferenceKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.light;
  late SharedPreferences _prefs;

  ThemeProvider() {
    _loadThemePreference();
  }

  ThemeMode get themeMode => _themeMode;

  Future<void> _loadThemePreference() async {
    _prefs = await SharedPreferences.getInstance();
    final savedThemeMode = _prefs.getString(_themePreferenceKey);
    if (savedThemeMode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.toString() == savedThemeMode,
        orElse: () => ThemeMode.light,
      );
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}

// Location Service
class LocationService {
  Location? currentLocation;
  
  Future<void> updateLocation() async {
    // Implementation for location updates
  }
}

class Location {
  final String? address;
  final double latitude;
  final double longitude;
  final double maxDistance;

  Location({
    this.address,
    required this.latitude,
    required this.longitude,
    required this.maxDistance,
  });
}

// Settings Service
class SettingsService {
  TimeOfDay workingHoursStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay workingHoursEnd = const TimeOfDay(hour: 18, minute: 0);
  int gracePeriodMinutes = 15;

  Future<void> updateWorkingHours(TimeOfDay start, TimeOfDay end) async {
    workingHoursStart = start;
    workingHoursEnd = end;
  }

  Future<void> updateGracePeriod(int minutes) async {
    gracePeriodMinutes = minutes;
  }
}

// Settings Tab Widget
class SettingsTab extends StatefulWidget {
  final LocationService locationService;
  final SettingsService settingsService;

  const SettingsTab({
    super.key,
    required this.locationService,
    required this.settingsService,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String _address = '';
  String _latitude = '';
  String _longitude = '';
  String _maxDistance = '';

  @override
  void initState() {
    super.initState();
    _loadLocationSettings();
  }

  Future<void> _loadLocationSettings() async {
    final location = widget.locationService.currentLocation;
    if (location != null) {
      setState(() {
        _address = location.address ?? '';
        _latitude = location.latitude.toString();
        _longitude = location.longitude.toString();
        _maxDistance = location.maxDistance.toString();
      });
    }
  }

  Widget _buildSettingsTab() {
    final addressController = TextEditingController(text: _address);
    final latitudeController = TextEditingController(text: _latitude);
    final longitudeController = TextEditingController(text: _longitude);
    final maxDistanceController = TextEditingController(text: _maxDistance);

    return Expanded(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Admin Settings Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Admin Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Change Admin Password
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.lock_outline, color: Colors.blue),
                      ),
                      title: const Text(
                        'Change Admin Password',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => _showChangePasswordDialog(context),
                    ),
                    const Divider(height: 32),
                    // Location Settings
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.location_on_outlined, color: Colors.green),
                      ),
                      title: const Text(
                        'Location Settings',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        'Current: ${widget.locationService.currentLocation?.address ?? 'Not set'}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => _showLocationSettingsDialog(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Company Settings Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Company Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Working Hours
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.access_time, color: Colors.orange),
                      ),
                      title: const Text(
                        'Working Hours',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${widget.settingsService.workingHoursStart.format(context)} - ${widget.settingsService.workingHoursEnd.format(context)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => _showWorkingHoursDialog(context),
                    ),
                    const Divider(height: 32),
                    // Grace Period
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.timer_outlined, color: Colors.purple),
                      ),
                      title: const Text(
                        'Grace Period',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${widget.settingsService.gracePeriodMinutes} minutes',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => _showGracePeriodDialog(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Change Admin Password',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Old Password',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (newPasswordController.text != confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match!')),
                  );
                  return;
                }
                // For demo, just show success
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password changed successfully!')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
              ),
              child: const Text('Change'),
            ),
          ],
        );
      },
    );
  }

  void _showLocationSettingsDialog(BuildContext context) {
    final addressController = TextEditingController(text: _address);
    final latitudeController = TextEditingController(text: _latitude);
    final longitudeController = TextEditingController(text: _longitude);
    final maxDistanceController = TextEditingController(text: _maxDistance);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Location Settings',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: latitudeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: longitudeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: maxDistanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max Distance (meters)',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // Update location settings
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location settings updated!')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showWorkingHoursDialog(BuildContext context) {
    TimeOfDay startTime = widget.settingsService.workingHoursStart;
    TimeOfDay endTime = widget.settingsService.workingHoursEnd;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Working Hours',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Start Time'),
                subtitle: Text(startTime.format(context)),
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: startTime,
                  );
                  if (picked != null) {
                    setState(() => startTime = picked);
                  }
                },
              ),
              ListTile(
                title: const Text('End Time'),
                subtitle: Text(endTime.format(context)),
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: endTime,
                  );
                  if (picked != null) {
                    setState(() => endTime = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await widget.settingsService.updateWorkingHours(startTime, endTime);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Working hours updated!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showGracePeriodDialog(BuildContext context) {
    final controller = TextEditingController(
      text: widget.settingsService.gracePeriodMinutes.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Grace Period',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Grace Period (minutes)',
              labelStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final minutes = int.tryParse(controller.text);
                if (minutes != null && minutes > 0) {
                  await widget.settingsService.updateGracePeriod(minutes);
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Grace period updated!')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid number of minutes')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildSettingsTab();
  }
}

// Main App Widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kalam Attendance',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        buttonTheme: const ButtonThemeData(
          buttonColor: Colors.blue,
          textTheme: ButtonTextTheme.primary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2196F3),
            side: const BorderSide(color: Color(0xFF2196F3), width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F7FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 20,
            horizontal: 16,
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.black87),
          titleMedium: TextStyle(color: Colors.black87),
          titleLarge: TextStyle(color: Colors.black),
        ),
      ),
      themeMode: ThemeMode.light,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Main Entry Point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider(create: (_) => LocationService()),
        Provider(create: (_) => SettingsService()),
      ],
      child: const MyApp(),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Spacer(flex: 2),
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.network(
                    'https://images.unsplash.com/photo-1464983953574-0892a716854b?auto=format&fit=crop&w=400&q=80',
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'KDL Attendance',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Track your attendance with ease',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 350,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EmployeeLoginPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      textStyle: const TextStyle(fontSize: 22),
                      backgroundColor: const Color(0xFF2196F3),
                    ),
                    child: const Text('Employee Login'),
                  ),
// Location Service
class LocationService {
  Location? currentLocation;
  
  Future<void> updateLocation() async {
    // Implementation for location updates
  }
}

class Location {
  final String? address;
  final double latitude;
  final double longitude;
  final double maxDistance;

  Location({
    this.address,
    required this.latitude,
    required this.longitude,
    required this.maxDistance,
  });
}

// Settings Service
class SettingsService {
  TimeOfDay workingHoursStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay workingHoursEnd = const TimeOfDay(hour: 18, minute: 0);
  int gracePeriodMinutes = 15;

  Future<void> updateWorkingHours(TimeOfDay start, TimeOfDay end) async {
    workingHoursStart = start;
    workingHoursEnd = end;
  }

  Future<void> updateGracePeriod(int minutes) async {
    gracePeriodMinutes = minutes;
  }
}
