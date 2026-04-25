import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import 'helper/user_data_helper.dart';
import 'order_detail_page.dart';
import 'helper/invoice_download_helper.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  bool _isInvoiceProcessing = false; // ✅ Loader flag

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    try {
      final userData = await loadUserData();

      if (userData == null) {
        setState(() => _isLoading = false);
        return;
      }

      final userId = userData['id'];

      final response = await supabase.rpc(
        'get_orders1',
        params: {
          'p_language_code': 'ka',
          'p_user_id': userId,
          'p_company_id': null,
        },
      );

      if (response == null) {
        setState(() => _isLoading = false);
        return;
      }

      if (response is List) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      } else if (response is Map && response.containsKey('data')) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(response['data']);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e, stack) {
      print("Error fetching orders: $e");
      print(stack);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openInvoiceUrl(String urlString) async {
    try {
      final Uri url = Uri.parse(urlString);
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      print("Error launching invoice URL: $e");
    }
  }

  Future<void> _handleInvoiceDownload({
    required BuildContext context,
    required int index,
  }) async {
    setState(() => _isInvoiceProcessing = true);
    try {
      final order = _orders[index];
      final orderId = order['order_id'];
      final orderNo = order['order_no'] ?? 'N/A';
      final companyName = order['company_name'] ?? 'Unknown';
      final totalAmount =
          (order['order_adjust_amount'] ?? order['order_amount'] ?? 0)
              .toDouble();
      final invoiceUrl = order['invoice_url'];

      // ✅ Case 1: Invoice already exists
      if (invoiceUrl != null && invoiceUrl.toString().trim().isNotEmpty) {
        await _openInvoiceUrl(invoiceUrl);
        return;
      }

      // ✅ Case 2: Generate a new invoice
      final response = await supabase.rpc(
        'get_order_summary',
        params: {'p_order_id': orderId, 'p_language_code': 'ka'},
      );

      if (response == null || response is! Map) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to fetch invoice details'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final products = List<Map<String, dynamic>>.from(
        response['products'] ?? [],
      );
      final priceComponents = List<Map<String, dynamic>>.from(
        response['price_components'] ?? [],
      );

      // ✅ Generate invoice PDF & upload
      final newInvoiceUrl = await generateUploadAndSaveInvoicePDF(
        context: context,
        orderId: orderId,
        orderNo: orderNo,
        companyName: companyName,
        totalAmount: totalAmount,
        products: products,
        priceComponents: priceComponents,
      );

      if (newInvoiceUrl != null && newInvoiceUrl.toString().isNotEmpty) {
        // ✅ Save invoice URL to state so it won’t regenerate next time
        setState(() {
          _orders[index]['invoice_url'] = newInvoiceUrl;
        });

        await _openInvoiceUrl(newInvoiceUrl);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate invoice'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      print('Invoice error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _isInvoiceProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AbsorbPointer(
          // ✅ Prevent user actions when loader active
          absorbing: _isInvoiceProcessing,
          child: Scaffold(
            appBar: AppBar(title: const Text('My Orders')),
            drawer: const AppDrawer(),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                ? const Center(child: Text('No orders found.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      final orderStatus = (order['order_status_name'] ?? '')
                          .toString()
                          .toLowerCase();
                      final isCompleted =
                          orderStatus.contains('completed') ||
                          orderStatus.contains('complete');

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            final orderId = order['order_id'];
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    OrderDetailPage(orderId: orderId),
                              ),
                            ).then((_) => fetchOrders());
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order No: ${order['order_no'] ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  order['company_name'] ?? 'No Company',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Amount: ₹${order['order_amount']?.toStringAsFixed(2) ?? '0.00'}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    Text(
                                      order['order_status_name'] ?? 'Unknown',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((order['order_adjust_amount'] ?? 0) > 0 &&
                                    order['order_adjust_amount'] !=
                                        order['order_amount'])
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      'Updated Amount: ₹${order['order_adjust_amount'].toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      order['created_at'] != null
                                          ? DateTime.parse(order['created_at'])
                                                .toLocal()
                                                .toString()
                                                .split(".")
                                                .first
                                          : 'No Date',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (isCompleted)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.download),
                                      label: const Text('Download Invoice'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _handleInvoiceDownload(
                                        context: context,
                                        index: index,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),

        // ✅ Loader Overlay (blocks UI fully)
        if (_isInvoiceProcessing)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 14),
                  Text(
                    'Processing invoice...',
                    style: TextStyle(color: Colors.white, fontSize: 17),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
