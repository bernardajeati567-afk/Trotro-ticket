import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() => runApp(const TrotroApp());

class TrotroApp extends StatelessWidget {
  const TrotroApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'REAL ME TROTRO GOV',
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Map<String, Map<String, double>> routes = {
    "cape coast": {"swedru": 45, "accra": 35, "kumasi": 25},
    "swedru": {"cape coast": 45, "accra": 20, "kumasi": 30},
    "accra": {"cape coast": 35, "swedru": 20, "kumasi": 45},
    "kumasi": {"cape coast": 25, "swedru": 30, "accra": 45, "tamale": 65},
    "tamale": {"kumasi": 65},
  };

  Map<String, Map<String, String>> users = {
    "admin": {"password": "Ad1My", "station": "Head Office", "role": "admin", "full_name": "System Admin"}
  };

  List<String> usedSeats = [];
  List<Map<String, dynamic>> sales = [];
  String curUser = "Guest";
  String curRole = "passenger";
  String curStation = "Head Office";

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final rf = p.getString('fares');
      if (rf!= null) {
        final decoded = jsonDecode(rf) as Map<String, dynamic>;
        routes = decoded.map((k, v) => MapEntry(k, (v as Map).map((kk, vv) => MapEntry(kk.toString(), (vv as num).toDouble()))));
      }
      final ru = p.getString('users');
      if (ru!= null) {
        final decoded = jsonDecode(ru) as Map<String, dynamic>;
        users = decoded.map((k, v) => MapEntry(k, Map<String, String>.from(v as Map)));
      }
      usedSeats = List<String>.from(jsonDecode(p.getString('seats')?? "[]"));
      sales = List<Map<String, dynamic>>.from(jsonDecode(p.getString('sales')?? "[]"));
      curUser = p.getString('curUser')?? "Guest";
      curRole = p.getString('curRole')?? "passenger";
      curStation = p.getString('curStation')?? "Head Office";
      setState(() {});
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('fares', jsonEncode(routes));
    await p.setString('users', jsonEncode(users));
    await p.setString('seats', jsonEncode(usedSeats));
    await p.setString('sales', jsonEncode(sales));
    await p.setString('curUser', curUser);
    await p.setString('curRole', curRole);
    await p.setString('curStation', curStation);
  }

  String suggest(String input) {
    var u = input.toLowerCase().trim();
    if (routes.containsKey(u)) return u;
    for (var k in routes.keys) {
      if (k.contains(u)) return k;
    }
    return u;
  }

  List<String> availableSeats() {
    final all = [for (int i = 1; i <= 30; i++) "A${i.toString().padLeft(2, '0')}"];
    return all.where((e) =>!usedSeats.contains(e)).toList();
  }

  void sellTicket(String name, String from, String to, double fare, String seat) {
    final now = DateTime.now();
    final tid = "T${Random().nextInt(90000) + 9999}";
    final date = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final time = "${now.hour}:${now.minute}:${now.second}";
    final sale = {"ticket_id": tid, "date": date, "time": time, "name": name, "from": from, "to": to, "fare": fare, "seat": seat, "sold_by": curUser};
    setState(() { sales.insert(0, sale); usedSeats.add(seat); });
    _save();
    final qr = "REALME|$tid|$seat|${from.toUpperCase()}-${to.toUpperCase()}|$fare|$date";
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("SOLD $tid"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        QrImageView(data: qr, size: 160),
        const SizedBox(height: 8),
        Text("$name\n$from -> $to\nSeat $seat\nGHS $fare\n$qr", style: const TextStyle(fontSize: 11)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final av = availableSeats();
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.black, title: Text('TROTRO GOV - $curUser ($curRole) @ $curStation', style: const TextStyle(color: Colors.white, fontSize: 11))),
      body: ListView(padding: const EdgeInsets.all(10), children: [
        Container(color: Colors.black, padding: const EdgeInsets.all(10), child: const Text('Safe. Fast. Reliable. | Government Approved', style: TextStyle(color: Colors.green, fontSize: 10))),
        Card(child: ListTile(title: const Text("1. Passenger - CHECK FARE"), onTap: () {
          String f="", t="";
          showDialog(context: context, builder: (_) => AlertDialog(
            title: const Text("Check Fare"), content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(decoration: const InputDecoration(labelText: "From"), onChanged: (v)=>f=v),
              TextField(decoration: const InputDecoration(labelText: "To"), onChanged: (v)=>t=v),
            ]), actions: [TextButton(onPressed: (){
              final fs=suggest(f); final ts=suggest(t); final fare=routes[fs]?[ts];
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fare!=null? "${fs.toUpperCase()}->${ts.toUpperCase()} = GHS $fare" : "No route")));
            }, child: const Text("CHECK"))],
          ));
        })),
        Card(child: ListTile(title: const Text("2. Station Master Login - admin/Ad1My"), onTap: () {
          String u="", p="";
          showDialog(context: context, builder: (_) => AlertDialog(
            title: const Text("Login"), content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(decoration: const InputDecoration(labelText: "Username"), onChanged: (v)=>u=v.toLowerCase().trim()),
              TextField(decoration: const InputDecoration(labelText: "Password"), obscureText: true, onChanged: (v)=>p=v),
            ]), actions: [TextButton(onPressed: (){
              if(users.containsKey(u) && users[u]!['password']==p){
                setState((){curUser=u; curRole=users[u]!['role']!; curStation=users[u]!['station']!;}); _save(); Navigator.pop(context);
              } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong password"))); }
            }, child: const Text("LOGIN"))],
          ));
        })),
        Card(color: Colors.orange[100], child: ListTile(title: const Text("3. Create/Delete Account (Admin)"), subtitle: const Text("Admin only: admin/Ad1My"), onTap: () {
          if(curRole!="admin"){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Admin only!"))); return;}
          String nu="", np="", fn="", st="accra";
          showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx,setD)=>AlertDialog(
            title: const Text("Create Account for Station Masters"), content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(decoration: const InputDecoration(labelText: "Username"), onChanged: (v)=>nu=v.toLowerCase().trim()),
              TextField(decoration: const InputDecoration(labelText: "Full Name"), onChanged: (v)=>fn=v),
              TextField(decoration: const InputDecoration(labelText: "Password"), onChanged: (v)=>np=v),
              DropdownButton<String>(value: st, items: routes.keys.map((e)=>DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(), onChanged: (v)=>setD(()=>st=v!)),
            ]), actions: [
              TextButton(onPressed: (){
                if(nu.isEmpty||users.containsKey(nu)) return;
                setState(()=>users[nu]={"password":np,"station":st,"role":"station_master","full_name":fn.isEmpty?nu:fn}); _save(); Navigator.pop(context);
              }, child: const Text("CREATE")),
            ],
          )));
        })),
        Card(child: ListTile(title: const Text("4. Verify Ticket REALME|"), onTap: ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>VerifyPage(sales: sales))))),
        if(curRole!="passenger" && curUser!="Guest")...[
          const Divider(), const Text("STATION MASTER MENU - FULL POWER", style: TextStyle(fontWeight: FontWeight.bold)),
          Card(color: Colors.green[100], child: ListTile(title: const Text(">>> SELL TICKET <<<"), subtitle: Text("Seats left ${av.length}/30"), onTap: (){
            String name="", from=curStation=="Head Office"?"accra":curStation, to="", seat=av.isNotEmpty?av[0]:"A01";
            showDialog(context: context, builder: (_)=>StatefulBuilder(builder: (ctx,setD)=>AlertDialog(
              title: const Text("Sell Ticket"), content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(decoration: const InputDecoration(labelText: "Passenger Name"), onChanged: (v)=>name=v),
                TextField(decoration: InputDecoration(labelText: "From [$from]"), onChanged: (v){if(v.isNotEmpty) from=v;}),
                TextField(decoration: const InputDecoration(labelText: "To"), onChanged: (v)=>to=v),
                DropdownButton<String>(value: seat, items: av.map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v)=>setD(()=>seat=v!)),
              ]), actions: [TextButton(onPressed: (){
                final fs=suggest(from); final ts=suggest(to); final fare=routes[fs]?[ts];
                if(fare==null) return; Navigator.pop(context); sellTicket(name,fs,ts,fare,seat);
              }, child: const Text("SELL"))],
            )));
          })),
          Card(child: ListTile(title: const Text("Seat Map A01-A30"), onTap: (){
            showDialog(context: context, builder: (_)=>AlertDialog(
              title: const Text("Seat Map"), content: Wrap(spacing: 5, children: [for(int i=1;i<=30;i++) Container(padding: const EdgeInsets.all(6), color: usedSeats.contains("A${i.toString().padLeft(2,'0')}")?Colors.red:Colors.green, child: Text("A${i.toString().padLeft(2,'0')}", style: const TextStyle(color: Colors.white, fontSize: 10)))]),
              actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("OK"))],
            ));
          })),
          Card(child: ListTile(title: const Text("Daily Sales Report"), onTap: (){
            final today=DateTime.now().toString().substring(0,10); final tod=sales.where((e)=>e['date']==today).toList();
            final money=tod.fold<double>(0,(a,b)=>a+(b['fare'] as num).toDouble());
            showDialog(context: context, builder: (_)=>AlertDialog(title: Text("Report $today"), content: Text("Today: ${tod.length}\nGHS $money\nAll: ${sales.length}"), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("OK"))]));
          })),
          Card(child: ListTile(title: const Text("Export CSV"), onTap: (){
            final buf=StringBuffer("Ticket,Date,Name,From,To,Fare,Seat\n"); for(var r in sales) buf.writeln("${r['ticket_id']},${r['date']},${r['name']},${r['from']},${r['to']},${r['fare']},${r['seat']}");
            showDialog(context: context, builder: (_)=>AlertDialog(title: const Text("CSV"), content: SingleChildScrollView(child: Text(buf.toString(), style: const TextStyle(fontSize: 8))), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("OK"))]));
          })),
          Card(color: Colors.red[100], child: ListTile(title: const Text("Reset Seats"), onTap: (){setState(()=>usedSeats=[]); _save();})),
          Card(child: ListTile(title: const Text("Logout"), onTap: (){setState((){curUser="Guest"; curRole="passenger"; curStation="Head Office";}); _save();})),
        ],
      ]),
    );
  }
}

