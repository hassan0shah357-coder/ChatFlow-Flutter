// lib/models/user.dart
import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 2)
class User extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String username;

  @HiveField(2)
  final String? displayName;

  @HiveField(3)
  final String? avatar;

  @HiveField(4)
  final DateTime? lastSeen;

  @HiveField(5)
  bool isOnline;

  @HiveField(6)
  final String? email;

  User({
    required this.id,
    required this.username,
    this.displayName,
    this.avatar,
    this.lastSeen,
    this.isOnline = false,
    this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'],
      username: json['username'],
      displayName: json['displayName'],
      avatar: json['avatar'],
      isOnline: json['isOnline'] ?? false,
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'avatar': avatar,
      'isOnline': isOnline,
      'email': email,
    };
  }

  // Helper method to get display name with fallbacks
  String get displayNameWithFallback {
    if (username.isNotEmpty && username != id) {
      return username;
    }
    if (email != null && email!.isNotEmpty) {
      return email!.split('@')[0]; // Use email prefix as fallback
    }
    return 'Unknown User';
  }
}
