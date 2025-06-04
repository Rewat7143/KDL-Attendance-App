import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'employees';

  // Add a new employee
  Future<void> addEmployee({
    required String name,
    required String phone,
    required String email,
    required String domain,
    required String role,
    required String shiftStartTime,
    required String shiftEndTime,
    required DateTime dateOfJoining,
  }) async {
    try {
      await _firestore.collection(_collection).add({
        'name': name,
        'phone': phone,
        'email': email,
        'domain': domain,
        'role': role,
        'shiftStartTime': shiftStartTime,
        'shiftEndTime': shiftEndTime,
        'dateOfJoining': Timestamp.fromDate(dateOfJoining),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'avatar':
            'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random',
      });
    } catch (e) {
      throw Exception('Failed to add employee: $e');
    }
  }

  // Get all employees
  Stream<List<Map<String, dynamic>>> getEmployees() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Add document ID to the data
        return data;
      }).toList();
    });
  }

  // Update employee
  Future<void> updateEmployee({
    required String employeeId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.collection(_collection).doc(employeeId).update(data);
    } catch (e) {
      throw Exception('Failed to update employee: $e');
    }
  }

  // Delete employee
  Future<void> deleteEmployee(String employeeId) async {
    try {
      await _firestore.collection(_collection).doc(employeeId).delete();
    } catch (e) {
      throw Exception('Failed to delete employee: ${e.toString()}');
    }
  }

  // Search employees
  Stream<List<Map<String, dynamic>>> searchEmployees(String query) {
    return _firestore
        .collection(_collection)
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: query + '\uf8ff')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }
}
