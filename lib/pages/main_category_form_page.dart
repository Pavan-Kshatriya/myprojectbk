import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainCategoryFormPage extends StatefulWidget {
  final Map? category;

  const MainCategoryFormPage({super.key, this.category});

  @override
  State<MainCategoryFormPage> createState() => _MainCategoryFormPageState();
}

class _MainCategoryFormPageState extends State<MainCategoryFormPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();

  List languages = [];

  Map<String, TextEditingController> nameControllers = {};

  TabController? tabController;

  /// LOAD LANGUAGES
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
    }

    tabController = TabController(length: languages.length, vsync: this);

    if (widget.category != null) {
      nameController.text = widget.category!['name'] ?? "";

      await loadTranslations(widget.category!['id']);
    }

    setState(() {});
  }

  /// LOAD TRANSLATIONS
  Future loadTranslations(int id) async {
    final data = await supabase
        .from('main_category_translations')
        .select()
        .eq('main_category_id', id)
        .eq('is_deleted', false);

    for (var row in data) {
      String code = row['language_code'];

      if (nameControllers.containsKey(code)) {
        nameControllers[code]!.text = row['name'] ?? "";
      }
    }

    setState(() {});
  }

  /// SAVE
  Future saveCategory() async {
    if (nameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("English name required")));

      return;
    }

    int id;

    /// INSERT
    if (widget.category == null) {
      final res = await supabase
          .from('main_category')
          .insert({"name": nameController.text})
          .select()
          .single();

      id = res['id'];
    }
    /// UPDATE
    else {
      id = widget.category!['id'];

      await supabase
          .from('main_category')
          .update({"name": nameController.text})
          .eq('id', id);
    }

    /// TRANSLATIONS
    for (var lang in languages) {
      String code = lang['language_code'];
      String name = nameControllers[code]!.text;

      if (name.isEmpty) continue;

      final existing = await supabase
          .from('main_category_translations')
          .select()
          .eq('main_category_id', id)
          .eq('language_code', code)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('main_category_translations').insert({
          "main_category_id": id,
          "language_code": code,
          "name": name,
        });
      } else {
        await supabase
            .from('main_category_translations')
            .update({"name": name})
            .eq('main_category_id', id)
            .eq('language_code', code);
      }
    }

    Navigator.pop(context);
  }

  Widget languageForm(String code) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: nameControllers[code],
        decoration: const InputDecoration(
          labelText: "Category Name",
          border: OutlineInputBorder(),
        ),
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

    for (var c in nameControllers.values) {
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
        title: Text(
          widget.category == null ? "Add Main Category" : "Edit Main Category",
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              children: languages
                  .map((lang) => languageForm(lang['language_code']))
                  .toList(),
            ),
          ),

          const SizedBox(height: 30),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: saveCategory,
              child: const Text("Save Category"),
            ),
          ),
        ],
      ),
    );
  }
}
