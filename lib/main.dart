import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(PosApp());
}

class PosApp extends StatefulWidget {
  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  Locale _locale = Locale('uz');
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Kassa Platforma',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: [Locale('uz'), Locale('ru'), Locale('en')],
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainPage(
        onLocaleChange: (Locale loc) => setState(() => _locale = loc),
        locale: _locale,
      ),
    );
  }
}

// -------------------- Models --------------------
class Product {
  final String sku;
  final String name;
  final int price;
  final String imageUrl;
  final bool perishable;
  final bool hasAllergy;
  final List<String> expectedAiLabels;

  Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.imageUrl,
    this.perishable = false,
    this.hasAllergy = false,
    required this.expectedAiLabels,
  });

  factory Product.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Product(
      sku: data['sku'] ?? '',
      name: data['name'] ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      imageUrl: data['imageUrl'] ?? '',
      perishable: data['perishable'] ?? false,
      hasAllergy: data['hasAllergy'] ?? false,
      expectedAiLabels: List<String>.from(data['expectedAiLabels'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'sku': sku,
    'name': name,
    'price': price,
    'imageUrl': imageUrl,
    'perishable': perishable,
    'hasAllergy': hasAllergy,
    'expectedAiLabels': expectedAiLabels,
  };
}

class CartItem {
  final Product product;
  int qty;
  CartItem(this.product, {this.qty = 1});
}

// -------------------- Main Page --------------------
class MainPage extends StatefulWidget {
  final Function(Locale) onLocaleChange;
  final Locale locale;
  MainPage({required this.onLocaleChange, required this.locale});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final List<CartItem> cart = [];
  List<Product> catalog = [];
  final NumberFormat currency = NumberFormat.decimalPattern();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController scannerController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();
  final List<Map<String, dynamic>> salesLog = [];
  final Map<String, int> bonusBalances = {};
  String mode = 'self';
  final ImagePicker _picker = ImagePicker();
  final BarcodeScanner barcodeScanner = GoogleMlKit.vision.barcodeScanner();
  final ImageLabeler imageLabeler = GoogleMlKit.vision.imageLabeler();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, Map<String, String>> lang = {
    'uz': {
      'title': 'AI Kassa Platforma',
      'search': 'Qidirish...',
      'scan_here': 'Skaner kiritish (yoki barcode kiriting)',
      'add': 'Qoʻshish',
      'remove': 'Oʻchirish',
      'qty': 'Miqdor',
      'total': 'Jami',
      'pay': 'Toʻlov',
      'cash': 'Naqd',
      'card': 'Karta',
      'qr': 'QR',
      'receipt': 'Chek',
      'insufficient':
          'Pul yetmayapti — mahsulotni qaytarish yoki tovarni olib tashlang.',
      'forgive_rule':
          'Agar jami 10 000 soʻmdan koʻp bo‘lsa, 1000 so‘mdan kam yetishmayotgan pul kechiladi.',
      'must_full':
          'Agar mahsulot narxi 1000 soʻmdan kam bo‘lsa — toʻliq toʻlash kerak.',
      'language': 'Til',
      'admin': 'Admin panel',
      'reports': 'Hisobotlar',
      'clear_cart': 'Savatni tozalash',
      'apply_discount': 'Chegirma qoʻllash',
      'return_item': 'Qaytarish',
      'checkout_success': 'Toʻlov muvaffaqiyatli! Chek saqlandi.',
      'print_receipt': 'Chekni chop etish',
      'login_admin': 'Adminga oʻtish',
      'mode': 'Rejim',
      'self': 'Self-checkout',
      'cashier': 'Kassir rejimi',
      'camera_scan': 'Kamera orqali skanerlash',
      'no_barcode': 'Barcode topilmadi',
      'product_not_found': 'Mahsulot topilmadi',
      'ai_match': 'AI tasdiqladi, mahsulot qoʻshildi',
      'ai_mismatch': 'QR kod mahsulotga mos kelmaydi! Aniqlangan: ',
      'backend_error': 'Backend xatosi: ',
    },
    'ru': {/* Same as original */},
    'en': {/* Same as original */},
  };

  String t(String key) =>
      lang[widget.locale.languageCode]?[key] ?? lang['uz']![key] ?? key;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    barcodeScanner.close();
    imageLabeler.close();
    searchController.dispose();
    scannerController.dispose();
    super.dispose();
  }

  void _loadCatalog() {
    _firestore
        .collection('products')
        .snapshots()
        .listen(
          (snapshot) => setState(
            () => catalog = snapshot.docs
                .map((doc) => Product.fromFirestore(doc))
                .toList(),
          ),
          onError: (e) => showSnack('${t('backend_error')} $e'),
        );
  }

  Future<Product?> findBySku(String sku) async {
    try {
      final doc = await _firestore.collection('products').doc(sku).get();
      return doc.exists ? Product.fromFirestore(doc) : null;
    } catch (e) {
      showSnack('${t('backend_error')} $e');
      return null;
    }
  }

  List<Product> searchProducts(String q) {
    if (q.trim().isEmpty) return catalog;
    final qq = q.toLowerCase();
    return catalog
        .where((p) => p.name.toLowerCase().contains(qq) || p.sku.contains(q))
        .toList();
  }

  void addToCart(Product p) {
    final existing = cart.where((c) => c.product.sku == p.sku).toList();
    setState(
      () =>
          existing.isNotEmpty ? existing.first.qty += 1 : cart.add(CartItem(p)),
    );
  }

  void removeFromCart(CartItem item) => setState(() => cart.remove(item));

  int cartSubtotal() =>
      cart.fold(0, (prev, c) => prev + c.product.price * c.qty);

  int calculateDiscountAmount() {
    int discount = 0;
    for (var c in cart) {
      if (c.qty >= 3) discount += ((c.product.price * c.qty) * 0.10).round();
      if (c.product.perishable)
        discount += ((c.product.price * c.qty) * 0.05).round();
    }
    return discount;
  }

  int calculateBonusPoints(int subtotal) => (subtotal * 0.01).round();

  Map<String, dynamic> evaluatePaymentRules(int payAmount) {
    int subtotal = cartSubtotal();
    int discount = calculateDiscountAmount();
    int total = subtotal - discount;
    int shortage = total - payAmount;
    bool allowForgive = false;
    String msg = '';
    bool hasTinyItem = cart.any((c) => c.product.price < 1000);
    if (payAmount >= total) {
      msg = 'ok';
    } else if (total >= 10000 &&
        shortage > 0 &&
        shortage < 1000 &&
        !hasTinyItem) {
      allowForgive = true;
      msg = 'forgive_allowed';
    } else {
      msg = 'insufficient';
    }
    return {
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'shortage': shortage,
      'allowForgive': allowForgive,
      'message': msg,
    };
  }

  Future<void> checkout({
    required String method,
    required int payAmount,
    String? customerId,
  }) async {
    final eval = evaluatePaymentRules(payAmount);
    if (eval['message'] == 'insufficient') {
      showSnack(t('insufficient'));
      return;
    }
    int total = eval['total'];
    bool forgiven = eval['message'] == 'forgive_allowed';
    int change = payAmount >= total ? payAmount - total : 0;
    int amountCharged = forgiven ? payAmount : (payAmount >= total ? total : 0);

    final sale = {
      'timestamp': DateTime.now().toIso8601String(),
      'items': cart
          .map(
            (c) => {
              'sku': c.product.sku,
              'name': c.product.name,
              'price': c.product.price,
              'qty': c.qty,
            },
          )
          .toList(),
      'subtotal': eval['subtotal'],
      'discount': eval['discount'],
      'total': total,
      'method': method,
      'paid': amountCharged,
      'change': change,
      'forgiven': forgiven,
      'customer': customerId ?? '',
    };

    try {
      await _firestore.collection('sales').add(sale);
      salesLog.add(sale);
    } catch (e) {
      showSnack('${t('backend_error')} $e');
      return;
    }

    if (customerId != null && customerId.isNotEmpty) {
      final pts = calculateBonusPoints(total - (eval['discount'] as int));
      try {
        final docRef = _firestore.collection('bonus_balances').doc(customerId);
        final doc = await docRef.get();
        final currentPoints = doc.exists
            ? (doc.data()!['points'] as num?)?.toInt() ?? 0
            : 0;
        await docRef.set({'points': currentPoints + pts});
        bonusBalances[customerId] = currentPoints + pts;
      } catch (e) {
        showSnack('${t('backend_error')} $e');
      }
    }

    final receiptText = generateReceiptText(sale);
    await saveReceiptToFile(receiptText);
    setState(() => cart.clear());
    showSnack(t('checkout_success'));
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('print_receipt')),
        content: SingleChildScrollView(child: SelectableText(receiptText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await tryPrint(receiptText);
            },
            child: Text(t('print_receipt')),
          ),
        ],
      ),
    );
  }

  Future<void> tryPrint(String receiptText) async {
    try {
      final doc = await PdfCreation.createSimplePdf(receiptText);
      await Printing.layoutPdf(onLayout: (_) async => Uint8List.fromList(doc));
      showSnack('Printed');
    } catch (e) {
      showSnack('Printing not available (simulate).');
    }
  }

  Future<void> saveReceiptToFile(String text) async {
    try {
      final dir = Directory.current;
      final file = File(
        '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(text);
    } catch (e) {}
  }

  String generateReceiptText(Map<String, dynamic> sale) {
    final sb = StringBuffer();
    sb.writeln('=== ${t('receipt')} ===');
    sb.writeln('Time: ${sale['timestamp']}');
    sb.writeln('Items:');
    for (var it in sale['items']) {
      sb.writeln(
        '${it['qty']} x ${it['name']} @ ${currency.format(it['price'])} = ${currency.format(it['price'] * it['qty'])}',
      );
    }
    sb.writeln('Subtotal: ${currency.format(sale['subtotal'])}');
    sb.writeln('Discount: ${currency.format(sale['discount'])}');
    sb.writeln('Total: ${currency.format(sale['total'])}');
    sb.writeln('Paid: ${currency.format(sale['paid'])}');
    sb.writeln('Change: ${currency.format(sale['change'])}');
    sb.writeln('Forgiven: ${sale['forgiven']}');
    sb.writeln('Method: ${sale['method']}');
    sb.writeln('======================');
    sb.writeln('Thank you for shopping!');
    return sb.toString();
  }

  void showSnack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> cameraScan() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;
      final inputImage = InputImage.fromFilePath(photo.path);
      final List<Barcode> barcodes = await barcodeScanner.processImage(
        inputImage,
      );
      if (barcodes.isEmpty) {
        showSnack(t('no_barcode'));
        return;
      }
      final String sku = barcodes.first.rawValue ?? '';
      final Product? p = await findBySku(sku);
      if (p == null) {
        showSnack('${t('product_not_found')} SKU: $sku');
        return;
      }
      final List<ImageLabel> labels = await imageLabeler.processImage(
        inputImage,
      );
      bool match = false;
      for (ImageLabel label in labels) {
        if (p.expectedAiLabels.any(
              (exp) => label.label.toLowerCase().contains(exp.toLowerCase()),
            ) &&
            label.confidence > 0.5) {
          match = true;
          break;
        }
      }
      if (match) {
        addToCart(p);
        showSnack(t('ai_match'));
      } else {
        final detected = labels
            .map((l) => '${l.label} (${(l.confidence * 100).round()}%)')
            .join(', ');
        showSnack('${t('ai_mismatch')} $detected');
      }
    } catch (e) {
      showSnack('Error: $e');
    }
  }

  List<Product> getRecommendations(List<CartItem> cart) {
    if (cart.any((c) => c.product.name.contains('Non'))) {
      return catalog.where((p) => p.name.contains('Sut')).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final filtered = searchProducts(searchController.text);
    return ScaffoldMessenger(
      key: scaffoldKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('title')),
          actions: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<String>(
                value: mode,
                underline: SizedBox(),
                items: [
                  DropdownMenuItem(value: 'self', child: Text(t('self'))),
                  DropdownMenuItem(value: 'cashier', child: Text(t('cashier'))),
                ],
                onChanged: (v) => setState(() => mode = v ?? 'self'),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<Locale>(
                value: widget.locale,
                underline: SizedBox(),
                items: [
                  DropdownMenuItem(value: Locale('uz'), child: Text('Oʻzbek')),
                  DropdownMenuItem(value: Locale('ru'), child: Text('Рус')),
                  DropdownMenuItem(value: Locale('en'), child: Text('EN')),
                ],
                onChanged: (loc) =>
                    loc != null ? widget.onLocaleChange(loc) : null,
              ),
            ),
            IconButton(
              icon: Icon(Icons.admin_panel_settings),
              tooltip: t('admin'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminPage(
                    salesLog: salesLog,
                    onClearReports: () async {
                      try {
                        final batch = _firestore.batch();
                        final docs = await _firestore.collection('sales').get();
                        for (var doc in docs.docs) batch.delete(doc.reference);
                        await batch.commit();
                        setState(() => salesLog.clear());
                      } catch (e) {
                        showSnack('${t('backend_error')} $e');
                      }
                    },
                    catalog: catalog,
                    onUpdateCatalog: (newCatalog) async {
                      try {
                        final batch = _firestore.batch();
                        for (var product in newCatalog) {
                          batch.set(
                            _firestore.collection('products').doc(product.sku),
                            product.toFirestore(),
                          );
                        }
                        await batch.commit();
                        setState(() => catalog = newCatalog);
                      } catch (e) {
                        showSnack('${t('backend_error')} $e');
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Row(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: t('search'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: scannerController,
                            decoration: InputDecoration(
                              hintText: t('scan_here'),
                            ),
                            onSubmitted: (val) async {
                              if (val.trim().isEmpty) return;
                              final p = await findBySku(val.trim());
                              if (p != null) {
                                addToCart(p);
                                scannerController.clear();
                                showSnack('${p.name} ${t('add')}');
                              } else {
                                showSnack('${t('product_not_found')} $val');
                              }
                            },
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final val = scannerController.text.trim();
                            if (val.isEmpty) return;
                            final p = await findBySku(val);
                            if (p != null) {
                              addToCart(p);
                              scannerController.clear();
                              showSnack('${p.name} ${t('add')}');
                            } else {
                              showSnack('${t('product_not_found')} $val');
                            }
                          },
                          child: Text(t('add')),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: cameraScan,
                          child: Text(t('camera_scan')),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(t('recommend')),
                    ...getRecommendations(cart).map(
                      (p) => ListTile(
                        title: Text(p.name),
                        onTap: () => addToCart(p),
                      ),
                    ),
                    Expanded(
                      child: catalog.isEmpty
                          ? Center(child: CircularProgressIndicator())
                          : GridView.builder(
                              itemCount: filtered.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisExtent: 120,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemBuilder: (_, idx) {
                                final p = filtered[idx];
                                return Card(
                                  child: InkWell(
                                    onTap: () => addToCart(p),
                                    child: Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Row(
                                        children: [
                                          Image.network(
                                            p.imageUrl,
                                            width: 64,
                                            height: 64,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Icon(Icons.image),
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p.name,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Spacer(),
                                                Text(
                                                  '${currency.format(p.price)} so\'m',
                                                ),
                                                Text(
                                                  'SKU: ${p.sku}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.grey[50],
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        'Cart',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: cart.length,
                          itemBuilder: (_, i) {
                            final c = cart[i];
                            return ListTile(
                              leading: Image.network(
                                c.product.imageUrl,
                                width: 48,
                                height: 48,
                                errorBuilder: (_, __, ___) => Icon(Icons.image),
                              ),
                              title: Text(c.product.name),
                              subtitle: Text(
                                '${currency.format(c.product.price)} x ${c.qty}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () => setState(
                                      () => c.qty > 1
                                          ? c.qty--
                                          : cart.removeAt(i),
                                    ),
                                    icon: Icon(Icons.remove),
                                  ),
                                  Text('${c.qty}'),
                                  IconButton(
                                    onPressed: () => setState(() => c.qty++),
                                    icon: Icon(Icons.add),
                                  ),
                                  IconButton(
                                    onPressed: () => removeFromCart(c),
                                    icon: Icon(Icons.delete, color: Colors.red),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Divider(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Subtotal:'),
                              Text('${currency.format(cartSubtotal())} so\'m'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Discount:'),
                              Text(
                                '${currency.format(calculateDiscountAmount())} so\'m',
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t('total') + ':',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${currency.format(cartSubtotal() - calculateDiscountAmount())} so\'m',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () async {
                                        final tendered = await showTenderDialog(
                                          context,
                                        );
                                        if (tendered != null)
                                          await checkout(
                                            method: 'cash',
                                            payAmount: tendered,
                                            customerId: null,
                                          );
                                      },
                                icon: Icon(Icons.money),
                                label: Text(t('cash')),
                              ),
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: Text(t('card')),
                                            content: Text(
                                              'Simulate card processing (OK to approve)',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: Text('OK'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await checkout(
                                            method: 'card',
                                            payAmount:
                                                cartSubtotal() -
                                                calculateDiscountAmount(),
                                            customerId: null,
                                          );
                                        } else {
                                          showSnack('Card payment cancelled');
                                        }
                                      },
                                icon: Icon(Icons.credit_card),
                                label: Text(t('card')),
                              ),
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: Text(t('qr')),
                                            content: Text(
                                              'Simulate QR payment provider. Press OK when paid.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: Text('OK'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await checkout(
                                            method: 'qr',
                                            payAmount:
                                                cartSubtotal() -
                                                calculateDiscountAmount(),
                                            customerId: null,
                                          );
                                        } else {
                                          showSnack('QR payment cancelled');
                                        }
                                      },
                                icon: Icon(Icons.qr_code),
                                label: Text(t('qr')),
                              ),
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () async {
                                        final res = await showDialog<bool>(
                                          context: context,
                                          builder: (_) =>
                                              ReturnDialog(cart: cart),
                                        );
                                        if (res == true) setState(() {});
                                      },
                                icon: Icon(Icons.undo),
                                label: Text(t('return_item')),
                              ),
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () => setState(() => cart.clear()),
                                icon: Icon(Icons.clear),
                                label: Text(t('clear_cart')),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            t('forgive_rule'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            t('must_full'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> showTenderDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('cash')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter amount tendered (integer, som)'),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(hintText: 'e.g., 10000'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}

class ReturnDialog extends StatefulWidget {
  final List<CartItem> cart;
  ReturnDialog({required this.cart});
  @override
  State<ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<ReturnDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Return / Adjust cart'),
      content: Container(
        width: 400,
        height: 300,
        child: ListView.builder(
          itemCount: widget.cart.length,
          itemBuilder: (_, i) {
            final c = widget.cart[i];
            return ListTile(
              title: Text('${c.product.name} (${c.qty})'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => c.qty > 1 ? c.qty-- : widget.cart.removeAt(i),
                    ),
                    icon: Icon(Icons.remove),
                  ),
                  IconButton(
                    onPressed: () => setState(() => c.qty++),
                    icon: Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: () => setState(() => widget.cart.removeAt(i)),
                    icon: Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Done'),
        ),
      ],
    );
  }
}

class AdminPage extends StatefulWidget {
  final List<Map<String, dynamic>> salesLog;
  final VoidCallback onClearReports;
  final List<Product> catalog;
  final Function(List<Product>) onUpdateCatalog;
  AdminPage({
    required this.salesLog,
    required this.onClearReports,
    required this.catalog,
    required this.onUpdateCatalog,
  });
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final NumberFormat currency = NumberFormat.decimalPattern();
  @override
  Widget build(BuildContext context) {
    int totalSales = widget.salesLog.fold(
      0,
      (prev, s) => prev + (s['paid'] as int),
    );
    return Scaffold(
      appBar: AppBar(title: Text('Admin / Reports')),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total sales: ${currency.format(totalSales)} som',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                ElevatedButton(
                  onPressed: widget.onClearReports,
                  child: Text('Clear reports'),
                ),
              ],
            ),
            SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: widget.salesLog.length,
                itemBuilder: (_, i) {
                  final s = widget.salesLog[i];
                  return Card(
                    child: ListTile(
                      title: Text('Sale ${i + 1} — ${s['timestamp']}'),
                      subtitle: Text(
                        'Total: ${currency.format(s['total'])} | Paid: ${currency.format(s['paid'])} | Method: ${s['method']} | Forgiven: ${s['forgiven']}',
                      ),
                      trailing: IconButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text('Details'),
                            content: SingleChildScrollView(
                              child: Text(jsonEncode(s)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Close'),
                              ),
                            ],
                          ),
                        ),
                        icon: Icon(Icons.more_vert),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                final newCatalog = List<Product>.from(widget.catalog);
                final sku = (newCatalog.length + 1).toString().padLeft(4, '0');
                newCatalog.add(
                  Product(
                    sku: sku,
                    name: 'NewProd $sku',
                    price: 2000,
                    imageUrl: 'https://via.placeholder.com/80?text=New',
                    expectedAiLabels: ['new product'],
                  ),
                );
                widget.onUpdateCatalog(newCatalog);
              },
              child: Text('Add demo product'),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfCreation {
  static Future<List<int>> createSimplePdf(String text) async =>
      utf8.encode(text);
}
