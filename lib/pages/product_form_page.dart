import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductFormPage extends StatefulWidget {
  final Map? product;

  const ProductFormPage({super.key, this.product});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();
  final descController = TextEditingController();

  List languages = [];
  Map<String, TextEditingController> nameControllers = {};
  Map<String, TextEditingController> descControllers = {};

  TabController? tabController;

  List mainCategories = [];
  List categories = [];

  int? selectedMainCategory;
  int? selectedCategory;

  File? selectedImage;
  String? imageUrl;

  bool isLoading = false;

  /// INIT
  @override
  void initState() {
    super.initState();
    loadInitialData();
  }

  /// LOAD ALL DATA
  Future loadInitialData() async {
    await fetchLanguages();
    await fetchMainCategories();

    if (widget.product != null) {
      final p = widget.product!;

      nameController.text = p['name'] ?? "";
      descController.text = p['description'] ?? "";

      selectedMainCategory = p['main_category_id'];
      selectedCategory = p['category_id'];
      imageUrl = p['image'];

      if (selectedMainCategory != null) {
        await fetchCategories(selectedMainCategory);
      }

      await loadTranslations(p['id']);
    }
  }

  /// LANGUAGES
  Future fetchLanguages() async {
    final data = await supabase
        .from('languages')
        .select()
        .eq('is_active', 'yes')
        .order('id');

    languages = data;

    for (var lang in languages) {
      String code = lang['language_code'];

      nameControllers[code] = TextEditingController();
      descControllers[code] = TextEditingController();
    }

    tabController = TabController(length: languages.length, vsync: this);

    setState(() {});
  }

  /// LOAD TRANSLATIONS
  Future loadTranslations(int productId) async {
    final data = await supabase
        .from('product_translations')
        .select()
        .eq('product_id', productId)
        .eq('is_deleted', false);

    for (var row in data) {
      String code = row['language_code'];

      if (nameControllers.containsKey(code)) {
        nameControllers[code]!.text = row['name'] ?? "";
        descControllers[code]!.text = row['description'] ?? "";
      }
    }

    setState(() {});
  }

  /// MAIN CATEGORY
  Future fetchMainCategories() async {
    final data = await supabase
        .from('main_category')
        .select()
        .eq('is_deleted', false);

    setState(() => mainCategories = data);
  }

  /// CATEGORY
  Future fetchCategories(int? mainId) async {
    var query = supabase
        .from('product_categories')
        .select()
        .eq('is_deleted', false);

    if (mainId != null) {
      query = query.eq('main_category_id', mainId);
    }

    final data = await query;

    setState(() => categories = data);
  }

  /// IMAGE
  Future pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      final file = File(picked.path);

      // ✅ FILE SIZE CHECK (1MB = 1024 * 1024)
      final fileSize = await file.length();

      if (fileSize > 1024 * 1024) {
        // ❌ SHOW ERROR
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Image size should be less than or equal to 1 MB"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // ✅ VALID IMAGE
      setState(() => selectedImage = file);
    }
  }

  Future<String?> uploadImage(File file) async {
    final path = "products/${DateTime.now().millisecondsSinceEpoch}.jpg";

    await supabase.storage.from('peoducts_images').upload(path, file);

    return supabase.storage.from('peoducts_images').getPublicUrl(path);
  }

  /// SAVE
  Future saveProduct() async {
    if (nameController.text.isEmpty) return;

    setState(() => isLoading = true);

    String? finalImage = imageUrl;

    if (selectedImage != null) {
      finalImage = await uploadImage(selectedImage!);
    }

    int id;

    if (widget.product == null) {
      final res = await supabase
          .from('products')
          .insert({
            "name": nameController.text,
            "description": descController.text,
            "image": finalImage,
            "category_id": selectedCategory,
            "main_category_id": selectedMainCategory,
          })
          .select()
          .single();

      id = res['id'];
    } else {
      id = widget.product!['id'];

      await supabase
          .from('products')
          .update({
            "name": nameController.text,
            "description": descController.text,
            "image": finalImage,
            "category_id": selectedCategory,
            "main_category_id": selectedMainCategory,
          })
          .eq('id', id);
    }

    /// SAVE TRANSLATIONS
    for (var lang in languages) {
      String code = lang['language_code'];

      String name = nameControllers[code]!.text;
      String desc = descControllers[code]!.text;

      if (name.isEmpty) continue;

      final existing = await supabase
          .from('product_translations')
          .select()
          .eq('product_id', id)
          .eq('language_code', code)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('product_translations').insert({
          "product_id": id,
          "language_code": code,
          "name": name,
          "description": desc,
        });
      } else {
        await supabase
            .from('product_translations')
            .update({"name": name, "description": desc})
            .eq('product_id', id)
            .eq('language_code', code);
      }
    }

    setState(() => isLoading = false);

    Navigator.pop(context);
  }

  /// TAB FORM
  Widget languageForm(String code) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: nameControllers[code],
            decoration: const InputDecoration(
              labelText: "Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: descControllers[code],
            decoration: const InputDecoration(
              labelText: "Description",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (languages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Product")),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Name"),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: "Description"),
                ),

                const SizedBox(height: 15),

                DropdownButtonFormField<int>(
                  value: selectedMainCategory,
                  hint: const Text("Main Category"),
                  items: mainCategories.map<DropdownMenuItem<int>>((e) {
                    return DropdownMenuItem<int>(
                      value: e['id'],
                      child: Text(e['name']),
                    );
                  }).toList(),
                  onChanged: (val) {
                    selectedMainCategory = val;
                    selectedCategory = null;
                    fetchCategories(val);
                    setState(() {});
                  },
                ),

                const SizedBox(height: 10),

                DropdownButtonFormField<int>(
                  value: selectedCategory,
                  hint: const Text("Category"),
                  items: categories.map<DropdownMenuItem<int>>((e) {
                    return DropdownMenuItem<int>(
                      value: e['id'],
                      child: Text(e['name']),
                    );
                  }).toList(),
                  onChanged: (val) {
                    selectedCategory = val;
                    setState(() {});
                  },
                ),

                const SizedBox(height: 20),

                /// IMAGE
                GestureDetector(
                  onTap: pickImage,
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                    ),
                    child: selectedImage != null
                        ? Image.file(selectedImage!, fit: BoxFit.cover)
                        : (imageUrl != null && imageUrl!.isNotEmpty)
                        ? Image.network(imageUrl!, fit: BoxFit.cover)
                        : const Center(child: Icon(Icons.add_a_photo)),
                  ),
                ),

                const SizedBox(height: 20),

                /// LANGUAGE TABS
                TabBar(
                  controller: tabController,
                  isScrollable: true,
                  tabs: languages
                      .map((e) => Tab(text: e['language_name']))
                      .toList(),
                ),

                SizedBox(
                  height: 200,
                  child: TabBarView(
                    controller: tabController,
                    children: languages
                        .map((e) => languageForm(e['language_code']))
                        .toList(),
                  ),
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: saveProduct,
                  child: const Text("Save Product"),
                ),
              ],
            ),
    );
  }
}
