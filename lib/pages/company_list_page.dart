import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_edit_company_page.dart';

class CompanyListPage extends StatefulWidget {
  const CompanyListPage({super.key});

  @override
  State<CompanyListPage> createState() => _CompanyListPageState();
}

class _CompanyListPageState extends State<CompanyListPage> {
  final supabase = Supabase.instance.client;

  List companies = [];
  bool loading = true;

  Future<void> fetchCompanies() async {
    setState(() {
      loading = true;
    });

    final data = await supabase
        .from('company')
        .select()
        .eq('is_deleted', 'no')
        .order('id');

    setState(() {
      companies = data;
      loading = false;
    });
  }

  Future<void> deleteCompany(int id) async {
    await supabase.from('company').update({'is_deleted': 'yes'}).eq('id', id);

    await supabase
        .from('company_translations')
        .update({'is_deleted': 'yes'})
        .eq('company_id', id);

    fetchCompanies();
  }

  @override
  void initState() {
    super.initState();
    fetchCompanies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Shops")),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditCompanyPage()),
          );

          fetchCompanies();
        },
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: companies.length,
              itemBuilder: (context, index) {
                final company = companies[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                          company['company_image'] != null &&
                              company['company_image'].toString().isNotEmpty
                          ? NetworkImage(company['company_image'])
                          : null,
                      child:
                          company['company_image'] == null ||
                              company['company_image'].toString().isEmpty
                          ? const Icon(Icons.store, size: 28)
                          : null,
                    ),

                    title: Text(company['company_name'] ?? ""),

                    subtitle: Text(
                      company['address'] ?? "",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        /// EDIT
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AddEditCompanyPage(company: company),
                              ),
                            );

                            fetchCompanies();
                          },
                        ),

                        /// DELETE
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            deleteCompany(company['id']);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
