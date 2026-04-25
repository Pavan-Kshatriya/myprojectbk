import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_edit_user_page.dart';
import 'helper/notification_helper.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final supabase = Supabase.instance.client;

  List users = [];
  List userTypes = [];

  bool loading = true;

  int? selectedType;
  final searchController = TextEditingController();

  /// Fetch User Types
  Future<void> fetchUserTypes() async {
    final data = await supabase
        .from('user_type')
        .select()
        .eq('is_deleted', 'no');

    setState(() {
      userTypes = data;
    });
  }

  /// Fetch Users
  Future<void> fetchUsers() async {
    setState(() {
      loading = true;
    });

    var query = supabase
        .from('users')
        .select('*, user_type(id,name), company(id,company_name)')
        .eq('is_deleted', 'no');

    /// Filter by user type
    if (selectedType != null) {
      query = query.eq('user_type', selectedType!);
    }

    final data = await query.order('id');

    /// Search filter
    final search = searchController.text.toLowerCase();

    final filtered = data.where((u) {
      final name = (u['full_name'] ?? '').toLowerCase();
      final email = (u['email_id'] ?? '').toLowerCase();
      final mobile = (u['mobile_no'] ?? '').toLowerCase();

      return name.contains(search) ||
          email.contains(search) ||
          mobile.contains(search);
    }).toList();

    setState(() {
      users = filtered;
      loading = false;
    });
  }

  /// Soft Delete
  Future<void> deleteUser(int id) async {
    await supabase.from('users').update({'is_deleted': 'yes'}).eq('id', id);
    await NotificationHelper().deactivateDevice(id);

    fetchUsers();
  }

  @override
  void initState() {
    super.initState();
    fetchUserTypes();
    fetchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Users")),

      /// ADD USER BUTTON
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditUserPage()),
          );

          fetchUsers();
        },
      ),

      body: Column(
        children: [
          /// FILTER SECTION
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                /// SEARCH FIELD
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: "Search User",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) {
                    fetchUsers();
                  },
                ),

                const SizedBox(height: 10),

                /// USER TYPE FILTER
                DropdownButtonFormField<int>(
                  value: selectedType,
                  hint: const Text("Filter by User Type"),
                  items: userTypes.map((type) {
                    return DropdownMenuItem<int>(
                      value: type['id'],
                      child: Text(type['name']),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      selectedType = val;
                    });

                    fetchUsers();
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                /// CLEAR FILTER
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text("Clear Filters"),
                      onPressed: () {
                        setState(() {
                          selectedType = null;
                          searchController.clear();
                        });

                        fetchUsers();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          /// USER LIST
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.grey[300],
                            backgroundImage:
                                user['user_photo'] != null &&
                                    user['user_photo'].toString().isNotEmpty
                                ? NetworkImage(user['user_photo'])
                                : null,
                            child:
                                user['user_photo'] == null ||
                                    user['user_photo'].toString().isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),

                          title: Text(user['full_name'] ?? ''),

                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user['email_id'] ?? ''),
                              Text(user['mobile_no'] ?? ''),
                              Text("Role: ${user['user_type']?['name'] ?? ''}"),

                              /// DISPLAY COMPANY NAME
                              if (user['company'] != null)
                                Text(
                                  "Company: ${user['company']['company_name']}",
                                ),
                            ],
                          ),

                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /// EDIT USER
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddEditUserPage(user: user),
                                    ),
                                  );

                                  fetchUsers();
                                },
                              ),

                              /// DELETE USER
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  deleteUser(user['id']);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
