import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_drawer.dart';
import 'helper/user_data_helper.dart';
import 'shop_order_detail_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'helper/notification_helper.dart';
import '../services/db_service.dart';

class ShopOrdersPage extends StatefulWidget {
  const ShopOrdersPage({super.key});

  @override
  State<ShopOrdersPage> createState() => _ShopOrdersPageState();
}

class _ShopOrdersPageState extends State<ShopOrdersPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _statuses = [];
  bool _isLoading = true;
  bool _isStatusLoading = true;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    await Future.wait([fetchStatuses(), fetchOrders()]);
  }

  Future<void> fetchStatuses() async {
    try {
      final response = await supabase
          .from('order_status')
          .select('id, name')
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');

      setState(() {
        _statuses = List<Map<String, dynamic>>.from(response);
        _isStatusLoading = false;
      });
    } catch (e) {
      print('Error fetching statuses: $e');
      setState(() => _isStatusLoading = false);
    }
  }

  Future<void> fetchOrders() async {
    try {
      final userData = await loadUserData();

      if (userData == null) {
        setState(() => _isLoading = false);
        return;
      }

      final companyId = userData['company_id'] ?? 0;

      final response = await supabase.rpc(
        'get_orders',
        params: {
          'p_language_code': 'ka',
          'p_user_id': null,
          'p_company_id': companyId,
        },
      );

      if (response is List) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error fetching orders: $e");
      setState(() => _isLoading = false);
    }
  }

  String cleanPhoneNumber(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91$digits';
    return '+$digits';
  }

  Future<void> updateOrderStatus(int orderId, int newStatusId) async {
    try {
      final templatename = newStatusId == 4 ? "Order Ready" : "Order Completed";
      final userData = await loadUserData();
      await supabase
          .from('order')
          .update({'order_status': newStatusId})
          .eq('id', orderId);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Order status updated')));

      // call here for notification
      final db = DBService();
      final orderData = await db.fetchData(
        table: 'order',
        filters: {"id": orderId},
        select: "user_id,order_no",
      );

      final shopData = await db.fetchData(
        table: 'company',
        filters: {"id": userData!['company_id']},
        select: "company_name",
      );
      final company = shopData.isNotEmpty ? shopData.first : null;
      final order = orderData.isNotEmpty ? orderData.first : null;
      if (order != null) {
        // ✅ Get template ONCE
        final template = await NotificationHelper().getParsedTemplate(
          templateName: templatename,
          data: {
            "shop_name": company['company_name'],
            "order_no": order['order_no'],
          },
        );
        if (template != null) {
          await NotificationHelper().sendAndStoreNotification(
            userId: order['user_id'],
            title: template['subject']!,
            body: template['body']!,
          );
        }
      }

      fetchOrders();
    } catch (e) {
      print('Error updating status: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to update status')));
    }
  }

  Widget buildOrderCard(Map<String, dynamic> order, BuildContext context) {
    final orderId = order['order_id'];
    final currentStatusId = order['order_status_id'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShopOrderDetailPage(orderId: orderId),
            ),
          ).then((_) => fetchOrders());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row with order no + View Details button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order No: ${order['order_no'] ?? 'N/A'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              Text(
                order['user_full_name'] ?? 'Unknown User',
                style: const TextStyle(fontSize: 16),
              ),
              GestureDetector(
                onTap: () {
                  final rawPhone = order['user_mobile_no'];
                  if (rawPhone != null && rawPhone.toString().isNotEmpty) {
                    final cleanedPhone = cleanPhoneNumber(rawPhone);
                    launchUrl(Uri.parse('tel:$cleanedPhone'));
                  }
                },
                child: Text(
                  order['user_mobile_no'] ?? 'No Mobile',
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Amount: ₹${order['order_amount']?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  // ✅ Dropdown for Status
                  _isStatusLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : AbsorbPointer(
                          absorbing:
                              order['order_status_name'] ==
                              'Completed', // disable entire dropdown after completed
                          child: DropdownButton<int>(
                            value: currentStatusId,
                            items: _statuses.map((status) {
                              final String name = status['name']
                                  .toString()
                                  .toLowerCase();

                              // Define disabled statuses
                              final bool isDisabled = [
                                'pending',
                                'hold',
                                'accepted',
                                'cancelled',
                              ].contains(name);

                              // Only ready → completed allowed logic
                              final bool canSelectReady =
                                  name == 'ready' &&
                                  order['order_status_name']
                                          .toString()
                                          .toLowerCase() ==
                                      'accepted';
                              final bool canSelectCompleted =
                                  name == 'completed' &&
                                  order['order_status_name']
                                          .toString()
                                          .toLowerCase() ==
                                      'ready';

                              // Determine if item should be selectable
                              final bool selectable =
                                  !isDisabled &&
                                  (canSelectReady ||
                                      canSelectCompleted ||
                                      name ==
                                          order['order_status_name']
                                              .toString()
                                              .toLowerCase());

                              return DropdownMenuItem<int>(
                                value: status['id'],
                                enabled:
                                    selectable, // disable item if not allowed
                                child: Text(
                                  status['name'],
                                  style: TextStyle(
                                    color: selectable
                                        ? Colors.black
                                        : Colors.grey,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              if (value != null) {
                                final selectedStatus = _statuses
                                    .firstWhere((s) => s['id'] == value)['name']
                                    .toString()
                                    .toLowerCase();

                                final currentStatus = order['order_status_name']
                                    .toString()
                                    .toLowerCase();

                                // Enforce ready → completed transition
                                if (currentStatus == 'accepted' &&
                                    selectedStatus == 'ready') {
                                  await updateOrderStatus(orderId, value);
                                } else if (currentStatus == 'ready' &&
                                    selectedStatus == 'completed') {
                                  await updateOrderStatus(orderId, value);
                                }
                              }
                            },
                          ),
                        ),
                ],
              ),

              if ((order['order_adjust_amount'] ?? 0) > 0 &&
                  order['order_adjust_amount'] != order['order_amount'])
                Text(
                  'Updated Amount: ₹${order['order_adjust_amount'].toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    order['created_at'] != null
                        ? DateTime.parse(
                            order['created_at'],
                          ).toLocal().toString().split(".").first
                        : 'No Date',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop Orders')),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
          ? const Center(child: Text('No orders found.'))
          : ListView.builder(
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                return buildOrderCard(_orders[index], context);
              },
            ),
    );
  }
}
