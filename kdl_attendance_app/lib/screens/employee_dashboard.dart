class EmployeeDashboard extends StatefulWidget {
  final String userName;
  final Map<String, dynamic> employeeData;
  final bool isAdminView;

  const EmployeeDashboard({
    super.key,
    required this.userName,
    required this.employeeData,
    this.isAdminView = false,
  });

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  late Stream<DocumentSnapshot> _employeeStream;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    try   {
      _employeeStream = FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeData['uid'])
          .snapshots();
    } catch (e) {
      debugPrint('Error initializing employee stream: $e');
      // Handle the error gracefully in the build method
      _employeeStream = Stream.error(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdminView
              ? '${widget.userName}\'s Dashboard'
              : 'Welcome, ${widget.userName}',
        ),
        actions: [
          if (!widget.isAdminView)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) {
                    Navigator.of(context).pushReplacementNamed('/');
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error signing out: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _employeeStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No data available'));
          }

          final employeeData = snapshot.data!.data() as Map<String, dynamic>;
          final attendanceRecords = employeeData['attendanceRecords'] as List<dynamic>? ?? [];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Employee Information',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text('Role: ${employeeData['role'] ?? 'N/A'}'),
                        Text('Domain: ${employeeData['domain'] ?? 'N/A'}'),
                        Text(
                          'Joined: ${employeeData['dateOfJoining'] != null ? DateFormat('dd/MM/yyyy').format((employeeData['dateOfJoining'] as Timestamp).toDate()) : 'N/A'}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: attendanceRecords.length,
                  itemBuilder: (context, index) {
                    final record = attendanceRecords[index];
                    final date = (record['date'] as Timestamp).toDate();
                    final checkInTime = record['checkInTime'] != null
                        ? (record['checkInTime'] as Timestamp).toDate()
                        : null;
                    final checkOutTime = record['checkOutTime'] != null
                        ? (record['checkOutTime'] as Timestamp).toDate()
                        : null;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        title: Text(
                          DateFormat('EEEE, MMMM d, y').format(date),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-in: ${checkInTime != null ? DateFormat('hh:mm a').format(checkInTime) : 'Not checked in'}',
                            ),
                            Text(
                              'Check-out: ${checkOutTime != null ? DateFormat('hh:mm a').format(checkOutTime) : 'Not checked out'}',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!widget.isAdminView)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final employeeDoc = await FirebaseFirestore
                                        .instance
                                        .collection('employees')
                                        .doc(widget.employeeData['uid'])
                                        .get();

                                    if (!employeeDoc.exists) {
                                      throw Exception('Employee document not found');
                                    }

                                    final currentDate = DateTime.now();
                                    final today = DateTime(currentDate.year,
                                        currentDate.month, currentDate.day);

                                    final records =
                                        List<Map<String, dynamic>>.from(
                                            employeeDoc.data()?[
                                                    'attendanceRecords'] ??
                                                []);

                                    final todayRecord = records.firstWhere(
                                      (record) {
                                        final recordDate =
                                            (record['date'] as Timestamp).toDate();
                                        return recordDate.year == today.year &&
                                            recordDate.month == today.month &&
                                            recordDate.day == today.day;
                                      },
                                      orElse: () => {
                                        'date': Timestamp.fromDate(today),
                                        'checkInTime': null,
                                        'checkOutTime': null,
                                      },
                                    );

                                    if (!records.contains(todayRecord)) {
                                      records.add(todayRecord);
                                    }

                                    final index = records.indexOf(todayRecord);
                                    if (todayRecord['checkInTime'] == null) {
                                      records[index]['checkInTime'] =
                                          Timestamp.now();
                                    } else if (todayRecord['checkOutTime'] ==
                                        null) {
                                      records[index]['checkOutTime'] =
                                          Timestamp.now();
                                    }

                                    await employeeDoc.reference
                                        .update({'attendanceRecords': records});

                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            todayRecord['checkInTime'] == null
                                                ? 'Checked in successfully'
                                                : todayRecord['checkOutTime'] ==
                                                        null
                                                    ? 'Checked out successfully'
                                                    : 'Already checked in and out for today',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Error: ${e.toString()}'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Check In/Out'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
} 