import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const String dbFile = "trotro.db";
const String fareFile = "fares.json";
const String appSlogan = "Safe. Fast. Reliable. | Government Approved";
String? currentUser;
const Color ghRed = Color(0xFFCE1126);
const Color ghGold = Color(0xFFFCD116);
const Color ghGreen = Color(0xFF006B3F);

const List<Map<String, String>> defaultAccounts = [
  {'username': 'admin', 'password': 'Ad1My', 'station': 'Head Office', 'role': 'admin', 'full_name': 'System Admin'},
  {'username': 'capecoast', 'password': 'cape123', 'station': 'Cape Coast', 'role': 'station_master', 'full_name': 'Cape Coast Master'},
  {'username': 'swedru', 'password': 'swedru123', 'station': 'Swedru', 'role': 'station_master', 'full_name': 'Swedru Master'},
  {'username': 'accra', 'password': 'accra123', 'station': 'Accra', 'role': 'station_master', 'full_name': 'Accra Master'},
  {'username': 'kumasi', 'password': 'kumasi123', 'station': 'Kumasi', 'role': 'station_master', 'full_name': 'Kumasi Master'},
  {'username': 'tamale', 'password': 'tamale123', 'station': 'Tamale', 'role': 'station_master', 'full_name': 'Tamale Master'},
  {'username': 'master', 'password': 'master123', 'station': 'All Stations', 'role': 'station_master', 'full_name': 'General Master'},
];

String hashPassword(String p) {
  final salt = Random.secure().toString() + DateTime.now().millisecondsSinceEpoch.toString();
  final s = sha256.convert(utf8.encode(salt)).toString().substring(0, 32);
  final bytes = utf8.encode(p + s);
  var h = sha256.convert(bytes);
  for (int i = 0; i < 1000; i++) { h = sha256.convert(h.bytes); }
  return "$s\$${h.toString()}";
}
bool verifyPassword(String stored, String provided) {
  try {
    if (stored.contains("\$")) {
      final parts = stored.split("\$");
      final s = parts[0]; final h = parts[1];
      final bytes = utf8.encode(provided + s);
      var ch = sha256.convert(bytes);
      for (int i = 0; i < 1000; i++) { ch = sha256.convert(ch.bytes); }
      return ch.toString() == h;
    } else { return stored == sha256.convert(utf8.encode(provided)).toString(); }
  } catch (_) { return false; }
}

class AppDB {
  static Database? _db;
  static Future<Database> getDB() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(path.join(dbPath, dbFile), version: 2, onCreate: (db, v) async {
      await db.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY,password TEXT,station TEXT,role TEXT,full_name TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS fares (from_s TEXT,to_s TEXT,fare REAL,PRIMARY KEY (from_s,to_s))');
      await db.execute('CREATE TABLE IF NOT EXISTS seats (seat TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE IF NOT EXISTS sales (ticket_id TEXT PRIMARY KEY,date TEXT,time TEXT,name TEXT,from_s TEXT,to_s TEXT,fare REAL,seat TEXT,sold_by TEXT)');
    }, onUpgrade: (db, oldV, newV) async {
      await db.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY,password TEXT,station TEXT,role TEXT,full_name TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS fares (from_s TEXT,to_s TEXT,fare REAL,PRIMARY KEY (from_s,to_s))');
      await db.execute('CREATE TABLE IF NOT EXISTS seats (seat TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE IF NOT EXISTS sales (ticket_id TEXT PRIMARY KEY,date TEXT,time TEXT,name TEXT,from_s TEXT,to_s TEXT,fare REAL,seat TEXT,sold_by TEXT)');
    });
    return _db!;
  }
}

