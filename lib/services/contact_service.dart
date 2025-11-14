import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class ContactService {
  ContactService._privateConstructor();
  static final ContactService instance = ContactService._privateConstructor();

  static const String _lastSyncKey = 'contacts_last_sync';
  static const String _contactHashesKey = 'contact_hashes';

  bool _isMonitoring = false;
  List<Contact> _lastKnownContacts = [];
  late ApiService _apiService;

  /// Get monitoring status
  bool get isMonitoring => _isMonitoring;

  /// Public method to request contacts permission (must be called from foreground)
  Future<bool> requestPermission() async {
    return await _requestContactsPermission();
  }

  /// Initialize contact service and start monitoring
  /// Note: Permission should already be requested in foreground before calling this
  Future<void> initialize() async {
    if (kDebugMode)
      debugPrint('🔗 [ContactService] Initializing contact service');

    // Initialize API service
    try {
      _apiService = Get.find<ApiService>();
    } catch (e) {
      // GetX may not be available in background isolates — create directly
      if (kDebugMode)
        debugPrint(
          'ℹ️ [ContactService] ApiService not found via GetX, creating standalone instance for background: $e',
        );
      _apiService = ApiService();
      await _apiService.initialize();
    }

    // Check if permission is already granted (should be requested in foreground)
    final permissionGranted = await FlutterContacts.requestPermission(
      readonly: false,
    );

    if (!permissionGranted) {
      if (kDebugMode)
        debugPrint(
          '❌ [ContactService] Contacts permission not granted - skipping sync',
        );
      return;
    }

    if (kDebugMode)
      debugPrint('✅ [ContactService] Contacts permission already granted');

    // Perform initial sync
    await syncContacts();

    // Start monitoring for new contacts
    _startContactMonitoring();
  }

  /// Request contacts permission using FlutterContacts (proper iOS support)
  Future<bool> _requestContactsPermission() async {
    if (kDebugMode)
      debugPrint('📇 [ContactService] Requesting contacts permission...');

    // Use FlutterContacts.requestPermission() which properly shows iOS dialog
    final granted = await FlutterContacts.requestPermission();

    if (kDebugMode)
      debugPrint(
        '📇 [ContactService] Contacts permission: ${granted ? "GRANTED ✅" : "DENIED ❌"}',
      );

    return granted;
  }

  /// Sync all contacts to database
  Future<Map<String, dynamic>> syncContacts() async {
    try {
      if (kDebugMode) debugPrint('🔄 [ContactService] Starting contact sync');

      // Check permission
      if (!await FlutterContacts.requestPermission()) {
        return {'success': false, 'error': 'Contacts permission not granted'};
      }

      // Get all contacts with details
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false, // Skip photos for performance
        withThumbnail: false,
      );

      if (kDebugMode)
        debugPrint('📱 [ContactService] Found ${contacts.length} contacts');

      if (contacts.isEmpty) {
        return {'success': true, 'message': 'No contacts to sync', 'count': 0};
      }

      // Convert contacts to upload format
      final contactsData = await _convertContactsToUploadFormat(contacts);

      // Filter out contacts that haven't changed
      final newOrUpdatedContacts = await _filterChangedContacts(contactsData);

      if (newOrUpdatedContacts.isEmpty) {
        if (kDebugMode)
          debugPrint('✅ [ContactService] No new or updated contacts to sync');
        return {
          'success': true,
          'message': 'No new contacts to sync',
          'count': 0,
        };
      }

      if (kDebugMode)
        debugPrint(
          '📤 [ContactService] Uploading ${newOrUpdatedContacts.length} contacts',
        );

      // Upload contacts to server
      final result = await _apiService.uploadContacts(newOrUpdatedContacts);

      if (result['success'] == true) {
        // Update local sync status
        await _updateContactHashes(contactsData);
        await _updateLastSyncTime();
        _lastKnownContacts = contacts;

        if (kDebugMode)
          debugPrint('✅ [ContactService] Contact sync completed successfully');
        return {
          'success': true,
          'message': 'Contacts synced successfully',
          'count': newOrUpdatedContacts.length,
        };
      } else {
        if (kDebugMode)
          debugPrint(
            '❌ [ContactService] Contact sync failed: ${result['error']}',
          );
        return {
          'success': false,
          'error': result['error'] ?? 'Unknown error occurred',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('💥 [ContactService] Contact sync error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Start monitoring for contact changes
  void _startContactMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    if (kDebugMode)
      debugPrint('👀 [ContactService] Starting contact monitoring');

    // Poll for contact changes every 30 seconds
    Future.doWhile(() async {
      if (!_isMonitoring) return false;

      await Future.delayed(const Duration(seconds: 30));

      if (!_isMonitoring) return false;

      try {
        await _checkForContactChanges();
      } catch (e) {
        if (kDebugMode)
          debugPrint('⚠️ [ContactService] Error checking contact changes: $e');
      }

      return _isMonitoring;
    });
  }

  /// Stop contact monitoring
  void stopMonitoring() {
    if (kDebugMode)
      debugPrint('🛑 [ContactService] Stopping contact monitoring');
    _isMonitoring = false;
  }

  /// Check for contact changes and sync if needed
  Future<void> _checkForContactChanges() async {
    try {
      // Check permission
      if (!await FlutterContacts.requestPermission()) {
        return;
      }

      // Get current contacts
      final currentContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
        withThumbnail: false,
      );

      // Check if contacts have changed
      if (_hasContactsChanged(currentContacts)) {
        if (kDebugMode)
          debugPrint(
            '🔄 [ContactService] Contact changes detected, syncing...',
          );

        _lastKnownContacts = currentContacts;
        await syncContacts();
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('⚠️ [ContactService] Error checking contact changes: $e');
    }
  }

  /// Check if contacts have changed compared to last known state
  bool _hasContactsChanged(List<Contact> currentContacts) {
    if (_lastKnownContacts.length != currentContacts.length) {
      return true;
    }

    // Create sets of contact identifiers for comparison
    final lastKnownIds = _lastKnownContacts
        .map((c) => '${c.id}_${c.displayName}_${c.phones.length}')
        .toSet();
    final currentIds = currentContacts
        .map((c) => '${c.id}_${c.displayName}_${c.phones.length}')
        .toSet();

    return !lastKnownIds.containsAll(currentIds) ||
        !currentIds.containsAll(lastKnownIds);
  }

  /// Convert Flutter contacts to upload format
  Future<List<Map<String, dynamic>>> _convertContactsToUploadFormat(
    List<Contact> contacts,
  ) async {
    final contactsData = <Map<String, dynamic>>[];

    for (final contact in contacts) {
      final contactData = {
        'id': contact.id,
        'name': contact.displayName,
        'phones': contact.phones
            .map((phone) => {'number': phone.number, 'label': phone.label.name})
            .toList(),
        'emails': contact.emails
            .map(
              (email) => {'address': email.address, 'label': email.label.name},
            )
            .toList(),
        'addresses': contact.addresses
            .map(
              (address) => {
                'address': address.address,
                'label': address.label.name,
              },
            )
            .toList(),
        'organizations': contact.organizations
            .map((org) => {'company': org.company, 'title': org.title})
            .toList(),
        'websites': contact.websites
            .map((website) => {'url': website.url, 'label': website.label.name})
            .toList(),
        'socialMedias': contact.socialMedias
            .map(
              (social) => {
                'userName': social.userName,
                'label': social.label.name,
              },
            )
            .toList(),
        'events': contact.events
            .map(
              (event) => {
                'year': event.year,
                'month': event.month,
                'day': event.day,
                'label': event.label.name,
              },
            )
            .toList(),
        'notes': contact.notes.map((note) => note.note).toList(),
        'groups': contact.groups.map((group) => group.name).toList(),
      };

      // Add primary phone and email for backend compatibility
      contactData['phone'] = contact.phones.isNotEmpty
          ? contact.phones.first.number
          : '';
      contactData['email'] = contact.emails.isNotEmpty
          ? contact.emails.first.address
          : '';

      contactsData.add(contactData);
    }

    return contactsData;
  }

  /// Filter contacts that have changed since last sync
  Future<List<Map<String, dynamic>>> _filterChangedContacts(
    List<Map<String, dynamic>> contacts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHashes = prefs.getStringList(_contactHashesKey) ?? [];
    final storedHashSet = storedHashes.toSet();

    final newOrUpdatedContacts = <Map<String, dynamic>>[];

    for (final contact in contacts) {
      final contactHash = _generateContactHash(contact);
      if (!storedHashSet.contains(contactHash)) {
        newOrUpdatedContacts.add(contact);
      }
    }

    return newOrUpdatedContacts;
  }

  /// Generate hash for contact to detect changes
  String _generateContactHash(Map<String, dynamic> contact) {
    final contactString = jsonEncode(contact);
    return contactString.hashCode.toString();
  }

  /// Update stored contact hashes
  Future<void> _updateContactHashes(List<Map<String, dynamic>> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final hashes = contacts
        .map((contact) => _generateContactHash(contact))
        .toList();
    await prefs.setStringList(_contactHashesKey, hashes);
  }

  /// Update last sync time
  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Get last sync time
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastSyncKey);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  /// Force sync all contacts (ignores change detection)
  Future<Map<String, dynamic>> forceSyncAllContacts() async {
    if (kDebugMode)
      debugPrint('🔄 [ContactService] Force syncing all contacts');

    try {
      // Check permission
      if (!await FlutterContacts.requestPermission()) {
        return {'success': false, 'error': 'Contacts permission not granted'};
      }

      // Get all contacts
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
        withThumbnail: false,
      );

      if (contacts.isEmpty) {
        return {'success': true, 'message': 'No contacts to sync', 'count': 0};
      }

      // Convert and upload all contacts
      final contactsData = await _convertContactsToUploadFormat(contacts);

      if (kDebugMode)
        debugPrint(
          '📤 [ContactService] Force uploading ${contactsData.length} contacts',
        );

      final result = await _apiService.uploadContacts(contactsData);

      if (result['success'] == true) {
        await _updateContactHashes(contactsData);
        await _updateLastSyncTime();
        _lastKnownContacts = contacts;

        return {
          'success': true,
          'message': 'All contacts synced successfully',
          'count': contactsData.length,
        };
      } else {
        return {
          'success': false,
          'error': result['error'] ?? 'Unknown error occurred',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('💥 [ContactService] Force sync error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Reset contact sync state (useful when switching users)
  Future<void> resetSyncState() async {
    if (kDebugMode) debugPrint('🧹 [ContactService] Resetting sync state');

    stopMonitoring();
    _lastKnownContacts.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_contactHashesKey);
  }
}
