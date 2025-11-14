import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/forgot_password_controller.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ForgotPasswordController controller = Get.put(
      ForgotPasswordController(),
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Forgot Password',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
        body: SafeArea(
          child: Obx(
            () => controller.isVerified.value
                ? _buildResetPasswordForm(controller, context)
                : _buildVerificationForm(controller, context),
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationForm(
    ForgotPasswordController controller,
    BuildContext context,
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: controller.verifyFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your details to verify your account',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text('Email', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: controller.emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: controller.validateEmail,
                    decoration: _buildInputDecoration(
                      'Enter your email',
                      context,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Phone Number', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: controller.phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: controller.validatePhone,
                    decoration: _buildInputDecoration(
                      'Enter your phone number',
                      context,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Nickname', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: controller.nickNameController,
                    textInputAction: TextInputAction.done,
                    validator: controller.validateNickName,
                    decoration: _buildInputDecoration(
                      'Enter your nickname',
                      context,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            width: double.infinity,
            child: Obx(
              () => ElevatedButton(
                onPressed: controller.isLoading.value
                    ? null
                    : controller.verifyUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
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
                    : const Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetPasswordForm(
    ForgotPasswordController controller,
    BuildContext context,
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: controller.resetFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Verification Successful!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(child: Text('Please enter your new password')),
                  const SizedBox(height: 24),
                  const Text('New Password', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Obx(
                    () => TextFormField(
                      controller: controller.passwordController,
                      obscureText: !controller.isPasswordVisible.value,
                      textInputAction: TextInputAction.next,
                      validator: controller.validatePassword,
                      decoration: _buildPasswordDecoration(
                        'Enter new password',
                        controller.isPasswordVisible.value,
                        controller.togglePasswordVisibility,
                        context,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Confirm Password',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () => TextFormField(
                      controller: controller.confirmPasswordController,
                      obscureText: !controller.isConfirmPasswordVisible.value,
                      textInputAction: TextInputAction.done,
                      validator: controller.validateConfirmPassword,
                      decoration: _buildPasswordDecoration(
                        'Confirm new password',
                        controller.isConfirmPasswordVisible.value,
                        controller.toggleConfirmPasswordVisibility,
                        context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            width: double.infinity,
            child: Obx(
              () => ElevatedButton(
                onPressed: controller.isLoading.value
                    ? null
                    : controller.resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
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
                    : const Text(
                        'Reset Password',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String hint, BuildContext context) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  InputDecoration _buildPasswordDecoration(
    String hint,
    bool isVisible,
    VoidCallback onToggle,
    BuildContext context,
  ) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      suffixIcon: IconButton(
        icon: Icon(
          isVisible ? Icons.visibility_off : Icons.visibility,
          color: Colors.grey[600],
        ),
        onPressed: onToggle,
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
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}
