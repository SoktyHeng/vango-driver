import 'package:driver_vango/pages/trip_details_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? currentDriverId;
  String? currentDriverName;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  Future<void> _loadDriverData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          errorMessage = 'Not authenticated';
          isLoading = false;
        });
        return;
      }

      // Query the drivers collection to find the current user's data
      final querySnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final driverData = querySnapshot.docs.first.data();
        final driverId =
            querySnapshot.docs.first.id; // Use document ID instead of user.uid
        setState(() {
          currentDriverId = driverId;
          currentDriverName = driverData['name'] ?? 'Driver';
          isLoading = false;
        });

        print('Driver loaded: $currentDriverName with ID: $currentDriverId');

        // Test query to see if any schedules exist
        _testScheduleQuery();
      } else {
        setState(() {
          errorMessage = 'Driver data not found';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading driver data: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _testScheduleQuery() async {
    try {
      final allSchedules = await FirebaseFirestore.instance
          .collection('schedules')
          .limit(5)
          .get();

      print('Total schedules in collection: ${allSchedules.docs.length}');

      for (var doc in allSchedules.docs) {
        final data = doc.data();
        print(
          'Schedule: ${doc.id} - driverId: ${data['driverId']}, date: ${data['date']}',
        );
      }

      final driverSchedules = await FirebaseFirestore.instance
          .collection('schedules')
          .where('driverId', isEqualTo: currentDriverId)
          .get();

      print(
        'Schedules for driver $currentDriverId: ${driverSchedules.docs.length}',
      );
    } catch (e) {
      print('Error testing schedule query: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDriverData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDriverData,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Welcome Header
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue[600]!,
                                      Colors.blue[400]!,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome back,',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      currentDriverName ?? 'Driver',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Today is ${DateFormat('EEEE, MMMM d').format(DateTime.now())}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Today's Schedule Section
                              Text(
                                'Today\'s Schedule',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      // Today's Schedule List
                      SliverToBoxAdapter(child: _buildTodaySchedule()),

                      // Upcoming Schedules Section
                      SliverToBoxAdapter(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              Text(
                                'Upcoming Schedules',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      // Upcoming Schedules List
                      SliverToBoxAdapter(child: _buildUpcomingSchedules()),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTodaySchedule() {
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('schedules')
        .where('driverId', isEqualTo: currentDriverId)
        .where('date', isEqualTo: today)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _buildErrorWidget(
          'Error loading today\'s schedule: ${snapshot.error}',
        );
      }

      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(20.0),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      final allSchedules = snapshot.data?.docs ?? [];

      // Exclude completed
      final schedules = allSchedules.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] != 'completed';
      }).toList();

      // Sort by time
      schedules.sort((a, b) {
        final aTime = (a.data() as Map<String, dynamic>)['time'] ?? '';
        final bTime = (b.data() as Map<String, dynamic>)['time'] ?? '';
        return aTime.compareTo(bTime);
      });

      // ✅ Take only 5
      final limitedSchedules = schedules.take(5).toList();

      if (limitedSchedules.isEmpty) {
        return _buildEmptyScheduleWidget('No schedules for today');
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          children: limitedSchedules.map((doc) {
            final schedule = doc.data() as Map<String, dynamic>;
            schedule['scheduleId'] = doc.id;
            return _buildScheduleCard(schedule, isToday: true);
          }).toList(),
        ),
      );
    },
  );
}


  Widget _buildUpcomingSchedules() {
  final today = DateTime.now();
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('schedules')
        .where('driverId', isEqualTo: currentDriverId)
        .where('date', isEqualTo: tomorrowStr)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _buildErrorWidget(
          'Error loading upcoming schedules: ${snapshot.error}',
        );
      }

      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(20.0),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      final allSchedules = snapshot.data?.docs ?? [];

      // Exclude completed
      final schedules = allSchedules.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] != 'completed';
      }).toList();

      // Sort by time
      schedules.sort((a, b) {
        final aTime = (a.data() as Map<String, dynamic>)['time'] ?? '';
        final bTime = (b.data() as Map<String, dynamic>)['time'] ?? '';
        return aTime.compareTo(bTime);
      });

      // ✅ Take only 6
      final limitedSchedules = schedules.take(6).toList();

      if (limitedSchedules.isEmpty) {
        return _buildEmptyScheduleWidget('No trips for tomorrow');
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          children: limitedSchedules.map((doc) {
            final schedule = doc.data() as Map<String, dynamic>;
            schedule['scheduleId'] = doc.id;
            return _buildScheduleCard(schedule, isToday: false);
          }).toList(),
        ),
      );
    },
  );
}


  Widget _buildScheduleCard(
    Map<String, dynamic> schedule, {
    required bool isToday,
  }) {
    final time = schedule['time'] ?? 'No time';
    final date = schedule['date'] ?? 'No date';
    final routeId = schedule['routeId'] ?? 'No route';
    final vanId = schedule['vanId'] ?? 'No van';
    final vanLicense = schedule['vanLicense'] ?? 'No license';
    final scheduleId = schedule['scheduleId'] ?? '';

    // Safe parsing of numeric fields
    final seatsTotal = _parseToInt(schedule['seatsTotal']) ?? 0;

    // Parse date for display
    DateTime? scheduleDate;
    try {
      scheduleDate = DateFormat('yyyy-MM-dd').parse(date);
    } catch (e) {
      scheduleDate = null;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripDetailsPage(
              scheduleId: scheduleId,
              scheduleData: schedule,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: isToday
              ? Border.all(color: Colors.blue[300]!, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isToday ? Colors.blue[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: isToday
                          ? Border.all(color: Colors.blue[300]!)
                          : null,
                    ),
                    child: Text(
                      isToday
                          ? 'TODAY'
                          : scheduleDate != null
                          ? DateFormat('MMM dd').format(scheduleDate)
                          : date,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isToday ? Colors.blue[700] : Colors.grey[600],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Route Info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.route, size: 20, color: Colors.blue[600]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        FutureBuilder<String>(
                          future: _getRouteDisplay(routeId),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Text(
                                'Loading...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[500],
                                ),
                              );
                            }
                            return Text(
                              snapshot.data ?? routeId,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Van Info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.directions_bus,
                      size: 20,
                      color: Colors.green[600],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Van',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$vanId • $vanLicense',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Seats Info - Use FutureBuilder to calculate taken seats dynamically
              FutureBuilder<int>(
                future: _calculateTakenSeats(scheduleId, date, time, routeId),
                builder: (context, snapshot) {
                  final seatsTaken = snapshot.data ?? 0;
                  final seatsAvailable = seatsTotal - seatsTaken;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSeatInfo('Total', seatsTotal.toString(), Colors.blue),
                        _buildSeatInfo(
                          'Taken',
                          seatsTaken.toString(),
                          Colors.orange,
                        ),
                        _buildSeatInfo(
                          'Available',
                          seatsAvailable.toString(),
                          Colors.green,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add this new method to calculate taken seats by counting actual bookings
  Future<int> _calculateTakenSeats(String scheduleId, String date, String time, String routeId) async {
    try {
      int totalTaken = 0;

      // Strategy 1: Try to find bookings with exact scheduleId
      var bookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('scheduleId', isEqualTo: scheduleId)
          .get();

      print('Found ${bookingsSnapshot.docs.length} bookings with exact scheduleId for $scheduleId');

      // Strategy 2: If no exact match, find by date, time, and route
      if (bookingsSnapshot.docs.isEmpty) {
        print('No exact scheduleId match, trying date/time/route');
        
        // First try date and time
        bookingsSnapshot = await FirebaseFirestore.instance
            .collection('bookings')
            .where('date', isEqualTo: date)
            .where('time', isEqualTo: time)
            .get();

        print('Found ${bookingsSnapshot.docs.length} bookings matching date/time');

        // Filter by route if we have multiple results
        if (bookingsSnapshot.docs.length > 1 && routeId.isNotEmpty) {
          final filteredDocs = bookingsSnapshot.docs.where((doc) {
            final bookingData = doc.data();
            final bookingFrom = bookingData['from']?.toString().toLowerCase();
            final bookingTo = bookingData['to']?.toString().toLowerCase();
            
            // Check if route matches
            if (routeId == 'mega_au') {
              return (bookingFrom == 'mega' && bookingTo == 'au');
            }
            
            return bookingData['routeId'] == routeId;
          }).toList();
          
          // Count passengers from filtered bookings
          for (var doc in filteredDocs) {
            final bookingData = doc.data();
            final passengerCount = bookingData['passengerCount'] ?? 1;
            totalTaken += (passengerCount as int);
          }
        } else {
          // Count passengers from all matching bookings
          for (var doc in bookingsSnapshot.docs) {
            final bookingData = doc.data();
            final passengerCount = bookingData['passengerCount'] ?? 1;
            totalTaken += (passengerCount as int);
          }
        }
      } else {
        // Count passengers from exact scheduleId matches
        for (var doc in bookingsSnapshot.docs) {
          final bookingData = doc.data();
          final passengerCount = bookingData['passengerCount'] ?? 1;
          totalTaken += (passengerCount as int);
        }
      }

      print('Total taken seats calculated: $totalTaken for schedule $scheduleId');
      return totalTaken;
    } catch (e) {
      print('Error calculating taken seats: $e');
      return 0;
    }
  }

  Widget _buildEmptyScheduleWidget(String message) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          Icon(Icons.schedule, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.red[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Add this helper method to safely parse integers
  int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is List && value.isNotEmpty) {
      return _parseToInt(value.first);
    }
    return null;
  }

  // Method to fetch route display from routes collection
  Future<String> _getRouteDisplay(String routeId) async {
    try {
      if (routeId.isEmpty || routeId == 'No route') {
        return routeId;
      }

      final routeDoc = await FirebaseFirestore.instance
          .collection('routes')
          .doc(routeId)
          .get();

      if (routeDoc.exists) {
        final routeData = routeDoc.data() as Map<String, dynamic>;
        final from = routeData['from'] ?? '';
        final to = routeData['to'] ?? '';

        if (from.isNotEmpty && to.isNotEmpty) {
          return '$from - $to';
        }
      }

      // Fallback to routeId if route not found
      return routeId;
    } catch (e) {
      print('Error fetching route: $e');
      return routeId;
    }
  }

  // Add the missing _buildSeatInfo method
  Widget _buildSeatInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
