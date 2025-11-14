import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/signup_controller.dart';
import 'package:node_chat/screens/login_screen.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize the SignupController using GetX
    final SignupController controller = Get.put(SignupController());

    return GestureDetector(
      // Unfocus keyboard when tapping outside of a text field
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Sign Up',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // This Expanded + SingleChildScrollView ensures the form is scrollable
              // and avoids overflow when the keyboard appears.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: controller.formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Email Field ---
                        const Text('Email', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: controller.emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: controller.validateEmail,
                          decoration: InputDecoration(
                            hintText: 'Enter your email',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- Phone Number Field ---
                        const Text(
                          'Phone Number',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: controller.phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          validator: controller.validatePhone,
                          decoration: InputDecoration(
                            hintText: 'Enter your phone number',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- Nickname Field ---
                        const Text('Nickname', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: controller.nickNameController,
                          textInputAction: TextInputAction.next,
                          validator: controller.validateNickName,
                          decoration: InputDecoration(
                            hintText: 'Enter your nickname',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- Password Field ---
                        const Text('Password', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        Obx(
                          () => TextFormField(
                            controller: controller.passwordController,
                            obscureText: !controller.isPasswordVisible.value,
                            textInputAction: TextInputAction.next,
                            validator: controller.validatePassword,
                            decoration: InputDecoration(
                              hintText: 'Enter your password',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  controller.isPasswordVisible.value
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed: controller.togglePasswordVisibility,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- Confirm Password Field ---
                        const Text(
                          'Confirm Password',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Obx(
                          () => TextFormField(
                            controller: controller.confirmPasswordController,
                            obscureText:
                                !controller.isConfirmPasswordVisible.value,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => controller.handleSignup(),
                            validator: controller.validateConfirmPassword,
                            decoration: InputDecoration(
                              hintText: 'Confirm your password',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  controller.isConfirmPasswordVisible.value
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed:
                                    controller.toggleConfirmPasswordVisibility,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- Bottom Button and Login Row ---
              Container(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // --- Permission Warning ---
                    Obx(
                      () => !controller.permissionsGranted.value
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                border: Border.all(color: Colors.orange),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'All permissions must be granted to signup',
                                      style: TextStyle(color: Colors.orange),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: controller.requestPermissions,
                                    child: const Text('Grant'),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // --- Sign Up Button ---
                    SizedBox(
                      width: double.infinity,
                      child: Obx(
                        () => ElevatedButton(
                          onPressed:
                              (controller.isLoading.value ||
                                  !controller.permissionsGranted.value)
                              ? null
                              : controller.handleSignup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: controller.permissionsGranted.value
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: controller.isLoading.value
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  controller.permissionsGranted.value
                                      ? 'Sign Up'
                                      : 'Grant Permissions First',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Login Redirect ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account? '),
                        TextButton(
                          onPressed: () {
                            Get.delete<SignupController>();
                            Get.off(() => const LoginScreen());
                          },
                          child: const Text('Login'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
