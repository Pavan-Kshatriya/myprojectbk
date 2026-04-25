import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/home_page.dart';
import 'dart:convert';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString('user');

    if (storedUser != null) {
      setState(() {
        user = jsonDecode(storedUser);
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');

    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _goHome(BuildContext context) async {
    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(user: user!)),
      );
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Widget menuItem(IconData icon, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.deepPurple.withOpacity(0.1),
          child: Icon(icon, color: Colors.deepPurple, size: 18),
        ),
        title: Text(title),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          /// 🔥 HEADER WITH USER INFO
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff6a11cb), Color(0xff2575fc)],
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      user != null &&
                          user!['user_photo'] != null &&
                          user!['user_photo'] != ""
                      ? NetworkImage(user!['user_photo'])
                      : null,
                  child: user == null || user!['user_photo'] == null
                      ? const Icon(Icons.person, size: 30)
                      : null,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?['full_name'] ?? "Guest User",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        user?['email_id'] ?? "",
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          /// MENU ITEMS
          Expanded(
            child: ListView(
              children: [
                menuItem(Icons.home, "Home", () => _goHome(context)),

                menuItem(
                  Icons.shopping_bag,
                  "Products",
                  () => Navigator.pushReplacementNamed(context, '/products'),
                ),

                menuItem(
                  Icons.store,
                  "Shops",
                  () => Navigator.pushReplacementNamed(context, '/shop_list'),
                ),

                menuItem(
                  Icons.shopping_cart,
                  "My Cart",
                  () => Navigator.pushReplacementNamed(context, '/my_cart'),
                ),

                menuItem(
                  Icons.receipt_long,
                  "My Orders",
                  () => Navigator.pushReplacementNamed(context, '/orders'),
                ),

                menuItem(
                  Icons.storefront,
                  "Shop Orders",
                  () => Navigator.pushReplacementNamed(context, '/shoporders'),
                ),

                menuItem(
                  Icons.person,
                  "Profile",
                  () => Navigator.pushReplacementNamed(context, '/profile'),
                ),

                const Divider(height: 30),

                /// LOGOUT
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.redAccent,
                      child: Icon(Icons.logout, color: Colors.white, size: 18),
                    ),
                    title: const Text(
                      "Logout",
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () => _logout(context),
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
