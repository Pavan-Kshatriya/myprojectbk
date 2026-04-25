import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';

class HomePage extends StatelessWidget {
  final Map<String, dynamic> user;

  const HomePage({Key? key, required this.user}) : super(key: key);

  String getRole() {
    if (user['user_type'] == 1) {
      return "Admin";
    } else if (user['user_type'] == 2) {
      return "Shop Owner";
    } else {
      return "Customer";
    }
  }

  List<Map<String, dynamic>> getMenuOptions() {
    int type = user['user_type'];

    if (type == 1) {
      return [
        {"title": "Manage Users", "icon": Icons.people, "route": "/users"},
        {
          "title": "Manage Shops",
          "icon": Icons.store,
          "route": "/company_list",
        },
        {
          "title": "Main Categories",
          "icon": Icons.category,
          "route": "/main_category_list", // ✅ NEW ROUTE
        },
        {
          "title": "Product Categories",
          "icon": Icons.inventory_2,
          "route": "/product_category",
        },
        {
          "title": "Products",
          "icon": Icons.shopping_bag, // 👈 good icon for products
          "route": "/product_list",
        },
        {"title": "Orders", "icon": Icons.shopping_cart, "route": "/orders"},
        {"title": "Reports", "icon": Icons.bar_chart, "route": "/reports"},
      ];
    }

    if (type == 2) {
      return [
        {"title": "My Products", "icon": Icons.inventory, "route": "/products"},
        {"title": "Add Product", "icon": Icons.add_box, "route": "/products"},
        {
          "title": "Orders",
          "icon": Icons.shopping_cart,
          "route": "/shoporders",
        },
        {
          "title": "Earnings",
          "icon": Icons.currency_rupee,
          "route": "/earnings",
        },
      ];
    }

    return [
      {
        "title": "Browse Shops",
        "icon": Icons.storefront,
        "route": "/shop_list",
      },
      {"title": "My Orders", "icon": Icons.shopping_bag, "route": "/orders"},
      {"title": "Wishlist", "icon": Icons.favorite, "route": "/my_cart"},
      {"title": "My Profile", "icon": Icons.person, "route": "/profile"},
    ];
  }

  @override
  Widget build(BuildContext context) {
    List options = getMenuOptions();

    return Scaffold(
      appBar: AppBar(title: Text("Hello ${user['first_name']} 👋")),
      drawer: AppDrawer(),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            /// USER PROFILE CARD
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                          user['user_photo'] != null &&
                              user['user_photo'].toString().isNotEmpty
                          ? NetworkImage(user['user_photo'])
                          : null,
                      child:
                          user['user_photo'] == null ||
                              user['user_photo'].toString().isEmpty
                          ? Icon(Icons.person, size: 35)
                          : null,
                    ),

                    SizedBox(width: 16),

                    Expanded(
                      // ⭐ FIX
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['full_name'] ?? '',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          Text(
                            user['email_id'] ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),

                          Text(
                            user['mobile_no'] ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(height: 5),

                          Chip(label: Text(getRole())),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 25),

            /// DASHBOARD TITLE
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Dashboard",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),

            SizedBox(height: 15),

            /// ROLE BASED OPTIONS
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: options.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
              ),
              itemBuilder: (context, index) {
                var item = options[index];

                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () {
                      // Navigate to respective pages
                      Navigator.pushNamed(context, item['route']);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item['icon'], size: 40, color: Colors.blue),
                        SizedBox(height: 10),
                        Text(
                          item['title'],
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
