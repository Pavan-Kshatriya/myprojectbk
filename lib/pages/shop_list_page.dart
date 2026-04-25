import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shop_products.dart'; // adjust path if in different folder

import '../widgets/app_drawer.dart';

class ShopListPage extends StatefulWidget {
  const ShopListPage({super.key});

  @override
  State<ShopListPage> createState() => _ShopListPageState();
}

class _ShopListPageState extends State<ShopListPage> {
  late Future<List<Map<String, dynamic>>> _shopsFuture;

  @override
  void initState() {
    super.initState();
    _shopsFuture = fetchShops();
  }

  Future<List<Map<String, dynamic>>> fetchShops() async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('company_translations')
        .select('''
          name,
          address,
          company_id,
          company:company_id (
            company_image,
            status,
            is_deleted
          )
        ''')
        .eq('language_code', 'ka')
        .eq('is_active', 'yes')
        .eq('is_deleted', 'no');

    if (response.isEmpty) {
      return [];
    }

    // Filter out deleted or inactive companies
    final filtered = response.where(
      (item) =>
          item['company'] != null &&
          item['company']['is_deleted'] == 'no' &&
          item['company']['status'] == 'active',
    );

    return filtered.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Shop List')),
      drawer: AppDrawer(),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _shopsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No shops found.'));
          }

          final shops = snapshot.data!;

          return ListView.builder(
            itemCount: shops.length,
            itemBuilder: (context, index) {
              final shop = shops[index];
              final shopName = shop['name'] ?? 'Unnamed';
              final shopAddress = shop['address'] ?? '-';
              final shopImage = shop['company']['company_image'];
              final companyId = shop['company_id'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 4,
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ShopProductsPage(companyId: companyId),
                      ),
                    );
                  },
                  leading: shopImage != null && shopImage.isNotEmpty
                      ? Image.network(
                          shopImage,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.store, size: 40),

                  title: Text(shopName),

                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shopAddress),
                      Text(
                        shop['company']['status'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
