import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_drawer.dart';
import 'helper/user_data_helper.dart';
import 'orders.dart';
import 'helper/notification_helper.dart';
import '../services/db_service.dart';

class CheckoutPage extends StatefulWidget {
  final int companyId;

  const CheckoutPage({super.key, required this.companyId});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final supabase = Supabase.instance.client;
  bool _isSubmitting = false;

  Map<String, dynamic>? userData;
  String languageCode = 'ka';
  List<Map<String, dynamic>> _cartItems = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _appliedExtrasList = [];
  double? _adjustedTotal;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    await fetchUser();
    if (userData != null) {
      await fetchCartItems();
      await applyExtras(calculateTotal(), widget.companyId);
    }
    setState(() => _isLoading = false);
  }

  Future<void> fetchUser() async {
    final data = await loadUserData();
    if (mounted) {
      setState(() {
        userData = data;
      });
    }
  }

  Future<void> fetchCartItems() async {
    final int userId = userData!['id'];
    final String lang = languageCode;

    final result = await supabase.rpc(
      'get_cart_details_by_company',
      params: {
        'p_user_id': userId,
        'p_language_code': lang,
        'p_company_id': widget.companyId,
      },
    );
    final List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(
      result,
    );
    setState(() {
      _cartItems = list;
    });
  }

  double calculateTotal() {
    return _cartItems.fold(0.0, (sum, item) {
      final price = (item['price'] as num).toDouble();
      final quantity = item['quantity'] as int;
      return sum + (price * quantity);
    });
  }

  Future<void> applyExtras(double total, int companyId) async {
    try {
      final result = await supabase.rpc(
        'get_applicable_extras',
        params: {'p_company_id': companyId, 'p_total': total},
      );

      final List<Map<String, dynamic>> extrasList =
          List<Map<String, dynamic>>.from(result);

      double adjustedTotal = total;
      List<Map<String, dynamic>> applied = [];

      for (var extra in extrasList) {
        final String type = extra['extras_type'];
        final String discountType = extra['discount_type'];
        final double discountValue =
            double.tryParse(extra['discount_value'].toString()) ?? 0;

        double adjustment = 0;
        if (discountType == 'flat') {
          adjustment = discountValue;
        } else if (discountType == 'percentage') {
          adjustment = total * (discountValue / 100);
        }

        if (type == 'add') {
          adjustedTotal += adjustment;
        } else if (type == 'sub') {
          adjustedTotal -= adjustment;
        }

        applied.add({
          'name': extra['extras_name'],
          'type': type,
          'discount_type': discountType,
          'value': discountValue,
          'adjustment': adjustment,
        });
      }

      setState(() {
        _appliedExtrasList = applied;
        _adjustedTotal = adjustedTotal;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error applying extras: $e')));
    }
  }

  Future<void> confirmOrder() async {
    try {
      final userId = userData!['id'];
      final companyId = widget.companyId;
      final orderNo = generateOrderNumber();
      final total = _adjustedTotal ?? calculateTotal();
      final adjustedTotal = 0;

      // Insert into 'order' table
      final orderInsert = await supabase
          .from('order')
          .insert({
            'user_id': userId,
            'company_id': companyId,
            'order_no': orderNo,
            'order_amount': total,
            'order_adjust_amount': adjustedTotal,
            'order_status': 1,
            'created_by': userId,
          })
          .select('id');

      final orderId = orderInsert.first['id'];

      // Insert into 'order_details' table
      final orderDetailsData = _cartItems.map((item) {
        return {
          'order_id': orderId,
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'price': item['price'] * item['quantity'],
          'created_by': userId,
        };
      }).toList();

      await supabase.from('order_details').insert(orderDetailsData);

      // Insert into 'price_details' table
      List<Map<String, dynamic>> priceDetails = [
        {
          'order_id': orderId,
          'price_component': 'product_total',
          'actual_price': calculateTotal(),
          'adjusted_price': 0,
          'created_by': userId,
        },
      ];

      for (final extra in _appliedExtrasList) {
        priceDetails.add({
          'order_id': orderId,
          'price_component': extra['name'],
          'actual_price': extra['type'] == 'add'
              ? extra['adjustment']
              : -extra['adjustment'],
          'adjusted_price': 0,
          'created_by': userId,
        });
      }

      await supabase.from('price_details').insert(priceDetails);

      await supabase
          .from('cart_items')
          .update({'is_billed': 'yes'})
          .inFilter(
            'product_id',
            _cartItems.map((e) => e['product_id']).toList(),
          )
          .match({'user_id': userId, 'company_id': companyId});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order Confirmed Successfully')),
      );
      // call here for notification
      final db = DBService();

      final users = await db.fetchData(
        table: 'users',
        filters: {"company_id": companyId, "user_type": 2},
        select: "id",
      );

      // ✅ Get template ONCE
      final template = await NotificationHelper().getParsedTemplate(
        templateName: 'Order Placed',
        data: {"customer_name": userData!['full_name'], "order_no": orderNo},
      );
      if (template != null) {
        for (var user in users) {
          await NotificationHelper().sendAndStoreNotification(
            userId: user['id'],
            title: template['subject']!,
            body: template['body']!,
          );
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => OrdersPage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error confirming order: $e')));
    }
  }

  String generateOrderNumber() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(12, (index) {
      final randIndex = DateTime.now().millisecondsSinceEpoch + index;
      return chars[randIndex % chars.length];
    }).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cartItems.isEmpty
          ? const Center(child: Text("No items in cart"))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  const Text(
                    "Order Summary",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Table(
                    columnWidths: const {
                      0: FixedColumnWidth(40),
                      1: FlexColumnWidth(),
                      2: FixedColumnWidth(60),
                      3: FixedColumnWidth(60),
                      4: FixedColumnWidth(80),
                    },
                    border: TableBorder.all(color: Colors.grey.shade300),
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: Color(0xFFEFEFEF)),
                        children: [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              "Sl",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              "Product",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              "Qty",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              "Price",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              "Subtotal",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      ..._cartItems.asMap().entries.map((entry) {
                        final index = entry.key + 1;
                        final item = entry.value;
                        final price = (item['price'] as num).toDouble();
                        final quantity = item['quantity'] as int;
                        final subtotal = price * quantity;

                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(index.toString()),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(item['product_name']),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(quantity.toString()),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(price.toStringAsFixed(2)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(subtotal.toStringAsFixed(2)),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Price Details:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Products Total:"),
                      Text("₹${calculateTotal().toStringAsFixed(2)}"),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._appliedExtrasList.map((extra) {
                    final sign = extra['type'] == 'add' ? '+' : '-';
                    final name = extra['name'];
                    final adj = (extra['adjustment'] as double).toStringAsFixed(
                      2,
                    );
                    final discountType = extra['discount_type'];
                    final discountValue = extra['value'];

                    final discountDisplay = discountType == 'percentage'
                        ? ' (${discountValue.toStringAsFixed(2)}%)'
                        : '';

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$name$discountDisplay'),
                        Text('$sign ₹$adj'),
                      ],
                    );
                  }),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Total",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "₹${_adjustedTotal?.toStringAsFixed(2) ?? '0.00'}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() => _isSubmitting = true);
                    await confirmOrder();
                    setState(() => _isSubmitting = false);
                  },
            child: Text(_isSubmitting ? "Please wait..." : "Confirm Order"),
          ),
        ),
      ),
    );
  }
}
