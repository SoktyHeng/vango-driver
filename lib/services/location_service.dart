import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTracking = false;
  String? _currentScheduleId;
  String? _currentDriverId;

  // DRIVER-SPECIFIC METHODS
  // =======================

  /// Start sharing driver location for a specific schedule
  Future<void> startDriverLocationSharing(
    String scheduleId,
    String driverId,
  ) async {
    if (_isTracking && _currentScheduleId == scheduleId) {
      print('⚠️ Location sharing already active for this schedule');
      return;
    }

    // If tracking a different schedule, stop first
    if (_isTracking && _currentScheduleId != scheduleId) {
      await stopLocationSharing();
    }

    try {
      // Request permissions
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        throw Exception('Location permission denied');
      }

      // Check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      // Configure location settings for drivers
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _isTracking = true;
      _currentScheduleId = scheduleId;
      _currentDriverId = driverId;

      // Start location stream
      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              _updateDriverLocationInFirestore(scheduleId, driverId, position);
            },
            onError: (error) {
              print('❌ Location stream error: $error');
              stopLocationSharing();
            },
          );

      // Mark schedule as having active location sharing
      await _updateScheduleLocationStatus(scheduleId, true);

      print('🚗 Driver location sharing started for schedule: $scheduleId');
    } catch (e) {
      _isTracking = false;
      _currentScheduleId = null;
      _currentDriverId = null;
      print('❌ Failed to start location sharing: $e');
      rethrow;
    }
  }

  /// Update driver location in Firestore
  Future<void> _updateDriverLocationInFirestore(
    String scheduleId,
    String driverId,
    Position position,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('driver_locations')
          .doc(scheduleId)
          .set({
            'driverId': driverId,
            'scheduleId': scheduleId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': FieldValue.serverTimestamp(),
            'speed': position.speed,
            'heading': position.heading,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true));

      print(
        '📍 Driver location updated: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      print('❌ Error updating driver location: $e');
    }
  }

  /// Stop sharing driver location
  Future<void> stopLocationSharing() async {
    try {
      // Cancel location stream
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;

      // Update schedule status if we were tracking one
      if (_currentScheduleId != null) {
        await _updateScheduleLocationStatus(_currentScheduleId!, false);
      }

      _isTracking = false;
      _currentScheduleId = null;
      _currentDriverId = null;

      print('🛑 Driver location sharing stopped');
    } catch (e) {
      print('❌ Error stopping location sharing: $e');
    }
  }

  /// Update schedule to indicate location sharing status
  Future<void> _updateScheduleLocationStatus(
    String scheduleId,
    bool isActive,
  ) async {
    try {
      final Map<String, dynamic> updateData = {
        'locationSharingActive': isActive,
      };

      if (isActive) {
        updateData['locationSharingStartedAt'] = FieldValue.serverTimestamp();
      } else {
        updateData['locationSharingStoppedAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('schedules')
          .doc(scheduleId)
          .update(updateData);
    } catch (e) {
      print('❌ Error updating schedule location status: $e');
    }
  }

  /// Clean up location data when trip is completed
  Future<void> cleanupLocationData(String scheduleId) async {
    try {
      // Stop tracking first
      await stopLocationSharing();

      // Update schedule status
      await _updateScheduleLocationStatus(scheduleId, false);

      // Delete driver location data from Firestore
      await FirebaseFirestore.instance
          .collection('driver_locations')
          .doc(scheduleId)
          .delete();

      print('🧹 Location data cleaned up for schedule: $scheduleId');
    } catch (e) {
      print('❌ Error cleaning up location data: $e');
    }
  }

  // SHARED UTILITY METHODS
  // ======================

  /// Request location permissions
  Future<bool> requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions are denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        return false;
      }

      // Request background location for Android (optional)
      if (await Permission.locationAlways.isDenied) {
        final backgroundPermission = await Permission.locationAlways.request();
        if (backgroundPermission.isDenied) {
          print('⚠️ Background location permission denied');
          // Continue anyway - foreground location is sufficient
        }
      }

      print('✅ Location permissions granted');
      return true;
    } catch (e) {
      print('❌ Error requesting location permission: $e');
      return false;
    }
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Get current position once (for testing or initial setup)
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('❌ Error getting current position: $e');
      return null;
    }
  }

  /// Calculate distance between two points (useful for driver analytics)
  double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Calculate bearing between two points
  double calculateBearing(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.bearingBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  // GETTERS
  // =======

  /// Check if driver is currently sharing location
  bool get isTracking => _isTracking;

  /// Get location sharing status
  bool get isLocationSharingActive => _isTracking;

  /// Check if currently sharing location for a specific schedule
  bool isTrackingSchedule(String scheduleId) {
    return _isTracking && _currentScheduleId == scheduleId;
  }

  /// Get the current schedule being tracked
  String? get currentTrackingSchedule => _currentScheduleId;
}
