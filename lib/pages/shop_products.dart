import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'my_cart_page.dart';
import 'helper/user_data_helper.dart';

class ShopProductsPage extends StatefulWidget {
  final int companyId;

  const ShopProductsPage({super.key, required this.companyId});

  @override
  State<ShopProductsPage> createState() => _ShopProductsPageState();
}

class _ShopProductsPageState extends State<ShopProductsPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> productList = [];
  List<Map<String, dynamic>> measurementUnits = [];
  List<Map<String, dynamic>> mainCategories = [];
  List<Map<String, dynamic>> productCategories = [];

  Map<int, int> _quantities = {}; // product_id => quantity

  bool isLoading = true; // initial full-page loader
  bool isBusy = false; // overlay loader for actions
  bool isLoadingMore = false;
  bool hasMore = true;

  // Filters
  int? selectedMainCategory;
  int? selectedProductCategory;
  bool filterByCompany = true;

  String languageCode = 'ka';
  Map<String, dynamic>? userData;

  // Pagination
  int page = 0;
  final int limit = 20;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    initialize();

    // Lazy load
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !isLoadingMore &&
          hasMore) {
        fetchProducts(isLoadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    await fetchUser();
    await Future.wait([fetchMeasurementUnits(), fetchMainCategories()]);
    await fetchProducts();
  }

  Future<void> fetchUser() async {
    final data = await loadUserData();
    if (mounted) setState(() => userData = data);
  }

  Future<void> fetchMeasurementUnits() async {
    final response = await supabase
        .from('measurement_unit')
        .select('id, name')
        .eq('is_active', 'yes')
        .eq('is_deleted', 'no');

    if (mounted) {
      setState(() {
        measurementUnits = List<Map<String, dynamic>>.from(response);
      });
    }
  }

  Future<void> fetchMainCategories() async {
    final response = await supabase
        .from('main_category_translations')
        .select('id, name')
        .eq('language_code', languageCode)
        .eq('is_active', true)
        .eq('is_deleted', false)
        .order('name');

    if (mounted) {
      setState(() {
        mainCategories = List<Map<String, dynamic>>.from(response);
      });
    }
  }

  Future<void> fetchProductCategories() async {
    if (selectedMainCategory == null) {
      setState(() => productCategories = []);
      return;
    }

    final response = await supabase
        .from('product_category_translations')
        .select('id, name, product_categories!inner(main_category_id)')
        .eq('language_code', languageCode)
        .eq('is_active', true)
        .eq('is_deleted', false)
        .eq('product_categories.main_category_id', selectedMainCategory!)
        .order('name');

    if (mounted) {
      setState(() {
        productCategories = List<Map<String, dynamic>>.from(response);
      });
    }
  }

  Future<void> fetchProducts({bool isLoadMore = false}) async {
    if (userData == null) return;
    final int companyId = widget.companyId;

    if (isLoadMore) {
      setState(() => isLoadingMore = true);
    } else {
      setState(() {
        isLoading = true;
        page = 0;
        hasMore = true;
        productList.clear();
      });
    }

    try {
      final data = await supabase.rpc(
        'products_data_v1',
        params: {
          'p_company_id': companyId,
          'p_language_code': languageCode,
          'p_only_active': true,
          'p_only_not_deleted': true,
          'p_main_category_id': selectedMainCategory,
          'p_category_id': selectedProductCategory,
          'p_filter_company_id': filterByCompany ? companyId : null,
          'p_limit': limit,
          'p_offset': page * limit,
        },
      );

      if (data != null && data.isNotEmpty) {
        setState(() {
          if (isLoadMore) {
            productList.addAll(data);
          } else {
            productList = List<Map<String, dynamic>>.from(data);
          }

          if (data.length < limit) hasMore = false;
          page++;
        });
      } else {
        setState(() => hasMore = false);
      }
    } catch (e) {
      debugPrint('RPC Error: $e');
    } finally {
      if (isLoadMore) {
        setState(() => isLoadingMore = false);
      } else {
        setState(() => isLoading = false);
      }
    }
  }

  String getUnitName(int unitId) {
    return measurementUnits.firstWhere(
      (unit) => unit['id'] == unitId,
      orElse: () => {'name': ''},
    )['name']!;
  }

  void incrementQuantity(int productId) {
    setState(() {
      _quantities[productId] = (_quantities[productId] ?? 1) + 1;
    });
  }

  void decrementQuantity(int productId) {
    setState(() {
      final current = _quantities[productId] ?? 1;
      if (current > 1) _quantities[productId] = current - 1;
    });
  }

  Future<void> addToCart(Map<String, dynamic> product, int quantity) async {
    final productId = product['product_id'];
    final userId = userData?['id'];
    final companyId = widget.companyId;
    final unitCost = product['cost']?.toDouble() ?? 0.0;
    final totalAmount = unitCost * quantity;

    if (userId == null) return;

    setState(() => isBusy = true);

    try {
      final existing = await supabase
          .from('cart_items')
          .select()
          .eq('user_id', userId)
          .eq('company_id', companyId)
          .eq('product_id', productId)
          .eq('is_billed', 'no')
          .eq('is_deleted', 'no')
          .eq('is_active', 'yes')
          .maybeSingle();

      if (existing != null) {
        await supabase
            .from('cart_items')
            .update({
              'quantity': quantity,
              'total_price': totalAmount,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existing['id']);
      } else {
        await supabase.from('cart_items').insert({
          'user_id': userId,
          'company_id': companyId,
          'product_id': productId,
          'quantity': quantity,
          'total_price': totalAmount,
          'is_billed': 'no',
          'is_active': 'yes',
          'is_deleted': 'no',
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product['product_name']} added/updated in cart'),
        ),
      );
    } catch (e) {
      debugPrint('Add to cart error: $e');
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            tooltip: "Go to Cart",
            onPressed: isBusy
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MyCartPage(),
                      ),
                    );
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: Column(
        children: [
          // --- FILTER SECTION ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // Main Category
                DropdownButtonFormField<int>(
                  value: selectedMainCategory,
                  decoration: const InputDecoration(
                    labelText: 'Main Category',
                    border: OutlineInputBorder(),
                  ),
                  items: mainCategories.map((mc) {
                    return DropdownMenuItem<int>(
                      value: mc['id'],
                      child: Text(mc['name']),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    setState(() {
                      selectedMainCategory = value;
                      selectedProductCategory = null;
                    });
                    await fetchProductCategories();
                    await fetchProducts();
                  },
                ),
                const SizedBox(height: 8),

                // Product Category
                DropdownButtonFormField<int>(
                  value: selectedProductCategory,
                  decoration: const InputDecoration(
                    labelText: 'Product Category',
                    border: OutlineInputBorder(),
                  ),
                  items: productCategories.map((pc) {
                    return DropdownMenuItem<int>(
                      value: pc['id'],
                      child: Text(pc['name']),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    setState(() => selectedProductCategory = value);
                    await fetchProducts();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          const Divider(),

          // --- PRODUCT LIST ---
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: productList.length + (isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= productList.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final product = productList[index];
                final productId = product['product_id'];
                final quantity = _quantities[productId] ?? 1;
                final unitCost = product['cost']?.toDouble() ?? 0.0;
                final totalAmount = unitCost * quantity;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Image
                        Container(
                          height: 150,
                          width: double.infinity,
                          color: Colors.grey[200],
                          child: product['image'] != null
                              ? Image.network(
                                  product['image'],
                                  fit: BoxFit.cover,
                                )
                              : const Center(child: Text("No Image")),
                        ),
                        const SizedBox(height: 10),

                        // Name and total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                product['product_name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              "₹${totalAmount.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),
                        Text(
                          "₹${unitCost.toStringAsFixed(2)} / ${getUnitName(product['measurement_unit'])}",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Quantity & Add to Cart
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.indeterminate_check_box),
                              onPressed: () => decrementQuantity(productId),
                            ),
                            Text(
                              '$quantity',
                              style: const TextStyle(fontSize: 16),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_box),
                              onPressed: () => incrementQuantity(productId),
                            ),
                            const Spacer(),
                            ElevatedButton(
                              onPressed: isBusy
                                  ? null
                                  : () => addToCart(product, quantity),
                              child: const Text("Add to Cart"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
