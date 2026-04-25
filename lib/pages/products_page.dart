import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_drawer.dart';
import 'helper/user_data_helper.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final supabase = Supabase.instance.client;

  // Core data
  Map<String, dynamic>? userData;
  String languageCode = 'ka';

  // Lists
  List<Map<String, dynamic>> measurementUnits = [];
  List<dynamic> productList = [];
  List<Map<String, dynamic>> mainCategories = [];
  List<Map<String, dynamic>> productCategories = [];

  // Filters
  int? selectedMainCategory;
  int? selectedProductCategory;
  bool filterByCompany = false;

  // Controllers
  Map<int, TextEditingController> costControllers = {};
  final ScrollController _scrollController = ScrollController();

  // Loading flags
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Pagination
  int _page = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    initialize();

    // Lazy load listener
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        fetchProducts(isLoadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var controller in costControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> initialize() async {
    await fetchUser();
    await fetchMeasurementUnits();
    await fetchMainCategories();
    await fetchProducts();
  }

  Future<void> fetchUser() async {
    try {
      final data = await loadUserData();
      if (mounted) setState(() => userData = data);
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> fetchMeasurementUnits() async {
    try {
      final response = await supabase
          .from('measurement_unit')
          .select('id, name')
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');
      setState(() {
        measurementUnits = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error fetching measurement units: $e');
    }
  }

  Future<void> fetchMainCategories() async {
    try {
      final response = await supabase
          .from('main_category_translations')
          .select('id, name')
          .eq('language_code', languageCode)
          .eq('is_active', true)
          .eq('is_deleted', false)
          .order('name');

      setState(() {
        mainCategories = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error fetching main categories: $e');
    }
  }

  Future<void> fetchProductCategories() async {
    if (selectedMainCategory == null) {
      setState(() => productCategories = []);
      return;
    }

    try {
      final response = await supabase
          .from('product_category_translations')
          .select('id, name, product_categories!inner(main_category_id)')
          .eq('language_code', languageCode)
          .eq('is_active', true)
          .eq('is_deleted', false)
          .eq('product_categories.main_category_id', selectedMainCategory!)
          .order('name');

      setState(() {
        productCategories = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error fetching product categories: $e');
    }
  }

  Future<void> fetchProducts({bool isLoadMore = false}) async {
    if (userData == null || userData!['company_id'] == null) return;
    final int companyId = userData!['company_id'];

    if (isLoadMore) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _page = 0;
        _hasMore = true;
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
          'p_limit': _limit,
          'p_offset': _page * _limit,
        },
      );

      if (data != null && data.isNotEmpty) {
        setState(() {
          if (isLoadMore) {
            productList.addAll(data);
          } else {
            productList = data;
          }

          for (var item in data) {
            final int id = item['product_id'];
            costControllers[id] ??= TextEditingController(
              text: item['cost']?.toString() ?? '',
            );
          }

          if (data.length < _limit) _hasMore = false;
          _page++;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (error) {
      debugPrint('RPC Error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching products: $error')),
      );
    } finally {
      if (isLoadMore) {
        setState(() => _isLoadingMore = false);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateProduct(Map<String, dynamic> item) async {
    final productId = item['product_id'];
    final categoryId = item['category_id'];
    final mainCategoryId = item['main_category_id'];
    final companyProductId = item['company_product_id'];

    final costText = costControllers[productId]?.text ?? '';
    final double parsedCost = double.tryParse(costText) ?? 0.0;
    final measurementUnit = item['measurement_unit'];
    final int companyId = userData?['company_id'] ?? 0;

    if (measurementUnit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit of measurement cannot be empty')),
      );
      return;
    }

    if (parsedCost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be greater than 0')),
      );
      return;
    }

    final updateData = {
      'company_id': companyId,
      'product_id': productId,
      'product_category_id': categoryId,
      'main_category_id': mainCategoryId,
      'cost': parsedCost,
      'measurement_unit': measurementUnit,
      'in_stock': item['in_stock'] ?? false,
      'is_active': 'yes',
      'is_deleted': 'no',
    };

    setState(() => _isUpdating = true);

    try {
      if (companyProductId == null) {
        final response = await supabase
            .from('company_products')
            .insert(updateData)
            .select()
            .maybeSingle();
        if (response != null) {
          setState(() => item['company_product_id'] = response['id']);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product inserted successfully')),
          );
        }
      } else {
        await supabase
            .from('company_products')
            .update(updateData)
            .eq('id', companyProductId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error updating product: $e');
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // --- FILTERS SECTION ---
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

                // Company Filter Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Show only company products'),
                    Switch(
                      value: filterByCompany,
                      onChanged: (value) async {
                        setState(() => filterByCompany = value);
                        await fetchProducts();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // --- PRODUCTS LIST ---
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : productList.isEmpty
                    ? const Center(child: Text('No products found'))
                    : RefreshIndicator(
                        onRefresh: () async => fetchProducts(),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: productList.length + 1,
                          itemBuilder: (context, index) {
                            if (index == productList.length) {
                              return _isLoadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            }

                            final item = productList[index];
                            final productId = item['product_id'];
                            final productName =
                                item['product_name'] ?? 'No Name';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Product Image
                                    Container(
                                      height: 150,
                                      width: double.infinity,
                                      color: Colors.grey[200],
                                      child:
                                          (item['image'] != null &&
                                              item['image']
                                                  .toString()
                                                  .isNotEmpty)
                                          ? Image.network(
                                              item['image'],
                                              fit: BoxFit.cover,
                                            )
                                          : const Center(
                                              child: Text("No Image"),
                                            ),
                                    ),
                                    const SizedBox(height: 12),

                                    Text(
                                      productName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    DropdownButton<int>(
                                      value: item['measurement_unit'],
                                      hint: const Text('Select Unit'),
                                      isExpanded: true,
                                      items: measurementUnits
                                          .map(
                                            (unit) => DropdownMenuItem<int>(
                                              value: unit['id'],
                                              child: Text(unit['name']),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          item['measurement_unit'] = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    TextField(
                                      controller: costControllers[productId],
                                      decoration: const InputDecoration(
                                        labelText: 'Amount',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Checkbox(
                                              value: item['in_stock'] ?? false,
                                              onChanged: (newValue) {
                                                setState(() {
                                                  item['in_stock'] =
                                                      newValue ?? false;
                                                });
                                              },
                                            ),
                                            const Text('In Stock'),
                                          ],
                                        ),
                                        ElevatedButton(
                                          onPressed: _isUpdating
                                              ? null
                                              : () => _updateProduct(item),
                                          child: _isUpdating
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Text('Update'),
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
                if (_isUpdating)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
