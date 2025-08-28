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

  @override
  void initState() {
    super.initState();
    _loadTripHistory();
  }

  Future<void> _loadTripHistory() async {
    try {
      setState(() {
        isLoading = true;
      });

      final historySnapshot = await FirebaseFirestore.instance
          .collection('trip_history')
          .orderBy('completedAt', descending: true)
          .get();

      List<Map<String, dynamic>> trips = [];
      
      for (var doc in historySnapshot.docs) {
        final data = doc.data();
        trips.add({
          'id': doc.id,
          ...data,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Trip History', style: TextStyle(fontSize: 20)),
        backgroundColor: Colors.white,
        centerTitle: true,
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
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No trip history yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Completed trips will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${scheduleData['date']} • ${scheduleData['time']}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.green[700],
                  ),
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
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
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
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
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
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}