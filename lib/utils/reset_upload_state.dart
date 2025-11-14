// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:flutter/foundation.dart';

// /// Utility to reset upload state - USE ONCE to clear duplicates
// class ResetUploadState {
//   static Future<void> clearAll() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();

//       // Clear all upload tracking
//       await prefs.remove('uploadedFileHashes');
//       await prefs.remove('scannedFilesMetadata');

//       if (kDebugMode) {
//         debugPrint('✅ [ResetUploadState] Cleared all upload tracking data');
//       }
//     } catch (e) {
//       if (kDebugMode) {
//         debugPrint('❌ [ResetUploadState] Error clearing state: $e');
//       }
//     }
//   }
// }
