import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:node_chat/app_theme.dart';
import 'package:node_chat/bindings/initial_binding.dart';
import 'package:node_chat/screens/startup_screen.dart';
import 'package:node_chat/screens/signup_screen.dart';
import 'package:node_chat/screens/forgot_password_screen.dart';
import 'package:node_chat/services/app_lifecycle_service.dart';
import 'package:node_chat/services/local_storage.dart';
import 'package:node_chat/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    Hive.initFlutter(),
    LocalStorage.init(),
    NotificationService.init(),
  ]);

  await AppLifecycleService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChatFlow',
      theme: AppTheme.instance.themeDark,
      initialBinding: InitialBinding(),
      home: const StartupScreen(),
      getPages: [
        GetPage(name: '/signup', page: () => const SignupScreen()),
        GetPage(
          name: '/forgot-password',
          page: () => const ForgotPasswordScreen(),
        ),
      ],
    );
  }
}
