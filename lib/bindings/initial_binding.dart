import 'package:get/get.dart';
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/services/api_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    // Services
    Get.put(ApiService(), permanent: true);

    // Controllers
    Get.put(AuthController(), permanent: true);
    Get.put(ChatController(), permanent: true);
    Get.put(CallController(), permanent: true);
  }
}
