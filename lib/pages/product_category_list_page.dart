import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_category_form_page.dart';

class ProductCategoryListPage extends StatefulWidget {
  const ProductCategoryListPage({super.key});

  @override
  State<ProductCategoryListPage> createState() =>
      _ProductCategoryListPageState();
}

class _ProductCategoryListPageState extends State<ProductCategoryListPage> {
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

    var query = supabase
        .from('product_categories')
        .select('*, main_category(name)')
        .eq('is_deleted', false);

    if (search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final data = await query.order('id', ascending: false).range(from, to);

    setState(() {
      categories = data;
      isLoading = false;
    });
  }

  Future softDelete(int id) async {
    await supabase
        .from('product_categories')
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
      appBar: AppBar(title: const Text("Product Categories")),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductCategoryFormPage()),
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

                        subtitle: Text(
                          cat['main_category']?['name'] ?? "No Main Category",
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ProductCategoryFormPage(category: cat),
                                  ),
                                );

                                fetchCategories();
                              },
                            ),

                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => softDelete(cat['id']),
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
