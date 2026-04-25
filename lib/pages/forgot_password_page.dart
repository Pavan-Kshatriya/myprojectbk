import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helper/email_helper.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final otpController = TextEditingController();
  final newPasswordController = TextEditingController();

  bool otpSent = false;
  bool otpVerified = false;
  bool isLoading = false;

  /// OTP GENERATE
  String generateOTP() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  /// VALIDATION
  bool isValidEmail(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  bool isStrongPassword(String pass) {
    return pass.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(pass) &&
        RegExp(r'[0-9]').hasMatch(pass);
  }

  /// SEND OTP
  Future sendOtp() async {
    if (!isValidEmail(emailController.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid email")));
      return;
    }

    /// CHECK USER EXISTS
    final user = await supabase
        .from('users')
        .select()
        .eq('email_id', emailController.text)
        .maybeSingle();

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Email not registered")));
      return;
    }

    String otp = generateOTP();

    /// STORE OTP
    await supabase.from('email_otp').insert({
      "email": emailController.text,
      "otp": otp,
      "is_verified": false,
      "expires_at": DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    });

    /// SEND EMAIL
    bool sent = await EmailHelper.sendEmail(
      templateName: "OTP",
      toEmail: emailController.text,
      variables: {"otp": otp, "email": emailController.text, "minutes": "5"},
    );

    if (sent) {
      setState(() => otpSent = true);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("OTP sent to email")));
    }
  }

  /// VERIFY OTP
  Future verifyOtp() async {
    final data = await supabase
        .from('email_otp')
        .select()
        .eq('email', emailController.text)
        .eq('otp', otpController.text)
        .eq('is_verified', false)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid OTP ❌")));
      return;
    }

    DateTime expiry = DateTime.parse(data['expires_at']);

    if (DateTime.now().isAfter(expiry)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("OTP expired ⏳")));
      return;
    }

    /// MARK VERIFIED
    await supabase
        .from('email_otp')
        .update({"is_verified": true})
        .eq('id', data['id']);

    setState(() => otpVerified = true);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("OTP Verified ✅")));
  }

  /// RESET PASSWORD
  Future resetPassword() async {
    if (!otpVerified) return;

    if (!isStrongPassword(newPasswordController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must be strong (8+ chars, 1 uppercase, 1 number)",
          ),
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      await supabase
          .from('users')
          .update({"password": newPasswordController.text})
          .eq('email_id', emailController.text);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password updated successfully 🎉")),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    setState(() => isLoading = false);
  }

  /// TEXTFIELD
  Widget buildField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Forgot Password")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            buildField(emailController, "Email"),

            /// SEND OTP
            if (!otpVerified)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: otpSent ? null : sendOtp,
                  child: Text(otpSent ? "OTP Sent" : "Send OTP"),
                ),
              ),

            /// OTP INPUT
            if (otpSent && !otpVerified) ...[
              const SizedBox(height: 10),
              buildField(otpController, "Enter OTP"),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text("Verify OTP"),
                ),
              ),
            ],

            /// NEW PASSWORD
            if (otpVerified) ...[
              const SizedBox(height: 15),
              buildField(newPasswordController, "New Password"),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Update Password"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
