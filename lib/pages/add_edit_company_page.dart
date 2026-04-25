import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEditCompanyPage extends StatefulWidget {
  final Map? company;

  const AddEditCompanyPage({super.key, this.company});

  @override
  State<AddEditCompanyPage> createState() => _AddEditCompanyPageState();
}

class _AddEditCompanyPageState extends State<AddEditCompanyPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  /// ENGLISH CONTROLLERS
  final nameController = TextEditingController();
  final addressController = TextEditingController();

  /// LANGUAGE DATA
  List languages = [];

  /// TRANSLATION CONTROLLERS
  Map<String, TextEditingController> nameControllers = {};
  Map<String, TextEditingController> addressControllers = {};

  TabController? tabController;

  File? imageFile;
  String? imageUrl;

  final ImagePicker picker = ImagePicker();

  /// FETCH LANGUAGES
  Future fetchLanguages() async {
    final data = await supabase
        .from('languages')
        .select()
        .eq('is_active', 'yes')
        .order('id');

    languages = data;

    /// CREATE CONTROLLERS
    for (var lang in languages) {
      String code = lang['language_code'];

      nameControllers[code] = TextEditingController();
      addressControllers[code] = TextEditingController();
    }

    tabController = TabController(length: languages.length, vsync: this);

    /// LOAD EXISTING DATA
    if (widget.company != null) {
      nameController.text = widget.company!['company_name'] ?? "";
      addressController.text = widget.company!['address'] ?? "";
      imageUrl = widget.company!['company_image'];

      await loadTranslations(widget.company!['id']);
    }

    setState(() {});
  }

  /// LOAD TRANSLATIONS
  Future loadTranslations(int companyId) async {
    final data = await supabase
        .from('company_translations')
        .select()
        .eq('company_id', companyId)
        .eq('is_deleted', 'no');

    for (var row in data) {
      String code = row['language_code'];

      if (nameControllers.containsKey(code)) {
        nameControllers[code]!.text = row['name'] ?? "";
        addressControllers[code]!.text = row['address'] ?? "";
      }
    }

    setState(() {});
  }

  /// PICK IMAGE
  Future pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      File file = File(picked.path);

      int size = await file.length();

      if (size > 1024 * 1024) {
        showDialog(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text("Image Too Large"),
            content: Text("Please select image smaller than 1MB"),
          ),
        );

        return;
      }

      setState(() {
        imageFile = file;
      });
    }
  }

  /// UPLOAD IMAGE
  Future<String?> uploadImage() async {
    if (imageFile == null) return imageUrl;

    final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
    final path = "companies/$fileName";

    await supabase.storage.from('company_photo').upload(path, imageFile!);

    return supabase.storage.from('company_photo').getPublicUrl(path);
  }

  /// SAVE COMPANY
  Future saveCompany() async {
    if (nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("English company name required")),
      );

      return;
    }

    String? uploadedImage = await uploadImage();

    int companyId;

    /// INSERT
    if (widget.company == null) {
      final res = await supabase
          .from('company')
          .insert({
            "company_name": nameController.text,
            "address": addressController.text,
            "company_image": uploadedImage,
          })
          .select()
          .single();

      companyId = res['id'];
    }
    /// UPDATE
    else {
      companyId = widget.company!['id'];

      await supabase
          .from('company')
          .update({
            "company_name": nameController.text,
            "address": addressController.text,
            "company_image": uploadedImage,
          })
          .eq('id', companyId);
    }

    /// SAVE TRANSLATIONS
    for (var lang in languages) {
      String code = lang['language_code'];

      String name = nameControllers[code]!.text;
      String address = addressControllers[code]!.text;

      if (name.isEmpty) continue;

      final existing = await supabase
          .from('company_translations')
          .select()
          .eq('company_id', companyId)
          .eq('language_code', code)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('company_translations').insert({
          "company_id": companyId,
          "language_code": code,
          "name": name,
          "address": address,
        });
      } else {
        await supabase
            .from('company_translations')
            .update({"name": name, "address": address})
            .eq('company_id', companyId)
            .eq('language_code', code);
      }
    }

    Navigator.pop(context);
  }

  /// IMAGE PREVIEW
  Widget buildImage() {
    if (imageFile != null) {
      return CircleAvatar(radius: 50, backgroundImage: FileImage(imageFile!));
    }

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(radius: 50, backgroundImage: NetworkImage(imageUrl!));
    }

    return const CircleAvatar(radius: 50, child: Icon(Icons.store));
  }

  /// LANGUAGE FORM
  Widget languageForm(String code) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: nameControllers[code],
            decoration: const InputDecoration(
              labelText: "Company Name",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: addressControllers[code],
            decoration: const InputDecoration(
              labelText: "Address",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchLanguages();
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();

    for (var c in nameControllers.values) {
      c.dispose();
    }

    for (var c in addressControllers.values) {
      c.dispose();
    }

    tabController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (languages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.company == null ? "Add Company" : "Edit Company"),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// IMAGE
          Center(child: buildImage()),

          const SizedBox(height: 10),

          Center(
            child: ElevatedButton(
              onPressed: pickImage,
              child: const Text("Upload Company Image"),
            ),
          ),

          const SizedBox(height: 20),

          /// ENGLISH SECTION
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: "Company Name (English) *",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 15),

          TextField(
            controller: addressController,
            decoration: const InputDecoration(
              labelText: "Address (English)",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 25),

          /// LANGUAGE TABS
          TabBar(
            controller: tabController,
            isScrollable: true,
            tabs: languages
                .map((lang) => Tab(text: lang['language_name']))
                .toList(),
          ),

          SizedBox(
            height: 220,
            child: TabBarView(
              controller: tabController,
              children: languages
                  .map((lang) => languageForm(lang['language_code']))
                  .toList(),
            ),
          ),

          const SizedBox(height: 30),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: saveCompany,
              child: const Text("Save Company"),
            ),
          ),
        ],
      ),
    );
  }
}
