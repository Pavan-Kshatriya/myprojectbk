import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductCategoryFormPage extends StatefulWidget {
  final Map? category;

  const ProductCategoryFormPage({super.key, this.category});

  @override
  State<ProductCategoryFormPage> createState() =>
      _ProductCategoryFormPageState();
}

class _ProductCategoryFormPageState extends State<ProductCategoryFormPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();

  int? selectedMainCategory;

  List mainCategories = [];
  List languages = [];

  Map<String, TextEditingController> nameControllers = {};

  TabController? tabController;

  Future fetchInitialData() async {
    /// MAIN CATEGORY
    mainCategories = await supabase
        .from('main_category')
        .select()
        .eq('is_deleted', false)
        .order('name');

    /// LANGUAGES
    languages = await supabase
        .from('languages')
        .select()
        .eq('is_active', 'yes')
        .order('id');

    for (var lang in languages) {
      nameControllers[lang['language_code']] = TextEditingController();
    }

    tabController = TabController(length: languages.length, vsync: this);

    if (widget.category != null) {
      nameController.text = widget.category!['name'];
      selectedMainCategory = widget.category!['main_category_id'];

      await loadTranslations(widget.category!['id']);
    }

    setState(() {});
  }

  Future loadTranslations(int id) async {
    final data = await supabase
        .from('product_category_translations')
        .select()
        .eq('category_id', id)
        .eq('is_deleted', false);

    for (var row in data) {
      nameControllers[row['language_code']]?.text = row['name'];
    }
  }

  Future saveCategory() async {
    if (nameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Name required")));
      return;
    }

    int id;

    if (widget.category == null) {
      final res = await supabase
          .from('product_categories')
          .insert({
            "name": nameController.text,
            "main_category_id": selectedMainCategory,
          })
          .select()
          .single();

      id = res['id'];
    } else {
      id = widget.category!['id'];

      await supabase
          .from('product_categories')
          .update({
            "name": nameController.text,
            "main_category_id": selectedMainCategory,
          })
          .eq('id', id);
    }

    /// SAVE TRANSLATIONS
    for (var lang in languages) {
      String code = lang['language_code'];
      String name = nameControllers[code]!.text;

      if (name.isEmpty) continue;

      final existing = await supabase
          .from('product_category_translations')
          .select()
          .eq('category_id', id)
          .eq('language_code', code)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('product_category_translations').insert({
          "category_id": id,
          "language_code": code,
          "name": name,
        });
      } else {
        await supabase
            .from('product_category_translations')
            .update({"name": name})
            .eq('category_id', id)
            .eq('language_code', code);
      }
    }

    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  @override
  Widget build(BuildContext context) {
    if (languages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.category == null
              ? "Add Product Category"
              : "Edit Product Category",
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// MAIN CATEGORY DROPDOWN
          DropdownButtonFormField<int>(
            value: selectedMainCategory,
            hint: const Text("Select Main Category"),
            items: mainCategories.map<DropdownMenuItem<int>>((cat) {
              return DropdownMenuItem<int>(
                value: cat['id'] as int,
                child: Text(cat['name']),
              );
            }).toList(),
            onChanged: (v) {
              setState(() {
                selectedMainCategory = v;
              });
            },
          ),

          const SizedBox(height: 20),

          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: "Category Name (English)",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 25),

          TabBar(
            controller: tabController,
            isScrollable: true,
            tabs: languages
                .map((lang) => Tab(text: lang['language_name']))
                .toList(),
          ),

          SizedBox(
            height: 150,
            child: TabBarView(
              controller: tabController,
              children: languages.map((lang) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: nameControllers[lang['language_code']],
                    decoration: const InputDecoration(
                      labelText: "Translated Name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 30),

          ElevatedButton(
            onPressed: saveCategory,
            child: const Text("Save Category"),
          ),
        ],
      ),
    );
  }
}
