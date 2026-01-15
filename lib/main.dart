import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApartmentApp());
}

class ApartmentApp extends StatelessWidget {
  const ApartmentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'نظام إدارة العقارات',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const LoginScreen(),
    );
  }
}

// --- شاشة تسجيل الدخول ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passController = TextEditingController();

  void _login() {
    if (_passController.text == "2026") {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (context) => const HomeScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("كلمة المرور خاطئة!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.apartment_rounded, size: 80, color: Color(0xFF0D47A1)),
              const SizedBox(height: 20),
              const Text("HOUSE SYSTEM", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "كلمة المرور",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("دخول", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- الشاشة الرئيسية ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Database? _db;
  List<Map<String, dynamic>> _results = [];
  Map<String, int> _stats = {'total': 0, 'occupied': 0, 'vacant': 0};

  final _buildSearchController = TextEditingController();
  final _apartSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    // تم رفع الإصدار إلى v9 وتعديل الجدول ليشمل الموقع location
    String path = p.join(await getDatabasesPath(), 'apartments_v9.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) {
      return db.execute(
          "CREATE TABLE apartments(id INTEGER PRIMARY KEY AUTOINCREMENT, propertyCode TEXT, location TEXT, suburb TEXT, buildingNum TEXT, apartmentNum TEXT, floor TEXT, area TEXT, rooms TEXT, status TEXT, region TEXT, workplace TEXT, title TEXT, occupantName TEXT)");
    });
    _refreshData();
  }

  Future<void> _refreshData() async {
    _buildSearchController.clear();
    _apartSearchController.clear();
    final data = await _db!.query('apartments');
    
    int occupied = data.where((item) => item['status'] == 'مسكونة').length;
    int vacant = data.where((item) => item['status'] == 'شاغرة').length;

    setState(() {
      _results = data;
      _stats = {
        'total': data.length,
        'occupied': occupied,
        'vacant': vacant,
      };
    });
  }

  // دالة البحث المنفصلة (تستدعى عند الضغط على زر البحث فقط)
  void _performSearch() async {
    String build = _buildSearchController.text;
    String apart = _apartSearchController.text;

    String where = "";
    List<dynamic> args = [];

    if (build.isNotEmpty) {
      where += "buildingNum LIKE ?";
      args.add('%$build%');
    }
    if (apart.isNotEmpty) {
      if (where.isNotEmpty) where += " AND ";
      where += "apartmentNum LIKE ?";
      args.add('%$apart%');
    }

    final data = await _db!.query('apartments', where: where.isEmpty ? null : where, whereArgs: args.isEmpty ? null : args);
    setState(() => _results = data);
  }

  Future<void> _deleteApartment(int id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: const Text("هل أنت متأكد من حذف هذا السجل نهائياً؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm) {
      await _db!.delete('apartments', where: "id = ?", whereArgs: [id]);
      _refreshData();
    }
  }

  Future<void> _exportToExcel() async {
    if (await Permission.storage.request().isDenied) {
      await Permission.manageExternalStorage.request();
    }

    var excel = Excel.createExcel();
    Sheet sheet = excel['Apartments'];
    sheet.appendRow([
      TextCellValue("كود العقار"), TextCellValue("الموقع"), TextCellValue("البناية"), TextCellValue("الشقة"), 
      TextCellValue("الحالة"), TextCellValue("الشاغل")
    ]);

    for (var row in _results) {
      sheet.appendRow([
        TextCellValue(row['propertyCode'] ?? ""),
        TextCellValue(row['location'] ?? ""),
        TextCellValue(row['buildingNum'] ?? ""),
        TextCellValue(row['apartmentNum'] ?? ""),
        TextCellValue(row['status'] ?? ""),
        TextCellValue(row['occupantName'] ?? ""),
      ]);
    }

    try {
      Directory? downloads = Directory('/storage/emulated/0/Download');
      if (!await downloads.exists()) downloads = await getExternalStorageDirectory();
      
      String filePath = p.join(downloads!.path, "House_Report_${DateTime.now().millisecond}.xlsx");
      File(filePath)..createSync(recursive: true)..writeAsBytesSync(excel.encode()!);
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم الحفظ في التنزيلات: $filePath"), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("فشل التصدير: تحقق من الصلاحيات")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("نظام إدارة العقارات", style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF0D47A1),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _refreshData)
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildDashboard(),
          _buildSearchBars(),
          Expanded(child: _buildList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        backgroundColor: const Color(0xFF0D47A1),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildDashboard() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0D47A1).withOpacity(0.05),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statCard("الكل", _stats['total'].toString(), Colors.blue),
          _statCard("مسكونة", _stats['occupied'].toString(), Colors.green),
          _statCard("شاغرة", _stats['vacant'].toString(), Colors.orange),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  // تم تعديل هذا القسم لإضافة زر البحث المنفصل
  Widget _buildSearchBars() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _buildSearchController,
              decoration: const InputDecoration(labelText: "رقم البناية", border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _apartSearchController,
              decoration: const InputDecoration(labelText: "رقم الشقة", border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: _performSearch, // لا يبحث إلا عند الضغط هنا
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item['status'] == 'مسكونة' ? Colors.green : Colors.orange,
              child: const Icon(Icons.home, color: Colors.white),
            ),
            title: Text("بناية ${item['buildingNum']} - شقة ${item['apartmentNum']}"),
            subtitle: Text("الموقع: ${item['location'] ?? 'غير محدد'}\nالشاغل: ${item['occupantName']}"),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showFormDialog(item: item)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteApartment(item['id'])),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF0D47A1)),
            child: Center(child: Text("القائمة الرئيسية", style: TextStyle(color: Colors.white, fontSize: 20))),
          ),
          ListTile(leading: const Icon(Icons.download), title: const Text("تصدير إلى Excel"), onTap: () { Navigator.pop(context); _exportToExcel(); }),
          ListTile(leading: const Icon(Icons.logout), title: const Text("تسجيل الخروج"), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()))),
        ],
      ),
    );
  }

  void _showFormDialog({Map<String, dynamic>? item}) {
    final bool isUpdate = item != null;
    final formKey = GlobalKey<FormState>();
    
    final Map<String, TextEditingController> ctrls = {
      'propertyCode': TextEditingController(text: isUpdate ? item['propertyCode'] : ""),
      'location': TextEditingController(text: isUpdate ? item['location'] : ""), // حقل الموقع الجديد
      'suburb': TextEditingController(text: isUpdate ? item['suburb'] : ""),
      'buildingNum': TextEditingController(text: isUpdate ? item['buildingNum'] : ""),
      'apartmentNum': TextEditingController(text: isUpdate ? item['apartmentNum'] : ""),
      'occupantName': TextEditingController(text: isUpdate ? item['occupantName'] : ""),
    };
    String currentStatus = isUpdate ? item['status'] : "شاغرة";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isUpdate ? "تعديل بيانات" : "إضافة عقار جديد"),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: ListView(
                shrinkWrap: true,
                children: [
                  TextFormField(controller: ctrls['location'], decoration: const InputDecoration(labelText: "موقع الشقة (الحي/الشارع)"), validator: (v) => v!.isEmpty ? "مطلوب" : null),
                  const SizedBox(height: 10),
                  TextFormField(controller: ctrls['buildingNum'], decoration: const InputDecoration(labelText: "رقم البناية"), validator: (v) => v!.isEmpty ? "مطلوب" : null, keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  TextFormField(controller: ctrls['apartmentNum'], decoration: const InputDecoration(labelText: "رقم الشقة"), validator: (v) => v!.isEmpty ? "مطلوب" : null, keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: currentStatus,
                    decoration: const InputDecoration(labelText: "حالة الشقة"),
                    items: ["شاغرة", "مسكونة", "صيانة"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) => setDialogState(() => currentStatus = val!),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(controller: ctrls['occupantName'], decoration: const InputDecoration(labelText: "اسم الشاغل")),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Map<String, dynamic> data = ctrls.map((key, value) => MapEntry(key, value.text));
                  data['status'] = currentStatus;
                  
                  if (isUpdate) {
                    await _db!.update('apartments', data, where: "id = ?", whereArgs: [item['id']]);
                  } else {
                    await _db!.insert('apartments', data);
                  }
                  Navigator.pop(context);
                  _refreshData();
                }
              },
              child: Text(isUpdate ? "تحديث" : "حفظ"),
            )
          ],
        ),
      ),
    );
  }
}