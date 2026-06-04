import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../widgets/app_drawer.dart';
import 'helper/user_data_helper.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();

  Map<String, dynamic>? userData;
  List<Map<String, dynamic>> userAddresses = [];

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  // ================= LOAD PROFILE =================
  Future<void> loadProfile() async {
    final data = await loadUserData();
    if (data == null) return;

    final userId = data['id'];

    final user = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .single();

    final addresses = await supabase
        .from('user_addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false);

    setState(() {
      userData = user;
      _firstName.text = user['first_name'] ?? '';
      _middleName.text = user['middle_name'] ?? '';
      _lastName.text = user['last_name'] ?? '';
      _mobile.text = user['mobile_no'] ?? '';
      _email.text = user['email_id'] ?? '';
      userAddresses = List<Map<String, dynamic>>.from(addresses);
      _loading = false;
    });
  }

  // ================= SAVE PROFILE =================
  Future<void> saveProfile() async {
    if (_firstName.text.isEmpty ||
        _mobile.text.isEmpty ||
        _email.text.isEmpty) {
      _snack("Required fields cannot be empty");
      return;
    }

    setState(() => _saving = true);

    await supabase
        .from('users')
        .update({
          'first_name': _firstName.text.trim(),
          'middle_name': _middleName.text.trim(),
          'last_name': _lastName.text.trim(),
          'mobile_no': _mobile.text.trim(),
          'email_id': _email.text.trim(),
          'full_name':
              "${_firstName.text} ${_middleName.text} ${_lastName.text}".trim(),
        })
        .eq('id', userData!['id']);

    setState(() => _saving = false);
    _snack("Profile updated successfully");
  }

  // ================= SET DEFAULT ADDRESS =================
  Future<void> setDefaultAddress(int addressId) async {
    final userId = userData!['id'];

    await supabase
        .from('user_addresses')
        .update({'is_default': false})
        .eq('user_id', userId);

    await supabase
        .from('user_addresses')
        .update({'is_default': true})
        .eq('id', addressId);

    _snack("Default address updated");
    loadProfile();
  }

  // ================= LOCATION =================
  Future<Map<String, double>?> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    return {'lat': pos.latitude, 'lng': pos.longitude};
  }

  // ================= REVERSE GEOCODE =================
  Future<Map<String, String>?> reverseGeocode(double lat, double lng) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json',
    );

    final res = await http.get(url, headers: {'User-Agent': 'FlutterApp'});

    if (res.statusCode == 200) {
      final a = jsonDecode(res.body)['address'] ?? {};
      return {
        'line1': "${a['house_number'] ?? ''} ${a['road'] ?? ''}".trim(),
        'landmark': a['neighbourhood'] ?? '',
        'city': a['city'] ?? a['town'] ?? a['village'] ?? '',
        'state': a['state'] ?? '',
        'pincode': a['postcode'] ?? '',
      };
    }
    return null;
  }

  // ================= ADDRESS → COORDS =================
  Future<String> addressToCoordinates(String address) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(address)}&format=json&limit=1',
    );

    final res = await http.get(url, headers: {'User-Agent': 'FlutterApp'});

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data.isNotEmpty) {
        return "${data[0]['lat']},${data[0]['lon']}";
      }
    }
    return "";
  }

  // ================= ADD / EDIT ADDRESS =================
  Future<void> addOrEditAddress({Map<String, dynamic>? address}) async {
    final isEdit = address != null;

    final l1 = TextEditingController(text: address?['address_line1']);
    final l2 = TextEditingController(text: address?['address_line2']);
    final lm = TextEditingController(text: address?['landmark']);
    final city = TextEditingController(text: address?['city']);
    final state = TextEditingController(text: address?['state']);
    final pin = TextEditingController(text: address?['pincode']);

    bool useLocation = false;
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text(
                  isEdit ? "Edit Address" : "Add Address",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _field(l1, "Address Line 1", true, Icons.home),
                _field(l2, "Address Line 2", false, Icons.home_outlined),
                _field(lm, "Landmark", false, Icons.place),
                _field(city, "City", true, Icons.location_city),
                _field(state, "State", true, Icons.map),
                _field(pin, "Pincode", true, Icons.local_post_office),
                CheckboxListTile(
                  value: useLocation,
                  title: const Text("Use Current Location"),
                  onChanged: (v) async {
                    setState(() => loading = true);
                    useLocation = v!;
                    if (v) {
                      final loc = await getCurrentLocation();
                      if (loc != null) {
                        final a = await reverseGeocode(
                          loc['lat']!,
                          loc['lng']!,
                        );
                        if (a != null) {
                          l1.text = a['line1']!;
                          lm.text = a['landmark']!;
                          city.text = a['city']!;
                          state.text = a['state']!;
                          pin.text = a['pincode']!;
                        }
                      }
                    }
                    setState(() => loading = false);
                  },
                ),
                if (loading) const CircularProgressIndicator(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final fullAddress =
                                "${l1.text}, ${city.text}, ${state.text}, ${pin.text}";
                            final coords = await addressToCoordinates(
                              fullAddress,
                            );

                            if (isEdit) {
                              await supabase
                                  .from('user_addresses')
                                  .update({
                                    'address_line1': l1.text,
                                    'address_line2': l2.text,
                                    'landmark': lm.text,
                                    'city': city.text,
                                    'state': state.text,
                                    'pincode': pin.text,
                                    'coordinates': coords,
                                  })
                                  .eq('id', address!['id']);
                            } else {
                              await supabase.from('user_addresses').insert({
                                'user_id': userData!['id'],
                                'address_line1': l1.text,
                                'address_line2': l2.text,
                                'landmark': lm.text,
                                'city': city.text,
                                'state': state.text,
                                'pincode': pin.text,
                                'coordinates': coords,
                                'is_default': false,
                              });
                            }
                            Navigator.pop(context);
                            loadProfile();
                          },
                    child: Text(isEdit ? "Save Address" : "Add Address"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    bool req,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: req ? "$label *" : label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      drawer: AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _field(_firstName, "First Name", true, Icons.person),
                        _field(
                          _middleName,
                          "Middle Name",
                          false,
                          Icons.person_outline,
                        ),
                        _field(
                          _lastName,
                          "Last Name",
                          false,
                          Icons.person_outline,
                        ),
                        _field(_mobile, "Mobile", true, Icons.phone),
                        _field(_email, "Email", true, Icons.email),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _saving ? null : saveProfile,
                            child: Text(_saving ? "Saving..." : "Save Profile"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Saved Addresses",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...userAddresses.map(
                  (a) => Card(
                    elevation: a['is_default'] ? 4 : 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.location_on,
                        color: a['is_default'] ? Colors.green : Colors.grey,
                      ),
                      title: Text(a['address_line1']),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${a['city']}, ${a['state']} - ${a['pincode']}"),
                          if (a['is_default'])
                            const Text(
                              "Default Address",
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            addOrEditAddress(address: a);
                          } else if (v == 'default') {
                            setDefaultAddress(a['id']);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text("Edit"),
                          ),
                          if (!a['is_default'])
                            const PopupMenuItem(
                              value: 'default',
                              child: Text("Set as Default"),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => addOrEditAddress(),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text("Add New Addresss"),
                ),
              ],
            ),
    );
  }
}