Future<String> syncUsersFromCloud() async {
  try {
    final snap = await FirebaseFirestore.instance.collection('users').get().timeout(const Duration(seconds: 6));
    if (snap.docs.isEmpty) return "Cloud: No new accounts - Default accounts active";
    final db = await AppDB.getDB();
    int count = 0;
    for (var doc in snap.docs) {
      final data = doc.data();
      await db.insert('users', {
        'username': data['username'],
        'password': data['password'],
        'station': data['station'],
        'role': data['role'],
        'full_name': data['full_name'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }
    return "✅ Synced $count accounts from cloud";
  } catch (e) {
    return "Offline mode - Using local accounts. Turn on data to sync new accounts";
  }
}

Future<void> ensureDefaultUsers(Database db) async {
  for (var acc in defaultAccounts) {
    try {
      await db.insert('users', {
        'username': acc['username'],
        'password': hashPassword(acc['password']!),
        'station': acc['station'],
        'role': acc['role'],
        'full_name': acc['full_name'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (_) {}
  }
  try {
    final snap = await FirebaseFirestore.instance.collection('users').get().timeout(const Duration(seconds: 4));
    for (var doc in snap.docs) {
      final data = doc.data();
      await db.insert('users', {
        'username': data['username'],
        'password': data['password'],
        'station': data['station'],
        'role': data['role'],
        'full_name': data['full_name'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  } catch (_) {}
}

Future<void> initDB() async {
  final db = await AppDB.getDB();
  await ensureDefaultUsers(db);
  final dir = await getApplicationDocumentsDirectory();
  final f = File(path.join(dir.path, fareFile));
  if (await f.exists()) {
    try {
      final old = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (var fs in old.keys) {
        final dests = old[fs] as Map<String, dynamic>;
        for (var ts in dests.keys) {
          await db.insert('fares', {'from_s': fs, 'to_s': ts, 'fare': (dests[ts] as num).toDouble()}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    } catch (_) {}
  } else {
    final dr = {"cape coast": {"swedru": 45.0, "accra": 35.0, "kumasi": 25.0}, "swedru": {"cape coast": 45.0, "accra": 20.0, "kumasi": 30.0}, "accra": {"cape coast": 35.0, "swedru": 20.0, "kumasi": 45.0}, "kumasi": {"cape coast": 25.0, "swedru": 30.0, "accra": 45.0, "tamale": 65.0}, "tamale": {"kumasi": 65.0}};
    for (var fs in dr.keys) { for (var ts in dr[fs]!.keys) { await db.insert('fares', {'from_s': fs, 'to_s': ts, 'fare': dr[fs]![ts]}, conflictAlgorithm: ConflictAlgorithm.replace); } }
  }
}
Future<Map<String, Map<String, dynamic>>> loadUsers() async {
  final db = await AppDB.getDB();
  await ensureDefaultUsers(db);
  final rows = await db.query('users');
  final Map<String, Map<String, dynamic>> users = {};
  for (var r in rows) { users[r['username'] as String] = {'password': r['password'], 'station': r['station'], 'role': r['role'], 'full_name': r['full_name']}; }
  if (users.isEmpty) {
    for (var acc in defaultAccounts) {
      users[acc['username']!] = {"password": hashPassword(acc['password']!), "station": acc['station'], "role": acc['role'], "full_name": acc['full_name']};
    }
  }
  return users;
}
Future<void> saveUsers(Map<String, Map<String, dynamic>> users) async {
  final db = await AppDB.getDB();
  for (var u in users.keys) {
    await db.insert('users', {
      'username': u,
      'password': users[u]!['password'],
      'station': users[u]!['station'],
      'role': users[u]!['role'],
      'full_name': users[u]!['full_name']
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  try {
    for (var u in users.keys) {
      if (!defaultAccounts.any((a) => a['username'] == u)) {
        FirebaseFirestore.instance.collection('users').doc(u).set({
          'username': u,
          'password': users[u]!['password'],
          'station': users[u]!['station'],
          'role': users[u]!['role'],
          'full_name': users[u]!['full_name'],
        });
      }
    }
  } catch (_) {}
}
Future<Map<String, Map<String, double>>> loadFares() async {
  final db = await AppDB.getDB();
  final rows = await db.query('fares');
  final Map<String, Map<String, double>> routes = {};
  for (var r in rows) { final fs = r['from_s'] as String; final ts = r['to_s'] as String; routes.putIfAbsent(fs, () => {})[ts] = (r['fare'] as num).toDouble(); }
  if (routes.isEmpty) { return {"cape coast": {"swedru": 45.0, "accra": 35.0, "kumasi": 25.0}, "swedru": {"cape coast": 45.0, "accra": 20.0, "kumasi": 30.0}, "accra": {"cape coast": 35.0, "swedru": 20.0, "kumasi": 45.0}, "kumasi": {"cape coast": 25.0, "swedru": 30.0, "accra": 45.0, "tamale": 65.0}, "tamale": {"kumasi": 65.0}}; }
  return routes;
}
Future<void> saveFares(Map<String, Map<String, double>> routes) async {
  final db = await AppDB.getDB(); await db.delete('fares');
  for (var fs in routes.keys) { for (var ts in routes[fs]!.keys) { await db.insert('fares', {'from_s': fs, 'to_s': ts, 'fare': routes[fs]![ts]}); } }
  final dir = await getApplicationDocumentsDirectory(); await File(path.join(dir.path, fareFile)).writeAsString(jsonEncode(routes));
}
Future<List<String>> loadSeats() async {
  final db = await AppDB.getDB(); final rows = await db.query('seats'); final used = rows.map((e) => e['seat'] as String).toSet();
  final allSeats = [for (int i = 1; i <= 30; i++) "A${i.toString().padLeft(2, '0')}"];
  return allSeats.where((s) => !used.contains(s)).toList();
}
Future<void> saveSeat(String seat) async { final db = await AppDB.getDB(); await db.insert('seats', {'seat': seat}, conflictAlgorithm: ConflictAlgorithm.ignore); }
String generateTicketId() => "T${Random().nextInt(90001) + 9999}";
String titleCase(String s) => s.isEmpty ? s : s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

Future<String> printSmallPaper(Map<String, dynamic> sale) async {
  final dir = await getApplicationDocumentsDirectory();
  final fn = "PRINT_${sale['ticket_id']}.txt";
  final rn = "${titleCase(sale['from'])}-${titleCase(sale['to'])}";
  final qr = "REALME|${sale['ticket_id']}|${sale['seat']}|$rn|${sale['fare']}|${sale['date']}";
  final content = "REAL ME TROTRO - GOV EDITION\nTicket: ${sale['ticket_id']}\nDate: ${sale['date']} ${sale['time']}\nPassenger: ${sale['name']}\nRoute: $rn\nSeat: ${sale['seat']}\nSold By: ${sale['sold_by']}\nFARE: GHS ${(sale['fare'] as double).toStringAsFixed(2)} PAID\nQR: $qr\n";
  final file = File(path.join(dir.path, fn)); await file.writeAsString(content, encoding: utf8); return file.path;
}
Future<String> generatePdfTicket(Map<String, dynamic> d) async {
  try {
    final rn = "${titleCase(d['from'])}-${titleCase(d['to'])}";
    final qr = "REALME|${d['ticket_id']}|${d['seat']}|$rn|${d['fare']}|${d['date']} ${d['time']}";
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (context) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(color: PdfColor.fromHex('CE1126'), width: double.infinity, padding: const pw.EdgeInsets.all(12), child: pw.Column(children: [pw.Text('REAL ME TROTRO - GOVERNMENT EDITION', style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)), pw.Text('Safe. Fast. Reliable. | Government Approved', style: const pw.TextStyle(color: PdfColors.white, fontSize: 9))])),
        pw.SizedBox(height: 16), pw.Text('Ticket ID: ${d['ticket_id']}'), pw.Text('Name: ${d['name']}'), pw.Text('Sold By: ${d['sold_by']}'), pw.Text('Route: $rn'), pw.Text('Seat: ${d['seat']}'), pw.Text('Fare: GHS ${(d['fare'] as double).toStringAsFixed(2)} PAID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('Date: ${d['date']} ${d['time']}'), pw.SizedBox(height: 12), pw.Text('QR: $qr', style: const pw.TextStyle(fontSize: 8)),
      ]);
    }));
    final dir = await getApplicationDocumentsDirectory();
    final fn = path.join(dir.path, "ticket_${d['ticket_id']}.pdf");
    final file = File(fn); await file.writeAsBytes(await pdf.save()); return fn;
  } catch (_) {
    final dir = await getApplicationDocumentsDirectory(); final fn = path.join(dir.path, "ticket_${d['ticket_id']}.txt"); await File(fn).writeAsString("REAL ME TROTRO\n$d\n"); return fn;
  }
}
Future<Map<String, dynamic>> saveSale(String name, String fs, String ts, double fare, String seat) async {
  final now = DateTime.now();
  final today = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";
  final tn = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";
  final tid = generateTicketId();
  final sale = {"ticket_id": tid, "date": today, "time": tn, "name": name, "from": fs, "to": ts, "fare": fare, "seat": seat, "sold_by": currentUser ?? "Kiosk"};
  final db = await AppDB.getDB();
  await db.insert('sales', {'ticket_id': tid, 'date': today, 'time': tn, 'name': name, 'from_s': fs, 'to_s': ts, 'fare': fare, 'seat': seat, 'sold_by': sale['sold_by']});
  try { await generatePdfTicket(sale); } catch (_) {}
  return sale;
}
Future<String> showSalesReport() async {
  final now = DateTime.now(); final today = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";
  final db = await AppDB.getDB(); final rows = await db.query('sales', where: 'date=?', whereArgs: [today]);
  if (rows.isEmpty) return "No sales today";
  final total = rows.length; final money = rows.fold<double>(0, (p, e) => p + (e['fare'] as num).toDouble()); final seatsLeft = (await loadSeats()).length;
  return "DAILY SALES - $today\nTotal: $total | GHS ${money.toStringAsFixed(2)} | Seats left: $seatsLeft/30";
}
Future<String> showSeatMap() async {
  final db = await AppDB.getDB(); final rows = await db.query('seats'); final used = rows.map((e) => e['seat'] as String).toSet();
  final buffer = StringBuffer("SEAT MAP\n${"=" * 35}\n");
  for (int i = 0; i < 30; i += 4) { final row = [for (int j = i + 1; j <= i + 4; j++) "A${j.toString().padLeft(2, '0')}"]; buffer.writeln(row.map((s) => used.contains(s) ? "[XX]" : "[$s]").join(" ")); }
  buffer.writeln("=" * 35); return buffer.toString();
}
Future<String> exportSalesToExcel({required bool todayOnly}) async {
  final now = DateTime.now(); final today = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";
  final db = await AppDB.getDB(); List<Map<String, Object?>> rows; String base;
  if (todayOnly) { rows = await db.query('sales', where: 'date=?', whereArgs: [today]); base = "sales_$today"; } else { rows = await db.query('sales'); base = "sales_ALL_$today"; }
  if (rows.isEmpty) return "No sales!";
  final dir = await getApplicationDocumentsDirectory(); final csvFile = File(path.join(dir.path, "$base.csv")); final sb = StringBuffer();
  sb.writeln("Ticket ID,Date,Time,Name,From,To,Fare,Seat,Sold By"); double tot = 0;
  for (var r in rows) { sb.writeln("${r['ticket_id']},${r['date']},${r['time']},${r['name']},${r['from_s']},${r['to_s']},${r['fare']},${r['seat']},${r['sold_by']}"); tot += (r['fare'] as num).toDouble(); }
  sb.writeln(); sb.writeln("TOTAL,${rows.length}"); sb.writeln("MONEY,GHS ${tot.toStringAsFixed(2)}"); await csvFile.writeAsString(sb.toString());
  return "CSV: ${csvFile.path} | ${rows.length} tickets";
}
int _levenshtein(String a, String b) {
  if (a == b) return 0; if (a.isEmpty) return b.length; if (b.isEmpty) return a.length;
  List<List<int>> d = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (int i = 0; i <= a.length; i++) d[i][0] = i; for (int j = 0; j <= b.length; j++) d[0][j] = j;
  for (int i = 1; i <= a.length; i++) { for (int j = 1; j <= b.length; j++) { int cost = a[i-1] == b[j-1] ? 0 : 1; d[i][j] = [d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost].reduce((x,y) => x<y?x:y); } }
  return d[a.length][b.length];
}
double _ratio(String a, String b) { if (a.isEmpty && b.isEmpty) return 1; final dist = _levenshtein(a, b); final maxLen = a.length > b.length ? a.length : b.length; return 1 - dist / maxLen; }
String suggestStation(String u, Map<String, Map<String, double>> routes, {bool Function(String found)? onConfirm}) {
  final input = u.toLowerCase().trim().replaceAll(" ", "");
  final allS = routes.keys.toList(); if (allS.contains(input)) return input;
  final noSpace = {for (var s in allS) s.replaceAll(" ", ""): s};
  final matches = [for (var k in noSpace.keys) if (k.contains(input)) noSpace[k]!];
  if (matches.isNotEmpty) return matches[0];
  String? best; double bestScore = 0;
  for (var k in noSpace.keys) { final r = _ratio(input, k); if (r > bestScore && r >= 0.6) { bestScore = r; best = k; } }
  if (best != null) { final found = noSpace[best]!; if (onConfirm == null || onConfirm(found)) return found; }
  return u.toLowerCase().trim();
}
String resolveStation(String typedText, String? dropVal) {
  if (typedText.trim().isNotEmpty) return suggestStation(typedText, routes);
  if (dropVal != null) return dropVal;
  return "";
}
late Map<String, Map<String, double>> routes;
late Map<String, Map<String, dynamic>> users;

Future<void> main() async { 
  WidgetsFlutterBinding.ensureInitialized(); 
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint("Firebase init offline: $e");
  }
  await initDB(); 
  routes = await loadFares(); 
  users = await loadUsers(); 
  runApp(const TrotroApp()); 
}

class TrotroApp extends StatelessWidget {
  const TrotroApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(title: 'Real Me Trotro', debugShowCheckedModeBanner: false, theme: ThemeData(primaryColor: ghRed, colorScheme: ColorScheme.fromSeed(seedColor: ghRed, primary: ghRed), appBarTheme: const AppBarTheme(backgroundColor: ghRed, foregroundColor: Colors.white)), home: const MainMenuScreen());
  }
}

class MainMenuScreen extends StatefulWidget { const MainMenuScreen({super.key}); @override State<MainMenuScreen> createState() => _MainMenuScreenState(); }
class _MainMenuScreenState extends State<MainMenuScreen> {
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("REAL ME TROTRO"), backgroundColor: ghRed, foregroundColor: Colors.white),
      body: Column(children: [
        Container(width: double.infinity, color: ghRed, padding: const EdgeInsets.all(16), child: Column(children: [const Text("🇬🇭 REAL ME TROTRO", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), Text(appSlogan, style: const TextStyle(color: Colors.white)), const SizedBox(height: 8), Container(height: 6, color: ghGold), Container(height: 6, color: ghGreen)])),
        Expanded(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("Login: ${currentUser ?? 'Guest'}", textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PassengerScreen())), style: ElevatedButton.styleFrom(backgroundColor: ghGreen, foregroundColor: Colors.white), child: const Text("1. Passenger - CHECK FARE")),
          ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())), style: ElevatedButton.styleFrom(backgroundColor: ghRed, foregroundColor: Colors.white), child: const Text("2. Station Master Login")),
          ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAccountScreen())), style: ElevatedButton.styleFrom(backgroundColor: ghGold, foregroundColor: Colors.black), child: const Text("3. Admin - Create/Delete")),
          ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerifyScreen())), child: const Text("4. Verify Ticket")),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("5. Exit")),
        ]))),
      ]));
  }
}

