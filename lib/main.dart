import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:crypto/crypto.dart';

void main()=>runApp(const TrotroApp());
class TrotroApp extends StatelessWidget{
const TrotroApp({super.key});
@override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'REAL ME TROTRO',theme:ThemeData(primaryColor:const Color(0xFFCE1126)),home:const Home());
}

// MODELS
Map<String,Map<String,double>> defaultFares={
"cape coast":{"swedru":45,"accra":35,"kumasi":25},
"swedru":{"cape coast":45,"accra":20,"kumasi":30},
"accra":{"cape coast":35,"swedru":20,"kumasi":45,"tamale":80,"kasoa":10},
"kumasi":{"cape coast":25,"swedru":30,"accra":45,"tamale":65},
"tamale":{"kumasi":65,"accra":80}
};

class Home extends StatefulWidget{const Home({super.key});@override State<Home>createState()=>_HomeS();}
class _HomeS extends State<Home>{
String? curUser;String? curRole;String? curStation;
Map<String,Map<String,double>> fares={};
Map<String,dynamic> users={};
List usedSeats=[]; List sales=[];

@override void initState(){super.initState();loadAll();}
Future loadAll()async{
final p=await SharedPreferences.getInstance();
fares=defaultFares;
if(p.getString('fares')!=null){fares=Map<String,Map<String,double>>.from((jsonDecode(p.getString('fares')!) as Map).map((k,v)=>MapEntry(k,Map<String,double>.from((v as Map).map((k2,v2)=>MapEntry(k2,(v2 as num).toDouble()))))));}
users=p.getString('users')!=null?jsonDecode(p.getString('users')!):{"admin":{"pw":sha256.convert(utf8.encode("Ad1My")).toString(),"station":"Head Office","role":"admin","name":"System Admin"}};
usedSeats=p.getStringList('seats')??[]; sales=p.getString('sales')!=null?jsonDecode(p.getString('sales')!):[];
setState((){});
}
Future saveAll()async{
final p=await SharedPreferences.getInstance();
p.setString('fares',jsonEncode(fares));p.setString('users',jsonEncode(users));p.setStringList('seats',usedSeats.cast<String>());p.setString('sales',jsonEncode(sales));
}
String hash(String s)=>sha256.convert(utf8.encode(s)).toString();

// UI
@override Widget build(BuildContext context){
return Scaffold(appBar:AppBar(backgroundColor:const Color(0xFFCE1126),title:const Text('REAL ME TROTRO - GOV',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),centerTitle:true),
body:ListView(padding:const EdgeInsets.all(16),children:[
Container(padding:const EdgeInsets.all(12),color:Colors.black,child:const Text('Safe. Fast. Reliable. | Government Approved',style:TextStyle(color:Color(0xFFFCD116)),textAlign:TextAlign.center)),
const SizedBox(height:20),
if(curUser==null)...[
btn('1. Passenger - CHECK FARE ONLY',Colors.green,()=>openPassenger()),
btn('2. Station Master Login',Colors.blue,()=>openLogin()),
btn('3. Create/Delete Account (Admin)',Colors.orange,()=>openAdminCreate()),
btn('4. Verify Ticket QR',Colors.purple,()=>openVerify()),
] else...[
Text('Welcome $curUser | $curStation | $curRole',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:10),
if(curRole=='station_master')...[
btn('>>> SELL TICKET <<<',const Color(0xFFCE1126),()=>openSell()),
btn('View Routes',Colors.grey,()=>openRoutes()),
btn('Daily Sales Report',Colors.teal,()=>openReport()),
btn('Seat Map',Colors.brown,()=>openSeatMap()),
btn('Reset Seats',Colors.red,()=>resetSeats()),
],
if(curRole=='admin')...[
btn('Create Station Account',Colors.orange,()=>openAdminCreate()),
btn('View Routes',Colors.grey,()=>openRoutes()),
btn('Daily Sales Report',Colors.teal,()=>openReport()),
],
ElevatedButton(onPressed:(){setState((){curUser=null;curRole=null;curStation=null;});},child:const Text('Logout'))
]
]));
}

Widget btn(String t,Color c,VoidCallback f)=>Padding(padding:const EdgeInsets.only(bottom:10),child:ElevatedButton(style:ElevatedButton.styleFrom(backgroundColor:c,padding:const EdgeInsets.all(16)),onPressed:f,child:Text(t,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold))));

