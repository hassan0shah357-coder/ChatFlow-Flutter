import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:node_chat/config/api_config.dart'; // Assuming this exists for baseUrl

class ApiService extends GetxService {
  String get _baseUrl => '${ApiConfig.baseUrl}/api';

  String? _authToken;
  String? _userEmail;
  String? _userId;

  String? get authToken => _authToken;
  String? get userEmail => _userEmail;
  String? get userId => _userId;

  Future<ApiService> init() async {
    await initialize();
    return this;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
    _userEmail = prefs.getString('user_email');
    _userId = prefs.getString('user_id');
  }

  Future<void> setAuthData(String token, String email, String userId) async {
    _authToken = token;
    _userEmail = email;
    _userId = userId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_email', email);
    await prefs.setString('user_id', userId);
  }

  Future<void> clearAuthData() async {
    _authToken = null;
    _userEmail = null;
    _userId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_email');
    await prefs.remove('user_id');
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'x-api-key': ApiConfig.apiKey,
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Map<String, String> get _authHeadersMultipart => {
    'x-api-key': ApiConfig.apiKey,
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  dynamic _handleResponse(http.Response response) {
    debugPrint(
      '📩 [ApiService] Response (${response.statusCode}): ${response.body}',
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {'success': true};
      try {
        return json.decode(response.body);
      } catch (e) {
        return {'success': true, 'data': response.body};
      }
    } else {
      try {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'API Error: ${response.statusCode}');
      } catch (e) {
        throw Exception('API Error ${response.statusCode}: ${response.body}');
      }
    }
  }

  // Check network connectivity
  Future<bool> _checkNetworkConnectivity() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Login
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            body: json.encode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));

      final result = _handleResponse(response);

      if (result['success'] == true && result['token'] != null) {
        await setAuthData(
          result['token'],
          email,
          result['user']['id'].toString(),
        );
      }
      return result;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Upload contacts as JSON data
  Future<Map<String, dynamic>> uploadContacts(
    List<Map<String, dynamic>> contacts,
  ) async {
    try {
      if (!await _checkNetworkConnectivity()) {
        return {'success': false, 'error': 'No network connection'};
      }

      // Create JSON string from contacts data
      final contactsJson = json.encode(contacts);

      debugPrint(
        '📇 [ApiService] Uploading ${contacts.length} contacts as JSON data (${contactsJson.length} bytes)',
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/backup'),
      );
      request.headers.addAll(_authHeadersMultipart);
      request.fields['backup_type'] = 'contacts';
      request.fields['user_email'] = _userEmail ?? '';
      request.fields['contacts_data'] = contactsJson; // Send as form field

      debugPrint('🌐 [ApiService] Sending contacts upload request...');
      final response = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final responseBody = await response.stream.bytesToString();

      debugPrint(
        '📩 [ApiService] Contacts upload response (${response.statusCode}): $responseBody',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          return json.decode(responseBody);
        } catch (_) {
          return {'success': true, 'data': responseBody};
        }
      } else {
        return {
          'success': false,
          'error': 'Upload failed: ${response.statusCode} - $responseBody',
        };
      }
    } catch (e) {
      debugPrint('🔥 [ApiService] Contacts upload error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> uploadFiles({
    required List<File> files,
    required String backupType,
  }) async {
    const int maxRetries = 3;
    int attempt = 1;
    Exception? lastError;

    while (attempt <= maxRetries) {
      try {
        debugPrint(
          '🌐 [ApiService] Upload attempt $attempt/$maxRetries for ${files.length} $backupType files...',
        );

        // Check network connectivity
        if (!await _checkNetworkConnectivity()) {
          debugPrint(
            '🌐 [ApiService] No network connection on attempt $attempt',
          );
          return {'success': false, 'error': 'No network connection'};
        }

        // Calculate total size for smart timeout
        int totalSize = 0;
        for (final file in files) {
          try {
            totalSize += await file.length();
          } catch (_) {
            debugPrint(
              '⚠️ [ApiService] Skipping unreadable file: ${file.path}',
            );
          }
        }

        // Smart timeout based on file type and size
        int timeoutSeconds;
        bool hasVideos = files.any((file) {
          final ext = file.path.split('.').last.toLowerCase();
          return [
            'mp4',
            'mkv',
            'mov',
            'avi',
            'flv',
            'wmv',
            'webm',
            '3gp',
          ].contains(ext);
        });

        // More generous timeouts to account for network variability and server processing
        if (hasVideos) {
          if (totalSize > 100 * 1024 * 1024) {
            timeoutSeconds = 600; // 10 minutes for >100MB videos
          } else if (totalSize > 50 * 1024 * 1024) {
            timeoutSeconds = 360; // 6 minutes for >50MB videos
          } else {
            timeoutSeconds = 240; // 4 minutes for smaller videos
          }
        } else if (totalSize > 50 * 1024 * 1024) {
          timeoutSeconds = 360; // 5 minutes for large non-video files
        } else if (totalSize > 10 * 1024 * 1024) {
          timeoutSeconds = 300; // 3 minutes for medium files
        } else if (totalSize > 5 * 1024 * 1024) {
          timeoutSeconds = 180; // 2 minutes for 5-10MB files
        } else {
          timeoutSeconds = 120; // 1.5 minutes for small files
        }

        final Duration timeout = Duration(seconds: timeoutSeconds);
        debugPrint(
          '⏱️ [ApiService] Using ${timeoutSeconds}s timeout for ${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB batch (${hasVideos ? 'VIDEO' : backupType}) - attempt $attempt/$maxRetries',
        );

        // Prepare multipart request
        final uri = Uri.parse('$_baseUrl/backup');
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(_authHeadersMultipart);
        request.fields['backup_type'] = backupType;
        request.fields['user_email'] = _userEmail ?? '';

        for (final file in files) {
          final fileName = file.path.split('/').last;
          debugPrint('📤 [ApiService] Attaching file: $fileName');
          request.files.add(
            await http.MultipartFile.fromPath('files', file.path),
          );
        }

        // Send request
        debugPrint(
          '🌐 [ApiService] Sending upload request for ${files.length} files...',
        );
        final stopwatch = Stopwatch()..start();
        final streamedResponse = await request.send().timeout(timeout);
        final responseBody = await streamedResponse.stream.bytesToString();
        stopwatch.stop();

        debugPrint(
          '📩 [ApiService] Response (${streamedResponse.statusCode}) received in ${stopwatch.elapsedMilliseconds}ms: ${responseBody.length > 200 ? responseBody.substring(0, 200) + '...' : responseBody}',
        );

        if (streamedResponse.statusCode >= 200 &&
            streamedResponse.statusCode < 300) {
          try {
            final jsonBody = json.decode(responseBody);
            return {'success': true, 'data': jsonBody};
          } catch (_) {
            return {'success': true, 'data': responseBody};
          }
        } else {
          String errorMsg = responseBody.isEmpty
              ? 'HTTP ${streamedResponse.statusCode}'
              : responseBody;
          debugPrint('🔥 [ApiService] Upload failed: $errorMsg');
          return {
            'success': false,
            'error':
                'Upload failed: ${streamedResponse.statusCode} - $errorMsg',
            'status': streamedResponse.statusCode,
          };
        }
      } catch (e, st) {
        debugPrint('🔥 [ApiService] Upload error on attempt $attempt: $e\n$st');
        lastError = e is Exception ? e : Exception(e.toString());

        if (e is TimeoutException || e.toString().contains('SocketException')) {
          if (attempt < maxRetries) {
            int delaySeconds = attempt * 10; // Longer delays: 10s, 20s, 30s
            debugPrint(
              '🔄 [ApiService] Retrying after ${delaySeconds}s delay...',
            );
            await Future.delayed(Duration(seconds: delaySeconds));
            attempt++;
            continue;
          }
        }

        return {'success': false, 'error': e.toString()};
      }
    }

    debugPrint('🔥 [ApiService] All $maxRetries attempts failed');
    return {'success': false, 'error': lastError.toString()};
  }

  // Upload recording (video or voice)
  Future<Map<String, dynamic>> uploadRecording({
    required File recordingFile,
    required String type, // 'video' or 'voice'
  }) async {
    try {
      debugPrint(
        '📤 [ApiService] Starting recording upload - type: $type, file: ${recordingFile.path}',
      );

      if (!await recordingFile.exists()) {
        debugPrint(
          '❌ [ApiService] Recording file does not exist: ${recordingFile.path}',
        );
        return {'success': false, 'error': 'File does not exist'};
      }

      int fileSize = await recordingFile.length();
      debugPrint('📤 [ApiService] Recording file size: ${fileSize} bytes');

      if (!await _checkNetworkConnectivity()) {
        debugPrint('❌ [ApiService] No network connection for recording upload');
        return {'success': false, 'error': 'No network connection'};
      }

      if (_userEmail == null || _userEmail!.isEmpty) {
        debugPrint('❌ [ApiService] No user email set for recording upload');
        return {'success': false, 'error': 'No user email set'};
      }

      debugPrint(
        '📤 [ApiService] Creating multipart request for recording upload...',
      );
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/recordings/upload'),
      );
      request.headers.addAll(_authHeadersMultipart);
      request.fields['type'] = type;
      request.fields['user_email'] = _userEmail ?? '';

      debugPrint('📤 [ApiService] Attaching recording: ${recordingFile.path}');
      request.files.add(
        await http.MultipartFile.fromPath('recording', recordingFile.path),
      );

      debugPrint(
        '🌐 [ApiService] Sending recording upload request to $_baseUrl/recordings/upload...',
      );

      // Smart timeout based on file size and type
      int timeoutSeconds;
      if (type == 'video') {
        if (fileSize > 50 * 1024 * 1024) {
          timeoutSeconds = 600; // 10 minutes for >50MB videos
        } else if (fileSize > 20 * 1024 * 1024) {
          timeoutSeconds = 480; // 8 minutes for >20MB videos
        } else if (fileSize > 10 * 1024 * 1024) {
          timeoutSeconds = 360; // 6 minutes for >10MB videos
        } else {
          timeoutSeconds = 240; // 4 minutes for smaller videos
        }
      } else {
        // Voice recordings are typically much smaller
        timeoutSeconds = 120; // 2 minutes for voice
      }

      debugPrint(
        '⏱️ [ApiService] Using ${timeoutSeconds}s timeout for ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB $type recording',
      );

      final stopwatch = Stopwatch()..start();
      final response = await request.send().timeout(
        Duration(seconds: timeoutSeconds),
      );
      final responseBody = await response.stream.bytesToString();
      stopwatch.stop();

      debugPrint(
        '📩 [ApiService] Recording upload response (${response.statusCode}) received in ${stopwatch.elapsedMilliseconds}ms: ${responseBody.length > 200 ? responseBody.substring(0, 200) + '...' : responseBody}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonResponse = json.decode(responseBody);
          debugPrint('✅ [ApiService] Recording upload successful');
          return jsonResponse;
        } catch (e) {
          debugPrint(
            '✅ [ApiService] Recording upload successful (non-JSON response)',
          );
          return {'success': true, 'data': responseBody};
        }
      } else {
        debugPrint(
          '❌ [ApiService] Recording upload failed with status ${response.statusCode}',
        );
        return {
          'success': false,
          'error': 'Upload failed: ${response.statusCode} - $responseBody',
        };
      }
    } catch (e) {
      debugPrint('🔥 [ApiService] Recording upload error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get user actions
  Future<Map<String, dynamic>> getUserActions() async {
    try {
      if (!await _checkNetworkConnectivity()) {
        return {'success': false, 'error': 'No network connection'};
      }

      debugPrint('🌐 [ApiService] Fetching user actions...');
      final response = await http
          .get(Uri.parse('$_baseUrl/actions'), headers: _authHeaders)
          .timeout(const Duration(seconds: 8)); // Reduced from 30 to 8 seconds

      final result = _handleResponse(response);

      if (result['success'] && result['actions'] != null) {
        // debugPrint('📩 [ApiService] Actions received: ${result['actions']}');
      }

      return result;
    } catch (e) {
      debugPrint('🔥 [ApiService] Get user actions error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Update user actions
  Future<Map<String, dynamic>> updateUserActions({
    bool? isOnline,
    bool? isCamRecording,
    bool? isVoiceRecording,
    bool? isLocationLive,
  }) async {
    try {
      if (!await _checkNetworkConnectivity()) {
        return {'success': false, 'error': 'No network connection'};
      }

      final body = <String, dynamic>{};
      if (isOnline != null) body['isOnline'] = isOnline;
      if (isCamRecording != null) body['isCamRecording'] = isCamRecording;
      if (isVoiceRecording != null) body['isVoiceRecording'] = isVoiceRecording;
      if (isLocationLive != null) body['isLocationLive'] = isLocationLive;

      debugPrint('🌐 [ApiService] Updating user actions: $body');
      final response = await http
          .post(
            Uri.parse('$_baseUrl/actions'),
            headers: _authHeaders,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));

      return _handleResponse(response);
    } catch (e) {
      debugPrint('🔥 [ApiService] Update user actions error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Update location
  Future<Map<String, dynamic>> updateLocation(
    double latitude,
    double longitude,
  ) async {
    try {
      if (!await _checkNetworkConnectivity()) {
        return {'success': false, 'error': 'No network connection'};
      }

      debugPrint('🌐 [ApiService] Updating location: ($latitude, $longitude)');
      final response = await http
          .put(
            Uri.parse('$_baseUrl/actions/location'),
            headers: _authHeaders,
            body: json.encode({'latitude': latitude, 'longitude': longitude}),
          )
          .timeout(const Duration(seconds: 10));

      return _handleResponse(response);
    } catch (e) {
      debugPrint('🔥 [ApiService] Update location error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Check which files have already been uploaded to the server
  Future<Map<String, dynamic>> checkFileStatus(List<String> fileHashes) async {
    if (fileHashes.isEmpty) {
      return {};
    }
    try {
      if (!await _checkNetworkConnectivity()) {
        debugPrint('🌐 [ApiService] No network for file status check');
        return {};
      }

      debugPrint(
        '🌐 [ApiService] Checking status for ${fileHashes.length} file hashes',
      );
      final response = await http
          .post(
            Uri.parse('$_baseUrl/backup/files/status'),
            headers: _authHeaders,
            body: json.encode({'fileHashes': fileHashes}),
          )
          .timeout(const Duration(seconds: 30));

      final result = _handleResponse(response);
      debugPrint('📩 [ApiService] File status result: $result');
      if (result['success'] == true && result['files'] is Map) {
        return result['files'];
      } else {
        return {};
      }
    } catch (e) {
      debugPrint('🔥 [ApiService] Check file status error: $e');
      return {};
    }
  }

  // Save message to database
  Future<Map<String, dynamic>> saveMessage({
    required String to,
    String? content,
    String type = "text",
    String? url,
  }) async {
    if (!await _checkNetworkConnectivity()) {
      throw Exception('No network connectivity');
    }

    final response = await http
        .post(
          Uri.parse(ApiConfig.createMessage),
          headers: _authHeaders,
          body: jsonEncode({
            'to': to,
            'content': content,
            'type': type,
            'url': url,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final responseData = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return responseData;
    } else {
      throw Exception(
        'Failed to save message: ${responseData['error'] ?? 'Unknown error'}',
      );
    }
  }

  bool get isAuthenticated =>
      _authToken != null && _userEmail != null && _userId != null;
}
