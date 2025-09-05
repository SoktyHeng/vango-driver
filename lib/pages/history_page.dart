import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> historyTrips = [];
  bool isLoading = true;
  DateTime? selectedDate; // ✅ store filter date

  @override
  void initState() {
    super.initState();
    _loadTripHistory();
  }

  Future<void> _loadTripHistory({DateTime? filterDate}) async {
    try {
      setState(() {
        isLoading = true;
      });

      Query query = FirebaseFirestore.instance
          .collection('trip_history')
          .orderBy('completedAt', descending: true);

      // ✅ If a specific date is selected, filter trips for that day
      if (filterDate != null) {
        DateTime startOfDay = DateTime(filterDate.year, filterDate.month, filterDate.day);
        DateTime endOfDay = startOfDay.add(const Duration(days: 1));

        query = query
            .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('completedAt', isLessThan: Timestamp.fromDate(endOfDay));
      }

      final historySnapshot = await query.get();

      List<Map<String, dynamic>> trips = [];
      for (var doc in historySnapshot.docs) {
        trips.add({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        });
      }

      setState(() {
        historyTrips = trips;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading trip history: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  // ✅ Date Picker
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      _loadTripHistory(filterDate: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Trip History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.blue),
            onPressed: _pickDate,
            tooltip: "Filter by date",
          ),
          if (selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red),
              onPressed: () {
                setState(() {
                  selectedDate = null;
                });
                _loadTripHistory(); // reload all trips
              },
              tooltip: "Clear filter",
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : historyTrips.isEmpty
              ? _buildEmptyState()
              : _buildHistoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            selectedDate != null
                ? 'No trips found on ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                : 'No trip history yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Completed trips will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: historyTrips.length,
      itemBuilder: (context, index) {
        final trip = historyTrips[index];
        return _buildHistoryCard(trip);
      },
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> trip) {
    final scheduleData = trip['scheduleData'] as Map<String, dynamic>? ?? {};
    final completedAt = trip['completedAt'] as Timestamp?;
    final checkedInCount = trip['checkedInCount'] ?? 0;
    final totalPassengers = trip['totalPassengers'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[200]!.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route and Date
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip['routeDisplay'] ?? 'Unknown Route',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${scheduleData['date']} • ${scheduleData['time']}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Completed',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.green[700]),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Passenger Info
          Row(
            children: [
              Icon(Icons.people, size: 18, color: Colors.blue[600]),
              const SizedBox(width: 8),
              Text(
                'Checked in: $checkedInCount / $totalPassengers passengers',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ),

          if (completedAt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 18, color: Colors.orange[600]),
                const SizedBox(width: 8),
                Text(
                  'Completed: ${_formatDateTime(completedAt)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

