import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helper/user_data_helper.dart';
import 'helper/notification_helper.dart';
import '../services/db_service.dart';

class ShopOrderDetailPage extends StatefulWidget {
  final int orderId;
  const ShopOrderDetailPage({super.key, required this.orderId});

  @override
  State<ShopOrderDetailPage> createState() => _ShopOrderDetailPageState();
}

class _ShopOrderDetailPageState extends State<ShopOrderDetailPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _priceComponents = [];
  bool _isLoading = true;
  bool _isBusy = false;
  final String _languageCode = 'ka';
  Map<String, dynamic>? userData;

  Map<int, String> _orderStatusMap = {}; // id → name mapping
  int? _orderStatusId; // current order status id
  int? _rebillStatus;
  String _orderStatusName = ''; // readable name
  double get totalActualPrice {
    return _priceComponents.fold(0.0, (sum, item) {
      final price = item['actual_price'];
      return sum + (price is num ? price.toDouble() : 0.0);
    });
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    await fetchUser();
    await fetchOrderSummary();
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

  Future<void> fetchOrderSummary() async {
    try {
      // 1️⃣ Fetch available statuses
      final List<dynamic> statusData = await supabase
          .from('order_status')
          .select('id, name')
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');

      final Map<int, String> statusMap = {
        for (var s in statusData)
          s['id'] as int: s['name'] as String, // ✅ Use exact DB name
      };

      // 2️⃣ Get order’s current status and rebill status
      final orderData = await supabase
          .from('order')
          .select('order_status, rebill_status')
          .eq('id', widget.orderId)
          .maybeSingle();

      final int? statusId = orderData?['order_status'];
      final int? rebillStatus = orderData?['rebill_status'];

      final String statusName = statusMap[statusId ?? 0] ?? '';

      // 3️⃣ Fetch order details summary via RPC
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
        _orderStatusMap = statusMap;
        _orderStatusId = statusId;
        _rebillStatus = rebillStatus;
        _orderStatusName = statusName;
      });
    } catch (e, stack) {
      print('Error fetching order summary: $e');
      print(stack);
    }
  }

  void showLoader() {
    if (mounted) setState(() => _isBusy = true);
  }

  void hideLoader() {
    if (mounted) setState(() => _isBusy = false);
  }

  void handleStockToggle(int productId, bool newStockValue) async {
    showLoader();
    try {
      setState(() {
        final index = _products.indexWhere((p) => p['detail_id'] == productId);
        if (index != -1) {
          _products[index]['stock'] = newStockValue;
        }
      });

      await supabase
          .from('order_details')
          .update({
            'stock': newStockValue,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', productId);

      await recalculateBill();
    } catch (e) {
      print('Error updating stock: $e');
    } finally {
      hideLoader();
    }
  }

  Future<void> recalculateBill() async {
    showLoader();
    try {
      // Step 1: Soft-delete old price details
      await supabase
          .from('price_details')
          .update({
            'is_deleted': 'yes',
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('order_id', widget.orderId);

      final int companyId = userData!['company_id'];
      final int userId = userData!['id'];

      // Step 2: Get total product price
      final response = await supabase.rpc(
        'get_total_order_price',
        params: {'p_order_id': widget.orderId},
      );
      final double productTotal = ((response ?? 0) as num).toDouble();

      // Step 3: Fetch extras
      final List<dynamic> appliedExtrasList = await supabase.rpc(
        'get_applicable_extras',
        params: {'p_company_id': companyId, 'p_total': productTotal},
      );

      // Step 4: Prepare price details
      List<Map<String, dynamic>> priceDetails = [
        {
          'order_id': widget.orderId,
          'price_component': 'product_total',
          'actual_price': productTotal,
          'adjusted_price': 0,
          'created_by': userId,
        },
      ];

      double totalAdjustmentAmount = 0.0;

      for (final extra in appliedExtrasList) {
        final String name = extra['extras_name'];
        final String type = extra['extras_type']; // add/sub
        final String discountType = extra['discount_type']; // percentage/flat
        final double discountValue = (extra['discount_value'] ?? 0).toDouble();

        double adjustment = 0;

        if (discountType == 'percentage') {
          adjustment = (productTotal * discountValue) / 100;
        } else if (discountType == 'flat') {
          adjustment = discountValue;
        }

        if (type == 'sub') adjustment = -adjustment;

        totalAdjustmentAmount += adjustment;

        priceDetails.add({
          'order_id': widget.orderId,
          'price_component': name,
          'actual_price': adjustment,
          'adjusted_price': 0,
          'created_by': userId,
        });
      }

      await supabase.from('price_details').insert(priceDetails);

      // Step 6: Check product stock
      final stockFalse = await supabase
          .from('order_details')
          .select('stock')
          .eq('order_id', widget.orderId)
          .eq('stock', false)
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');

      final stockTrue = await supabase
          .from('order_details')
          .select('stock')
          .eq('order_id', widget.orderId)
          .eq('stock', true)
          .eq('is_active', 'yes')
          .eq('is_deleted', 'no');

      // Step 7: Identify partial/complete/pending IDs dynamically
      int idForHold = _orderStatusMap.entries
          .firstWhere(
            (e) => e.value.toLowerCase().contains('hold'),
            orElse: () => const MapEntry(0, ''),
          )
          .key;

      int idForCancelled = _orderStatusMap.entries
          .firstWhere(
            (e) => e.value.toLowerCase().contains('cancelled'),
            orElse: () => const MapEntry(0, ''),
          )
          .key;

      int idForPending = _orderStatusMap.entries
          .firstWhere(
            (e) => e.value.toLowerCase().contains('pending'),
            orElse: () => const MapEntry(0, ''),
          )
          .key;

      int newStatusId;
      if (stockFalse.isNotEmpty && stockTrue.isNotEmpty) {
        newStatusId = idForHold;
      } else if (stockTrue.isEmpty) {
        newStatusId = idForCancelled;
      } else {
        newStatusId = idForPending;
      }

      // Step 8: Final amount
      final double finalOrderAmount = productTotal + totalAdjustmentAmount;

      // Step 9: Update order
      await supabase
          .from('order')
          .update({
            'order_adjust_amount': finalOrderAmount,
            'order_status': newStatusId,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.orderId);

      // Step 10: Refresh UI
      await fetchOrderSummary();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bill recalculated successfully.\n'
            'Product Total: ₹${productTotal.toStringAsFixed(2)} | '
            'Adjustments: ₹${totalAdjustmentAmount.toStringAsFixed(2)} | '
            'Final: ₹${finalOrderAmount.toStringAsFixed(2)} | '
            'Status: ${_orderStatusName.toUpperCase()}',
          ),
        ),
      );
    } catch (e, stack) {
      print('Error recalculating bill: $e');
      print(stack);
    } finally {
      hideLoader();
    }
  }

  Future<void> acceptOrder() async {
    showLoader();
    try {
      final acceptedId = _orderStatusMap.entries
          .firstWhere(
            (e) => e.value.toLowerCase().contains('accept'),
            orElse: () => const MapEntry(0, ''),
          )
          .key;

      await supabase
          .from('order')
          .update({
            'order_status': acceptedId,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.orderId);

      setState(() => _orderStatusName = _orderStatusMap[acceptedId] ?? '');
      setState(() => _orderStatusId = acceptedId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order accepted successfully.')),
      );

      // call here for notification
      final db = DBService();
      final orderData = await db.fetchData(
        table: 'order',
        filters: {"id": widget.orderId},
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
          templateName: 'Order Accept',
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
    } catch (e) {
      print('Error accepting order: $e');
    } finally {
      hideLoader();
    }
  }

  Future<void> rejectOrder(String remark) async {
    showLoader();
    try {
      final cancelledId = _orderStatusMap.entries
          .firstWhere(
            (e) =>
                e.value.toLowerCase().contains('cancel') ||
                e.value.toLowerCase().contains('reject'),
            orElse: () => const MapEntry(0, ''),
          )
          .key;

      await supabase
          .from('order')
          .update({
            'order_status': cancelledId,
            'cancel_remark': remark,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.orderId);

      setState(() => _orderStatusName = _orderStatusMap[cancelledId] ?? '');
      setState(() => _orderStatusId = cancelledId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order has been cancelled.')),
      );

      // call here for notification
      final db = DBService();
      final orderData = await db.fetchData(
        table: 'order',
        filters: {"id": widget.orderId},
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
          templateName: 'Order Cancelled',
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
    } catch (e) {
      print('Error rejecting order: $e');
    } finally {
      hideLoader();
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
                  rejectOrder(remark);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> confirmAndUpdateOrder() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Update'),
        content: const Text(
          'Are you sure you want to update the stock? Once updated, you cannot alter the order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await supabase
          .from('order')
          .update({
            'rebill_status': 1,
            'modified_on': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.orderId);
      setState(() => _rebillStatus = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated stock to customer.')),
      );

      // call here for notification
      final db = DBService();
      final orderData = await db.fetchData(
        table: 'order',
        filters: {"id": widget.orderId},
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
          templateName: 'Order Partial',
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
    }
  }

  // HEADER ROW
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

  Widget buildProductRow(Map<String, dynamic> product, int index) {
    return Container(
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
            child:
                ((_rebillStatus != null && _rebillStatus! > 0) ||
                    (_orderStatusId != null &&
                        [3, 4, 5, 6].contains(_orderStatusId)))
                ? Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(disabledColor: Colors.grey),
                    child: Checkbox(
                      value: product['stock'] == true,
                      onChanged: null,
                    ),
                  )
                : Checkbox(
                    value: product['stock'] == true,
                    onChanged: (bool? newValue) {
                      if (newValue != null)
                        handleStockToggle(product['detail_id'], newValue);
                    },
                    checkColor: Colors.white,
                    activeColor: Colors.green,
                  ),
          ),
        ],
      ),
    );
  }

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

  Widget buildActionButtonsRow() {
    final currentStatusId = _orderStatusId;

    final acceptedId = _orderStatusMap.entries
        .firstWhere(
          (e) => e.value.toLowerCase().contains('accept'),
          orElse: () => const MapEntry(0, ''),
        )
        .key;

    final cancelledId = _orderStatusMap.entries
        .firstWhere(
          (e) =>
              e.value.toLowerCase().contains('cancel') ||
              e.value.toLowerCase().contains('reject'),
          orElse: () => const MapEntry(0, ''),
        )
        .key;

    final pendingId = _orderStatusMap.entries
        .firstWhere(
          (e) => e.value.toLowerCase().contains('pending'),
          orElse: () => const MapEntry(0, ''),
        )
        .key;
    final readyId = _orderStatusMap.entries
        .firstWhere(
          (e) => e.value.toLowerCase().contains('ready'),
          orElse: () => const MapEntry(0, ''),
        )
        .key;
    final completedId = _orderStatusMap.entries
        .firstWhere(
          (e) => e.value.toLowerCase().contains('completed'),
          orElse: () => const MapEntry(0, ''),
        )
        .key;

    final isAccepted = currentStatusId == acceptedId;
    final isCancelled = currentStatusId == cancelledId;
    final isPending = currentStatusId == pendingId;
    final isReady = currentStatusId == readyId;
    final isCompleted = currentStatusId == completedId;

    if (isAccepted) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          icon: const Icon(Icons.check_circle, color: Colors.white),
          label: Text(
            _orderStatusName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (isCancelled) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          icon: const Icon(Icons.cancel, color: Colors.white),
          label: Text(
            _orderStatusName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    if (isReady) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          icon: const Icon(Icons.hourglass_bottom, color: Colors.white),
          label: Text(
            _orderStatusName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    if (isCompleted) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          icon: const Icon(Icons.check_circle, color: Colors.white),
          label: Text(
            _orderStatusName,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: (isPending) ? acceptOrder : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          icon: const Icon(Icons.check_circle, color: Colors.white),
          label: const Text('Accept', style: TextStyle(color: Colors.white)),
        ),
        ElevatedButton.icon(
          onPressed: showRejectDialog,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          icon: const Icon(Icons.cancel, color: Colors.white),
          label: const Text('Reject', style: TextStyle(color: Colors.white)),
        ),
        ElevatedButton.icon(
          onPressed:
              (isPending || (_rebillStatus != null && _rebillStatus! > 0))
              ? null
              : confirmAndUpdateOrder,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          icon: const Icon(Icons.update, color: Colors.white),
          label: const Text('Update', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
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
        const SizedBox(height: 20),
        buildActionButtonsRow(),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _products.isEmpty && _priceComponents.isEmpty
                      ? const Center(child: Text('No details found.'))
                      : buildTable(),
                ),
          if (_isBusy)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
