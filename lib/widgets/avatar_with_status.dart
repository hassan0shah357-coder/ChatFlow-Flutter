import 'package:flutter/material.dart';
import 'package:node_chat/app_theme.dart';

/// A reusable avatar widget that displays a user's avatar with an optional online status indicator.
///
/// The online status is shown as a colored circle border around the avatar.
class AvatarWithStatus extends StatelessWidget {
  /// The display name of the user (used to show the initial letter)
  final String displayName;

  /// Whether the user is currently online
  final bool isOnline;

  /// Whether to show the online status indicator (defaults to true)
  final bool showOnlineStatus;

  /// The radius of the avatar
  final double radius;

  /// Optional background color for the avatar
  final Color? backgroundColor;

  /// Optional text style for the avatar letter
  final TextStyle? textStyle;

  const AvatarWithStatus({
    super.key,
    required this.displayName,
    this.isOnline = false,
    this.showOnlineStatus = true,
    this.radius = 20,
    this.backgroundColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    // If online status should be shown and user is online, add a border
    if (showOnlineStatus && isOnline) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.green, width: 2.5),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor ?? AppTheme.primaryVariant,
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style:
                textStyle ??
                TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.9,
                ),
          ),
        ),
      );
    }

    // Regular avatar without online indicator
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppTheme.primaryVariant,
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style:
            textStyle ??
            TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.9,
            ),
      ),
    );
  }
}
