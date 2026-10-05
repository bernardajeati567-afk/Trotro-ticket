import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math';

void main() => runApp(TrotroGovApp());

// ===== DATA MODELS FROM YOUR V11 =====
class User {
  String username, password, station, role, fullName;
  User(this.username, this.password, this.station, this.role, this.fullName);
}
class Sale {
  String ticketId, date, time, name, fromS, toS, seat, soldBy;
  double fare;
  Sale({required this.ticketId, required this.date, required this.time, required this.name, required this.fromS, required this.toS, required this.fare, required this.seat, required this.soldBy});
}

class TrotroGovApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Real Me Trotro - Gov',
      theme: ThemeData(primaryColor: Color(0xFF006B3F)),
      home: MainMenu(),
    );
  }
}

class MainMenu extends StatefulWidget {
  @override
  _MainMenuState createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  Map<String, Map<String, double>> routes = {
    "cape coast": {"swedru": 45.0, "accra": 35.0, "kumasi": 25.0},
    "swedru": {"cape coast": 45.0, "accra": 20.0, "kumasi": 30.0},
    "accra": {"cape coast": 35.0, "swedru": 20.0, "kumasi": 45.0},
    "kumasi": {"cape coast": 25.0, "swedru": 30.0, "accra": 45.0, "tamale": 65.0},
    "tamale": {"kumasi": 65.0}
  };
  Map<String, User> users = {
    "admin": User("admin", "Ad1My", "Head Office", "admin", "System Admin")
  };
  List<String> usedSeats = [];
  List<Sale> sales = [];
  List<String> get allSeats => List.generate(30, (i) => "A${(i+1).toString().padLeft(2,'0')}");
  List<String> get freeSeats => allSeats.where((s) =>!usedSeats.contains(s)).toList();