// PASSENGER - CHECK ONLY
void openPassenger(){
String from='',to='';double? found;
showDialog(context:context,builder:(d)=>StatefulBuilder(builder:(c,setS)=>AlertDialog(title:const Text('PASSENGER CHECK FARE'),content:Column(mainAxisSize:MainAxisSize.min,children:[
TextField(decoration:const InputDecoration(labelText:'From'),onChanged:(v)=>from=v.toLowerCase()),
TextField(decoration:const InputDecoration(labelText:'To'),onChanged:(v)=>to=v.toLowerCase()),
if(found!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text('FARE: GHS ${found!.toStringAsFixed(2)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:Colors.green))),
]),actions:[
TextButton(onPressed:(){
var f=fares[from.trim()];if(f!=null&&f.containsKey(to.trim())){setS(()=>found=f[to.trim()]);}
else{setS(()=>found=null); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No route found')));}
},child:const Text('CHECK')),
TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close'))
])));
}

// LOGIN
void openLogin(){
String u='',p='';
showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('Station Master Login'),content:Column(mainAxisSize:MainAxisSize.min,children:[
TextField(decoration:const InputDecoration(labelText:'Username'),onChanged:(v)=>u=v.toLowerCase()),
TextField(decoration:const InputDecoration(labelText:'Password'),obscureText:true,onChanged:(v)=>p=v),
]),actions:[
TextButton(onPressed:(){
if(users.containsKey(u)&&users[u]['pw']==hash(p)){
setState((){curUser=u;curRole=users[u]['role'];curStation=users[u]['station'];});
Navigator.pop(d);
}else{ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Wrong!')));}
},child:const Text('Login'))
]));
}

// ADMIN CREATE
void openAdminCreate(){
String nu='',np='',fn='',st=''; String adminP='';
showDialog(context:context,builder:(d)=>StatefulBuilder(builder:(c,setS)=>AlertDialog(title:const Text('Admin - Create Station'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
if(users.length>1)TextField(decoration:const InputDecoration(labelText:'Admin Password to confirm'),obscureText:true,onChanged:(v)=>adminP=v),
TextField(decoration:const InputDecoration(labelText:'New Username (one word)'),onChanged:(v)=>nu=v.toLowerCase()),
TextField(decoration:const InputDecoration(labelText:'Full Name'),onChanged:(v)=>fn=v),
TextField(decoration:const InputDecoration(labelText:'Password'),onChanged:(v)=>np=v),
TextField(decoration:const InputDecoration(labelText:'Station'),onChanged:(v)=>st=v),
const SizedBox(height:10),
...users.entries.map((e)=>Text('${e.key} | ${e.value['name']} | ${e.value['station']} | ${e.value['role']}',style:const TextStyle(fontSize:11))).toList()
])),actions:[
TextButton(onPressed:(){
if(users.length>1&&hash(adminP)!=users['admin']['pw']){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Admin auth failed')));return;}
if(nu.isEmpty||np.isEmpty||users.containsKey(nu)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Invalid username')));return;}
users[nu]={'pw':hash(np),'station':st,'role':'station_master','name':fn};saveAll();setState((){});Navigator.pop(c);
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Created $fn')));
},child:const Text('Create')),
TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close'))
])));
}

// SELL
void openSell(){
String name='',from='',to='';String seat='';
List<String> allSeats=[for(var i=1;i<=30;i++)'A${i.toString().padLeft(2,'0')}'];
List<String> avail=[for(var s in allSeats)if(!usedSeats.contains(s))s];
showDialog(context:context,builder:(d)=>StatefulBuilder(builder:(c,setS)=>AlertDialog(title:const Text('SELL TICKET'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
TextField(decoration:const InputDecoration(labelText:'Passenger Name'),onChanged:(v)=>name=v),
TextField(decoration:const InputDecoration(labelText:'From'),onChanged:(v)=>from=v.toLowerCase()),
TextField(decoration:const InputDecoration(labelText:'To'),onChanged:(v)=>to=v.toLowerCase()),
DropdownButton<String>(value:seat.isEmpty?null:seat,hint:Text('Seat ${avail.isNotEmpty?avail.first:''}'),items:avail.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setS(()=>seat=v??''))
])),actions:[
TextButton(onPressed:(){
if(from.isEmpty||to.isEmpty||name.isEmpty)return;
var fare=fares[from.trim()]?[to.trim()];
if(fare==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No route')));return;}
if(seat.isEmpty)seat=avail.first;
var tid='T${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
var qr='REALME|$tid|$seat|${from.toUpperCase()}-${to.toUpperCase()}|$fare|${DateTime.now()}|${curUser}';
var sale={'ticket_id':tid,'name':name,'from':from,'to':to,'fare':fare,'seat':seat,'sold_by':curUser,'date':DateTime.now().toString().split(' ')[0],'time':DateTime.now().toString().split(' ')[1].substring(0,5),'qr':qr,'used':false};
sales.add(sale);usedSeats.add(seat);saveAll();setState((){});Navigator.pop(c);
showDialog(context:context,builder:(b)=>AlertDialog(title:Text('SOLD $tid'),content:Column(mainAxisSize:MainAxisSize.min,children:[Text('Route ${from.toUpperCase()} -> ${to.toUpperCase()}\nSeat $seat\nGHS $fare'),const SizedBox(height:10),QrImageView(data:qr,size:180,version:QrVersions.auto)]),actions:[TextButton(onPressed:()=>Navigator.pop(b),child:const Text('Done'))]));
},child:const Text('SELL & PRINT QR'))
]));
}

void openVerify(){
final ctrl=MobileScannerController();
showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('Verify Ticket'),content:SizedBox(height:300,width:300,child:MobileScanner(controller:ctrl,onDetect:(cap){
var raw=cap.barcodes.first.rawValue??'';
if(!raw.startsWith('REALME|'))return;
var tid=raw.split('|')[1];
var found=sales.where((e)=>e['ticket_id']==tid).toList();
if(found.isEmpty){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('FAKE! $tid not found')));}
else if(found.first['used']==true){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ALREADY USED! FRAUD BLOCK')));}
else{found.first['used']=true;saveAll();setState((){});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('VALID! ${found.first['name']} ${found.first['from']}->${found.first['to']} Seat ${found.first['seat']}')));Navigator.pop(d);}
})),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Close'))]));
}