class PassengerScreen extends StatefulWidget { const PassengerScreen({super.key}); @override State<PassengerScreen> createState() => _PassengerScreenState(); }
class _PassengerScreenState extends State<PassengerScreen> {
  String? fromVal; String? toVal; final fromC = TextEditingController(); final toC = TextEditingController(); String result = "";
  double? autoFare; String autoRoute = "";
  @override void initState() {
    super.initState();
    fromC.addListener(_autoCheck);
    toC.addListener(_autoCheck);
  }
  @override void dispose() { fromC.dispose(); toC.dispose(); super.dispose(); }
  void _autoCheck() {
    final fs = resolveStation(fromC.text, fromVal);
    final ts = resolveStation(toC.text, toVal);
    if (fs.isEmpty || ts.isEmpty) { setState(() { autoFare = null; autoRoute = ""; }); return; }
    if (routes.containsKey(fs) && routes[fs]!.containsKey(ts)) {
      setState(() { autoFare = routes[fs]![ts]!; autoRoute = "${titleCase(fs)} -> ${titleCase(ts)}"; result = "FARE: $autoRoute = GHS ${autoFare!.toStringAsFixed(2)}"; });
    } else { setState(() { autoFare = null; autoRoute = ""; }); }
  }
  @override Widget build(BuildContext context) {
    final stations = routes.keys.toList();
    return Scaffold(appBar: AppBar(title: const Text("PASSENGER CHECK")), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
      const Text("Select OR Type Station - Both Work", style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: fromVal, decoration: const InputDecoration(labelText: "From - Select"), items: stations.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { setState(() { fromVal = v; fromC.text = v ?? ""; }); _autoCheck(); }),
      TextField(controller: fromC, decoration: const InputDecoration(labelText: "From - Or Type Here", hintText: "e.g. Cape Coast")),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: toVal, decoration: const InputDecoration(labelText: "To - Select"), items: stations.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { setState(() { toVal = v; toC.text = v ?? ""; }); _autoCheck(); }),
      TextField(controller: toC, decoration: const InputDecoration(labelText: "To - Or Type Here", hintText: "e.g. Swedru")),
      const SizedBox(height: 12),
      if (autoFare != null) Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: ghGreen, width: 2), borderRadius: BorderRadius.circular(12)), child: Column(children: [
        Text(autoRoute, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text("FARE: GHS ${autoFare!.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: ghGreen)),
        const Text("Safe. Fast. Reliable.", style: TextStyle(fontSize: 12, color: Colors.grey)),
      ])),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: () {
        final fs = resolveStation(fromC.text, fromVal);
        final ts = resolveStation(toC.text, toVal);
        if (fs.isEmpty || ts.isEmpty) { setState(() => result = "Select or type From and To"); return; }
        if (routes.containsKey(fs) && routes[fs]!.containsKey(ts)) { setState(() => result = "FARE: ${titleCase(fs)} -> ${titleCase(ts)} = GHS ${routes[fs]![ts]!.toStringAsFixed(2)}"); } else { setState(() => result = "No route from $fs to $ts"); }
      }, child: const Text("CHECK FARE")),
      const SizedBox(height: 16),
      Text(result, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      if (result.startsWith("FARE:")) ...[
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: ghRed, width: 2), borderRadius: BorderRadius.circular(8)), child: const Text("⚠️ Don't pay any amount except this fare! If driver asks for more, do NOT pay.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ghRed))),
      ],
    ])));
  }
}

