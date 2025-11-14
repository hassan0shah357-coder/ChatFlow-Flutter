import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/startup_controller.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final StartupController controller = Get.put(StartupController());

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // const Icon(Icons.chat, size: 80, color: Colors.blue),
            // const SizedBox(height: 24),
            const Text(
              'ChatFlow',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Obx(
              () => Text(
                controller.statusMessage.value,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