  String ticketIdGen() => "T${Random().nextInt(90000)+9999}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF006B3F),
        title: Row(children: [
          Image.asset('assets/icon.jpg', height: 32),
          SizedBox(width:8),
          Text("REAL ME TROTRO - GOV", style: TextStyle(fontSize:14, fontWeight:FontWeight.bold, color:Colors.white)),
        ]),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Container(height:6, child: Row(children: [
            Expanded(child: Container(color:Colors.red)),
            Expanded(child: Container(color:Colors.yellow)),
            Expanded(child: Container(color:Color(0xFF006B3F))),
          ])),
          SizedBox(height:10),
          Text("Safe. Fast. Reliable. | Government Approved", textAlign: TextAlign.center, style: TextStyle(fontSize:12, fontStyle:FontStyle.italic)),
          SizedBox(height:20),
          _menuCard("1. Passenger - CHECK FARE", Icons.search, () => _passengerFare()),
          _menuCard("2. Station Master Login", Icons.login, () => _loginDialog()),
          _menuCard("3. Create/Delete Account (Admin)", Icons.admin_panel_settings, () => _manageAccounts()),
          _menuCard("4. Verify Ticket", Icons.qr_code_scanner, () => _verifyTicket()),
          _menuCard("5. Seat Map - ${freeSeats.length}/30 free", Icons.event_seat, () => _showSeatMap()),
          _menuCard("Daily Sales: ${sales.length} tickets - GHS ${sales.fold(0.0,(a,b)=>a+b.fare).toStringAsFixed(2)}", Icons.bar_chart, () => _showReport()),
        ],
      ),
    );
  }

  Widget _menuCard(String title, IconData icon, VoidCallback onTap) {
    return Card(
      child: ListTile(leading: Icon(icon, color:Color(0xFF006B3F)), title: Text(title, style: TextStyle(fontWeight:FontWeight.bold)), onTap: onTap),
    );
  }

  void _passengerFare() {
    String from="", to="";
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Check Fare - ${routes.keys.map((e)=>e.toUpperCase()).join(', ')}"),
      content: Column(mainAxisSize:MainAxisSize.min, children: [
        TextField(decoration: InputDecoration(labelText:"From"), onChanged: (v)=>from=v.toLowerCase()),
        TextField(decoration: InputDecoration(labelText:"To"), onChanged: (v)=>to=v.toLowerCase()),
      ]),
      actions: [TextButton(onPressed: (){
        double? fare = routes[from]?[to];
        Navigator.pop(c);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fare!=null? "FARE: ${from.toUpperCase()} -> ${to.toUpperCase()} = GHS ${fare.toStringAsFixed(2)}" : "No route found!")));
      }, child: Text("CHECK"))],
    ));
  }

  void _loginDialog() {
    String u="", p="";
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Station Master Login"),
      content: Column(mainAxisSize:MainAxisSize.min, children: [
        TextField(decoration: InputDecoration(labelText:"Username"), onChanged: (v)=>u=v.toLowerCase()),
        TextField(decoration: InputDecoration(labelText:"Password"), obscureText:true, onChanged: (v)=>p=v),
      ]),
      actions: [TextButton(onPressed: (){
        if(users.containsKey(u) && users[u]!.password==p){
          Navigator.pop(c);
          _stationMasterScreen(users[u]!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wrong password!")));
        }
      }, child: Text("LOGIN"))],
    ));
  }

  void _stationMasterScreen(User user) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => StationMasterPage(
      user: user,
      routes: routes,
      users: users,
      usedSeats: usedSeats,
      freeSeats: freeSeats,
      allSeats: allSeats,
      sales: sales,
      genId: ticketIdGen,
      onSale: (s, seat){ setState((){ sales.add(s); usedSeats.add(seat); }); },
      onResetSeats: (){ setState(()=>usedSeats.clear()); },
      onUpdateFare: (f,t,price){ setState((){
        routes.putIfAbsent(f, ()=>{}); routes.putIfAbsent(t, ()=>{});
        routes[f]![t]=price; routes[t]![f]=price;
      });},
    )));
  }

  void _verifyTicket() {
    String qr="";
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Verify Ticket - Paste QR"),
      content: TextField(decoration: InputDecoration(labelText:"REALME|..."), onChanged: (v)=>qr=v),
      actions: [TextButton(onPressed: (){
        Navigator.pop(c);
        if(!qr.startsWith("REALME|")){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("INVALID!"))); return; }
        String tid = qr.split("|")[1];
        var found = sales.where((s)=>s.ticketId==tid);
        if(found.isNotEmpty){
          var s=found.first;
          showDialog(context: context, builder: (_)=>AlertDialog(title: Text("VALID ✅"), content: Text("Ticket: ${s.ticketId}\nName: ${s.name}\nRoute: ${s.fromS}->${s.toS}\nSeat: ${s.seat}\nFare: GHS ${s.fare}\nSold by: ${s.soldBy}")));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("FAKE! $tid not found in DB")));
        }
      }, child: Text("VERIFY"))],
    ));
  }

  void _showSeatMap() {
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Seat Map - ${freeSeats.length}/30"),
      content: Container(width:300, child: Wrap(spacing:8, runSpacing:8, children: allSeats.map((s){
        bool used=usedSeats.contains(s);
        return Container(width:50, height:35, alignment: Alignment.center, decoration: BoxDecoration(color: used?Colors.red:Colors.green, borderRadius: BorderRadius.circular(6)), child: Text(used?"XX":s, style: TextStyle(color:Colors.white, fontSize:12)));
      }).toList())),
      actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("CLOSE"))],
    ));
  }

  void _showReport() {
    double total = sales.fold(0.0,(a,b)=>a+b.fare);
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Daily Sales Report"),
      content: Text("Total Tickets: ${sales.length}\nTotal Money: GHS ${total.toStringAsFixed(2)}\nSeats left: ${freeSeats.length}/30\n\n${sales.map((s)=>"${s.ticketId} | ${s.name} | ${s.fromS}->${s.toS} | ${s.seat}").join("\n")}"),
      actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("OK"))],
    ));
  }

  void _manageAccounts() {
    String adminU="", adminP="";
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Admin Auth - Needed"),
      content: Column(mainAxisSize:MainAxisSize.min, children: [
        TextField(decoration: InputDecoration(labelText:"Admin Username"), onChanged: (v)=>adminU=v),
        TextField(decoration: InputDecoration(labelText:"Admin Password"), obscureText:true, onChanged: (v)=>adminP=v),
      ]),
      actions: [TextButton(onPressed: (){
        if(users[adminU]?.role=="admin" && users[adminU]!.password==adminP){
          Navigator.pop(c);
          _accountsPage();
        }
      }, child: Text("AUTH"))],
    ));
  }

  void _accountsPage() {
    String nu="", np="", fn="", st="";
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("Create Station Master"),
      content: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min, children: [
        TextField(decoration: InputDecoration(labelText:"Username 1 word"), onChanged: (v)=>nu=v.toLowerCase()),
        TextField(decoration: InputDecoration(labelText:"Full Name"), onChanged: (v)=>fn=v),
        TextField(decoration: InputDecoration(labelText:"Password"), onChanged: (v)=>np=v),
        TextField(decoration: InputDecoration(labelText:"Station"), onChanged: (v)=>st=v),
        SizedBox(height:10),
        Text("Existing: ${users.keys.join(", ")}", style: TextStyle(fontSize:10)),
      ])),
      actions: [TextButton(onPressed: (){
        if(nu.isNotEmpty &&!users.containsKey(nu)){
          setState(()=>users[nu]=User(nu,np,st,"station_master",fn));
          Navigator.pop(c);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Created $fn | $nu")));
        }
      }, child: Text("CREATE"))],
    ));
  }
}

