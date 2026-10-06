import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MaterialApp(home: TrotroFullApp(), debugShowCheckedModeBanner: false));

String hashPassword(String p) {
  var salt = Random().nextInt(999999).toString();
  return "$salt\$${sha256.convert(utf8.encode(salt + p)).toString()}";
}
bool verifyPassword(String stored, String provided) {
  try {
    if (stored.contains("\$")) {
      var a = stored.split("\$");
      return sha256.convert(utf8.encode(a[0] + provided)).toString() == a[1];
    }
    return false;
  } catch (_) { return false; }
}

class TrotroFullApp extends StatefulWidget { @override _TrotroFullAppState createState() => _TrotroFullAppState(); }

class _TrotroFullAppState extends State<TrotroFullApp> {
  Map<String, dynamic> users = {};
  Map<String, dynamic> routes = {};
  List<String> usedSeats = [];
  List<Map<String, dynamic>> sales = [];
  String? currentUser;
  String output = "Welcome to REAL ME TROTRO v12 FULL";

  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final fareCtrl = TextEditingController();
  final qrCtrl = TextEditingController();

  @override
  void initState() { super.initState(); initDB(); }

  Future<void> initDB() async {
    final prefs = await SharedPreferences.getInstance();
    var db = prefs.getString('trotro_v12_db');
    if (db!= null) {
      var d = jsonDecode(db);
      users = Map<String, dynamic>.from(d['users']?? {});
      routes = Map<String, dynamic>.from(d['routes']?? {});
      usedSeats = List<String>.from(d['seats']?? []);
      sales = List<Map<String, dynamic>>.from(d['sales']?? []);
    }
    if (users.isEmpty) {
      users["admin"] = {"password": hashPassword("Ad1My"), "station": "Head Office", "role": "admin", "full_name": "System Admin"};
    }
    if (routes.isEmpty) {
      routes = {
        "cape coast": {"swedru": 45.0, "accra": 35.0, "kumasi": 25.0},
        "swedru": {"cape coast": 45.0, "accra": 20.0, "kumasi": 30.0},
        "accra": {"cape coast": 35.0, "swedru": 20.0, "kumasi": 45.0},
        "kumasi": {"cape coast": 25.0, "swedru": 30.0, "accra": 45.0, "tamale": 65.0},
        "tamale": {"kumasi": 65.0}
      };
    }
    await saveDB();
    setState(()=>output="DB Loaded | Users: ${users.length} | Routes: ${routes.length} | Sales: ${sales.length}");
  }

