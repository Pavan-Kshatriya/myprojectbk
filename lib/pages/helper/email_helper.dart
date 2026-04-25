import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailHelper {
  static final supabase = Supabase.instance.client;

  /// MAIN FUNCTION
  static Future<bool> sendEmail({
    required String templateName,
    required String toEmail,
    required Map<String, String> variables,
  }) async {
    try {
      /// 1. FETCH EMAIL CONFIG
      final config = await supabase
          .from('email_config')
          .select()
          .eq('is_active', true)
          .maybeSingle();

      if (config == null) {
        throw Exception("Email config not found");
      }

      /// 2. FETCH TEMPLATE
      final template = await supabase
          .from('notification_templates')
          .select()
          .eq('template_name', templateName)
          .eq('is_active', true)
          .maybeSingle();

      if (template == null) {
        throw Exception("Template not found");
      }

      String subject = template['subject'] ?? "";
      String body = template['body'] ?? "";

      /// 3. REPLACE VARIABLES
      variables.forEach((key, value) {
        subject = subject.replaceAll("{{$key}}", value);
        body = body.replaceAll("{{$key}}", value);
      });

      /// 4. SMTP CONFIG
      final smtpServer = SmtpServer(
        config['smtp_host'],
        port: config['smtp_port'],
        username: config['smtp_username'],
        password: config['smtp_password'],
        ssl: false,
        allowInsecure: false,
      );

      /// 5. CREATE MESSAGE
      final message = Message()
        ..from = Address(config['smtp_username'], config['display_name'])
        ..recipients.add(toEmail)
        ..subject = subject
        ..html = body;

      /// 6. SEND EMAIL
      await send(message, smtpServer);

      return true;
    } catch (e) {
      print("Email Error: $e");
      return false;
    }
  }
}