class StationMasterPage extends StatefulWidget {
  final User user; final Map<String, Map<String, double>> routes; final Map<String, User> users;
  final List<String> usedSeats, freeSeats, allSeats; final List<Sale> sales;
  final String Function() genId; final Function(Sale,String) onSale; final VoidCallback onResetSeats; final Function(String,String,double) onUpdateFare;
  StationMasterPage({required this.user, required this.routes, required this.users, required this.usedSeats, required this.freeSeats, required this.allSeats, required this.sales, required this.genId, required this.onSale, required this.onResetSeats, required this.onUpdateFare});
  @override
  _StationMasterPageState createState() => _StationMasterPageState();
}

class _StationMasterPageState extends State<StationMasterPage> {
  void _sellTicket() {
    String name="", from="", to="", seat="";
    showDialog(context: context, builder: (c){
      return StatefulBuilder(builder: (context, setD){
        double? fare = widget.routes[from.toLowerCase()]?[to.toLowerCase()];
        return AlertDialog(
          title: Text(">>> SELL TICKET <<< - Avail: ${widget.freeSeats.take(8).join(", ")}"),
          content: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min, children: [
            TextField(decoration: InputDecoration(labelText:"Passenger Name"), onChanged: (v)=>name=v),
            TextField(decoration: InputDecoration(labelText:"From"), onChanged: (v){ from=v; setD((){}); }),
            TextField(decoration: InputDecoration(labelText:"To"), onChanged: (v){ to=v; setD((){}); }),
            if(fare!=null) Text("Fare: GHS ${fare.toStringAsFixed(2)}", style: TextStyle(fontWeight:FontWeight.bold, color:Colors.green)),
            TextField(decoration: InputDecoration(labelText:"Seat [${widget.freeSeats.isNotEmpty?widget.freeSeats.first:""}]"), onChanged: (v)=>seat=v.toUpperCase()),
          ])),
          actions: [TextButton(onPressed: (){
            if(name.isEmpty || fare==null || widget.freeSeats.isEmpty) return;
            String finalSeat = seat.isEmpty? widget.freeSeats.first : seat;
            if(!widget.allSeats.contains(finalSeat) || widget.usedSeats.contains(finalSeat)) finalSeat=widget.freeSeats.first;
            var now=DateTime.now();
            var sale=Sale(ticketId: widget.genId(), date: "${now.year}-${now.month}-${now.day}", time: "${now.hour}:${now.minute}", name: name, fromS: from, toS: to, fare: fare, seat: finalSeat, soldBy: widget.user.username);
            widget.onSale(sale, finalSeat);
            Navigator.pop(c);
            _showTicket(sale);
          }, child: Text("SELL"))],
        );
      });
    });
  }

  void _showTicket(Sale s) {
    String rn="${s.fromS.toUpperCase()}-${s.toS.toUpperCase()}";
    String qr="REALME|${s.ticketId}|${s.seat}|$rn|${s.fare}|${s.date}";
    showDialog(context: context, builder: (c)=>AlertDialog(
      title: Text("SOLD! ${s.ticketId} | Seat ${s.seat}"),
      content: SingleChildScrollView(child: Column(children: [
        Container(height:6, child: Row(children: [Expanded(child: Container(color:Colors.red)), Expanded(child: Container(color:Colors.yellow)), Expanded(child: Container(color:Color(0xFF006B3F)))])),
        SizedBox(height:10),
        Text("REAL ME TROTRO - GOV EDITION", style: TextStyle(fontWeight:FontWeight.bold)),
        Text("Safe. Fast. Reliable. | Gov App", style: TextStyle(fontSize:10)),
        SizedBox(height:10),
        Text("Ticket: ${s.ticketId}"), Text("Passenger: ${s.name}"), Text("Route: $rn"), Text("Seat: ${s.seat}"), Text("Sold By: ${s.soldBy}"),
        Text("FARE: GHS ${s.fare.toStringAsFixed(2)} PAID", style: TextStyle(fontWeight:FontWeight.bold, color:Colors.red)),
        SizedBox(height:10),
        QrImageView(data: qr, size: 180),
        SizedBox(height:5),
        Text(qr, style: TextStyle(fontSize:8, fontFamily: 'monospace')),
        SizedBox(height:10),
        Text("Small paper ticket ready: PRINT_${s.ticketId}.txt - Use Bluetooth thermal printer!", style: TextStyle(fontSize:10, color:Colors.grey)),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("CLOSE"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Welcome ${widget.user.fullName} - ${widget.user.station}"), backgroundColor: Color(0xFF006B3F)),
      body: ListView(padding: EdgeInsets.all(16), children: [
        ElevatedButton.icon(icon: Icon(Icons.confirmation_number), label: Text(">>> SELL TICKET <<<"), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF006B3F), minimumSize: Size(double.infinity,50)), onPressed: _sellTicket),
        ListTile(title: Text("2. Update fare"), onTap: (){
          String f="", t="", pr=""; showDialog(context: context, builder: (c)=>AlertDialog(
            title: Text("Update Fare"), content: Column(mainAxisSize:MainAxisSize.min, children: [
              TextField(decoration: InputDecoration(labelText:"From"), onChanged: (v)=>f=v.toLowerCase()),
              TextField(decoration: InputDecoration(labelText:"To"), onChanged: (v)=>t=v.toLowerCase()),
              TextField(decoration: InputDecoration(labelText:"New Fare"), keyboardType: TextInputType.number, onChanged: (v)=>pr=v),
            ]), actions: [TextButton(onPressed: (){ double? p=double.tryParse(pr); if(p!=null){ widget.onUpdateFare(f,t,p); Navigator.pop(c);} }, child: Text("UPDATE"))],
          ));
        }),
        ListTile(title: Text("3. Add NEW route"), onTap: (){
          String f="", t="", pr=""; showDialog(context: context, builder: (c)=>AlertDialog(
            title: Text("Add NEW route"), content: Column(mainAxisSize:MainAxisSize.min, children: [
              TextField(decoration: InputDecoration(labelText:"From"), onChanged: (v)=>f=v.toLowerCase()),
              TextField(decoration: InputDecoration(labelText:"To"), onChanged: (v)=>t=v.toLowerCase()),
              TextField(decoration: InputDecoration(labelText:"Fare"), keyboardType: TextInputType.number, onChanged: (v)=>pr=v),
            ]), actions: [TextButton(onPressed: (){ double? p=double.tryParse(pr); if(p!=null){ widget.onUpdateFare(f,t,p); Navigator.pop(c);} }, child: Text("ADD"))],
          ));
        }),
        ListTile(title: Text("4. View all routes"), onTap: (){
          showDialog(context: context, builder: (c)=>AlertDialog(title: Text("All Routes"), content: SingleChildScrollView(child: Column(children: widget.routes.entries.expand((e)=>e.value.entries.where((v)=>e.key.compareTo(v.key)<0).map((v)=>Text("${e.key.toUpperCase()} <-> ${v.key.toUpperCase()}: GHS ${v.value}"))).toList())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("OK"))]));
        }),
        ListTile(title: Text("5. Daily Sales Report"), onTap: (){
          double tot=widget.sales.fold(0.0,(a,b)=>a+b.fare);
          showDialog(context: context, builder: (c)=>AlertDialog(title: Text("Daily Sales"), content: Text("Total: ${widget.sales.length} | GHS ${tot.toStringAsFixed(2)}\nSeats left: ${widget.freeSeats.length}/30"), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("OK"))]));
        }),
        ListTile(title: Text("6. Seat Map"), onTap: (){
          showDialog(context: context, builder: (c)=>AlertDialog(title: Text("Seat Map"), content: Wrap(spacing:6, runSpacing:6, children: widget.allSeats.map((s){ bool used=widget.usedSeats.contains(s); return Container(width:45, height:30, color: used?Colors.red:Colors.green, alignment: Alignment.center, child: Text(used?"XX":s, style: TextStyle(color:Colors.white, fontSize:11))); }).toList()), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("CLOSE"))]));
        }),
        ListTile(title: Text("7. Export Sales to CSV"), onTap: (){
          String csv="Ticket ID,Date,Time,Name,From,To,Fare,Seat,Sold By\n"+widget.sales.map((r)=>"${r.ticketId},${r.date},${r.time},${r.name},${r.fromS},${r.toS},${r.fare},${r.seat},${r.soldBy}").join("\n");
          showDialog(context: context, builder: (c)=>AlertDialog(title: Text("Export CSV - ${widget.sales.length} tickets"), content: SingleChildScrollView(child: Text(csv, style: TextStyle(fontSize:9))), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text("OK"))]));
        }),
        ListTile(title: Text("8. Reset seats"), onTap: (){ if(widget.usedSeats.isNotEmpty){ widget.onResetSeats(); setState((){}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Seats Reset Done"))); } }),
        ListTile(title: Text("9. Logout"), leading: Icon(Icons.logout, color:Colors.red), onTap: ()=>Navigator.pop(context)),
      ]),
    );
  }
}
