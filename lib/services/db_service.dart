import 'package:supabase_flutter/supabase_flutter.dart';

class DBService {
  final supabase = Supabase.instance.client;

  Future<List<dynamic>> fetchData({
    required String table,
    Map<String, dynamic>? filters,
    String? select,
  }) async {
    try {
      final selectedFields = (select == null || select.isEmpty) ? '*' : select;

      var query = supabase.from(table).select(selectedFields);

      if (filters != null && filters.isNotEmpty) {
        filters.forEach((key, value) {
          query = query.eq(key, value);
        });
      }

      final response = await query;
      return response;
    } catch (e) {
      print("Error fetching data from $table: $e");
      return [];
    }
  }
}
