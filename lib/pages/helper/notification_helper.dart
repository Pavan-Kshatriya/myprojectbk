import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  factory NotificationHelper() => _instance;

  NotificationHelper._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final supabase = Supabase.instance.client;

  String? fcmToken;

  // =========================================================
  // 🔹 MAIN FUNCTION → Call this AFTER LOGIN
  // =========================================================
  Future<void> init(int userId) async {
    try {
      // ✅ Step 1: Request Permission
      await _requestPermission();

      // ✅ Step 2: Get Token
      await _getAndStoreToken(userId);

      // ✅ Step 3: Listen for Token Refresh
      _listenTokenRefresh(userId);

      // ✅ Step 4: Notification Listeners
      _initForegroundListener();
      _handleNotificationClick();
      await _checkInitialMessage();
    } catch (e) {
      print("Error initializing notifications: $e");
    }
  }

  // =========================================================
  // 🔹 PERMISSION
  // =========================================================
  Future<void> _requestPermission() async {
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print("Permission status: ${settings.authorizationStatus}");
  }

  // =========================================================
  // 🔹 GET TOKEN + STORE
  // =========================================================
  Future<void> _getAndStoreToken(int userId) async {
    fcmToken = await _messaging.getToken();

    print("fcmdata=$fcmToken");

    if (fcmToken != null) {
      await _upsertToken(userId, fcmToken!);
    }
  }

  // =========================================================
  // 🔹 TOKEN REFRESH LISTENER
  // =========================================================
  void _listenTokenRefresh(int userId) {
    _messaging.onTokenRefresh.listen((newToken) async {
      fcmToken = newToken;
      await _upsertToken(userId, newToken);
    });
  }

  // =========================================================
  // 🔹 UPSERT TOKEN (SUPABASE)
  // =========================================================
  Future<void> _upsertToken(int userId, String token) async {
    try {
      // ✅ Step 1: Remove token from any existing row
      await supabase.from('user_device_tokens').delete().eq('fcm_token', token);

      // ✅ Step 2: Insert/Update based on user_id
      await supabase.from('user_device_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'device_type': _getDeviceType(),
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      print("✅ Token stored/updated successfully");
    } catch (e) {
      print("❌ Error saving token: $e");
    }
  }

  // =========================================================
  // 🔹 DEVICE TYPE (DYNAMIC)
  // =========================================================
  String _getDeviceType() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }

  // =========================================================
  // 🔹 FOREGROUND NOTIFICATION
  // =========================================================
  void _initForegroundListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Foreground Notification:");
      print("Title: ${message.notification?.title}");
      print("Body: ${message.notification?.body}");
    });
  }

  // =========================================================
  // 🔹 CLICK HANDLER (BACKGROUND)
  // =========================================================
  void _handleNotificationClick() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("Notification Clicked (Background)");
      _handleNavigation(message);
    });
  }

  // =========================================================
  // 🔹 TERMINATED STATE HANDLER
  // =========================================================
  Future<void> _checkInitialMessage() async {
    RemoteMessage? message = await _messaging.getInitialMessage();

    if (message != null) {
      print("App opened from terminated state");
      _handleNavigation(message);
    }
  }

  // =========================================================
  // 🔹 NAVIGATION HANDLER (CUSTOMIZE THIS)
  // =========================================================
  void _handleNavigation(RemoteMessage message) {
    // Example:
    // String? screen = message.data['screen'];

    print("Navigate based on payload: ${message.data}");
  }

  // =========================================================
  // 🔹 LOGOUT → DEACTIVATE TOKEN
  // =========================================================
  Future<void> deactivateDevice(int userId) async {
    try {
      // if (fcmToken == null) {
      //   fcmToken = await _messaging.getToken();
      // }

      if (fcmToken != null) {
        await supabase
            .from('user_device_tokens')
            .update({
              'is_active': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', userId);

        print("Token deactivated");
      }
    } catch (e) {
      print("Error deactivating token: $e");
    }
  }

  Future<void> saveNotification({
    required int userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'data': data ?? {},
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      print("Notification saved");
    } catch (e) {
      print("Error saving notification: $e");
    }
  }

  Future<void> sendPushNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      const String serverKey =
          "cd440939a1fd80aeaa605b0c2fce1e917b4b30b7"; // ⚠️ replace

      final response = await http.post(
        Uri.parse(
          "https://fcm.googleapis.com/v1/projects/my-cart-zone/messages:send",
        ),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "key=$serverKey",
        },
        body: jsonEncode({
          "to": token,
          "notification": {"title": title, "body": body},
          "data": data ?? {},
          "priority": "high",
        }),
      );

      print("fcmresponse=$response");

      if (response.statusCode == 200) {
        print("Push sent");
      } else {
        print("Push failed: ${response.body}");
      }
    } catch (e) {
      print("Error sending push: $e");
    }
  }

  Future<void> sendNotificationToUser({
    required int userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final tokens = await supabase
          .from('user_device_tokens')
          .select('fcm_token')
          .eq('user_id', userId)
          .eq('is_active', true);

      print("Tokens: $tokens");

      for (var item in tokens) {
        try {
          final res = await supabase.functions.invoke(
            'send-push-v1', // ✅ use correct function
            body: {
              "token": item['fcm_token'],
              "title": title,
              "body": body,
              "sound": "alert",
            },
          );

          print("Response: ${res.data}");
        } catch (e) {
          print("Error for token ${item['fcm_token']}: $e");
        }
      }
    } catch (e, stack) {
      print("Main Error: $e");
      print("Stacktrace: $stack");
    }
  }

  Future<void> sendAndStoreNotification({
    required int userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // 1️⃣ Save in DB
      await saveNotification(
        userId: userId,
        title: title,
        body: body,
        data: data,
      );

      // 2️⃣ Send Push
      await sendNotificationToUser(
        userId: userId,
        title: title,
        body: body,
        data: data,
      );

      print("Notification processed");
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<List<dynamic>> getNotifications(int userId) async {
    try {
      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return response;
    } catch (e) {
      print("Error fetching notifications: $e");
      return [];
    }
  }

  Future<void> markAsRead(int notificationId) async {
    try {
      await supabase
          .from('notifications')
          .update({
            'is_read': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId);

      print("Marked as read");
    } catch (e) {
      print("Error updating: $e");
    }
  }

  Future<Map<String, String>?> getParsedTemplate({
    required String templateName,
    required Map<String, dynamic> data,
  }) async {
    try {
      // ✅ Fetch template
      final res = await supabase
          .from('notification_templates')
          .select('subject, body')
          .eq('template_name', templateName)
          .eq('is_active', true)
          .single();

      final subjectTemplate = res['subject'] ?? '';
      final bodyTemplate = res['body'] ?? '';

      // ✅ Replace variables
      String parseTemplate(String template, Map<String, dynamic> data) {
        return template.replaceAllMapped(RegExp(r"\{\{(.*?)\}\}"), (match) {
          final key = match.group(1)!.trim();
          return data[key]?.toString() ?? '';
        });
      }

      final subject = parseTemplate(subjectTemplate, data);
      final body = parseTemplate(bodyTemplate, data);

      // ✅ Return result
      return {"subject": subject, "body": body};
    } catch (e) {
      print("Error fetching template: $e");
      return null;
    }
  }
}
