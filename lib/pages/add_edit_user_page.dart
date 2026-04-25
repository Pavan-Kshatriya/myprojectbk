import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEditUserPage extends StatefulWidget {
  final Map? user;

  const AddEditUserPage({super.key, this.user});

  @override
  State<AddEditUserPage> createState() => _AddEditUserPageState();
}

class _AddEditUserPageState extends State<AddEditUserPage> {
  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final mobileController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  List userTypes = [];
  List companies = [];

  int? selectedType;
  int? selectedCompany;

  File? imageFile;
  String? imageUrl;

  final ImagePicker picker = ImagePicker();

  /// Pick Image
  Future pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      File file = File(picked.path);

      int fileSize = await file.length();

      /// 300 KB = 300 * 1024
      if (fileSize > 1000 * 1024) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Image Too Large"),
            content: const Text("Please select an image smaller than 1 MB."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("OK"),
              ),
            ],
          ),
        );

        return;
      }

      setState(() {
        imageFile = file;
      });
    }
  }

  /// Compress Image (to keep below 300KB)
  Future<File?> compressImage(File file) async {
    final dir = await getTemporaryDirectory();

    final targetPath =
        "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";

    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 50,
      minWidth: 800,
      minHeight: 800,
    );

    return result != null ? File(result.path) : null;
  }

  /// Upload Image to Supabase Storage
  Future<String?> uploadImage() async {
    if (imageFile == null) return imageUrl;

    try {
      File? compressed = await compressImage(imageFile!);

      if (compressed == null) return null;

      final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";

      final path = "users/$fileName";

      await supabase.storage.from('user_photo').upload(path, compressed);

      final publicUrl = supabase.storage.from('user_photo').getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      print("Upload Error: $e");
      return null;
    }
  }

  /// Fetch User Types
  Future<void> fetchUserTypes() async {
    final data = await supabase
        .from('user_type')
        .select()
        .eq('is_deleted', 'no');

    setState(() {
      userTypes = data;
    });

    if (widget.user != null) {
      final userType = widget.user!['user_type'];

      if (userType is Map) {
        selectedType = userType['id'];
      } else {
        selectedType = userType;
      }
    }
  }

  /// Fetch Companies
  Future<void> fetchCompanies() async {
    final data = await supabase.from('company').select().eq('is_deleted', 'no');

    setState(() {
      companies = data;
    });

    if (widget.user != null) {
      final company = widget.user!['company'];

      if (company is Map) {
        selectedCompany = company['id'];
      } else {
        selectedCompany = widget.user!['company_id'];
      }
    }
  }

  /// Save User
  Future<void> saveUser() async {
    final uploadedImage = await uploadImage();

    final data = {
      "full_name": nameController.text,
      "email_id": emailController.text,
      "mobile_no": mobileController.text,
      "username": usernameController.text,
      "password": passwordController.text,
      "user_type": selectedType,
      "company_id": selectedCompany,
      "user_photo": uploadedImage,
    };

    if (widget.user == null) {
      await supabase.from('users').insert(data);
    } else {
      await supabase.from('users').update(data).eq('id', widget.user!['id']);
    }

    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();

    fetchUserTypes();
    fetchCompanies();

    if (widget.user != null) {
      nameController.text = widget.user!['full_name'] ?? '';
      emailController.text = widget.user!['email_id'] ?? '';
      mobileController.text = widget.user!['mobile_no'] ?? '';
      usernameController.text = widget.user!['username'] ?? '';
      passwordController.text = widget.user!['password'] ?? '';

      selectedCompany = widget.user!['company_id'];
      imageUrl = widget.user!['user_photo'];
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    mobileController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// Image Preview
  Widget buildImage() {
    if (imageFile != null) {
      return CircleAvatar(radius: 50, backgroundImage: FileImage(imageFile!));
    }

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(radius: 50, backgroundImage: NetworkImage(imageUrl!));
    }

    return const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 40));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user == null ? "Add User" : "Edit User"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            /// PHOTO
            Center(child: buildImage()),

            const SizedBox(height: 10),

            Center(
              child: ElevatedButton(
                onPressed: pickImage,
                child: const Text("Upload Photo"),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Full Name",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Mobile",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            DropdownButtonFormField<int>(
              value: selectedType,
              hint: const Text("Select User Type"),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: userTypes.map((type) {
                return DropdownMenuItem<int>(
                  value: type['id'],
                  child: Text(type['name']),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  selectedType = val;
                });
              },
            ),

            const SizedBox(height: 20),

            DropdownButtonFormField<int>(
              value: selectedCompany,
              hint: const Text("Select Company"),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: companies.map((company) {
                return DropdownMenuItem<int>(
                  value: company['id'],
                  child: Text(company['company_name']),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  selectedCompany = val;
                });
              },
            ),

            const SizedBox(height: 30),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: saveUser,
                child: const Text("Save User", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
