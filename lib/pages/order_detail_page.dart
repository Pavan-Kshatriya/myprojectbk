import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helper/notification_helper.dart';
import '../services/db_service.dart';
import 'helper/user_data_helper.dart';

class OrderDetailPage extends StatefulWidget {
  final int orderId;
  const OrderDetailPage({super.key, required this.orderId});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _priceComponents = [];
  bool _isLoading = true; // page loader
  bool _isBusy = false; // action loader
  final String _languageCode = 'ka';
  int? _rebillStatus;
  int? _orderStatus;
  String _orderStatusName = '';

  double get totalActualPrice {
    return _priceComponents.fold(0.0, (sum, item) {
      final price = item['actual_price'];
      return sum + (price is num ? price.toDouble() : 0.0);
    });
  }

  @override
  void initState() {
    super.initState();
    fetchOrderSummary();
  }

  Future<void> fetchOrderSummary() async {
    try {
      setState(() => _isLoading = true);

      final List<dynamic> statusData = await supabase
          .from('order_status')
          .select('id, name')
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');

      final Map<int, String> statusMap = {
        for (var s in statusData) s['id'] as int: s['name'] as String,
      };

      final orderData = await supabase
          .from('order')
          .select('order_status, rebill_status')
          .eq('id', widget.orderId)
          .maybeSingle();

      final int? rebillStatus = orderData?['rebill_status'];
      final int? orderStatus = orderData?['order_status'];

      final response = await supabase.rpc(
        'get_order_summary',
        params: {
          'p_order_id': widget.orderId,
          'p_language_code': _languageCode,
        },
      );

      final data = response as Map<String, dynamic>;

      setState(() {
        _products = List<Map<String, dynamic>>.from(data['products'] ?? []);
        _priceComponents = List<Map<String, dynamic>>.from(
          data['price_components'] ?? [],
        );
        _rebillStatus = rebillStatus;
        _orderStatus = orderStatus;
        _orderStatusName = statusMap[orderStatus ?? 0] ?? 'Unknown';
        _isLoading = false;
      });
    } catch (e, stack) {
      print('Error fetching order summary: $e');
      print(stack);
      setState(() => _isLoading = false);
    }
  }