void openRoutes()=>showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('All Routes'),content:SingleChildScrollView(child:Column(children:[for(var fs in fares.keys)for(var ts in fares[fs]!.keys)if(fs.compareTo(ts)<0)Text('${fs.toUpperCase()} <-> ${ts.toUpperCase()} : GHS ${fares[fs]![ts]}')])),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Close'))]));
void openReport(){
var today=DateTime.now().toString().split(' ')[0];var todaySales=sales.where((e)=>e['date']==today).toList();double tot=todaySales.fold(0,(p,e)=>p+(e['fare'] as num).toDouble());
showDialog(context:context,builder:(d)=>AlertDialog(title:Text('Sales $today'),content:Text('Total: ${todaySales.length} tickets\nMoney: GHS ${tot.toStringAsFixed(2)}\nSeats left: ${30-usedSeats.length}/30'),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Close'))]));
}
void openSeatMap()=>showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('Seat Map'),content:SingleChildScrollView(child:Wrap(children:[for(var i=1;i<=30;i++)Padding(padding:const EdgeInsets.all(4),child:Container(padding:const EdgeInsets.all(8),color:usedSeats.contains('A${i.toString().padLeft(2,'0')}')?Colors.red:Colors.green,child:Text('A${i.toString().padLeft(2,'0')}',style:const TextStyle(color:Colors.white))))])),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Close'))]));
void resetSeats(){usedSeats.clear();saveAll();setState((){});ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Seats reset done')));}
           }
