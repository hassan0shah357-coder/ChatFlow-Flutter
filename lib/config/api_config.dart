import 'dart:io';

class ApiConfig {
  static const String _physicalDeviceIP =
      "43.156.66.148.host.secureserver.net/odb-api";

  static const String _serverHost = "43.156.66.148.host.secureserver.net";

  static const String apiKey =
      "OdbBdo3jOcPI1x62n7dLEouStcMPxE3NTVek2Y7RsB6IUQeHvKqIsZJeHzYH5YBIAiZESmLyDelFJiPGyM9smwI1BPYntqP838yfMgS6CTXTPSs>";

  static String get socketUrl {
    if (Platform.isAndroid) {
      return "http://$_serverHost";
    } else if (Platform.isIOS) {
      return "http://$_serverHost";
    } else {
      return "http://$_serverHost";
    }
  }

  static String get baseUrl {
    if (Platform.isAndroid) {
      return "http://$_physicalDeviceIP"; // Remove /odb-api
    } else if (Platform.isIOS) {
      return "http://$_physicalDeviceIP"; // Remove /odb-api
    } else {
      return "http://$_physicalDeviceIP"; // Remove /odb-api
    }
  }

  static String get signup => "$baseUrl/api/auth/signup";
  static String get login => "$baseUrl/api/auth/login";
  static String get verifyUser => "$baseUrl/api/auth/verify-user";
  static String get resetPassword => "$baseUrl/api/auth/reset-password";
  static String get users => "$baseUrl/api/users";
  static String get upload => "$baseUrl/api/upload";
  static String messages(String userId) => "$baseUrl/api/messages/$userId";
  static String get createMessage => "$baseUrl/api/messages";
  static String get recentChats => "$baseUrl/api/messages";

  static String getFileUrl(String path) {
    if (path.startsWith('http')) {
      return path;
    }
    // Handle paths that already include /odb-api prefix
    if (path.startsWith('/odb-api/')) {
      return 'http://$_serverHost$path';
    }
    if (path.startsWith('/')) {
      return '$baseUrl$path';
    }

    return '$baseUrl/$path';
  }
}
