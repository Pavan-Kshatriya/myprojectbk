import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_category_form_page.dart';

class MainCategoryListPage extends StatefulWidget {
  const MainCategoryListPage({super.key});

  @override
  State<MainCategoryListPage> createState() => _MainCategoryListPageState();
}

class _MainCategoryListPageState extends State<MainCategoryListPage> {
  final supabase = Supabase.instance.client;

  List categories = [];

  int page = 0;
  int limit = 10;

  bool isLoading = false;

  String search = "";

  final searchController = TextEditingController();

  Future fetchCategories() async {
    setState(() {
      isLoading = true;
    });

    int from = page * limit;
    int to = from + limit - 1;

    var query = supabase.from('main_category').select().eq('is_deleted', false);

    if (search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final data = await query.order('id', ascending: false).range(from, to);

    setState(() {
      categories = data;
      isLoading = false;
    });
  }

  /// SOFT DELETE FUNCTION
  Future softDelete(int id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Category"),
          content: const Text("Are you sure you want to delete this category?"),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: const Text("Delete"),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await supabase
        .from('main_category')
        .update({"is_deleted": true})
        .eq('id', id);

    fetchCategories();
  }

  @override
  void initState() {
    super.initState();
    fetchCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Main Categories")),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MainCategoryFormPage()),
          );

          fetchCategories();
        },
      ),

      body: Column(
        children: [
          /// SEARCH
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search category...",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    search = searchController.text;
                    page = 0;
                    fetchCategories();
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];

                      return ListTile(
                        title: Text(cat['name']),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            /// EDIT
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MainCategoryFormPage(category: cat),
                                  ),
                                );

                                fetchCategories();
                              },
                            ),

                            /// DELETE
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                softDelete(cat['id']);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          /// PAGINATION
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: page == 0
                    ? null
                    : () {
                        page--;
                        fetchCategories();
                      },
              ),

              Text("Page ${page + 1}"),

              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  page++;
                  fetchCategories();
                },
              ),
            ],
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
