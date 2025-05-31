import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../services/attendance_service.dart';

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
  final LocalAuthentication _localAuth = LocalAuthentication();
  final bool _isLoading = false;
  bool _isWithinRange = false;
  bool _isInitialized = false;
  double _distanceFromOffice = 0;
  DateTime _currentTime = DateTime.now();
  Timer? _locationTimer;
  Timer? _statsTimer;
  Timer? _clockTimer;
  bool? _isCheckedIn;
  String? _checkInTime;
  AttendanceStats _stats = AttendanceStats(
    attendancePercentage: 0,
    presentDays: 0,
    lateDays: 0,
    absentDays: 0,
  );

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
      await _updateCheckInStatus();
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

  Future<void> _updateCheckInStatus() async {
    if (!mounted) return;
    
    try {
      bool isCheckedIn = await _attendanceService.isCheckedIn();
      String? checkInTime = await _attendanceService.getCheckInTime();
      
      if (mounted) {
        setState(() {
          _isCheckedIn = isCheckedIn;
          _checkInTime = checkInTime;
        });
      }
    } catch (e) {
      debugPrint('Error updating check-in status: $e');
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

  Future<void> _handleAuthenticatedAction(BiometricType type, bool isCheckIn) async {
    try {
      bool authenticated = await _attendanceService.authenticateWithBiometrics(type: type);
      if (!mounted) return;

      if (authenticated) {
        if (isCheckIn) {
          await _handleCheckIn();
        } else {
          await _handleCheckOut();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleCheckIn() async {
    try {
      await _attendanceService.checkIn();
      await _updateCheckInStatus();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully checked in'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking in: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleCheckOut() async {
    try {
      await _attendanceService.checkOut();
      await _updateCheckInStatus();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully checked out'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking out: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showBiometricDialog({required bool isCheckIn}) async {
    if (kIsWeb) {
      // For web platform, skip biometric dialog and directly handle check-in/check-out
      if (isCheckIn) {
        await _handleCheckIn();
      } else {
        await _handleCheckOut();
      }
      return;
    }

    final availableBiometrics = await _localAuth.getAvailableBiometrics();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF23242A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCheckIn ? 'Check In Authentication' : 'Check Out Authentication',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isCheckIn ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select your preferred authentication method',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            if (availableBiometrics.contains(BiometricType.fingerprint))
              _buildAuthOptionTile(
                icon: Icons.fingerprint,
                title: 'Fingerprint',
                subtitle: 'Use your fingerprint to authenticate',
                onTap: () {
                  Navigator.pop(context);
                  _handleAuthenticatedAction(BiometricType.fingerprint, isCheckIn);
                },
              ),
            if (availableBiometrics.contains(BiometricType.fingerprint) &&
                availableBiometrics.contains(BiometricType.face))
              const SizedBox(height: 12),
            if (availableBiometrics.contains(BiometricType.face))
              _buildAuthOptionTile(
                icon: Icons.face,
                title: 'Face ID',
                subtitle: 'Use Face ID to authenticate',
                onTap: () {
                  Navigator.pop(context);
                  _handleAuthenticatedAction(BiometricType.face, isCheckIn);
                },
              ),
            if (availableBiometrics.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade300),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'No biometric authentication methods available on this device',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInOutButtons() {
    if (_isCheckedIn == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (!_isCheckedIn! && _isWithinRange && !_isLoading) 
                    ? () => _showBiometricDialog(isCheckIn: true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.login, color: Colors.white),
                    const SizedBox(width: 8),
                    Opacity(
                      opacity: (!_isCheckedIn! && _isWithinRange) ? 1.0 : 0.6,
                      child: const Text(
                        'Check In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: (_isCheckedIn! && _isWithinRange && !_isLoading)
                    ? () => _showBiometricDialog(isCheckIn: false)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout, color: Colors.white),
                    const SizedBox(width: 8),
                    Opacity(
                      opacity: (_isCheckedIn! && _isWithinRange) ? 1.0 : 0.6,
                      child: const Text(
                        'Check Out',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (!_isLoading && _checkInTime != null) ...[
          const SizedBox(height: 8),
          Text(
            'Checked in at $_checkInTime',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ],
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
                          'https://ui-avatars.com/api/?name=${Uri.encodeComponent(widget.userName)}&size=60&background=random',
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
                              color: _isWithinRange ? Colors.greenAccent : Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildCheckInOutButtons(),
                    const SizedBox(height: 8),
                    Center(
                      child: FutureBuilder<List<BiometricType>>(
                        future: _localAuth.getAvailableBiometrics(),
                        builder: (context, snapshot) {
                          String text = 'Biometric verification will be used for check-in';
                          if (snapshot.hasData && snapshot.data != null) {
                            if (snapshot.data!.contains(BiometricType.face)) {
                              text = 'Face recognition will be used for check-in';
                            } else if (snapshot.data!.contains(BiometricType.fingerprint)) {
                              text = 'Fingerprint verification will be used for check-in';
                            }
                          }
                          return Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          );
                        },
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
                      _attendanceService.getWorkingHours(),
                      Icons.access_time,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildWorkingStatsCard(
                      'Working Days',
                      _attendanceService.getWorkingDays(),
                      Icons.calendar_month,
                    ),
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
} 