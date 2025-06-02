import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/firebase_auth_service.dart';
import 'dart:async';

// Simple auth service
class AuthService {
  Future<bool> signInWithEmail(
      {required String email, required String password}) async {
    // For testing purposes, accept test@example.com with password123
    if ((email == 'test@example.com' && password == 'password123') ||
        (email.contains('@') && password.length >= 6)) {
      return true;
    }
    throw Exception(
        'Invalid credentials - Please use test@example.com and password123');
  }

  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    // In a real app, you would store this information
    if (email.isNotEmpty && password.isNotEmpty && fullName.isNotEmpty) {
      return true;
    }
    throw Exception('Invalid input');
  }

  Future<bool> adminSignIn(
      {required String username, required String password}) async {
    // Simple admin validation
    if (username == 'admin' && password == 'admin123') {
      return true;
    }
    throw Exception('Invalid admin credentials');
  }
}

class AttendanceService {
  static const String _attendanceKey = 'attendance_records';
  static const double _officeLatitude =
      17.724610; // Replace with actual office coordinates
  static const double _officeLongitude =
      83.314066; // Replace with actual office coordinates
  static const double _maxDistance = 200; // Maximum distance in meters

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

  Future<bool> authenticateWithFingerprint() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        throw Exception('Biometric authentication not available');
      }

      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to check in',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  Future<void> checkIn() async {
    try {
      bool isInRange = await isWithinOfficeRange();
      if (!isInRange) {
        throw Exception('You are not within office range');
      }

      bool isAuthenticated = await authenticateWithFingerprint();
      if (!isAuthenticated) {
        throw Exception('Authentication failed');
      }

      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String currentTime = DateFormat('HH:mm').format(DateTime.now());

      // Save attendance record
      Map<String, dynamic> record = {
        'date': today,
        'checkIn': currentTime,
        'status': _determineStatus(currentTime),
      };

      List<String> records = _prefs.getStringList(_attendanceKey) ?? [];
      records.add(DateTime.now().toIso8601String());
      await _prefs.setStringList(_attendanceKey, records);
    } catch (e) {
      throw Exception('Check-in failed: $e');
    }
  }

  String _determineStatus(String checkInTime) {
    // Define work hours (e.g., 9:00 AM start time)
    DateTime startTime = DateTime.parse('2000-01-01 09:00:00');
    DateTime checkIn = DateTime.parse('2000-01-01 $checkInTime:00');

    if (checkIn.isAfter(startTime.add(const Duration(minutes: 30)))) {
      return 'late';
    }
    return 'present';
  }

  AttendanceStats getAttendanceStats() {
    List<String> records = _prefs.getStringList(_attendanceKey) ?? [];

    // Get current month's records
    String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
    List<DateTime> monthRecords = records
        .map((r) => DateTime.parse(r))
        .where((date) => DateFormat('yyyy-MM').format(date) == currentMonth)
        .toList();

    int totalDays = DateTime.now().day;
    int presentDays = monthRecords.length;
    int lateDays = 0; // Implement late day counting logic
    int absentDays = totalDays - presentDays;
    double attendancePercentage = (presentDays / totalDays) * 100;

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

  String getWorkingDays() {
    List<String> records = _prefs.getStringList(_attendanceKey) ?? [];
    int presentDays = records.length;
    return '$presentDays/31';
  }
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: const [
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
                          children: const [
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
                          children: const [
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDxo0DF8yYsHjuYZcuLmfNn2OrWCft90-o",
        appId: "1:914608974935:ios:64310cf4f84b8f218a8712",
        messagingSenderId: "914608974935",
        projectId: "kalam-dream-labs",
        storageBucket: "kalam-dream-labs.firebasestorage.app",
      ),
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kalam Attendance',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
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
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 350,
                  height: 60,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminLoginPage(),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: const BorderSide(
                        color: Color(0xFF2196F3),
                        width: 2,
                      ),
                      textStyle: const TextStyle(fontSize: 22),
                    ),
                    child: const Text(
                      'Admin Login',
                      style: TextStyle(color: Color(0xFF2196F3)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 3),
          const Padding(
            padding: EdgeInsets.only(bottom: 24.0),
            child: Text(
              '© 2023 Kalam Dream Labs',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white,
    );
  }
}

class EmployeeLoginPage extends StatefulWidget {
  const EmployeeLoginPage({super.key});

  @override
  State<EmployeeLoginPage> createState() => _EmployeeLoginPageState();
}

class _EmployeeLoginPageState extends State<EmployeeLoginPage> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Extract name from email for demo purposes
      String userName = _emailController.text.split('@')[0];
      // Capitalize first letter
      userName = userName[0].toUpperCase() + userName.substring(1);

      // For testing purposes, allow direct login
      if (_emailController.text == 'test@example.com' &&
          _passwordController.text == 'password123') {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => EmployeeDashboard(userName: 'Test User'),
            ),
          );
        }
        return;
      }

      if (_emailController.text.contains('@') &&
          _passwordController.text.length >= 6) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => EmployeeDashboard(userName: userName),
            ),
          );
        }
      } else {
        throw Exception('Invalid credentials');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please use test@example.com and password123'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.network(
                  'https://images.unsplash.com/photo-1464983953574-0892a716854b?auto=format&fit=crop&w=400&q=80',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Kalam Attendance',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Track your attendance with ease',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Welcome Back',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sign in to continue',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined),
                  hintText: 'Email',
                  filled: true,
                  fillColor: const Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  hintText: 'Password',
                  filled: true,
                  fillColor: const Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: Color(0xFF2196F3)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignIn,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: const Color(0xFF2196F3),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Employee Sign In'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: Color(0xFF2196F3), width: 2),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: const Text(
                    'Admin Sign In',
                    style: TextStyle(color: Color(0xFF2196F3)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                      children: [
                        TextSpan(
                          text: 'Sign Up',
                          style: const TextStyle(
                            color: Color(0xFF2196F3),
                            fontWeight: FontWeight.bold,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const EmployeeSignUpPage(),
                                ),
                              );
                            },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmployeeSignUpPage extends StatefulWidget {
  const EmployeeSignUpPage({super.key});

  @override
  State<EmployeeSignUpPage> createState() => _EmployeeSignUpPageState();
}

class _EmployeeSignUpPageState extends State<EmployeeSignUpPage> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
      );
      if (mounted) {
        // TODO: Navigate to employee dashboard
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign up successful!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.network(
                  'https://images.unsplash.com/photo-1464983953574-0892a716854b?auto=format&fit=crop&w=400&q=80',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Kalam Attendance',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Track your attendance with ease',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Create Account',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sign up to get started',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Full Name',
                  filled: true,
                  fillColor: Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined),
                  hintText: 'Email',
                  filled: true,
                  fillColor: Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Password',
                  filled: true,
                  fillColor: Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Confirm Password',
                  filled: true,
                  fillColor: Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: const Color(0xFF2196F3),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Sign Up'),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      text: "Already have an account? ",
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                      children: [
                        TextSpan(
                          text: 'Login',
                          style: const TextStyle(
                            color: Color(0xFF2196F3),
                            fontWeight: FontWeight.bold,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.pop(context);
                            },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuthService.signInAdmin(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const AdminDashboardPage(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.network(
                  'https://images.unsplash.com/photo-1464983953574-0892a716854b?auto=format&fit=crop&w=400&q=80',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Admin Portal',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage your organization',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Admin Login',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sign in with admin credentials',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined),
                  hintText: 'Admin Email',
                  filled: true,
                  fillColor: const Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  hintText: 'Admin Password',
                  filled: true,
                  fillColor: const Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: const Color(0xFF2196F3),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Admin Sign In'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: Color(0xFF2196F3), width: 2),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: const Text(
                    'Back to User Login',
                    style: TextStyle(color: Color(0xFF2196F3)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.only(bottom: 24.0),
                child: Center(
                  child: Text(
                    'Use your admin email and password to sign in',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Simulate password reset delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset instructions sent to your email'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Reset Password',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Enter your email and we'll send you instructions to reset your password",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined),
                  hintText: 'Email',
                  filled: true,
                  fillColor: const Color(0xFFF6F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: const Color(0xFF2196F3),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send Reset Instructions'),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Back to Login',
                    style: TextStyle(
                      color: Color(0xFF2196F3),
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmployeeDashboard extends StatefulWidget {
  final String userName;

  const EmployeeDashboard({
    super.key,
    required this.userName,
  });

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _isLoading = false;
  bool _isWithinRange = false;
  bool _isInitialized = false;
  double _distanceFromOffice = 0;
  DateTime _currentTime = DateTime.now();
  AttendanceStats _stats = AttendanceStats(
    attendancePercentage: 0,
    presentDays: 0,
    lateDays: 0,
    absentDays: 0,
  );
  Timer? _locationTimer;
  Timer? _statsTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _initializeAttendance();
    _startClock();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _statsTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _clockTimer?.cancel();
    // Update time every second
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _initializeAttendance() async {
    if (_isInitialized) return;

    try {
      await _attendanceService.init();
      await _updateLocation();
      _updateStats();

      // Start periodic updates only after initial setup
      _startLocationUpdates();
      _startStatsUpdates();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
    }
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateLocation();
    });
  }

  void _startStatsUpdates() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _updateStats();
    });
  }

  Future<void> _updateLocation() async {
    if (!mounted) return;

    try {
      double distance = await _attendanceService.getDistanceFromOffice();
      bool inRange = distance <= 200; // 200 meters range

      if (mounted) {
        setState(() {
          _distanceFromOffice = distance;
          _isWithinRange = inRange;
        });
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  void _updateStats() {
    if (!mounted) return;

    setState(() {
      _stats = _attendanceService.getAttendanceStats();
    });
  }

  Future<void> _handleCheckIn() async {
    if (_isLoading || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await _attendanceService.checkIn();
      _updateStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in successful!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleViewHistory() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance History',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Coming soon! This feature will show your detailed attendance history.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleExportData() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export Attendance Data',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Coming soon! You will be able to export your attendance data in various formats.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Coming soon! You will be able to customize your app settings here.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    String formattedDate = DateFormat('yyyy-MM-dd').format(_currentTime);
    String formattedTime = DateFormat('h:mm a').format(_currentTime);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hello,',
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Engineering',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.blue,
                        width: 3,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.blue.shade100,
                      child: ClipOval(
                        child: Image.network(
                          'https://images.unsplash.com/photo-1633332755192-727a05c4013d?auto=format&fit=crop&w=100&q=80',
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Date and Time Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        formattedTime,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Check-in Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ready to start your day?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You are ${_distanceFromOffice.toStringAsFixed(0)}m from office ${_isWithinRange ? "(within range)" : "(out of range)"}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isWithinRange
                                  ? Colors.greenAccent
                                  : Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _isWithinRange && !_isLoading
                            ? _handleCheckIn
                            : null,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.blue),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.fingerprint,
                                    color: Colors.blue,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Check In',
                                    style: TextStyle(
                                      color: _isWithinRange
                                          ? Colors.blue
                                          : Colors.grey,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Fingerprint verification will be used for check-in',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Attendance Summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Attendance Summary',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.calendar_month,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMMM yyyy').format(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAttendanceCard(
                    '${_stats.attendancePercentage.toStringAsFixed(1)}%',
                    'Attendance',
                    Colors.blue,
                  ),
                  _buildAttendanceCard(
                    _stats.presentDays.toString(),
                    'Present',
                    Colors.green,
                  ),
                  _buildAttendanceCard(
                    _stats.lateDays.toString(),
                    'Late',
                    Colors.orange,
                  ),
                  _buildAttendanceCard(
                    _stats.absentDays.toString(),
                    'Absent',
                    Colors.red,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Working Stats
              Row(
                children: [
                  Expanded(
                    child: _buildWorkingStatsCard(
                      'Working Hours',
                      '0.0 hrs',
                      Icons.access_time,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildWorkingStatsCard(
                      'Working Days',
                      '1/31 days',
                      Icons.calendar_month,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Quick Actions
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildQuickActionButton(
                    'View History',
                    Icons.history,
                    _handleViewHistory,
                  ),
                  _buildQuickActionButton(
                    'Export Data',
                    Icons.download,
                    _handleExportData,
                  ),
                  _buildQuickActionButton(
                    'Settings',
                    Icons.settings,
                    _handleSettings,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Company Name
              const Center(
                child: Text(
                  '© Kalam Dream Labs',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(String value, String label, Color color) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingStatsCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.blue,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int selectedTabIndex = 0; // 0: Employees, 1: Attendance, 2: Settings

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuthService.signOut();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: ${e.toString()}')),
        );
      }
    }
  }

  // Example attendance data
  final List<Map<String, dynamic>> attendanceRecords = [
    {
      'date': '2025-05-28',
      'name': 'John Doe',
      'avatar': 'https://randomuser.me/api/portraits/men/1.jpg',
      'checkIn': '4:48 PM',
      'checkOut': '4:48 PM',
      'status': 'PRESENT',
      'note': 'Early checkout: jampallu konukovali',
    },
    // Add more records as needed
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181A20),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Admin Dashboard',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _handleLogout,
            child: const Text('Logout',
                style: TextStyle(color: Color(0xFF2196F3))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Search bar
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF23242A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search employees or departments...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  contentPadding: EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Tab bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabButton('Employees', 0),
                  const SizedBox(width: 8),
                  _buildTabButton('Attendance', 1),
                  const SizedBox(width: 8),
                  _buildTabButton('Settings', 2),
                  if (selectedTabIndex == 1) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.download, color: Colors.white),
                      label: const Text('Export CSV'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Tab content
            if (selectedTabIndex == 0)
              _buildEmployeesTab()
            else if (selectedTabIndex == 1)
              _buildAttendanceTab()
            else
              _buildSettingsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final bool isSelected = selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => selectedTabIndex = index),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: isSelected ? const Color(0xFF2196F3) : Colors.transparent),
          color: isSelected ? Colors.transparent : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Icon(
                index == 0
                    ? Icons.people_alt_outlined
                    : index == 1
                        ? Icons.calendar_month
                        : Icons.settings,
                color: isSelected ? const Color(0xFF2196F3) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF2196F3) : Colors.grey,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeesTab() {
    // Demo employee list
    final employees = [
      {
        'id': '1',
        'name': 'John Doe',
        'role': 'Software Engineer',
        'department': 'Engineering',
        'startDate': '2022-01-15',
        'avatar': 'https://randomuser.me/api/portraits/men/1.jpg',
        'email': 'john.doe@kalamdreamlabs.com',
        'workingHours': '09:00 -17:00',
      },
      {
        'id': '2',
        'name': 'Jane Smith',
        'role': 'UI/UX Designer',
        'department': 'Design',
        'startDate': '2022-03-10',
        'avatar': 'https://randomuser.me/api/portraits/women/2.jpg',
        'email': 'jane.smith@kalamdreamlabs.com',
        'workingHours': '09:00 -17:00',
      },
      {
        'id': '3',
        'name': 'Michael Johnson',
        'role': 'Marketing Manager',
        'department': 'Marketing',
        'startDate': '2021-11-05',
        'avatar': 'https://randomuser.me/api/portraits/men/3.jpg',
        'email': 'michael.johnson@kalamdreamlabs.com',
        'workingHours': '09:00 -17:00',
      },
      {
        'id': '4',
        'name': 'Vinod',
        'role': 'Jr. SDE',
        'department': 'AI&DS',
        'startDate': '2025-05-28',
        'avatar': 'https://randomuser.me/api/portraits/men/4.jpg',
        'email': 'vinod@kalamdreamlabs.com',
        'workingHours': '09:00 -17:00',
      },
    ];

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('All Employees (${employees.length})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddEmployeeDialog(context),
                  icon: const Icon(Icons.person_add_alt_1,
                      color: Colors.white, size: 20),
                  label: const Text('Add',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: employees.length,
              itemBuilder: (context, index) {
                final emp = employees[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF23242A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) =>
                            _EmployeeDetailsSheet(employee: emp),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundImage: NetworkImage(emp['avatar']!),
                            radius: 32,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(emp['name']!,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20)),
                                const SizedBox(height: 2),
                                Text(emp['role']!,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 16)),
                                Text(emp['department']!,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 15)),
                                Text('Started: ${emp['startDate']!}',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 14)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: Colors.white, size: 28),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    return Expanded(
      child: ListView(
        children: [
          const Text(
            'Recent Attendance',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...attendanceRecords
              .map((record) => _buildAttendanceCard(record))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF23242A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and status
            Row(
              children: [
                Expanded(
                  child: Text(
                    (record['date'] ?? '').toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PRESENT',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            // Employee info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(record['avatar']),
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record['name'],
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        'Check In: ${record['checkIn']}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        'Check Out: ${record['checkOut']}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if (record['note'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            record['note'],
                            style: const TextStyle(
                                color: Colors.amber,
                                fontStyle: FontStyle.italic,
                                fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    // Settings UI as per the provided image
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
                margin: const EdgeInsets.only(top: 12, bottom: 18),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF23242A),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Admin Settings',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _showChangePasswordDialog(context),
                        icon:
                            const Icon(Icons.lock_outline, color: Colors.white),
                        label: const Text('Change Admin Password',
                            style: TextStyle(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Office Location Card
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF23242A),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Office Location',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
                    const SizedBox(height: 16),
                    const Text('Address',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF181A20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                      ),
                      onChanged: (val) => _address = val,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Latitude',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 16)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: latitudeController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF181A20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 16, horizontal: 12),
                                ),
                                onChanged: (val) => _latitude = val,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Longitude',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 16)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: longitudeController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF181A20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 16, horizontal: 12),
                                ),
                                onChanged: (val) => _longitude = val,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Max Check-in Distance (meters)',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: maxDistanceController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF181A20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                      ),
                      onChanged: (val) => _maxDistance = val,
                    ),
                  ],
                ),
              ),
              // Working Hours Card
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF23242A),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Working Hours',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Start Time',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 16)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () async {
                                  TimeOfDay? picked = await showTimePicker(
                                    context: context,
                                    initialTime: _startTime,
                                  );
                                  if (picked != null) {
                                    setState(() => _startTime = picked);
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF181A20),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                          _startTime.hour
                                              .toString()
                                              .padLeft(2, '0'),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22)),
                                      const Text(' : ',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22)),
                                      Text(
                                          _startTime.minute
                                              .toString()
                                              .padLeft(2, '0'),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('End Time',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 16)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () async {
                                  TimeOfDay? picked = await showTimePicker(
                                    context: context,
                                    initialTime: _endTime,
                                  );
                                  if (picked != null) {
                                    setState(() => _endTime = picked);
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF181A20),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                          _endTime.hour
                                              .toString()
                                              .padLeft(2, '0'),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22)),
                                      const Text(' : ',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22)),
                                      Text(
                                          _endTime.minute
                                              .toString()
                                              .padLeft(2, '0'),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Save Changes Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _address = addressController.text;
                      _latitude = latitudeController.text;
                      _longitude = longitudeController.text;
                      _maxDistance = maxDistanceController.text;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Settings saved successfully!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Save Changes',
                      style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // State variables for settings
  String _address = 'Kalam Dream Labs';
  String _latitude = '17.724';
  String _longitude = '83.313';
  String _maxDistance = '250';
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  void _showChangePasswordDialog(BuildContext context) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF23242A),
              title: const Text('Change Admin Password',
                  style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (newPasswordController.text !=
                              confirmPasswordController.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('New passwords do not match'),
                              ),
                            );
                            return;
                          }

                          setState(() => isLoading = true);

                          try {
                            await FirebaseAuthService.changeAdminPassword(
                              currentPassword: oldPasswordController.text,
                              newPassword: newPasswordController.text,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Password changed successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Change Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddEmployeeDialog(BuildContext context) {
    final nameController = TextEditingController();
    final roleController = TextEditingController();
    final departmentController = TextEditingController();
    final startDateController = TextEditingController();
    final avatarController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF23242A),
          title:
              const Text('Add Employee', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: roleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: departmentController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: startDateController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Start Date (YYYY-MM-DD)',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: avatarController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Avatar URL',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                // Here you would add logic to actually add the employee
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

// Placeholder for employee attendance page with demo data
class EmployeeAttendancePage extends StatelessWidget {
  final Map<String, dynamic> employee;
  const EmployeeAttendancePage({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    // Demo attendance data for each employee
    final List<Map<String, String>> attendance = [
      {
        'date': '2024-06-01',
        'checkIn': '09:05 AM',
        'checkOut': '05:45 PM',
        'status': 'Present',
      },
      {
        'date': '2024-05-31',
        'checkIn': '09:20 AM',
        'checkOut': '05:30 PM',
        'status': 'Late',
      },
      {
        'date': '2024-05-30',
        'checkIn': '09:00 AM',
        'checkOut': '05:50 PM',
        'status': 'Present',
      },
      {
        'date': '2024-05-29',
        'checkIn': 'Absent',
        'checkOut': '-',
        'status': 'Absent',
      },
      {
        'date': '2024-05-28',
        'checkIn': '09:10 AM',
        'checkOut': '05:40 PM',
        'status': 'Present',
      },
    ];

    Color statusColor(String status) {
      switch (status) {
        case 'Present':
          return Colors.green;
        case 'Late':
          return Colors.orange;
        case 'Absent':
          return Colors.red;
        default:
          return Colors.grey;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181A20),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${employee['name']} Attendance',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF23242A),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: employee['avatar'] != null
                        ? NetworkImage(employee['avatar'])
                        : null,
                    radius: 36,
                    backgroundColor: Colors.white24,
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Text('Attendance Records',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: attendance.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final record = attendance[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF23242A),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status Dot
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor(record['status'] ?? ''),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Attendance Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      record['date'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    record['status'] ?? '',
                                    style: TextStyle(
                                      color:
                                          statusColor(record['status'] ?? ''),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Check In: ${record['checkIn']}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 15)),
                              Text('Check Out: ${record['checkOut']}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 15)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
