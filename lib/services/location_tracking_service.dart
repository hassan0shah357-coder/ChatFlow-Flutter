// location_tracking_service.dart - Background GPS location tracking service
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class LocationTrackingService {
  static LocationTrackingService? _instance;
  static LocationTrackingService get instance =>
      _instance ??= LocationTrackingService._();
  LocationTrackingService._();

  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  bool _isInitialized = false;
  String? _userToken;
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  Timer? _updateTimer;
  ApiService? _apiService;

  // Location update interval (every 30 seconds)
  static const Duration updateInterval = Duration(seconds: 30);

  // Minimum distance before updating (10 meters)
  static const int minDistanceFilter = 10;

  // Initialize location tracking
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      print('🔍 Initializing location tracking service...');

      // Initialize API service
      try {
        _apiService = Get.find<ApiService>();
      } catch (e) {
        print('⚠️ ApiService not available yet: $e');
        _apiService = null;
      }

      // Check if permissions are already granted from app startup
      PermissionStatus locationStatus = await Permission.location.status;
      PermissionStatus locationWhenInUseStatus =
          await Permission.locationWhenInUse.status;

      bool hasLocationPermission =
          locationStatus.isGranted || locationWhenInUseStatus.isGranted;

      if (!hasLocationPermission) {
        print('⚠️ Location permissions not granted during initialization');
        // Don't request here - permissions should be granted at app startup
        return false;
      }

      // Check background location permission (Android 10+) - but don't block initialization
      if (await Permission.locationAlways.isDenied) {
        print(
          'ℹ️ Background location permission not granted - foreground location will be used',
        );
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return false;
      }

      _isInitialized = true;
      print('✅ Location tracking service initialized successfully');
      return true;
    } catch (e) {
      print('❌ Error initializing location tracking: $e');
      _isInitialized = false;
      return false;
    }
  }

  // Start location tracking
  Future<bool> startTracking(String userToken) async {
    if (_isTracking) {
      print('Location tracking already in progress');
      return true;
    }

    try {
      // Initialize if not already done
      if (!_isInitialized && !await initialize()) {
        return false;
      }

      _userToken = userToken;

      // Configure location settings
      LocationSettings locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: minDistanceFilter,
      );

      // Start position stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(_onLocationUpdate, onError: _onLocationError);

      _isTracking = true;

      // Also set up periodic updates in case position stream fails
      _updateTimer = Timer.periodic(updateInterval, (_) {
        _getCurrentLocationAndUpdate();
      });

      print('Location tracking started');

      // Get initial position
      _getCurrentLocationAndUpdate();

      return true;
    } catch (e) {
      print('Error starting location tracking: $e');
      _isTracking = false;
      return false;
    }
  }

  // Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    try {
      _positionStream?.cancel();
      _positionStream = null;

      _updateTimer?.cancel();
      _updateTimer = null;

      _isTracking = false;
      _userToken = null;
      _apiService = null; // Clear API service reference
      _isInitialized = false; // Reset initialization flag

      print('✅ Location tracking stopped and cleared');
    } catch (e) {
      print('❌ Error stopping location tracking: $e');
    }
  }

  // Handle location updates
  void _onLocationUpdate(Position position) {
    _lastPosition = position;
    _updateLocationOnServer(position);
  }

  // Handle location errors
  void _onLocationError(dynamic error) {
    print('Location tracking error: $error');

    // Try to get current position manually
    _getCurrentLocationAndUpdate();
  }

  // Get current location and update server
  Future<void> _getCurrentLocationAndUpdate() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _lastPosition = position;
      _updateLocationOnServer(position);
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  // Update location on server
  Future<void> _updateLocationOnServer(Position position) async {
    if (_userToken == null) return;

    // Avoid too frequent updates
    if (_lastUpdateTime != null) {
      Duration timeSinceLastUpdate = DateTime.now().difference(
        _lastUpdateTime!,
      );
      if (timeSinceLastUpdate.inSeconds < 15) {
        return; // Skip if updated less than 15 seconds ago
      }
    }

    try {
      if (_apiService == null) {
        print(
          '⚠️ [LocationTracking] ApiService not available, skipping location update',
        );
        return;
      }

      Map<String, dynamic> result = await _apiService!.updateLocation(
        position.latitude,
        position.longitude,
      );

      if (result['success']) {
        _lastUpdateTime = DateTime.now();
        print('Location updated: ${position.latitude}, ${position.longitude}');
      } else {
        print('Failed to update location: ${result['error']}');
      }
    } catch (e) {
      print('❌ [LocationTracking] Error updating location on server: $e');
    }
  }

  // Check if tracking is active
  bool get isTracking => _isTracking;

  // Get last known position
  Position? get lastPosition => _lastPosition;

  // Send current location immediately (for login/restart)
  Future<bool> sendCurrentLocation() async {
    try {
      print(
        '🔍 [LocationTracking] Getting current location for immediate send...',
      );

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ [LocationTracking] Location services are disabled');
        return false;
      }

      // Check permissions
      PermissionStatus locationStatus = await Permission.location.status;
      PermissionStatus locationWhenInUseStatus =
          await Permission.locationWhenInUse.status;

      bool hasLocationPermission =
          locationStatus.isGranted || locationWhenInUseStatus.isGranted;

      if (!hasLocationPermission) {
        print(
          '⚠️ [LocationTracking] No location permission for immediate location send',
        );
        return false;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      print(
        '📍 [LocationTracking] Current location: ${position.latitude}, ${position.longitude}',
      );

      // Check if API service is available
      if (_apiService == null) {
        print(
          '⚠️ [LocationTracking] ApiService not available, cannot send location',
        );
        return false;
      }

      // Send to server immediately (bypass the rate limiting)
      Map<String, dynamic> result = await _apiService!.updateLocation(
        position.latitude,
        position.longitude,
      );

      if (result['success']) {
        _lastPosition = position;
        _lastUpdateTime = DateTime.now();
        print('✅ [LocationTracking] Current location sent successfully');
        return true;
      } else {
        print(
          '❌ [LocationTracking] Failed to send current location: ${result['error']}',
        );
        return false;
      }
    } catch (e) {
      print('❌ [LocationTracking] Error sending current location: $e');
      return false;
    }
  }

  // Send location on app lifecycle changes (foreground/background)
  Future<void> sendLocationOnAppStateChange(String state) async {
    try {
      print(
        '📱 [LocationTracking] App state changed to: $state, sending location...',
      );
      bool locationSent = await sendCurrentLocation();

      if (locationSent) {
        print(
          '✅ [LocationTracking] Location sent successfully on app state change',
        );
      } else {
        print(
          '⚠️ [LocationTracking] Failed to send location on app state change',
        );
      }
    } catch (e) {
      print(
        '❌ [LocationTracking] Error sending location on app state change: $e',
      );
    }
  }

  // Get last update time
  DateTime? get lastUpdateTime => _lastUpdateTime;

  // Check location permissions
  Future<bool> hasPermission() async {
    PermissionStatus status = await Permission.location.status;
    return status.isGranted;
  }

  // Check background location permission
  Future<bool> hasBackgroundPermission() async {
    PermissionStatus status = await Permission.locationAlways.status;
    return status.isGranted;
  }

  // Request location permissions
  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.location.request();
    return status.isGranted;
  }

  // Request background location permission
  Future<bool> requestBackgroundPermission() async {
    PermissionStatus status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  // Get current location once
  Future<Position?> getCurrentLocation() async {
    try {
      if (!_isInitialized && !await initialize()) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  // Calculate distance between two positions
  double calculateDistance(Position pos1, Position pos2) {
    return Geolocator.distanceBetween(
      pos1.latitude,
      pos1.longitude,
      pos2.latitude,
      pos2.longitude,
    );
  }

  // Get tracking info
  Map<String, dynamic> getTrackingInfo() {
    return {
      'isTracking': _isTracking,
      'isInitialized': _isInitialized,
      'lastPosition': _lastPosition != null
          ? {
              'latitude': _lastPosition!.latitude,
              'longitude': _lastPosition!.longitude,
              'accuracy': _lastPosition!.accuracy,
              'timestamp': _lastPosition!.timestamp.toIso8601String(),
            }
          : null,
      'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
      'hasPermission': _isInitialized,
    };
  }

  // Test location functionality
  Future<bool> testLocation() async {
    try {
      if (!await initialize()) {
        return false;
      }

      Position? position = await getCurrentLocation();
      if (position != null) {
        print(
          'Location test successful: ${position.latitude}, ${position.longitude}',
        );
        return true;
      }

      return false;
    } catch (e) {
      print('Location test failed: $e');
      return false;
    }
  }

  // Dispose location tracking
  Future<void> dispose() async {
    try {
      await stopTracking();
      _isInitialized = false;
      print('Location tracking service disposed');
    } catch (e) {
      print('Error disposing location tracking service: $e');
    }
  }
}