class VerifyPage extends StatelessWidget {
  final List<Map<String, dynamic>> sales;
  const VerifyPage({super.key, required this.sales});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify REALME|")),
      body: Column(children: [
        Expanded(child: MobileScanner(onDetect: (cap){
          final raw=cap.barcodes.first.rawValue??"";
          if(!raw.startsWith("REALME|")) return;
          final tid=raw.split("|")[1];
          final found=sales.where((e)=>e['ticket_id']==tid).toList();
          showDialog(context: context, builder: (_)=>AlertDialog(title: Text(found.isNotEmpty?"VALID":"FAKE"), content: Text(found.isNotEmpty?jsonEncode(found.first):"Fake $tid"), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("OK"))]));
        })),
        Padding(padding: const EdgeInsets.all(10), child: TextField(decoration: const InputDecoration(labelText: "Paste REALME|..."), onSubmitted: (raw){
          if(!raw.startsWith("REALME|")) return;
          final tid=raw.split("|")[1]; final found=sales.where((e)=>e['ticket_id']==tid).toList();
          showDialog(context: context, builder: (_)=>AlertDialog(title: Text(found.isNotEmpty?"VALID":"FAKE"), content: Text(found.isNotEmpty?jsonEncode(found.first):"Fake"), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("OK"))]));
        })),
      ]),
    );
  }
}