class CreateAccountScreen extends StatefulWidget { const CreateAccountScreen({super.key}); @override State<CreateAccountScreen> createState() => _CreateAccountScreenState(); }
class _CreateAccountScreenState extends State<CreateAccountScreen> {
  String? adminUser;
  final adminU = TextEditingController(); final adminP = TextEditingController();
  final newU = TextEditingController(); final fullN = TextEditingController(); final newP = TextEditingController(); final stationC = TextEditingController();
  final delU = TextEditingController();
  String cloudMsg = "";
  @override Widget build(BuildContext context) {
    if (adminUser == null) {
      return Scaffold(appBar: AppBar(title: const Text("ADMIN - SECURE ACCESS"), backgroundColor: ghRed), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Icon(Icons.lock, size: 60, color: ghRed),
        const Text("ADMIN ONLY", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text("Government Approved Access", style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        TextField(controller: adminU, decoration: const InputDecoration(labelText: "Admin Username")),
        TextField(controller: adminP, obscureText: true, decoration: const InputDecoration(labelText: "Admin Password")),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: () {
          final un = adminU.text.toLowerCase().trim();
          final pw = adminP.text.trim();
          if (users.containsKey(un) && verifyPassword(users[un]!['password'], pw) && users[un]!['role'] == 'admin') {
            setState(() => adminUser = un);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Admin Auth OK")));
          } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Auth failed!"))); }
        }, style: ElevatedButton.styleFrom(backgroundColor: ghGreen, foregroundColor: Colors.white), child: const Text("VERIFY ADMIN")),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Back")),
      ])));
    }
    return Scaffold(appBar: AppBar(title: Text("ADMIN - $adminUser"), backgroundColor: ghGreen), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue, width: 2), borderRadius: BorderRadius.circular(8)), child: const Text("Admin creates account here (needs internet) -> Account goes to cloud -> Station master taps SYNC on his own device to login. Secure & Tight!", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
      const SizedBox(height: 12),
      const Text("1. Create Station Master", style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: newU, decoration: const InputDecoration(labelText: "Username e.g. cape2")),
      TextField(controller: fullN, decoration: const InputDecoration(labelText: "Full Name")),
      TextField(controller: newP, decoration: const InputDecoration(labelText: "Password")),
      TextField(controller: stationC, decoration: const InputDecoration(labelText: "Station")),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () async {
        final nu = newU.text.toLowerCase().trim();
        if (nu.contains(" ") || nu.isEmpty || users.containsKey(nu)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid or exists!"))); return; }
        users[nu] = {"password": hashPassword(newP.text), "station": titleCase(stationC.text.trim()), "role": "station_master", "full_name": titleCase(fullN.text.trim())};
        setState(() => cloudMsg = "⏳ Uploading to cloud...");
        await saveUsers(users);
        setState(() => cloudMsg = "✅ $nu uploaded! Tell station master to SYNC");
        final createdName = users[nu]!['full_name'];
        newU.clear(); fullN.clear(); newP.clear(); stationC.clear();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Created $createdName | $nu - Station master can now login on his device!")));
      }, style: ElevatedButton.styleFrom(backgroundColor: ghGreen, foregroundColor: Colors.white), child: const Text("CREATE ACCOUNT")),
      Text(cloudMsg, style: const TextStyle(fontWeight: FontWeight.bold, color: ghGreen)),
      const Divider(),
      const Text("2. Delete", style: TextStyle(fontWeight: FontWeight.bold)),
      ...users.entries.map((e) => Text(" - ${e.key} | ${e.value['full_name']} | ${e.value['station']}")),
      TextField(controller: delU, decoration: const InputDecoration(labelText: "Delete username")),
      ElevatedButton(onPressed: () async {
        final du = delU.text.toLowerCase().trim();
        if (!users.containsKey(du)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Not found!"))); return; }
        if (du == adminUser || du == "admin") { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot delete self/admin!"))); return; }
        if (defaultAccounts.any((a) => a['username'] == du)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot delete default!"))); return; }
        final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text("DELETE $du?"), actions: [TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("YES")), TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("NO"))]));
        if (confirm == true) { 
          users.remove(du); 
          final db = await AppDB.getDB();
          await db.delete('users', where: 'username=?', whereArgs: [du]);
          try { await FirebaseFirestore.instance.collection('users').doc(du).delete(); } catch (_){}
          delU.clear(); setState(() {}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("DELETED $du"))); 
        }
      }, child: const Text("DELETE")),
      const Divider(),
      ...users.entries.map((e) => Text("${e.key} | ${e.value['full_name']} | ${e.value['station']}")),
      ElevatedButton(onPressed: () => setState(() => adminUser = null), child: const Text("Logout Admin")),
      ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Back")),
    ])));
  }
}

