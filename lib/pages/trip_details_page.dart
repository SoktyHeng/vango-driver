import 'package:driver_vango/pages/history_page.dart';
import 'package:driver_vango/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'qr_scanner_page.dart';
class TripDetailsPage extends StatefulWidget {
  final String scheduleId;
  final Map<String, dynamic> scheduleData;

  const TripDetailsPage({
    super.key,
    required this.scheduleId,
    required this.scheduleData,
  });

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
  String? routeDisplay;
  List<Map<String, dynamic>> bookings = [];
  Set<String> selectedBookings = {};
  bool isLoading = true;

  // Location sharing variables
  bool isLocationSharing = false;
  String? currentDriverId;

  // Global location service
  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    _checkLocationSharingStatus();
    _loadTripData();
  }

  @override
  void dispose() {
    // DON'T stop location sharing here - let it continue globally
    super.dispose();
  }

  // Load current driver data
  Future<void> _loadDriverData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('drivers')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          setState(() {
            currentDriverId = querySnapshot.docs.first.id;
          });
        }
      }
    } catch (e) {
      print('Error loading driver data: $e');
    }
  }

  // Check if location sharing is already active
  Future<void> _checkLocationSharingStatus() async {
    try {
      // Check both local service state and Firestore
      final isTrackingThisSchedule = _locationService.isTrackingSchedule(
        widget.scheduleId,
      );

      final doc = await FirebaseFirestore.instance
          .collection('schedules')
          .doc(widget.scheduleId)
          .get();

      bool firestoreStatus = false;
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        firestoreStatus = data['locationSharingActive'] ?? false;
      }

      // Also check if there's active location data
      final locationDoc = await FirebaseFirestore.instance
          .collection('driver_locations')
          .doc(widget.scheduleId)
          .get();

      bool hasLocationData = locationDoc.exists;

      // If Firestore says active but no location data, it means sharing stopped
      if (firestoreStatus && !hasLocationData) {
        firestoreStatus = false;
        // Clean up stale status
        await FirebaseFirestore.instance
            .collection('schedules')
            .doc(widget.scheduleId)
            .update({'locationSharingActive': false});
      }

      // Use the more authoritative source (local service state)
      final actualStatus =
          isTrackingThisSchedule || (firestoreStatus && hasLocationData);

      if (mounted) {
        setState(() {
          isLocationSharing = actualStatus;
        });
      }

      print(
        'Location sharing status: local=$isTrackingThisSchedule, firestore=$firestoreStatus, hasData=$hasLocationData, final=$actualStatus',
      );

      // REMOVED: Auto-restart logic - let user manually start if needed
    } catch (e) {
      print('Error checking location sharing status: $e');
      if (mounted) {
        setState(() {
          isLocationSharing = false;
        });
      }
    }
  }

  // Start location sharing using global service
  Future<void> _startLocationSharing() async {
    if (currentDriverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver ID not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _locationService.startDriverLocationSharing(
        widget.scheduleId,
        currentDriverId!,
      );

      setState(() {
        isLocationSharing = true;
      });

      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text(
      //       'Location sharing started! This will continue in the background.',
      //     ),
      //     backgroundColor: Colors.green,
      //   ),
      // );
    } catch (e) {
      setState(() {
        isLocationSharing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start location sharing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Stop location sharing using global service
  Future<void> _stopLocationSharing() async {
    try {
      await _locationService.stopLocationSharing();

      setState(() {
        isLocationSharing = false;
      });

      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('Location sharing stopped.'),
      //     backgroundColor: Colors.orange,
      //   ),
      // );
    } catch (e) {
      print('Error stopping location sharing: $e');
    }
  }

  Future<void> _loadTripData() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Load route details
      await _loadRouteDetails();

      // Load bookings
      await _loadBookings();
    } catch (e) {
      print('Error loading trip data: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadRouteDetails() async {
    try {
      final routeId = widget.scheduleData['routeId'] ?? '';
      if (routeId.isNotEmpty) {
        final routeDoc = await FirebaseFirestore.instance
            .collection('routes')
            .doc(routeId)
            .get();

        if (routeDoc.exists) {
          final routeData = routeDoc.data() as Map<String, dynamic>;
          final from = routeData['from'] ?? '';
          final to = routeData['to'] ?? '';

          setState(() {
            routeDisplay = '$from → $to';
          });
        }
      }
    } catch (e) {
      print('Error loading route: $e');
    }
  }

  Future<void> _loadBookings() async {
    try {
      print('=== DEBUGGING BOOKINGS ===');
      print('Loading bookings for scheduleId: ${widget.scheduleId}');
      print('Schedule data: ${widget.scheduleData}');

      // Only search by exact scheduleId
      var bookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('scheduleId', isEqualTo: widget.scheduleId)
          .where(
            'status',
            whereIn: ['confirmed', 'pending'],
          ) // Only confirmed/pending bookings
          .get();

      print(
        'Found ${bookingsSnapshot.docs.length} bookings with exact scheduleId match',
      );

      if (bookingsSnapshot.docs.isEmpty) {
        print(
          'No bookings found for this specific schedule - this is correct behavior',
        );
        setState(() {
          bookings = [];
        });
        return;
      }

      List<Map<String, dynamic>> loadedBookings = [];

      for (var doc in bookingsSnapshot.docs) {
        final bookingData = doc.data();
        print('Processing booking: ${doc.id} with data: $bookingData');

        if (bookingData['scheduleId'] != widget.scheduleId) continue;

        String passengerName = 'Unknown';
        String passengerPhone = '';
        final userId = bookingData['userId'];

        if (userId != null) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();

            if (userDoc.exists) {
              final userData = userDoc.data();
              passengerName =
                  userData?['name'] ?? userData?['fullName'] ?? 'Unknown';
              passengerPhone = (userData?['phone number'] ?? '').toString();
            }
          } catch (e) {
            print('Error loading user data for booking ${doc.id}: $e');
          }
        } else {
          passengerName =
              bookingData['passengerName'] ?? bookingData['name'] ?? 'Unknown';
          passengerPhone = (bookingData['phone number'] ?? '').toString();
        }

        print('Booking: $passengerName, phone: $passengerPhone');

        loadedBookings.add({
          'id': doc.id,
          'userId': userId,
          'passengerName': passengerName,
          'passengerPhone': passengerPhone,
          'selectedSeats': bookingData['selectedSeats'] ?? [],
          'passengerCount': bookingData['passengerCount'] ?? 1,
          'location': bookingData['location'] ?? 'Unknown',
          'pricePerSeat': bookingData['pricePerSeat'] ?? 0,
          'totalPrice': bookingData['totalPrice'] ?? 0,
          'timestamp': bookingData['timestamp'],
          'status': bookingData['status'] ?? 'pending',
          'scheduleId': bookingData['scheduleId'],
          'isSelected': bookingData['isSelected'] ?? false,
        });

        if (bookingData['isSelected'] == true) {
          selectedBookings.add(doc.id);
        }
      }

      print('Final loaded bookings count: ${loadedBookings.length}');
      print('Loaded bookings: $loadedBookings');

      setState(() {
        bookings = loadedBookings;
      });
    } catch (e) {
      print('Error loading bookings: $e');
      setState(() {
        bookings = [];
      });
    }
  }

  int get totalSeats => _parseToInt(widget.scheduleData['seatsTotal']) ?? 0;
  int get bookedSeats => bookings.fold(
    0,
    (sum, booking) => sum + (booking['passengerCount'] as int),
  );
  int get availableSeats => totalSeats - bookedSeats;

  int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _toggleBookingSelection(String bookingId) async {
    final bookingIndex = bookings.indexWhere((b) => b['id'] == bookingId);
    if (bookingIndex == -1) return;

    final isNowSelected = !(selectedBookings.contains(bookingId));

    setState(() {
      if (isNowSelected) {
        selectedBookings.add(bookingId);
      } else {
        selectedBookings.remove(bookingId);
      }

      // Also update local booking map so UI reflects immediately
      bookings[bookingIndex]['isSelected'] = isNowSelected;
    });

    // Persist to Firestore
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({'isSelected': isNowSelected});
    } catch (e) {
      print("Error updating selection in Firestore: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Trip Detail',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Location sharing toggle button
          IconButton(
            icon: Icon(
              isLocationSharing ? Icons.location_on : Icons.location_off,
              color: isLocationSharing ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              if (isLocationSharing) {
                _showStopSharingDialog();
              } else {
                _startLocationSharing();
              }
            },
            tooltip: isLocationSharing
                ? 'Stop Location Sharing'
                : 'Start Location Sharing',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Location sharing status banner
                if (isLocationSharing)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.green[50],
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Colors.green[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location sharing active',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _stopLocationSharing,
                          child: Icon(
                            Icons.close,
                            color: Colors.green[700],
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Seat Capacity Section
                _buildSeatCapacitySection(),

                // Passengers List
                Expanded(child: _buildPassengersList()),

                // Bottom Buttons
                _buildBottomButtons(),
                SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _buildSeatCapacitySection() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seat Capacity: $totalSeats',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Booked seat: $bookedSeats',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),
              Expanded(
                child: Text(
                  'Available seat: $availableSeats',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPassengersList() {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No passengers booked yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index];
        final isSelected =
            selectedBookings.contains(booking['id']) ||
            (booking['isSelected'] == true);

        final selectedSeats = booking['selectedSeats'] as List<dynamic>;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.white,
            border: Border.all(
              color: isSelected ? Colors.blue[300]! : Colors.grey[200]!,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey[200]!.withOpacity(0.5),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (bool? value) {
                  _toggleBookingSelection(booking['id']);
                },
                activeColor: Colors.blue[600],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side: Name + Seat + Location
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Passenger Name
                          Row(
                            children: [
                              Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.blue[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  booking['passengerName'],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Seat Number and Location
                          Row(
                            children: [
                              Icon(
                                Icons.airline_seat_recline_normal,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                selectedSeats.isNotEmpty
                                    ? 'Seat ${selectedSeats.join(', ')}'
                                    : 'No seat',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  booking['location'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Right side: circular phone icon
                    GestureDetector(
                      onTap: () async {
                        final passengerPhone =
                            booking['passengerPhone']?.toString() ?? '';
                        if (passengerPhone.isEmpty) return;

                        final uri = Uri(scheme: 'tel', path: passengerPhone);

                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.platformDefault,
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cannot launch phone dialer'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.blue[300]!,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.phone,
                          size: 20,
                          color: Colors.blue[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        children: [
          // QR Scanner Button with permission check
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                print('🔍 QR Scanner button pressed');

                try {
                  final result = await Navigator.push<List<String>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QRScannerPage(
                        scheduleId: widget.scheduleId,
                        scheduleData: widget.scheduleData,
                      ),
                    ),
                  );

                  if (result != null && result.isNotEmpty) {
                    setState(() {
                      selectedBookings.addAll(result);
                    });

                    for (String bookingId in result) {
                      final bookingIndex = bookings.indexWhere(
                        (b) => b['id'] == bookingId,
                      );
                      if (bookingIndex != -1) {
                        bookings[bookingIndex]['isSelected'] = true;
                      }
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${result.length} passengers checked in via QR',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );

                    _loadBookings();
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error opening QR scanner: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text(
                'Scan QR Codes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Manual Check in button (unchanged)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showCheckInDialog(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue[600],
                side: BorderSide(color: Colors.blue[300]!),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.how_to_reg),
              label: const Text(
                'Manual Check In',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStopSharingDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Stop Location Sharing'),
          content: const Text(
            'Are you sure you want to stop sharing your location? Passengers will no longer be able to track you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _stopLocationSharing();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Stop Sharing'),
            ),
          ],
        );
      },
    );
  }

  void _showCheckInDialog() {
    if (selectedBookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one passenger to check in'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Check In'),
          content: Text(
            'Check in ${selectedBookings.length} selected passengers?\n\nThis will complete the trip and stop location sharing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _performCheckIn();
              },
              child: const Text('Check In'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performCheckIn() async {
    try {
      // Parse the trip date from scheduleData
      final String? tripDateStr = widget.scheduleData['date'];
      if (tripDateStr == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip has no date set'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Normalize both trip date and today's date to yyyy-MM-dd
      final tripDate = DateTime.tryParse(tripDateStr);
      final today = DateTime.now();
      final todayStr =
          "${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      if (tripDate == null || tripDateStr != todayStr) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This trip is not scheduled for today"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Clean up location data using the global service
      await _locationService.cleanupLocationData(widget.scheduleId);

      // Update schedule status to completed
      await FirebaseFirestore.instance
          .collection('schedules')
          .doc(widget.scheduleId)
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'checkedInPassengers': selectedBookings.toList(),
            'locationSharingActive': false,
          });

      // Update booking statuses for selected passengers
      for (String bookingId in selectedBookings) {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .update({
              'status': 'checked_in',
              'checkedInAt': FieldValue.serverTimestamp(),
            });
      }

      // Create history entry
      await FirebaseFirestore.instance.collection('trip_history').add({
        'scheduleId': widget.scheduleId,
        'scheduleData': widget.scheduleData,
        'routeDisplay': routeDisplay,
        'checkedInPassengers': selectedBookings.toList(),
        'totalPassengers': bookings.length,
        'checkedInCount': selectedBookings.length,
        'completedAt': FieldValue.serverTimestamp(),
        'date': widget.scheduleData['date'],
        'time': widget.scheduleData['time'],
        'routeId': widget.scheduleData['routeId'],
      });

      // Hide loading indicator
      Navigator.pop(context);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully checked in ${selectedBookings.length} passengers',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Update UI to reflect that location sharing stopped
      setState(() {
        isLocationSharing = false;
      });

      // Navigate to history page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HistoryPage()),
      );
    } catch (e) {
      // Hide loading indicator
      Navigator.pop(context);

      print('Error during check-in: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong during check-in'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