  Future<void> saveDB() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trotro_v12_db', jsonEncode({"users": users, "routes": routes, "seats": usedSeats, "sales": sales}));
  }

  String genId() => "T${Random().nextInt(90000)+10000}";
  List<String> loadSeats() {
    var all = List.generate(30, (i) => "A${(i+1).toString().padLeft(2,'0')}");
    return all.where((s) =>!usedSeats.contains(s)).toList();
  }

  // 1. PASSENGER CHECK FARE
  void checkFare() {
    var f = fromCtrl.text.toLowerCase().trim();
    var t = toCtrl.text.toLowerCase().trim();
    if (!routes.containsKey(f)) { setState(()=>output="❌ No station '$f' | Available: ${routes.keys.join(', ')}"); return; }
    var fare = routes[f][t];
    setState(()=>output = fare!=null? "✅ FARE: ${f.toUpperCase()} -> ${t.toUpperCase()} = GHS $fare" : "❌ No route $f -> $t");
  }

  // 2. SELL TICKET
  void sellTicket() {
    if (currentUser == null) { setState(()=>output="❌ Login as Station Master first!"); return; }
    var seats = loadSeats();
    if (seats.isEmpty) { setState(()=>output="❌ Bus FULL! Reset seats"); return; }
    var f = fromCtrl.text.toLowerCase().trim();
    var t = toCtrl.text.toLowerCase().trim();
    var name = nameCtrl.text.trim();
    if (name.isEmpty || f.isEmpty || t.isEmpty) { setState(()=>output="❌ Fill Name, From, To"); return; }
    if (routes[f]?[t]==null) { setState(()=>output="❌ No route $f -> $t"); return; }
    var fare = routes[f][t].toDouble();
    var seat = seats[0];
    var now = DateTime.now();
    var sale = {
      "ticket_id": genId(),
      "date": "${now.year}-${now.month}-${now.day}",
      "time": "${now.hour}:${now.minute}:${now.second}",
      "name": name,
      "from": f,
      "to": t,
      "fare": fare,
      "seat": seat,
      "sold_by": currentUser
    };
    setState(() {
      sales.add(sale);
      usedSeats.add(seat);
      output = """
✅ SOLD!
Ticket: ${sale['ticket_id']}
Passenger: $name
Route: ${f.toUpperCase()}-${t.toUpperCase()}
Seat: $seat
Fare: GHS $fare
Sold by: $currentUser
QR: REALME|${sale['ticket_id']}|$seat|${f.toUpperCase()}-${t.toUpperCase()}|$fare|${sale['date']}

Small paper ready: PRINT_${sale['ticket_id']}.txt
""";
    });
    saveDB();
  }

  // 3. UPDATE FARE
  void updateFare() {
    var f = fromCtrl.text.toLowerCase().trim();
    var t = toCtrl.text.toLowerCase().trim();
    var fare = double.tryParse(fareCtrl.text.trim());
    if (fare==null) { setState(()=>output="❌ Enter valid fare in Fare box"); return; }
    if (f.isEmpty || t.isEmpty) { setState(()=>output="❌ Enter From and To"); return; }
    setState((){
      if (!routes.containsKey(f)) routes[f]={};
      if (!routes.containsKey(t)) routes[t]={};
      routes[f][t]=fare;
      routes[t][f]=fare;
      output="✅ Fare Updated: $f <-> $t = GHS $fare";
    });
    saveDB();
  }

  // 4. ADD NEW ROUTE
  void addRoute() => updateFare();

  // 5. VIEW ROUTES
  void viewRoutes() {
    var buf = StringBuffer("🛣️ ALL ROUTES:\n");
    routes.forEach((fs, dests){
      (dests as Map).forEach((ts, price){
        if (fs.compareTo(ts) < 0) buf.writeln("$fs <-> $ts : GHS $price");
      });
    });
    setState(()=>output=buf.toString());
  }

  // 6. DAILY REPORT
  void dailyReport() {
    var today = DateTime.now().toString().split(' ')[0];
    var todaySales = sales.where((s)=>s['date']==today).toList();
    double total = todaySales.fold(0.0, (a,b)=>a+(b['fare'] as num).toDouble());
    double allTotal = sales.fold(0.0, (a,b)=>a+(b['fare'] as num).toDouble());
    setState(()=>output="📊 DAILY REPORT - $today\nToday: ${todaySales.length} tickets | GHS $total\nALL TIME: ${sales.length} tickets | GHS $allTotal\nSeats left: ${loadSeats().length}/30");
  }

  // 7. SEAT MAP
  void seatMap() {
    var all = List.generate(30, (i)=>"A${(i+1).toString().padLeft(2,'0')}");
    var buf = StringBuffer("🪑 SEAT MAP - STATION MASTER ONLY\n================================\n");
    for (var i=0;i<30;i+=4){
      var row = all.sublist(i, (i+4).clamp(0,30));
      buf.writeln(row.map((s)=> usedSeats.contains(s)? "[XX]" : "[$s]").join(" "));
    }
    buf.writeln("================================\nFree: ${loadSeats().length}/30");
    setState(()=>output=buf.toString());
  }

  // 8. EXPORT CSV
  void exportCSV() {
    if (sales.isEmpty) { setState(()=>output="❌ No sales to export"); return; }
    var csv = StringBuffer("Ticket ID,Date,Time,Name,From,To,Fare,Seat,Sold By\n");
    double tot=0;
    for (var s in sales){ csv.writeln("${s['ticket_id']},${s['date']},${s['time']},${s['name']},${s['from']},${s['to']},${s['fare']},${s['seat']},${s['sold_by']}"); tot+=s['fare']; }
    csv.writeln("\nTOTAL,${sales.length}\nMONEY,GHS $tot");
    setState(()=>output="✅ CSV EXPORT READY (copy this):\n\n$csv\n\nFile: sales_${DateTime.now().toString().split(' ')[0]}.csv | ${sales.length} tickets | GHS $tot");
  }

  // 9. VERIFY TICKET
  void verifyTicket() {
    var qr = qrCtrl.text.trim();
    if (!qr.startsWith("REALME|")) { setState(()=>output="❌ INVALID QR! Must start with REALME|"); return; }
    var parts = qr.split("|");
    if (parts.length < 2) { setState(()=>output="❌ Invalid format"); return; }
    var tid = parts[1];
    var found = sales.where((s)=>s['ticket_id']==tid).toList();
    setState(()=>output = found.isEmpty? "❌ FAKE! Ticket $tid NOT FOUND!" : "✅ VALID! Ticket $tid\n${found.first}");
  }

  void loginDialog() {
    var uCtrl = TextEditingController(); var pCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("Station Master Login"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: uCtrl, decoration: InputDecoration(labelText: "Username (admin)")),
        TextField(controller: pCtrl, decoration: InputDecoration(labelText: "Password (Ad1My)"), obscureText: true),
      ]),
      actions: [TextButton(onPressed: (){
        var un = uCtrl.text.toLowerCase().trim();
        if (users.containsKey(un) && verifyPassword(users[un]['password'], pCtrl.text)){
          setState(()=>currentUser=un); Navigator.pop(context);
          setState(()=>output="✅ Welcome ${users[un]['full_name']} - ${users[un]['station']}");
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wrong! Use admin / Ad1My")));
        }
      }, child: Text("Login"))],
    ));
  }

  void adminCreateDialog() {
    var auCtrl = TextEditingController(); var apCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("Admin Auth - admin / Ad1My"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: auCtrl, decoration: InputDecoration(labelText: "Admin Username")),
        TextField(controller: apCtrl, decoration: InputDecoration(labelText: "Admin Password"), obscureText: true),
      ]),
      actions: [TextButton(onPressed: (){
        var au = auCtrl.text.toLowerCase().trim();
        if (au=="admin" && users.containsKey("admin") && verifyPassword(users["admin"]['password'], apCtrl.text)){
          Navigator.pop(context); createAccountDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Auth failed!")));
        }
      }, child: Text("Verify"))],
    ));
  }

  void createAccountDialog() {
    var nu = TextEditingController(); var fn = TextEditingController(); var np = TextEditingController(); var st = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("Create/Delete Account"),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Existing: ${users.keys.join(', ')}", style: TextStyle(fontSize: 10)),
        TextField(controller: nu, decoration: InputDecoration(labelText: "New Username")),
        TextField(controller: fn, decoration: InputDecoration(labelText: "Full Name")),
        TextField(controller: np, decoration: InputDecoration(labelText: "Password"), obscureText: true),
        TextField(controller: st, decoration: InputDecoration(labelText: "Station")),
        SizedBox(height: 10),
        ElevatedButton(onPressed: () async {
          var username = nu.text.toLowerCase().trim();
          if (username.isEmpty || users.containsKey(username)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid or exists"))); return; }
          users[username] = {"password": hashPassword(np.text), "station": st.text, "role": "station_master", "full_name": fn.text};
          await saveDB(); Navigator.pop(context);
          setState(()=>output="✅ Created ${fn.text} ($username) at ${st.text}");
        }, child: Text("Create")),
        ElevatedButton(onPressed: () async {
          var username = nu.text.toLowerCase().trim();
          if (username=="admin" ||!users.containsKey(username)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cannot delete admin or not found"))); return; }
          users.remove(username); await saveDB(); Navigator.pop(context);
          setState(()=>output="✅ Deleted $username");
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text("Delete Account")),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text("Close"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Color(0xFF0B6E4F), title: Row(children: [Icon(Icons.directions_bus, color: Colors.yellow), SizedBox(width: 8), Expanded(child: Text("REAL ME TROTRO v12 FULL - GOV", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))])),
      body: ListView(padding: EdgeInsets.all(12), children: [
        Container(height: 5, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.red, Colors.yellow, Color(0xFF0B6E4F)]))),
        Center(child: Text("Safe. Fast. Reliable. | Government Approved", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic))),
        SizedBox(height: 8),
        Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey[100], border: Border.all()), child: Text(output, style: TextStyle(fontSize: 12, fontFamily: 'monospace'))),
        SizedBox(height: 10),
        Text("PASSENGER SECTION", style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Passenger Name (for selling)", isDense: true)),
        Row(children: [Expanded(child: TextField(controller: fromCtrl, decoration: InputDecoration(labelText: "From", isDense: true))), SizedBox(width: 8), Expanded(child: TextField(controller: toCtrl, decoration: InputDecoration(labelText: "To", isDense: true))), SizedBox(width: 8), Expanded(child: TextField(controller: fareCtrl, decoration: InputDecoration(labelText: "Fare (for update)", isDense: true)))]),
        SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ElevatedButton(onPressed: checkFare, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF0B6E4F)), child: Text("1. CHECK FARE", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: sellTicket, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: Text("SELL TICKET", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: updateFare, child: Text("2. Update Fare", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: addRoute, child: Text("3. Add Route", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: viewRoutes, child: Text("4. View Routes", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: dailyReport, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: Text("5. Daily Report", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: seatMap, style: ElevatedButton.styleFrom(backgroundColor: Colors.purple), child: Text("6. Seat Map ${30-usedSeats.length}/30", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: exportCSV, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: Text("7. Export CSV", style: TextStyle(fontSize: 10))),
          ElevatedButton(onPressed: () async { usedSeats.clear(); await saveDB(); setState(()=>output="✅ Seats Reset - 30/30 free"); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text("8. Reset Seats", style: TextStyle(fontSize: 10))),
        ]),
        Divider(),
        Text("STATION MASTER & ADMIN", style: TextStyle(fontWeight: FontWeight.bold)),
        ListTile(leading: Icon(Icons.login), title: Text("Station Master Login - ${currentUser??'Not logged'}"), subtitle: Text("admin / Ad1My"), onTap: loginDialog),
        ListTile(leading: Icon(Icons.admin_panel_settings), title: Text("Create/Delete Account (Admin)"), onTap: adminCreateDialog),
        Divider(),
        Text("VERIFY TICKET", style: TextStyle(fontWeight: FontWeight.bold)),
        Row(children: [Expanded(child: TextField(controller: qrCtrl, decoration: InputDecoration(labelText: "Paste QR: REALME|T1234|...", isDense: true))), SizedBox(width: 6), ElevatedButton(onPressed: verifyTicket, child: Text("Verify"))]),
        SizedBox(height: 20),
        Text("Admin: admin / Ad1My | Routes: cape coast, swedru, accra, kumasi, tamale | v12 FULL = Python v11", style: TextStyle(fontSize: 9, color: Colors.grey)),
      ]),
    );
  }
}
