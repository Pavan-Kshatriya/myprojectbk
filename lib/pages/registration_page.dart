import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helper/email_helper.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final supabase = Supabase.instance.client;

  final firstName = TextEditingController();
  final middleName = TextEditingController();
  final lastName = TextEditingController();
  final mobile = TextEditingController();
  final email = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final otpController = TextEditingController();

  bool isLoading = false;
  bool showPassword = false;
  bool otpSent = false;
  bool otpVerified = false;

  File? imageFile;

  /// OTP GENERATE
  String generateOTP() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  /// IMAGE PICK
  Future pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      final file = File(picked.path);
      final size = await file.length();

      if (size > 1024 * 1024) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Image must be ≤ 1MB")));
        return;
      }

      setState(() => imageFile = file);
    }
  }

  /// UPLOAD IMAGE
  Future<String?> uploadImage() async {
    if (imageFile == null) return null;

    final path = "users/${DateTime.now().millisecondsSinceEpoch}.jpg";

    await supabase.storage.from('user_photo').upload(path, imageFile!);

    return supabase.storage.from('user_photo').getPublicUrl(path);
  }

  /// VALIDATIONS
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
    if (!isValidEmail(email.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid email")));
      return;
    }

    String otp = generateOTP();

    await supabase.from('email_otp').insert({
      "email": email.text,
      "otp": otp,
      "is_verified": false,
      "expires_at": DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    });

    bool sent = await EmailHelper.sendEmail(
      templateName: "OTP",
      toEmail: email.text,
      variables: {"otp": otp, "email": email.text, "minutes": "5"},
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
        .eq('email', email.text)
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

    await supabase
        .from('email_otp')
        .update({"is_verified": true})
        .eq('id', data['id']);

    setState(() => otpVerified = true);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("OTP Verified ✅")));
  }

  /// REGISTER
  Future register() async {
    if (!otpVerified) return;

    if (firstName.text.isEmpty ||
        mobile.text.isEmpty ||
        email.text.isEmpty ||
        username.text.isEmpty ||
        password.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Fill mandatory fields")));
      return;
    }

    if (!isStrongPassword(password.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Weak password")));
      return;
    }

    setState(() => isLoading = true);

    try {
      final existing = await supabase
          .from('users')
          .select()
          .or(
            'username.eq.${username.text},email_id.eq.${email.text},mobile_no.eq.${mobile.text}',
          );

      if (existing.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User already exists")));
        setState(() => isLoading = false);
        return;
      }

      String? imageUrl = await uploadImage();

      String fullName = firstName.text;
      if (middleName.text.isNotEmpty) fullName += " ${middleName.text}";
      if (lastName.text.isNotEmpty) fullName += " ${lastName.text}";

      await supabase.from('users').insert({
        "first_name": firstName.text,
        "middle_name": middleName.text,
        "last_name": lastName.text,
        "full_name": fullName,
        "mobile_no": mobile.text,
        "email_id": email.text,
        "username": username.text,
        "password": password.text,
        "user_photo": imageUrl,
        "user_type": 3,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration Successful 🎉")),
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
  Widget buildTextField(TextEditingController controller, String label) {
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
      appBar: AppBar(title: const Text("Register")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// IMAGE
            GestureDetector(
              onTap: pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey[200],
                backgroundImage: imageFile != null
                    ? FileImage(imageFile!)
                    : null,
                child: imageFile == null
                    ? const Icon(Icons.camera_alt, size: 35)
                    : null,
              ),
            ),

            const SizedBox(height: 20),

            buildTextField(firstName, "First Name *"),
            buildTextField(middleName, "Middle Name"),
            buildTextField(lastName, "Last Name"),
            buildTextField(mobile, "Mobile *"),
            buildTextField(email, "Email *"),
            buildTextField(username, "Username *"),

            TextField(
              controller: password,
              obscureText: !showPassword,
              decoration: InputDecoration(
                labelText: "Password *",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    showPassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => showPassword = !showPassword),
                ),
              ),
            ),

            const SizedBox(height: 15),

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
              TextField(
                controller: otpController,
                decoration: InputDecoration(
                  labelText: "Enter OTP",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
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

            /// REGISTER BUTTON (ONLY AFTER VERIFIED)
            if (otpVerified) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Register"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
