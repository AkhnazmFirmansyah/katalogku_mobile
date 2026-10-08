import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ============================================================
// KONFIGURASI: ganti dengan URL backend hasil deployment
// (sebelumnya: http://10.0.2.2:8000/api)
// ============================================================
const baseUrl = 'https://katalogku-production.up.railway.app/api';

const _headers = {
  'Accept': 'application/json',
  'Content-Type': 'application/json',
};

// ---------------------------- MODEL ----------------------------
class Product {
  final int id;
  final String name;
  final num price;

  Product({required this.id, required this.name, required this.price});

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: int.parse(json['id'].toString()),
      name: json['name']?.toString() ?? '',
      price: num.tryParse(json['price'].toString()) ?? 0,
    );
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

// ------------------------- API SERVICE -------------------------
class ApiService {
  // Timeout panjang karena hosting gratis bisa "tidur" (cold start)
  static const _timeout = Duration(seconds: 60);

  static Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static dynamic _handle(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;

    // Error validasi Laravel (422)
    if (r.statusCode == 422 && body is Map && body['errors'] is Map) {
      final msgs = (body['errors'] as Map).values
          .expand((e) => e as List)
          .join('\n');
      throw ApiException(msgs);
    }
    final msg = (body is Map && body['message'] != null)
        ? body['message'].toString()
        : 'Terjadi kesalahan';
    throw ApiException('[${r.statusCode}] $msg');
  }

  static Future<List<Product>> getAll() async {
    final r = await http
        .get(_uri('/products'), headers: _headers)
        .timeout(_timeout);
    final body = _handle(r);
    // Mendukung respons berupa array langsung atau {"data": [...]}
    final List list = body is List
        ? body
        : (body is Map && body['data'] != null ? body['data'] : []);

    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> create(String name, String price) async {
    final r = await http
        .post(
          _uri('/products'),
          headers: _headers,
          body: jsonEncode({'name': name, 'price': num.tryParse(price)}),
        )
        .timeout(_timeout);
    _handle(r);
  }

  static Future<void> update(int id, String name, String price) async {
    final r = await http
        .put(
          _uri('/products/$id'),
          headers: _headers,
          body: jsonEncode({'name': name, 'price': num.tryParse(price)}),
        )
        .timeout(_timeout);
    _handle(r);
  }

  static Future<void> delete(int id) async {
    final r = await http
        .delete(_uri('/products/$id'), headers: _headers)
        .timeout(_timeout);
    _handle(r);
  }
}

String _errorText(Object e) => e is ApiException ? e.message : 'Error: $e';

// ------------------------------ UI ------------------------------
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Katalogku',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const ProductPage(),
  );
}

class ProductPage extends StatefulWidget {
  const ProductPage({super.key});

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = ApiService.getAll();
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _showForm([Product? p]) async {
    final nameC = TextEditingController(text: p?.name ?? '');
    final priceC = TextEditingController(text: p?.price.toString() ?? '');
    String? error;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(p == null ? 'Tambah Produk' : 'Ubah Produk'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nama'),
              ),
              TextField(
                controller: priceC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setS(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        if (p == null) {
                          await ApiService.create(nameC.text, priceC.text);
                        } else {
                          await ApiService.update(
                            p.id,
                            nameC.text,
                            priceC.text,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _reload();
                        _snack(p == null ? 'Data ditambahkan' : 'Data diubah');
                      } catch (e) {
                        setS(() {
                          saving = false;
                          error = _errorText(e);
                        });
                      }
                    },
              child: Text(saving ? 'Menyimpan...' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus data?'),
        content: Text('"${p.name}" akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.delete(p.id);
      _reload();
      _snack('Data dihapus');
    } catch (e) {
      _snack(_errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Produk'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _showForm();
          _reload();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Product>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Memuat data dari server...'),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorText(snap.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _reload,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Belum ada data. Tekan + untuk menambah.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = items[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${p.id}')),
                  title: Text(p.name),
                  subtitle: Text('Rp ${p.price}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          await _showForm(p);
                          _reload();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(p),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