class VerifyScreen extends StatefulWidget { const VerifyScreen({super.key}); @override State<VerifyScreen> createState() => _VerifyScreenState(); }
class _VerifyScreenState extends State<VerifyScreen> {
  final qrC = TextEditingController(); String result = "";
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("VERIFY")), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: qrC, decoration: const InputDecoration(labelText: "Paste QR text")),
      ElevatedButton(onPressed: () async {
        final qr = qrC.text.trim();
        if (!qr.startsWith("REALME|")) { setState(() => result = "INVALID"); return; }
        final tid = qr.split("|")[1];
        final db = await AppDB.getDB();
        final row = await db.query('sales', where: 'ticket_id=?', whereArgs: [tid]);
        setState(() => result = row.isNotEmpty ? "VALID! ${row.first}" : "FAKE! $tid not found");
      }, child: const Text("VERIFY")),
      Text(result),
    ])));
  }
}

class LoginScreen extends StatefulWidget { const LoginScreen({super.key}); @override State<LoginScreen> createState() => _LoginScreenState(); }
class _LoginScreenState extends State<LoginScreen> {
  final unC = TextEditingController(); final pwC = TextEditingController();
  String syncStatus = "Checking cloud...";
  int cloudCount = 0;
  @override void initState() { super.initState(); _doSync(); }
  Future<void> _doSync() async {
    setState(() => syncStatus = "Syncing accounts from cloud...");
    final msg = await syncUsersFromCloud();
    users = await loadUsers();
    setState(() { syncStatus = msg; cloudCount = users.length; });
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("STATION MASTER LOGIN"), backgroundColor: ghRed),
      body: Padding(padding: const EdgeInsets.all(16), child: SingleChildScrollView(child: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: syncStatus.contains("✅") ? Colors.green.shade50 : Colors.orange.shade50, border: Border.all(color: syncStatus.contains("✅") ? ghGreen : ghGold, width: 2), borderRadius: BorderRadius.circular(8)), child: Column(children: [
          Text(syncStatus, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          Text("$cloudCount accounts available", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ])),
        const SizedBox(height: 12),
        ElevatedButton.icon(onPressed: _doSync, icon: const Icon(Icons.cloud_sync), label: const Text("SYNC FROM CLOUD"), style: ElevatedButton.styleFrom(backgroundColor: ghGold, foregroundColor: Colors.black, padding: const EdgeInsets.all(14))),
        const Divider(height: 24),
        const Text("Secure Login - Your Own Device", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(controller: unC, decoration: const InputDecoration(labelText: "Username", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
        const SizedBox(height: 12),
        TextField(controller: pwC, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
          final un = unC.text.toLowerCase().trim();
          users = await loadUsers();
          if (users.containsKey(un) && verifyPassword(users[un]!['password'], pwC.text.trim())) {
            currentUser = un;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Welcome ${users[un]!['full_name']}!")));
            Navigator.push(context, MaterialPageRoute(builder: (_) => StationMasterScreen(username: un)));
          } else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wrong password! Have $cloudCount accounts"))); }
        }, style: ElevatedButton.styleFrom(backgroundColor: ghGreen, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)), child: const Text("LOGIN"))),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: const Text("How it works:\n\n1. Admin creates account in Head Office (needs internet)\n2. Admin tells you username & password via phone\n3. Turn on data, tap SYNC FROM CLOUD\n4. Login with your credentials\n5. After first login, work offline\n\nSafe. Fast. Reliable. Government Approved!", style: TextStyle(fontSize: 12))),
      ]))),
    );
  }
}

