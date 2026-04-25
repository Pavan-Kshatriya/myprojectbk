import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import 'helper/user_data_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'checkout_page.dart';

class MyCartPage extends StatefulWidget {
  const MyCartPage({super.key});

  @override
  State<MyCartPage> createState() => _MyCartPageState();
}

class _MyCartPageState extends State<MyCartPage> {
  Map<String, dynamic>? userData;
  final supabase = Supabase.instance.client;
  String languageCode = 'ka';
  List<Map<String, dynamic>> allCartItems = [];

  bool isLoading = true; // 🌀 Page loader
  bool isBusy = false; // 🔒 Overlay loader for actions

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> fetchUser() async {
    final data = await loadUserData();
    if (mounted) {
      setState(() => userData = data);
    }
  }

  Future<void> fetchCartItems() async {
    final int userId = userData!['id'];
    final String lang = languageCode;

    final cartDetails = await fetchCartDetails(userId, lang);
    if (mounted) {
      setState(() {
        allCartItems = cartDetails;
        isLoading = false;
      });
    }
  }

  Future<void> initialize() async {
    setState(() => isLoading = true);
    await fetchUser();
    if (userData != null) {
      await fetchCartItems();
    } else {
      print('⚠️ User data not loaded, skipping cart fetch');
      setState(() => isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> fetchCartDetails(
    int userId,
    String lang,
  ) async {
    final result = await supabase.rpc(
      'get_cart_details',
      params: {'p_user_id': userId, 'p_language_code': lang},
    );
    return List<Map<String, dynamic>>.from(result);
  }

  // Group items by company_id
  Map<int, List<Map<String, dynamic>>> get groupedCartItems {
    Map<int, List<Map<String, dynamic>>> grouped = {};
    for (var item in allCartItems) {
      grouped.putIfAbsent(item['company_id'], () => []);
      grouped[item['company_id']]!.add(item);
    }
    return grouped;
  }

  void incrementQuantity(int productId) {
    setState(() {
      final index = allCartItems.indexWhere(
        (item) => item['cart_id'] == productId,
      );
      allCartItems[index]['quantity'] += 1;
    });
  }

  void decrementQuantity(int productId) {
    setState(() {
      final index = allCartItems.indexWhere(
        (item) => item['cart_id'] == productId,
      );
      if (allCartItems[index]['quantity'] > 1) {
        allCartItems[index]['quantity'] -= 1;
      }
    });
  }

  Future<void> removeItem(int productId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() => isBusy = true);

    try {
      await supabase
          .from('cart_items')
          .update({
            'is_deleted': 'yes',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', productId);

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Item removed from cart.'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        allCartItems.removeWhere((item) => item['cart_id'] == productId);
      });
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to remove item: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  double getCompanyTotal(List<Map<String, dynamic>> items) {
    return items.fold(0.0, (total, item) {
      return total + (item['price'] * item['quantity']);
    });
  }

  Future<void> handleCheckout(
    int companyId,
    List<Map<String, dynamic>> items,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final now = DateTime.now().toIso8601String();

    setState(() => isBusy = true);

    try {
      List<Future> updateFutures = [];

      for (var item in items) {
        final int cartId = item['cart_id'];
        final int quantity = item['quantity'];
        final double totalPrice =
            (item['price'] as num).toDouble() * item['quantity'];

        updateFutures.add(
          supabase
              .from('cart_items')
              .update({
                'quantity': quantity,
                'total_price': totalPrice,
                'updated_at': now,
              })
              .eq('id', cartId),
        );
      }

      await Future.wait(updateFutures);

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Cart updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CheckoutPage(companyId: companyId),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update cart: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🌀 Loader for initial data fetch
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Cart')),
        drawer: const AppDrawer(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Empty cart state
    if (allCartItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Cart')),
        drawer: const AppDrawer(),
        body: const Center(child: Text("Your cart is empty")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Cart')),
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(12),
            children: groupedCartItems.entries.map((entry) {
              final companyId = entry.key;
              final companyItems = entry.value;
              final companyName =
                  companyItems.first['company_name'] ?? 'Company $companyId';
              final total = getCompanyTotal(companyItems);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    companyName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...companyItems.map((item) {
                    final subtotal = item['price'] * item['quantity'];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Product image
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.grey[200],
                                    image: item['image'] != null
                                        ? DecorationImage(
                                            image: NetworkImage(item['image']),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: item['image'] == null
                                      ? const Icon(
                                          Icons.image_not_supported,
                                          size: 40,
                                          color: Colors.grey,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['product_name'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "₹${item['price']} x ${item['quantity']} = ₹${subtotal.toStringAsFixed(2)}",
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () => removeItem(item['cart_id']),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.indeterminate_check_box,
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () =>
                                            decrementQuantity(item['cart_id']),
                                ),
                                Text(
                                  '${item['quantity']}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_box),
                                  onPressed: isBusy
                                      ? null
                                      : () =>
                                            incrementQuantity(item['cart_id']),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total: ₹${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: isBusy
                            ? null
                            : () => handleCheckout(companyId, companyItems),
                        child: const Text('Check Out'),
                      ),
                    ],
                  ),
                  const Divider(thickness: 2),
                  const SizedBox(height: 30),
                ],
              );
            }).toList(),
          ),

          // 🔒 Overlay loader for busy operations
          if (isBusy)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
