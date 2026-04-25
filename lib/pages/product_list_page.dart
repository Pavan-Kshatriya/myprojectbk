import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_form_page.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  final supabase = Supabase.instance.client;

  List products = [];
  List mainCategories = [];
  List categories = [];

  int page = 0;
  int limit = 10;

  bool isLoading = false;

  String search = "";

  int? selectedMainCategory;
  int? selectedCategory;

  final searchController = TextEditingController();

  /// INIT
  @override
  void initState() {
    super.initState();
    fetchMainCategories();
    fetchProducts();
  }

  /// FETCH MAIN CATEGORY
  Future fetchMainCategories() async {
    final data = await supabase
        .from('main_category')
        .select()
        .eq('is_deleted', false);

    setState(() {
      mainCategories = data;
    });
  }

  /// FETCH CATEGORY
  Future fetchCategories(int? mainId) async {
    var query = supabase
        .from('product_categories')
        .select()
        .eq('is_deleted', false);

    if (mainId != null) {
      query = query.eq('main_category_id', mainId);
    }

    final data = await query;

    setState(() {
      categories = data;
    });
  }

  /// FETCH PRODUCTS
  Future fetchProducts() async {
    setState(() => isLoading = true);

    int from = page * limit;
    int to = from + limit - 1;

    var query = supabase
        .from('products')
        .select('''
      *,
      product_categories(
        id,
        name,
        main_category(
          id,
          name
        )
      )
    ''')
        .eq('is_deleted', false);

    /// SEARCH
    if (search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    /// FILTER
    if (selectedCategory != null) {
      query = query.eq('category_id', selectedCategory!);
    }

    final data = await query.order('id', ascending: false).range(from, to);

    setState(() {
      products = data;
      isLoading = false;
    });
  }

  /// SOFT DELETE
  Future deleteProduct(int id) async {
    await supabase.from('products').update({"is_deleted": true}).eq('id', id);

    fetchProducts();
  }

  /// IMAGE POPUP
  void showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            children: [
              /// ZOOM IMAGE
              InteractiveViewer(
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),

              /// CLOSE BUTTON
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Products")),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductFormPage()),
          );
          fetchProducts();
        },
      ),

      body: Column(
        children: [
          /// SEARCH
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search product...",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    search = searchController.text;
                    page = 0;
                    fetchProducts();
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),

          /// MAIN CATEGORY FILTER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButton<int>(
              hint: const Text("Select Main Category"),
              value: selectedMainCategory,
              isExpanded: true,
              items: mainCategories.map<DropdownMenuItem<int>>((e) {
                return DropdownMenuItem<int>(
                  value: e['id'],
                  child: Text(e['name']),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  selectedMainCategory = val;
                  selectedCategory = null;
                });
                fetchCategories(val);
              },
            ),
          ),

          /// CATEGORY FILTER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButton<int>(
              hint: const Text("Select Category"),
              value: selectedCategory,
              isExpanded: true,
              items: categories.map<DropdownMenuItem<int>>((e) {
                return DropdownMenuItem<int>(
                  value: e['id'],
                  child: Text(e['name']),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  selectedCategory = val;
                });
                fetchProducts();
              },
            ),
          ),

          const SizedBox(height: 10),

          /// LIST
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];

                      return ListTile(
                        /// IMAGE WITH CLICK
                        leading: GestureDetector(
                          onTap: () {
                            if (p['image'] != null &&
                                p['image'].toString().isNotEmpty) {
                              showImagePreview(p['image']);
                            }
                          },
                          child:
                              (p['image'] != null &&
                                  p['image'].toString().isNotEmpty)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    p['image'],
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image),
                                ),
                        ),

                        title: Text(p['name'] ?? ""),

                        subtitle: Text(
                          "${p['product_categories']?['name'] ?? ''} → "
                          "${p['product_categories']?['main_category']?['name'] ?? ''}",
                        ),

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
                                    builder: (_) => ProductFormPage(product: p),
                                  ),
                                );
                                fetchProducts();
                              },
                            ),

                            /// DELETE
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteProduct(p['id']),
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
                        fetchProducts();
                      },
              ),
              Text("Page ${page + 1}"),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  page++;
                  fetchProducts();
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
