import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
String CURRENT_USER = "None";
String CURRENT_STATION = "Head Office";
const APP_SLOGAN = "Safe. Fast. Reliable. | Government Approved";
String hashPassword(String pp){
final salt = List.generate(16, (_)=> Random().nextInt(256)).map((e)=> e.toRadixString(16).padLeft(2,'0')).join();
return "$salt\$${pbkdf2(salt, pp)}";
}
String pbkdf2(String salt, String password){
var key = utf8.encode(password);
var saltBytes = utf8.encode(salt);
var hmac = Hmac(sha256, key);
var block = hmac.convert(saltBytes).bytes;
var result = List<int>.from(block);
for(int i=1;i<100000;i++){ block = hmac.convert(block).bytes; for(int j=0;j<result.length;j++) result[j] ^= block[j]; }
return result.map((e)=> e.toRadixString(16).padLeft(2,'0')).join();
}
bool verifyPassword(String stored, String provided){
try{
if(stored.contains("\$")){ var s=stored.split("\$")[0]; var h=stored.split("\$")[1]; return pbkdf2(s, provided)==h; }
else { return stored==sha256.convert(utf8.encode(provided)).toString(); }
}catch(e){ return false; }
}
class DBHelper{
static Database? _db;
static Future<Database> get db async {
if(_db!=null) return _db!;
_db = await openDatabase(p.join(await getDatabasesPath(), 'trotro.db'),
onCreate: (db,v) async {
await db.execute('CREATE TABLE users (username TEXT PRIMARY KEY,password TEXT,station TEXT,role TEXT,full_name TEXT)');
await db.execute('CREATE TABLE fares (from_s TEXT,to_s TEXT,fare REAL,PRIMARY KEY (from_s,to_s))');
await db.execute('CREATE TABLE seats (seat TEXT PRIMARY KEY)');
await db.execute('CREATE TABLE sales (ticket_id TEXT PRIMARY KEY,date TEXT,time TEXT,name TEXT,from_s TEXT,to_s TEXT,fare REAL,seat TEXT,sold_by TEXT)');
await db.insert('users', {'username':'admin','password':hashPassword('Ad1My'),'station':'Head Office','role':'admin','full_name':'System Admin'}, conflictAlgorithm: ConflictAlgorithm.replace);
var dr = {'cape coast': {'swedru':45.0,'accra':35.0,'kumasi':25.0},'swedru': {'cape coast':45.0,'accra':20.0,'kumasi':30.0},'accra': {'cape coast':35.0,'swedru':20.0,'kumasi':45.0},'kumasi': {'cape coast':25.0,'swedru':30.0,'accra':45.0,'tamale':65.0},'tamale': {'kumasi':65.0}};
for(var fs in dr.keys){ for(var ts in dr[fs]!.keys){ await db.insert('fares', {'from_s':fs,'to_s':ts,'fare':dr[fs]![ts]}, conflictAlgorithm: ConflictAlgorithm.replace); } }
}, version: 2);
return _db!;
}
}
void main() => runApp(MaterialApp(debugShowCheckedModeBanner:false, home: MainMenu(), theme: ThemeData(useMaterial3:true, colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF008751)), elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 60), textStyle: TextStyle(fontSize:20, fontWeight: FontWeight.bold))))));
Future<String> suggestStation(String input, BuildContext context) async {
var db=await DBHelper.db; var rows=await db.query('fares'); var allS=rows.map((e)=> e['from_s'] as String).toSet().toList();
String u=input.toLowerCase().trim().replaceAll(" ", "");
if(allS.contains(u)) return u;
var noSpace={for(var s in allS) s.replaceAll(" ", ""): s};
var matches=noSpace.keys.where((k)=> k.contains(u) || u.contains(k)).toList();
if(matches.isNotEmpty) return noSpace[matches.first]!;
String best=""; double bestScore=0;
for(var k in noSpace.keys){ double score=1 - (levenshtein(k, u) / max(k.length, u.length)); if(score>bestScore && score>=0.6){ bestScore=score; best=noSpace[k]!; } }
if(best.isNotEmpty){ bool? yes=await showDialog<bool>(context: context, builder: (_)=> AlertDialog(title: Text("Did you mean: ${best.toUpperCase()}?"), actions: [TextButton(onPressed: ()=> Navigator.pop(_, false), child: Text("No")), TextButton(onPressed: ()=> Navigator.pop(_, true), child: Text("Yes"))])); if(yes==true) return best; }
return u;
}
int levenshtein(String s, String t){ if(s==t) return 0; if(s.isEmpty) return t.length; if(t.isEmpty) return s.length; List<int> v0=List.generate(t.length+1, (i)=> i); List<int> v1=List.filled(t.length+1, 0); for(int i=0;i<s.length;i++){ v1[0]=i+1; for(int j=0;j<t.length;j++){ int cost=s[i]==t[j]?0:1; v1[j+1]=min(v1[j]+1, min(v0[j+1]+1, v0[j]+cost)); } var tmp=v0; v0=v1; v1=tmp; } return v0[t.length]; }
class MainMenu extends StatelessWidget{
@override Widget build(BuildContext c){
return Scaffold(appBar: AppBar(title: Text("REAL ME TROTRO v11 - $APP_SLOGAN"), backgroundColor: Color(0xFF008751), foregroundColor: Colors.white),
body: ListView(padding: EdgeInsets.all(16), children: [
Icon(Icons.directions_bus, size: 80, color: Color(0xFF008751)), Center(child: Text("DB: trotro.db | Login: $CURRENT_USER", style: TextStyle(fontSize:16))),
_tile(c, "1. Passenger - CHECK FARE", Icons.search, PassengerCheck()),
_tile(c, "2. Station Master Login", Icons.login, LoginScreen()),
_tile(c, "3. Create/Delete Account (Admin)", Icons.admin_panel_settings, CreateAccountScreen()),
_tile(c, "4. Verify Ticket", Icons.qr_code_scanner, VerifyScreen()),
_tile(c, "5. Exit - Goodbye DB saved", Icons.exit_to_app, MainMenu(), isExit:true),
]));
}
Widget _tile(BuildContext c, String t, IconData ic, Widget dest, {bool isExit=false})=> Card(child: ListTile(leading: Icon(ic, color: Color(0xFF008751)), title: Text(t, style: TextStyle(fontWeight: FontWeight.bold)), onTap: isExit? (){ ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text("Goodbye! DB saved"))); } : (){ Navigator.push(c, MaterialPageRoute(builder: (_)=> dest)); }));
}
class LoginScreen extends StatefulWidget{ @override State<LoginScreen> createState()=> _LoginS(); }
class _LoginS extends State<LoginScreen>{
final u=TextEditingController(), pp=TextEditingController();
void doLogin() async {
final db=await DBHelper.db; var rows=await db.query('users', where: 'username=?', whereArgs: [u.text.trim().toLowerCase()]);
if(rows.isNotEmpty && verifyPassword(rows.first['password'] as String, pp.text)){
CURRENT_USER = rows.first['username'] as String; CURRENT_STATION = rows.first['station'] as String;
if((rows.first['role'] as String)=='admin') Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> AdminScreen()));
else Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> StationMasterScreen()));
} else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wrong password!"))); }
}
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("LOGIN - Station Master")), body: Padding(padding: EdgeInsets.all(20), child: Column(children: [TextField(controller: u, decoration: InputDecoration(labelText: "Username", border: OutlineInputBorder())), SizedBox(height:12), TextField(controller: pp, decoration: InputDecoration(labelText: "Password", border: OutlineInputBorder()), obscureText: true), SizedBox(height: 20), SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: doLogin, style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white), child: Text("LOGIN - BIG BUTTON"))), Text("Default admin / Ad1My")])));
}
class PassengerCheck extends StatefulWidget{ @override State<PassengerCheck> createState()=> _Pass(); }
class _Pass extends State<PassengerCheck>{
final fromCtrl=TextEditingController(), toCtrl=TextEditingController(); String result="";
void check() async {
String fs=await suggestStation(fromCtrl.text, context); String ts=await suggestStation(toCtrl.text, context);
final db=await DBHelper.db; var row=await db.query('fares', where: 'from_s=? AND to_s=?', whereArgs: [fs, ts]);
setState(()=> result=row.isEmpty? "No route from $fs to $ts\nAvailable: cape coast, swedru, accra, kumasi, tamale" : "FARE: ${fs.toUpperCase()} -> ${ts.toUpperCase()} = GHS ${row.first['fare']}");
}
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("PASSENGER CHECK")), body: Padding(padding: EdgeInsets.all(16), child: Column(children: [Text("Available: cape coast, swedru, accra, kumasi, tamale"), TextField(controller: fromCtrl, decoration: InputDecoration(labelText: "From", border: OutlineInputBorder())), SizedBox(height:8), TextField(controller: toCtrl, decoration: InputDecoration(labelText: "To", border: OutlineInputBorder())), SizedBox(height: 12), SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: check, child: Text("CHECK FARE - BIG"))), SizedBox(height: 20), Text(result, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green))])));
}
class StationMasterScreen extends StatefulWidget{ @override State<StationMasterScreen> createState()=> _SMS(); }
class _SMS extends State<StationMasterScreen>{
void updateFare(BuildContext c) async {
var fromCtrl=TextEditingController(); var toCtrl=TextEditingController(); var fareCtrl=TextEditingController();
showDialog(context: c, builder: (_)=> AlertDialog(title: Text("Update Fare"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: fromCtrl, decoration: InputDecoration(labelText: "From")), TextField(controller: toCtrl, decoration: InputDecoration(labelText: "To")), TextField(controller: fareCtrl, decoration: InputDecoration(labelText: "New fare"))]), actions: [ElevatedButton(onPressed: () async { var db=await DBHelper.db; await db.insert('fares', {'from_s':fromCtrl.text.toLowerCase(),'to_s':toCtrl.text.toLowerCase(),'fare':double.tryParse(fareCtrl.text)??20}, conflictAlgorithm: ConflictAlgorithm.replace); await db.insert('fares', {'from_s':toCtrl.text.toLowerCase(),'to_s':fromCtrl.text.toLowerCase(),'fare':double.tryParse(fareCtrl.text)??20}, conflictAlgorithm: ConflictAlgorithm.replace); Navigator.pop(c); ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text("Fare Updated"))); }, child: Text("SAVE"))]));
}
void viewRoutes(BuildContext c) async { var db=await DBHelper.db; var rows=await db.query('fares'); showDialog(context: c, builder: (_)=> AlertDialog(title: Text("All Routes"), content: SizedBox(width: double.maxFinite, height: 400, child: ListView(children: rows.map((r)=> Text("${r['from_s'].toString().toUpperCase()} <-> ${r['to_s'].toString().toUpperCase()}: GHS ${r['fare']}")).toList())))); }
void exportCSV(BuildContext c) async { var db=await DBHelper.db; var today=DateFormat('yyyy-MM-dd').format(DateTime.now()); var rows=await db.query('sales', where: 'date=?', whereArgs: [today]); if(rows.isEmpty){ rows=await db.query('sales'); } String csv="Ticket ID,Date,Time,Name,From,To,Fare,Seat,Sold By\n"; double tot=0; for(var r in rows){ csv+="${r['ticket_id']},${r['date']},${r['time']},${r['name']},${r['from_s']},${r['to_s']},${r['fare']},${r['seat']},${r['sold_by']}\n"; tot+=r['fare'] as double; } csv+="\nTOTAL,${rows.length}\nMONEY,GHS $tot\n"; await Printing.sharePdf(bytes: utf8.encode(csv), filename: "sales_${today}.csv"); }
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("STATION MASTER - FULL POWER - $CURRENT_STATION"), backgroundColor: Color(0xFF008751), foregroundColor: Colors.white),
body: ListView(padding: EdgeInsets.all(12), children: [
_b(c, "1. >>> SELL TICKET <<<", Icons.confirmation_num, SellTicketScreen()),
_b(c, "2. Update fare", Icons.edit, null, onTap: ()=> updateFare(c)),
_b(c, "3. Add NEW route", Icons.add_road, null, onTap: ()=> updateFare(c)),
_b(c, "4. View all routes", Icons.route, null, onTap: ()=> viewRoutes(c)),
_b(c, "5. Daily Sales Report", Icons.bar_chart, SalesReportScreen()),
_b(c, "6. Seat Map (Station Only)", Icons.event_seat, SeatMapScreen()),
_b(c, "7. Export Sales to Excel/CSV", Icons.file_download, null, onTap: ()=> exportCSV(c)),
_b(c, "8. Reset seats", Icons.refresh, null, onTap: () async { var db=await DBHelper.db; await db.delete('seats'); ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text("Reset done - 30 seats free"))); }),
_b(c, "9. Logout", Icons.logout, null, onTap: (){ CURRENT_USER="None"; Navigator.pushReplacement(c, MaterialPageRoute(builder: (_)=> MainMenu())); }),
]));
Widget _b(BuildContext c, String t, IconData ic, Widget? dest, {VoidCallback? onTap})=> Card(elevation: 2, margin: EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(backgroundColor: Color(0xFF008751), child: Icon(ic, color: Colors.white)), title: Text(t, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), trailing: Icon(Icons.arrow_forward_ios, size: 16), onTap: onTap?? (){ Navigator.push(c, MaterialPageRoute(builder: (_)=> dest!)); }));
}
class SellTicketScreen extends StatefulWidget{ @override State<SellTicketScreen> createState()=> _Sell(); }
class _Sell extends State<SellTicketScreen>{
final nameCtrl=TextEditingController(), fromCtrl=TextEditingController(text: "accra"), toCtrl=TextEditingController(text: "cape coast"), seatCtrl=TextEditingController();
String info=""; List<String> freeSeats=[];
@override void initState(){ super.initState(); loadFreeSeats(); }
Future<void> loadFreeSeats() async { final db=await DBHelper.db; var used=(await db.query('seats')).map((e)=> e['seat'] as String).toList(); var all=[for(int i=1;i<=30;i++) "A${i.toString().padLeft(2,'0')}"]; setState(()=> freeSeats=all.where((s)=>!used.contains(s)).toList()); if(freeSeats.isNotEmpty) seatCtrl.text=freeSeats.first; }
Future<void> sell() async {
String fs=await suggestStation(fromCtrl.text, context); String ts=await suggestStation(toCtrl.text, context);
final db=await DBHelper.db; var fareRow=await db.query('fares', where: 'from_s=? AND to_s=?', whereArgs: [fs, ts]); double fare=fareRow.isEmpty? 20.0 : fareRow.first['fare'] as double;
String seat=seatCtrl.text.trim().toUpperCase(); if(seat.isEmpty) seat=freeSeats.isNotEmpty? freeSeats.first : "A01";
var check=await db.query('seats', where: 'seat=?', whereArgs: [seat]); if(check.isNotEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Seat $seat already sold!"))); return; }
String tid="T${Random().nextInt(90000)+10000}"; String date=DateFormat('yyyy-MM-dd').format(DateTime.now()); String time=DateFormat('HH:mm').format(DateTime.now());
await db.insert('seats', {'seat':seat}); await db.insert('sales', {'ticket_id':tid,'date':date,'time':time,'name':nameCtrl.text,'from_s':fs,'to_s':ts,'fare':fare,'seat':seat,'sold_by':CURRENT_USER});
String rn="${fs.toUpperCase()}-${ts.toUpperCase()}"; String qr="REALME|$tid|$seat|$rn|$fare|$date";
final pdf=pw.Document();
pdf.addPage(pw.Page(build: (pw.Context ctx){
return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
pw.Container(color: PdfColor.fromInt(0xFFCE1126), width: double.infinity, height: 35, child: pw.Center(child: pw.Text("REAL ME TROTRO - GOVERNMENT EDITION", style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)))),
pw.Container(color: PdfColor.fromInt(0xFFFCD116), width: double.infinity, height: 3), pw.Container(color: PdfColor.fromInt(0xFF006B3F), width: double.infinity, height: 3),
pw.SizedBox(height: 15), pw.Text("Ticket ID: $tid"), pw.Text("Name: ${nameCtrl.text}"), pw.Text("Sold By: $CURRENT_USER"), pw.Text("Route: $rn"), pw.Text("Seat: $seat"),
pw.Text("Fare: GHS ${fare.toStringAsFixed(2)} PAID", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFCE1126))),
pw.Text("Date: $date $time"), pw.SizedBox(height: 10), pw.Text("QR Code Text: $qr", style: pw.TextStyle(fontSize: 8)),
]);
}));
await Printing.layoutPdf(onLayout: (f) async => pdf.save());
setState(()=> info="SOLD! $tid | Seat $seat | GHS $fare");
loadFreeSeats();
}
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("SELL TICKET - Like Python")), body: Padding(padding: EdgeInsets.all(16), child: ListView(children: [
TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Passenger Name", border: OutlineInputBorder())), SizedBox(height:8),
TextField(controller: fromCtrl, decoration: InputDecoration(labelText: "From", border: OutlineInputBorder())), SizedBox(height:8),
TextField(controller: toCtrl, decoration: InputDecoration(labelText: "To", border: OutlineInputBorder())), SizedBox(height:8),
TextField(controller: seatCtrl, decoration: InputDecoration(labelText: "Seat - Free: ${freeSeats.take(5).join(', ')}", border: OutlineInputBorder())),
SizedBox(height: 12), SizedBox(height: 65, child: ElevatedButton(onPressed: sell, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF008751), foregroundColor: Colors.white), child: Text("SAVE & PRINT TICKET - BIG BUTTON", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
SizedBox(height: 12), SelectableText(info, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), if(info.isNotEmpty) QrImageView(data: info, size: 150),
])));
}
class SeatMapScreen extends StatelessWidget{
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("SEAT MAP 30 SEATS")), body: FutureBuilder(future: DBHelper.db.then((db)=> db.query('seats')), builder: (ctx,snap){
if(!snap.hasData) return Center(child: CircularProgressIndicator()); var used=(snap.data as List).map((e)=> e['seat'] as String).toList();
return GridView.builder(padding: EdgeInsets.all(16), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8), itemCount: 30, itemBuilder: (cc,i){ String s="A${(i+1).toString().padLeft(2,'0')}"; bool sold=used.contains(s); return Container(decoration: BoxDecoration(color: sold? Colors.red : Colors.green, borderRadius: BorderRadius.circular(8)), child: Center(child: Text("$s\n${sold?'XX':'FREE'}", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))); });
}));
}
class VerifyScreen extends StatefulWidget{ @override State<VerifyScreen> createState()=> _Ver(); }
class _Ver extends State<VerifyScreen>{
final ctrl=TextEditingController(); String res="";
void verify() async { if(!ctrl.text.startsWith("REALME|")){ setState(()=> res="INVALID QR"); return; } var tid=ctrl.text.split("|")[1]; var db=await DBHelper.db; var row=await db.query('sales', where: 'ticket_id=?', whereArgs: [tid]); setState(()=> res=row.isEmpty? "FAKE! $tid not found" : "VALID! ${row.first}"); }
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("VERIFY TICKET")), body: Padding(padding: EdgeInsets.all(16), child: Column(children: [TextField(controller: ctrl, decoration: InputDecoration(labelText: "Paste QR REALME|...", border: OutlineInputBorder())), SizedBox(height: 10), SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: verify, child: Text("VERIFY - BIG"))), SizedBox(height: 20), Text(res, style: TextStyle(fontWeight: FontWeight.bold))])));
}
class SalesReportScreen extends StatelessWidget{
@override Widget build(BuildContext c){
String today=DateFormat('yyyy-MM-dd').format(DateTime.now());
return Scaffold(appBar: AppBar(title: Text("DAILY SALES - $today")), body: FutureBuilder(future: DBHelper.db.then((db)=> db.query('sales', where: 'date=?', whereArgs: [today])), builder: (ctx,snap){
if(!snap.hasData) return Center(child: CircularProgressIndicator()); var rows=snap.data as List; double money=rows.fold(0.0, (sum,e)=> sum+(e['fare'] as double));
return Column(children:[Padding(padding: EdgeInsets.all(16), child: Text("TOTAL: ${rows.length} tickets | GHS $money", style: TextStyle(fontSize:20, fontWeight:FontWeight.bold))), Expanded(child: ListView.builder(itemCount: rows.length, itemBuilder: (_,i){ var r=rows[i]; return ListTile(title: Text("${r['ticket_id']} - ${r['name']}"), subtitle: Text("${r['from_s']} -> ${r['to_s']} | Seat ${r['seat']}"), trailing: Text("GHS ${r['fare']}")); }))]);
}));
}
}
class AdminScreen extends StatelessWidget{
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("ADMIN - $CURRENT_USER"), backgroundColor: Colors.black), body: ListView(padding: EdgeInsets.all(16), children:[
ListTile(title: Text("Create/Delete Account"), leading: Icon(Icons.person_add), onTap: ()=> Navigator.push(c, MaterialPageRoute(builder: (_)=> CreateAccountScreen()))),
ListTile(title: Text("View All Users"), leading: Icon(Icons.people), onTap: () async { var db=await DBHelper.db; var rows=await db.query('users'); showDialog(context: c, builder: (_)=> AlertDialog(title: Text("All Users"), content: SizedBox(width: 300, height: 400, child: ListView(children: rows.map((r)=> Text("${r['username']} | ${r['station']} | ${r['role']}")).toList())))); }),
ListTile(title: Text("View All Sales"), leading: Icon(Icons.list), onTap: ()=> Navigator.push(c, MaterialPageRoute(builder: (_)=> AllSalesScreen()))),
ListTile(title: Text("Logout"), leading: Icon(Icons.logout), onTap: (){ CURRENT_USER="None"; Navigator.pushReplacement(c, MaterialPageRoute(builder: (_)=> MainMenu())); }),
]));
}
class CreateAccountScreen extends StatefulWidget{ @override State<CreateAccountScreen> createState()=> _CreateAcc(); }
class _CreateAcc extends State<CreateAccountScreen>{
final u=TextEditingController(), pp=TextEditingController(), station=TextEditingController(), full=TextEditingController(); String role="station_master";
void create() async { var db=await DBHelper.db; await db.insert('users', {'username':u.text.trim().toLowerCase(),'password':hashPassword(pp.text),'station':station.text.toLowerCase(),'role':role,'full_name':full.text}, conflictAlgorithm: ConflictAlgorithm.replace); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Account ${u.text} created"))); }
void del() async { var db=await DBHelper.db; await db.delete('users', where:'username=?', whereArgs:[u.text.trim().toLowerCase()]); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Deleted ${u.text}"))); }
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("Create/Delete Account")), body: Padding(padding: EdgeInsets.all(16), child: ListView(children:[
TextField(controller: full, decoration: InputDecoration(labelText: "Full Name", border: OutlineInputBorder())), SizedBox(height:8),
TextField(controller: u, decoration: InputDecoration(labelText: "Username", border: OutlineInputBorder())), SizedBox(height:8),
TextField(controller: pp, decoration: InputDecoration(labelText: "Password", border: OutlineInputBorder())), SizedBox(height:8),
TextField(controller: station, decoration: InputDecoration(labelText: "Station", border: OutlineInputBorder())), SizedBox(height:8),
DropdownButtonFormField(value: role, items: ["admin","station_master"].map((e)=> DropdownMenuItem(value:e, child:Text(e))).toList(), onChanged:(v)=> setState(()=> role=v as String), decoration: InputDecoration(labelText: "Role", border: OutlineInputBorder())),
SizedBox(height:16), SizedBox(height:60, child: ElevatedButton(onPressed: create, child: Text("CREATE - BIG"))), SizedBox(height:8), SizedBox(height:60, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: del, child: Text("DELETE - BIG"))),
])));
}
class AllSalesScreen extends StatelessWidget{
@override Widget build(BuildContext c)=> Scaffold(appBar: AppBar(title: Text("ALL SALES")), body: FutureBuilder(future: DBHelper.db.then((db)=> db.query('sales', orderBy: 'date DESC')), builder: (ctx,snap){
if(!snap.hasData) return Center(child: CircularProgressIndicator()); var rows=snap.data as List;
return ListView.builder(itemCount: rows.length, itemBuilder: (_,i){ var r=rows[i]; return Card(child: ListTile(title: Text("${r['ticket_id']} | ${r['name']} - ${r['seat']}"), subtitle: Text("${r['date']} ${r['time']} | ${r['from_s']}->${r['to_s']} | By ${r['sold_by']}"), trailing: Text("GHS ${r['fare']}"))); });
}));
}
