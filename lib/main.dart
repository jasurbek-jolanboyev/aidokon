// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart'; // optional; o'rnatilmasa comment qiling yoki pubspec ga qo'shing

// NOTE: This is a single-file prototype. For production split into multiple files,
// add backend integration, authentication, secure storage, and real payment/printing APIs.

void main() {
  runApp(PosApp());
}

class PosApp extends StatefulWidget {
  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  Locale _locale = Locale('uz'); // default uzbek
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Kassa Platforma (Prototype)',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: [Locale('uz'), Locale('ru'), Locale('en')],
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainPage(
        onLocaleChange: (Locale loc) {
          setState(() => _locale = loc);
        },
        locale: _locale,
      ),
    );
  }
}

// -------------------- Models --------------------
class Product {
  final String sku; // barcode / qr code
  final String name;
  final int price; // in som (integer)
  final String imageUrl;
  final bool perishable;
  final bool hasAllergy;

  Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.imageUrl,
    this.perishable = false,
    this.hasAllergy = false,
  });
}

class CartItem {
  final Product product;
  int qty;
  CartItem(this.product, {this.qty = 1});
}

// -------------------- Demo Product Catalog --------------------
List<Product> demoCatalog = [
  Product(
    sku: '0001',
    name: 'Ruchka 1 (pen)',
    price: 1000,
    imageUrl: 'https://via.placeholder.com/80?text=Ruchka',
    perishable: false,
  ),
  Product(
    sku: '0002',
    name: 'Sut 1L',
    price: 8500,
    imageUrl: 'https://via.placeholder.com/80?text=Sut',
    perishable: true,
  ),
  Product(
    sku: '0003',
    name: 'Non (loaf)',
    price: 5000,
    imageUrl: 'https://via.placeholder.com/80?text=Non',
    perishable: true,
  ),
  Product(
    sku: '0004',
    name: 'Olma (apple)',
    price: 12000,
    imageUrl: 'https://via.placeholder.com/80?text=Olma',
    perishable: true,
  ),
  Product(
    sku: '0005',
    name: 'Choy (tea)',
    price: 15000,
    imageUrl: 'https://via.placeholder.com/80?text=Choy',
    perishable: false,
  ),
  Product(
    sku: '0006',
    name: 'Banan',
    price: 4000,
    imageUrl: 'https://via.placeholder.com/80?text=Banan',
    perishable: true,
  ),
];

// -------------------- Main Page --------------------
class MainPage extends StatefulWidget {
  final Function(Locale) onLocaleChange;
  final Locale locale;
  MainPage({required this.onLocaleChange, required this.locale});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // Cart & catalog state
  final List<CartItem> cart = [];
  List<Product> catalog = List.from(demoCatalog);
  final NumberFormat currency =
      NumberFormat.decimalPattern(); // integer formatting
  final TextEditingController searchController = TextEditingController();
  final TextEditingController scannerController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  // Admin / reports
  final List<Map<String, dynamic>> salesLog = []; // each sale stored

  // Bonus system (simple)
  final Map<String, int> bonusBalances = {}; // phone/email -> points

  // Settings
  String mode = 'self'; // 'self' or 'cashier'

