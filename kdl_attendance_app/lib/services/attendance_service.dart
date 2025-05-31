import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

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

class AttendanceService {
  static const String _attendanceKey = 'attendance_records';
  static const String _checkInKey = 'check_in_time';
  static const String _checkOutKey = 'check_out_time';
  static const double _officeLatitude = 17.724610;
  static const double _officeLongitude = 83.314066;
  static const double _maxDistance = 200;

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

  Future<bool> authenticateWithBiometrics({required BiometricType type}) async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        throw Exception('Biometric authentication not available');
      }

      final List<BiometricType> availableBiometrics = 
          await _localAuth.getAvailableBiometrics();
      
      if (availableBiometrics.isEmpty || !availableBiometrics.contains(type)) {
        throw Exception('Selected biometric method is not available on this device');
      }

      String authMessage = type == BiometricType.face 
          ? 'Authenticate with Face ID'
          : 'Authenticate with fingerprint';

      return await _localAuth.authenticate(
        localizedReason: authMessage,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  Future<bool> isCheckedIn() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String? checkInTime = _prefs.getString('${_checkInKey}_$today');
    String? checkOutTime = _prefs.getString('${_checkOutKey}_$today');
    return checkInTime != null && checkOutTime == null;
  }

  Future<String?> getCheckInTime() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _prefs.getString('${_checkInKey}_$today');
  }

  Future<void> checkIn() async {
    try {
      bool isInRange = await isWithinOfficeRange();
      if (!isInRange) {
        throw Exception('You are not within office range');
      }

      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String currentTime = DateFormat('HH:mm').format(DateTime.now());
      
      // Save check-in time
      await _prefs.setString('${_checkInKey}_$today', currentTime);

      // Save attendance record
      List<String> records = _prefs.getStringList(_attendanceKey) ?? [];
      records.add(DateTime.now().toIso8601String());
      await _prefs.setStringList(_attendanceKey, records);
    } catch (e) {
      throw Exception('Check-in failed: $e');
    }
  }

  Future<void> checkOut() async {
    try {
      bool isInRange = await isWithinOfficeRange();
      if (!isInRange) {
        throw Exception('You are not within office range');
      }

      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String? checkInTime = await getCheckInTime();
      
      if (checkInTime == null) {
        throw Exception('You need to check in first');
      }

      String currentTime = DateFormat('HH:mm').format(DateTime.now());
      await _prefs.setString('${_checkOutKey}_$today', currentTime);
    } catch (e) {
      throw Exception('Check-out failed: $e');
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