class StationMasterScreen extends StatefulWidget { final String username; const StationMasterScreen({super.key, required this.username}); @override State<StationMasterScreen> createState() => _StationMasterScreenState(); }
class _StationMasterScreenState extends State<StationMasterScreen> {
  final nameC = TextEditingController(); final fromC = TextEditingController(); final toC = TextEditingController();
  String? fromVal; String? toVal;
  final updFromC = TextEditingController(); final updToC = TextEditingController(); final updFareC = TextEditingController();
  String? updFromVal; String? updToVal;
  final newFromC = TextEditingController(); final newToC = TextEditingController(); final newFareC = TextEditingController();
  String info = ""; Map<String, dynamic>? lastSale;
  Future<void> doPrint(Map<String, dynamic> sale) async {
    try {
      final pdfPath = await generatePdfTicket(sale);
      final bytes = await File(pdfPath).readAsBytes();
      await Printing.sharePdf(bytes: bytes, filename: 'ticket_${sale['ticket_id']}.pdf');
    } catch (_) {
      final p = await printSmallPaper(sale);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PRINT FILE: $p")));
    }
  }
  @override Widget build(BuildContext context) {
    final stations = routes.keys.toList();
    return Scaffold(appBar: AppBar(title: Text("Welcome ${users[widget.username]!['full_name']} - ${users[widget.username]!['station']}")), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text("STATION MASTER - SELL TICKET", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.yellow.shade100, border: Border.all(color: ghGold, width: 2), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("STEP 1: PASSENGER NAME *", style: TextStyle(fontWeight: FontWeight.bold, color: ghRed)),
        TextField(controller: nameC, decoration: const InputDecoration(labelText: "Type Passenger Name Here", hintText: "e.g. Kwame Mensah", border: OutlineInputBorder())),
      ])),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: fromVal, decoration: const InputDecoration(labelText: "From - Select"), items: stations.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { setState(() { fromVal = v; fromC.text = v ?? ""; }); }),
      TextField(controller: fromC, decoration: const InputDecoration(labelText: "From - Or Type Here")),
      DropdownButtonFormField<String>(value: toVal, decoration: const InputDecoration(labelText: "To - Select"), items: stations.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { setState(() { toVal = v; toC.text = v ?? ""; }); }),
      TextField(controller: toC, decoration: const InputDecoration(labelText: "To - Or Type Here")),
      ElevatedButton(onPressed: () async {
        if (nameC.text.trim().isEmpty) { setState(() => info = "Enter passenger name!"); return; }
        final fs = resolveStation(fromC.text, fromVal);
        final ts = resolveStation(toC.text, toVal);
        if (fs.isEmpty || ts.isEmpty) { setState(() => info = "Select From and To!"); return; }
        if (!routes.containsKey(fs) || !routes[fs]!.containsKey(ts)) { setState(() => info = "No route"); return; }
        final seats = await loadSeats();
        if (seats.isEmpty) { setState(() => info = "Bus FULL! Reset"); return; }
        final fare = routes[fs]![ts]!;
        final seat = seats.first;
        await saveSeat(seat);
        final sale = await saveSale(nameC.text.trim(), fs, ts, fare, seat);
        setState(() { lastSale = sale; info = "SOLD! ${sale['ticket_id']} | $seat | GHS ${fare.toStringAsFixed(2)}"; nameC.clear(); fromC.clear(); toC.clear(); fromVal = null; toVal = null; });
        if (!context.mounted) return;
        showDialog(context: context, builder: (_) => AlertDialog(title: const Text("✅ TICKET SOLD!"), content: Text("Ticket: ${sale['ticket_id']}\nPassenger: ${sale['name']}\nRoute: ${titleCase(fs)} -> ${titleCase(ts)}\nSeat: $seat\nFare: GHS ${fare.toStringAsFixed(2)}"), actions: [
          TextButton(onPressed: () async { Navigator.pop(context); await doPrint(sale); }, child: const Text("🖨️ PRINT")),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ]));
      }, style: ElevatedButton.styleFrom(backgroundColor: ghGreen, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)), child: const Text("SELL TICKET")),
      if (lastSale != null) ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: ghGreen)), child: Column(children: [
          Text("LAST: ${lastSale!['ticket_id']} | ${lastSale!['seat']} | GHS ${(lastSale!['fare'] as double).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: () => doPrint(lastSale!), style: ElevatedButton.styleFrom(backgroundColor: ghRed, foregroundColor: Colors.white), child: const Text("🖨️ PRINT THIS TICKET")),
        ])),
      ],
      const Divider(height: 30),
      ElevatedButton(onPressed: () { String s = ""; for (var fs in routes.keys) { for (var ts in routes[fs]!.keys) { if (fs.compareTo(ts) < 0) s += "${titleCase(fs)} <-> ${titleCase(ts)}: GHS ${routes[fs]![ts]!.toStringAsFixed(2)}\n"; } } setState(() => info = s); }, child: const Text("View routes")),
      ElevatedButton(onPressed: () async { final r = await showSalesReport(); setState(() => info = r); }, child: const Text("Daily Sales")),
      ElevatedButton(onPressed: () async { final r = await showSeatMap(); setState(() => info = r); }, child: const Text("Seat Map")),
      ElevatedButton(onPressed: () async { final r1 = await exportSalesToExcel(todayOnly: true); final r2 = await exportSalesToExcel(todayOnly: false); setState(() => info = "$r1\n$r2"); }, child: const Text("Export CSV")),
      ElevatedButton(onPressed: () async { final db = await AppDB.getDB(); await db.delete('seats'); setState(() => info = "Reset done"); }, child: const Text("Reset seats")),
      ElevatedButton(onPressed: () { currentUser = null; Navigator.pop(context); }, child: const Text("Logout")),
      const SizedBox(height: 16), Text(info, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
    ])));
  }
}