  // Localization map (very small)
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
    },
    'ru': {
      'title': 'AI Касса Платформа',
      'search': 'Поиск...',
      'scan_here': 'Ввод сканера (или штрихкода)',
      'add': 'Добавить',
      'remove': 'Удалить',
      'qty': 'Кол-во',
      'total': 'Итого',
      'pay': 'Оплатить',
      'cash': 'Наличные',
      'card': 'Карта',
      'qr': 'QR',
      'receipt': 'Чек',
      'insufficient': 'Недостаточно денег — удалите товар или верните.',
      'forgive_rule':
          'Если сумма > 10000 сум, недостающие до 1000 сум прощаются.',
      'must_full':
          'Если цена товара меньше 1000 сум — требуется полная оплата.',
      'language': 'Язык',
      'admin': 'Админ панель',
      'reports': 'Отчеты',
      'clear_cart': 'Очистить корзину',
      'apply_discount': 'Применить скидку',
      'return_item': 'Возврат',
      'checkout_success': 'Оплата успешна! Чек сохранён.',
      'print_receipt': 'Распечатать чек',
      'login_admin': 'Перейти в админ',
      'mode': 'Режим',
      'self': 'Self-checkout',
      'cashier': 'Режим кассира',
    },
    'en': {
      'title': 'AI POS Platform',
      'search': 'Search...',
      'scan_here': 'Scanner input (or enter barcode)',
      'add': 'Add',
      'remove': 'Remove',
      'qty': 'Qty',
      'total': 'Total',
      'pay': 'Pay',
      'cash': 'Cash',
      'card': 'Card',
      'qr': 'QR',
      'receipt': 'Receipt',
      'insufficient': 'Insufficient funds — return or remove items.',
      'forgive_rule':
          'If total > 10 000 som, missing amount < 1000 som can be forgiven.',
      'must_full': 'If item price < 1000 som — full payment required.',
      'language': 'Language',
      'admin': 'Admin panel',
      'reports': 'Reports',
      'clear_cart': 'Clear cart',
      'apply_discount': 'Apply discount',
      'return_item': 'Return item',
      'checkout_success': 'Payment successful! Receipt saved.',
      'print_receipt': 'Print receipt',
      'login_admin': 'Go to admin',
      'mode': 'Mode',
      'self': 'Self-checkout',
      'cashier': 'Cashier mode',
    },
  };

  String t(String key) =>
      lang[widget.locale.languageCode]?[key] ?? lang['uz']![key] ?? key;

  @override
  void initState() {
    super.initState();
    // Listen to keyboard input for scanner (many USB barcode scanners send input as keyboard)
    // Put focus on hidden TextField
    // For simplicity: user can type barcode into scanner text field and press Enter
  }

  // ---------------- Business logic ----------------

  Product? findBySku(String sku) {
    try {
      return catalog.firstWhere((p) => p.sku == sku);
    } catch (e) {
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
    if (existing.isNotEmpty) {
      setState(() => existing.first.qty += 1);
    } else {
      setState(() => cart.add(CartItem(p, qty: 1)));
    }
  }

  void removeFromCart(CartItem item) {
    setState(() {
      cart.remove(item);
    });
  }

  int cartSubtotal() {
    int s = 0;
    for (var c in cart) s += c.product.price * c.qty;
    return s;
  }

  // Example discount rules:
  // - If 3 or more of same product -> 10% off those items
  // - If perishable and close to expiration (simulated) -> 20% off
  int calculateDiscountAmount() {
    int discount = 0;
    for (var c in cart) {
      // 3+ same item -> 10% discount on those items
      if (c.qty >= 3) {
        discount += ((c.product.price * c.qty) * 0.10).round();
      }
      // perishable example discount
      if (c.product.perishable) {
        // In real scenario check expiration date. Here simulate small discount
        discount += ((c.product.price * c.qty) * 0.05).round();
      }
    }
    // Additional promos could be applied here
    return discount;
  }

  // Bonus points: 1 som => 0.01 point (example)
  int calculateBonusPoints(int subtotal) {
    return (subtotal * 0.01).round();
  }

  // Small-change forgiveness logic per specification:
  // If total >= 10000 som, and shortage < 1000 som -> allow forgiveness.
  // If any single item price < 1000 som (e.g., 1000 som pen) -> do not allow forgiveness (must pay in full).
  // If total < 10000 som -> no forgiveness.
  Map<String, dynamic> evaluatePaymentRules(int payAmount) {
    int subtotal = cartSubtotal();
    int discount = calculateDiscountAmount();
    int total = subtotal - discount;
    int shortage = total - payAmount; // if positive, need more money
    bool allowForgive = false;
    String msg = '';
    // If there is any item with price < 1000, do not allow forgiveness for that item unless payAmount covers it fully.
    bool hasTinyItem = cart.any((c) => c.product.price < 1000);
    if (payAmount >= total) {
      msg = 'ok';
    } else {
      if (total >= 10000 && shortage > 0 && shortage < 1000 && !hasTinyItem) {
        allowForgive = true;
        msg = 'forgive_allowed';
      } else {
        msg = 'insufficient';
      }
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
    required String method, // 'cash', 'card', 'qr'
    required int payAmount, // amount tendered (for cash simulation)
    String? customerId,
  }) async {
    final eval = evaluatePaymentRules(payAmount);
    if (eval['message'] == 'insufficient') {
      showSnack(t('insufficient'));
      return;
    }
    int total = eval['total'];
    bool forgiven = false;
    if (eval['message'] == 'forgive_allowed') {
      forgiven = true;
    }
    // compute change
    int change = 0;
    if (payAmount >= total) change = payAmount - total;
    // if forgiven, customer leaves with items and shortage forgiven
    int amountCharged = forgiven ? payAmount : (payAmount >= total ? total : 0);

    // Save sale in log
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
    salesLog.add(sale);

    // Bonus awarding
    if (customerId != null && customerId.isNotEmpty) {
      final pts = calculateBonusPoints(
        total.toInt() - (eval['discount'] as num).toInt(),
      );
      bonusBalances[customerId] = (bonusBalances[customerId] ?? 0) + pts;
    }

    // Create receipt (pdf or text)
    final receiptText = generateReceiptText(sale);
    // Save to local file for demo
    await saveReceiptToFile(receiptText);

    setState(() {
      cart.clear();
    });

    showSnack(t('checkout_success'));
    // Offer to print
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
      // Using printing package: prints a simple text PDF
      // If printing package missing or platform doesn't support, exception may occur.
      final doc = await generatePdfFromText(receiptText);
      await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(await doc),
      );
      showSnack('Printed');
    } catch (e) {
      showSnack('Printing not available (simulate).');
    }
  }

  Future<List<int>> generatePdfFromText(String text) async {
    // Very simple PDF generation using printing package utilities.
    // If not installed, catch and skip.
    final pdf = await PdfCreation.createSimplePdf(text);
    return pdf;
  }

  Future<void> saveReceiptToFile(String text) async {
    try {
      final dir = Directory.current;
      final file = File(
        '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(text);
    } catch (e) {
      // ignore
    }
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

  void showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- UI Widgets ----------------

  @override
  Widget build(BuildContext context) {
    final filtered = searchProducts(searchController.text);
    return ScaffoldMessenger(
      key: scaffoldKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('title')),
          actions: [
            // Mode switch
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<String>(
                value: mode,
                underline: SizedBox(),
                items: [
                  DropdownMenuItem(value: 'self', child: Text(t('self'))),
                  DropdownMenuItem(value: 'cashier', child: Text(t('cashier'))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => mode = v);
                },
              ),
            ),
            // Language switch
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
                onChanged: (loc) {
                  if (loc != null) {
                    widget.onLocaleChange(loc);
                    setState(() {});
                  }
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.admin_panel_settings),
              tooltip: t('admin'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminPage(
                      salesLog: salesLog,
                      onClearReports: () => setState(() => salesLog.clear()),
                      catalog: catalog,
                      onUpdateCatalog: (List<Product> newCatalog) =>
                          setState(() => catalog = newCatalog),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Row(
          children: [
            // Left: Catalog & search
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
                    // Scanner input (captures barcode as text)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: scannerController,
                            decoration: InputDecoration(
                              hintText: t('scan_here'),
                            ),
                            onSubmitted: (val) {
                              if (val.trim().isEmpty) return;
                              final p = findBySku(val.trim());
                              if (p != null) {
                                addToCart(p);
                                scannerController.clear();
                                showSnack('${p.name} ${t('add')}');
                              } else {
                                showSnack('Product not found for: $val');
                              }
                            },
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final val = scannerController.text.trim();
                            if (val.isEmpty) return;
                            final p = findBySku(val);
                            if (p != null) {
                              addToCart(p);
                              scannerController.clear();
                              showSnack('${p.name} ${t('add')}');
                            } else {
                              showSnack('Product not found: $val');
                            }
                          },
                          child: Text(t('add')),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        itemCount: filtered.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                                            style: TextStyle(fontSize: 10),
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

            // Right: Cart & payment
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
                              ),
                              title: Text(c.product.name),
                              subtitle: Text(
                                '${currency.format(c.product.price)} x ${c.qty}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        if (c.qty > 1)
                                          c.qty--;
                                        else
                                          cart.removeAt(i);
                                      });
                                    },
                                    icon: Icon(Icons.remove),
                                  ),
                                  Text('${c.qty}'),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        c.qty++;
                                      });
                                    },
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
                          // Payment buttons
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () async {
                                        // Cash flow: prompt cash amount tendered
                                        final tendered = await showTenderDialog(
                                          context,
                                        );
                                        if (tendered != null) {
                                          await checkout(
                                            method: 'cash',
                                            payAmount: tendered,
                                            customerId: null,
                                          );
                                        }
                                      },
                                icon: Icon(Icons.money),
                                label: Text(t('cash')),
                              ),
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () async {
                                        // Card: simulate card processing
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
                                        // QR payment simulation: show QR code or ask to confirm
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
                                        // Return / remove items flow
                                        final res = await showDialog<bool>(
                                          context: context,
                                          builder: (_) =>
                                              ReturnDialog(cart: cart),
                                        );
                                        if (res == true) {
                                          setState(() {});
                                        }
                                      },
                                icon: Icon(Icons.undo),
                                label: Text(t('return_item')),
                              ),
                              ElevatedButton.icon(
                                onPressed: cart.isEmpty
                                    ? null
                                    : () {
                                        setState(() => cart.clear());
                                      },
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
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(context, v);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ------------------ Return Dialog -------------------
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
                    onPressed: () {
                      setState(() {
                        if (c.qty > 1)
                          c.qty--;
                        else
                          widget.cart.removeAt(i);
                      });
                    },
                    icon: Icon(Icons.remove),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        c.qty++;
                      });
                    },
                    icon: Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        widget.cart.removeAt(i);
                      });
                    },
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

// ------------------ Admin Page ------------------
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
                  onPressed: () {
                    widget.onClearReports();
                    setState(() {});
                  },
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
                        onPressed: () {
                          showDialog(
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
                          );
                        },
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
                // Manage catalog example: add demo product
                final newCatalog = List<Product>.from(widget.catalog);
                final sku = (newCatalog.length + 1).toString().padLeft(4, '0');
                newCatalog.add(
                  Product(
                    sku: sku,
                    name: 'NewProd $sku',
                    price: 2000,
                    imageUrl: 'https://via.placeholder.com/80?text=New',
                  ),
                );
                widget.onUpdateCatalog(newCatalog);
                setState(() {});
              },
              child: Text('Add demo product'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------ PDF helper stub ------------------
class PdfCreation {
  // This is a minimal stub that returns bytes for a PDF document containing plain text.
  // For production, use package:pdf to create richer PDF.
  static Future<List<int>> createSimplePdf(String text) async {
    // If package:pdf available, implement real PDF generation.
    // For now, return utf8 bytes of the text (printing package expects PDF bytes,
    // so on platforms without proper pdf creation this will fail and be caught).
    return utf8.encode(text);
  }
}