  Future<void> acceptOrder() async {
    setState(() => _isBusy = true);
    try {
      final userData = await loadUserData();
      await supabase
          .from('order')
          .update({
            'order_status': 1,
            'rebill_status': 2,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.orderId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order accepted successfully.')),
      );

      // call here for notification
      final db = DBService();

      final orderData = await db.fetchData(
        table: 'order',
        filters: {"id": widget.orderId},
        select: "user_id,order_no,company_id",
      );
      final order = orderData.isNotEmpty ? orderData.first : null;
      final usersData = await db.fetchData(
        table: 'users',
        filters: {"company_id": order['company_id'], "user_type": 2},
        select: "id",
      );

      final users = usersData.isNotEmpty ? usersData.first : null;

      // ✅ Get template ONCE
      final template = await NotificationHelper().getParsedTemplate(
        templateName: 'Customer Accepted Order',
        data: {
          "customer_name": userData!['full_name'],
          "order_no": order['order_no'],
        },
      );
      if (template != null) {
        if (users != null) {
          await NotificationHelper().sendAndStoreNotification(
            userId: users['id'],
            title: template['subject']!,
            body: template['body']!,
          );
        }
      }

      setState(() {
        _rebillStatus = 2;
        _orderStatusName = 'Accepted';
      });
    } catch (e) {
      print('Error accepting order: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to accept order: $e')));
    } finally {
      setState(() => _isBusy = false);
    }
  }

  void showRejectDialog() {
    final TextEditingController remarkController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reject Order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please enter a remark for rejecting this order:'),
              const SizedBox(height: 10),
              TextField(
                controller: remarkController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter remark...',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final remark = remarkController.text.trim();
                if (remark.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Please enter a remark')),
                  );
                  return;
                }

                final confirm = await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: const Text('Confirm Cancel'),
                    content: const Text(
                      'Are you sure you want to cancel this order?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: const Text('No'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(confirmContext, true),
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  Navigator.pop(dialogContext);
                  await rejectOrder(remark);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> rejectOrder(String remark) async {
    setState(() => _isBusy = true);
    try {
      final userData = await loadUserData();
      final List<dynamic> statusData = await supabase
          .from('order_status')
          .select('id, name')
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');

      final cancelledEntry = statusData.firstWhere(
        (s) =>
            (s['name'] as String).toLowerCase() == 'cancelled' ||
            (s['name'] as String).toLowerCase() == 'rejected',
        orElse: () => {'id': 6, 'name': 'Cancelled'},
      );

      final cancelledId = cancelledEntry['id'];

      await supabase
          .from('order')
          .update({
            'order_status': cancelledId,
            'cancel_remark': remark,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.orderId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order has been cancelled.')),
      );

      // call here for notification
      final db = DBService();

      final orderData = await db.fetchData(
        table: 'order',
        filters: {"id": widget.orderId},
        select: "user_id,order_no,company_id",
      );
      final order = orderData.isNotEmpty ? orderData.first : null;
      final usersData = await db.fetchData(
        table: 'users',
        filters: {"company_id": order['company_id'], "user_type": 2},
        select: "id",
      );

      final users = usersData.isNotEmpty ? usersData.first : null;

      // ✅ Get template ONCE
      final template = await NotificationHelper().getParsedTemplate(
        templateName: 'Customer Rejected Order',
        data: {
          "customer_name": userData!['full_name'],
          "order_no": order['order_no'],
        },
      );
      if (template != null) {
        if (users != null) {
          await NotificationHelper().sendAndStoreNotification(
            userId: users['id'],
            title: template['subject']!,
            body: template['body']!,
          );
        }
      }

      setState(() => _orderStatusName = cancelledEntry['name']);
    } catch (e) {
      print('Error rejecting order: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reject order: $e')));
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Widget buildHeaderRow() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    color: Colors.grey[200],
    child: const Row(
      children: [
        Expanded(
          flex: 1,
          child: Text('Sl. No', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 3,
          child: Text('Product', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 2,
          child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 2,
          child: Text('Price', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 2,
          child: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  Widget buildProductRow(Map<String, dynamic> product, int index) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.grey)),
    ),
    child: Row(
      children: [
        Expanded(flex: 1, child: Text('${index + 1}')),
        Expanded(flex: 3, child: Text(product['product_name'] ?? 'N/A')),
        Expanded(flex: 2, child: Text('${product['quantity'] ?? 0}')),
        Expanded(
          flex: 2,
          child: Text('₹${(product['unit_price'] ?? 0).toStringAsFixed(2)}'),
        ),
        Expanded(
          flex: 2,
          child: Icon(
            product['stock'] == true ? Icons.check : Icons.close,
            color: product['stock'] == true ? Colors.green : Colors.red,
            size: 20,
          ),
        ),
      ],
    ),
  );

  Widget buildPriceComponentRow(Map<String, dynamic> item) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.grey)),
    ),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text(item['price_component'] ?? '-')),
        const Expanded(flex: 2, child: SizedBox()),
        const Expanded(flex: 2, child: SizedBox()),
        Expanded(
          flex: 2,
          child: Text('₹${(item['actual_price'] ?? 0).toStringAsFixed(2)}'),
        ),
      ],
    ),
  );

  Widget buildTotalRow() => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    color: Colors.grey[300],
    child: Row(
      children: [
        const Expanded(
          flex: 3,
          child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Expanded(flex: 2, child: SizedBox()),
        const Expanded(flex: 2, child: SizedBox()),
        Expanded(
          flex: 2,
          child: Text(
            '₹${totalActualPrice.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  Widget buildStatusOrActionRow() {
    if (_orderStatusName.isNotEmpty && _orderStatusName != 'hold') {
      return Center(
        child: ElevatedButton.icon(
          onPressed: null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
          icon: const Icon(Icons.info, color: Colors.white),
          label: Text(
            _orderStatusName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } else {
      if (_rebillStatus == 1) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _isBusy ? null : acceptOrder,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text(
                'Accept',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : showRejectDialog,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.cancel, color: Colors.white),
              label: const Text(
                'Reject',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget buildTable() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      buildHeaderRow(),
      ..._products.asMap().entries.map((entry) {
        final index = entry.key;
        final product = entry.value;
        return buildProductRow(product, index);
      }).toList(),
      if (_priceComponents.isNotEmpty) ...[
        const SizedBox(height: 16),
        ..._priceComponents.map(buildPriceComponentRow).toList(),
        buildTotalRow(),
      ],
      const SizedBox(height: 20),
      buildStatusOrActionRow(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _products.isEmpty && _priceComponents.isEmpty
                  ? const Center(child: Text('No details found.'))
                  : buildTable(),
            ),
          if (_isBusy)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
