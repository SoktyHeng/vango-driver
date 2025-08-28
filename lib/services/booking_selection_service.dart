import 'package:shared_preferences/shared_preferences.dart';

class BookingSelectionService {
  static final BookingSelectionService _instance = BookingSelectionService._internal();
  factory BookingSelectionService() => _instance;
  BookingSelectionService._internal();

  // In-memory storage for current session
  static Map<String, Set<String>> _selectedBookings = {};

  // Get selected bookings for a specific schedule, filtered by available bookings
  Set<String> getSelectedBookings(String scheduleId, List<String> availableBookingIds) {
    final savedSelections = _selectedBookings[scheduleId] ?? {};
    // Only return selections that exist in the current schedule's bookings
    return savedSelections.where((bookingId) => availableBookingIds.contains(bookingId)).toSet();
  }

  // Set selected bookings for a specific schedule
  void setSelectedBookings(String scheduleId, Set<String> bookingIds) {
    _selectedBookings[scheduleId] = Set.from(bookingIds);
    _saveToPreferences(scheduleId, bookingIds);
  }

  // Add a booking to selection
  void addBooking(String scheduleId, String bookingId) {
    _selectedBookings[scheduleId] ??= {};
    _selectedBookings[scheduleId]!.add(bookingId);
    _saveToPreferences(scheduleId, _selectedBookings[scheduleId]!);
  }

  // Remove a booking from selection
  void removeBooking(String scheduleId, String bookingId) {
    _selectedBookings[scheduleId]?.remove(bookingId);
    _saveToPreferences(scheduleId, _selectedBookings[scheduleId] ?? {});
  }

  // Clear selections for a specific schedule
  void clearScheduleSelections(String scheduleId) {
    _selectedBookings.remove(scheduleId);
    _removeFromPreferences(scheduleId);
  }

  // Load selections from shared preferences and filter by available bookings
  Future<void> loadFromPreferences(String scheduleId, List<String> availableBookingIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedIds = prefs.getStringList('selected_bookings_$scheduleId') ?? [];
      // Only keep selections that exist in current schedule's bookings
      final filteredSelections = selectedIds.where((id) => availableBookingIds.contains(id)).toSet();
      _selectedBookings[scheduleId] = filteredSelections;
    } catch (e) {
      print('Error loading booking selections: $e');
      _selectedBookings[scheduleId] = {};
    }
  }

  // Save to shared preferences
  Future<void> _saveToPreferences(String scheduleId, Set<String> bookingIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('selected_bookings_$scheduleId', bookingIds.toList());
    } catch (e) {
      print('Error saving booking selections: $e');
    }
  }

  // Remove from shared preferences
  Future<void> _removeFromPreferences(String scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_bookings_$scheduleId');
    } catch (e) {
      print('Error removing booking selections: $e');
    }
  }

  // Clear all selections (useful for cleanup)
  Future<void> clearAllSelections() async {
    try {
      _selectedBookings.clear();
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith('selected_bookings_'));
      for (String key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      print('Error clearing all selections: $e');
    }
  }
}