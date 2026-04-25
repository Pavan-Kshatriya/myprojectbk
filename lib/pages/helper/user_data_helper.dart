import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

Future<Map<String, dynamic>?> loadUserData() async {
  final prefs = await SharedPreferences.getInstance();
  final String? userJson = prefs.getString('user');

  if (userJson != null) {
    return jsonDecode(userJson);
  } else {
    print('No user data found in local storage');
    return null;
  }
}
