import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/products_page.dart';
import 'pages/profile_page.dart';
import 'pages/shop_list_page.dart';
import 'pages/my_cart_page.dart';
import 'pages/orders.dart';
import 'pages/shop_orders_page.dart';
import 'pages/users_page.dart';
import 'pages/company_list_page.dart';
import 'pages/main_category_list_page.dart';
import 'pages/product_category_list_page.dart';
import 'pages/product_list_page.dart';
import 'pages/registration_page.dart';
import 'pages/forgot_password_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const supabaseUrl = 'https://elzqxczroumihtclwfms.supabase.co';
const supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVsenF4Y3pyb3VtaWh0Y2x3Zm1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk1NDk2MzQsImV4cCI6MjA3NTEyNTYzNH0.VCoWkEu6k6ByMYnjNzQYCfkwsXUD_8JWZI8oyB6zr3E';
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  // Initialize Supabase
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  final storedUser = prefs.getString('user');
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'custom_sound_channel',
    'Custom Sound Notifications',
    description: 'This channel is used for custom sound',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('alert'),
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  runApp(MyApp(initialUser: storedUser));
}

class MyApp extends StatelessWidget {
  final String? initialUser;

  const MyApp({super.key, this.initialUser});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sidebar Navigation App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: initialUser != null
          ? HomePage(user: jsonDecode(initialUser!))
          : LoginPage(),
      routes: {
        '/products': (context) => ProductsPage(),
        '/users': (context) => UsersPage(),
        '/company_list': (context) => CompanyListPage(),
        '/main_category_list': (context) => const MainCategoryListPage(),
        '/product_category': (context) => ProductCategoryListPage(),
        '/product_list': (context) => ProductListPage(),
        '/profile': (context) => ProfilePage(),
        '/register': (context) => RegisterPage(),
        '/forgot_password': (context) => ForgotPasswordPage(),
        '/shop_list': (context) => ShopListPage(),
        '/my_cart': (context) => MyCartPage(),
        '/orders': (context) => OrdersPage(),
        '/shoporders': (context) => ShopOrdersPage(),
        '/login': (context) => LoginPage(), // for logout redirect
      },
    );
  }
}
