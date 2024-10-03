import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

// TODO: add rating-difference
// TODO: save player info to device
// TODO: prettify
// TODO: automatic update on PDGA ratings update (possibly with notification)
// TODO: deploy to app store (see https://medium.com/@magnigeeks3/deploying-flutter-apps-to-app-stores-a-step-by-step-guide-00dab049bea0)

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'PDGA Player Ratings'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

const Map<String,int> monthStringToInt = {
  "Jan": 1,
  "Feb": 2,
  "Mar": 3,
  "Apr": 4,
  "May": 5,
  "Jun": 6,
  "Jul": 7,
  "Aug": 8,
  "Sep": 9,
  "Oct": 10,
  "Nov": 11,
  "Dec": 12,
};

class Player {
  int pdgaNumber;
  String name;
  int? rating;
  DateTime? ratingDate;
  Uri url;

  Player(this.pdgaNumber, this.name, this.rating, this.ratingDate, this.url);

  String getDisplayDate() {
    final value = ratingDate;
    if (value == null) {
      return "N/A";
    } else {
      return DateFormat.yMd().format(value);
    }
  }

  String getDisplayRating() {
    final value = rating;
    if (value == null) {
      return "Expired";
    } else {
      return rating.toString();
    }
  }
}

Uri getPlayerUrl(int pdgaNumber) {
  String pdgaNumberString = pdgaNumber.toString();
  String url = 'https://pdga.com/player/$pdgaNumberString';
  final Uri uri = Uri.parse(url);
  return uri;
}

Future<String> getPlayerData(int pdgaNumber) async {
  Uri uri = getPlayerUrl(pdgaNumber);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    return response.body;
  }
  return "";
}

int? getPlayerRating(String responseBody) {
  if (responseBody.contains("PDGA membership has expired")) {
    return null;
  }
  if (!responseBody.contains("current-rating")) {
    return null;
  }
  String split_1 = responseBody.split("current-rating")[1];
  String split_2 = split_1.split("rating-date")[0];
  String split_3 = split_2.split("</strong>")[1];
  String split_4 = split_3.split("<")[0];
  String rating = split_4.replaceAll(RegExp(r"\s+"), "");
  return int.parse(rating);
}

DateTime? getPlayerRatingDate(String responseBody) {
  if (!responseBody.contains("rating-date")) {
    return null;
  }
  String split_1 = responseBody.split("rating-date")[1];
  String split_2 = split_1.split("(as of")[1];
  String split_3 = split_2.split(")<")[0];
  String ratingDateString = split_3.trim();
  List<String> ratingDateList = ratingDateString.split("-");
  int day = int.parse(ratingDateList[0]);
  int? month = monthStringToInt[ratingDateList[1]];
  int year = int.parse(ratingDateList[2]);
  if (month == null) {
    return null;
  }
  return DateTime(year, month, day);
}

String getPlayerName(String responseBody) {
  String split_1 = responseBody.split('page-title">')[1];
  String split_2 = split_1.split("</h1>")[0];
  String split_3 = split_2.split("#")[0];
  String name = split_3.trim();
  return name;
}

class _MyHomePageState extends State<MyHomePage> {
  late TextEditingController controller;
  List<Player> players = [];
  bool sortTableAscending = true;
  int lastSortColumn = 0;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _addPlayer(int pdgaNumber) {
    getPlayerData(pdgaNumber).then((responseBody) {
      setState(() {
        // This call to setState tells the Flutter framework that something has
        // changed in this State, which causes it to rerun the build method below
        // so that the display can reflect the updated values. If we changed
        // _counter without calling setState(), then the build method would not be
        // called again, and so nothing would appear to happen.

        // If the player data could not be fetched for this PDGA number, just return
        if (responseBody == "") {
          return;
        }

        // If we've already added this PDGA number, do not add it again
        for (final player in players) {
          if (player.pdgaNumber == pdgaNumber) {
            return;
          }
        }

        int? rating = getPlayerRating(responseBody);
        String name = getPlayerName(responseBody);
        DateTime? ratingDate = getPlayerRatingDate(responseBody);
        Uri url = getPlayerUrl(pdgaNumber);
        Player player = Player(pdgaNumber, name, rating, ratingDate, url);
        players.add(player);
      });
    });
  }

  void _removePlayer(Player player) {
    setState(() {
      players.remove(player);
    });
  }

  void _refreshPlayers() {
    for (final player in players) {
      getPlayerData(player.pdgaNumber).then((responseBody) {
        setState(() {
          int? rating = getPlayerRating(responseBody);
          DateTime? ratingDate = getPlayerRatingDate(responseBody);
          player.rating = rating;
          player.ratingDate = ratingDate;
        });
      });
    }
  }

  void _sortPlayers(int column) {
    setState(() {
      final nullFirst = DateTime(1);
      final nullLast = DateTime(99999);
      if (column == lastSortColumn) {
        sortTableAscending = !sortTableAscending; // Flip the sort direction
      }
      if (sortTableAscending) {
        switch (column) {
          case 0:
            players.sort((a, b) => a.pdgaNumber.compareTo(b.pdgaNumber));
          case 1:
            players.sort((a, b) => a.name.compareTo(b.name));
          case 2:
            players.sort((a, b) {
              final ratingA = a.rating; 
              final ratingB = b.rating; 
              if (ratingA == null) {return 1;} 
              if (ratingB == null) {return -1;} 
              return ratingA.compareTo(ratingB);
            });
          case 3:
            players.sortBy((e) => e.ratingDate ?? nullLast);
        }
      } else {
        switch (column) {
          case 0:
            players.sort((b, a) => a.pdgaNumber.compareTo(b.pdgaNumber));
          case 1:
            players.sort((b, a) => a.name.compareTo(b.name));
          case 2:
            players.sort((a, b) {
              final ratingA = a.rating; 
              final ratingB = b.rating; 
              if (ratingA == null) {return -1;} 
              if (ratingB == null) {return 1;} 
              return ratingA.compareTo(ratingB);
            });
            players = players.reversed.toList();
          case 3:
            players.sortBy((e) => e.ratingDate ?? nullFirst);
            players = players.reversed.toList();
        }
      }
      lastSortColumn = column;
    });
  }

  Future<String?> _openAddPlayerDialog() => showDialog<String>(
    context: context, 
    builder: (context) => AlertDialog(
      title: const Text("PDGA Number"),
      content: TextField(
        autofocus: true,
        controller: controller,
        decoration: const InputDecoration(labelText: "PDGA #"),
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly
        ],
      ),
      actions: [
        TextButton(
          onPressed: submit, 
          child: const Text("SUBMIT")
        )
      ]
    )
  );

  void submit() {
    Navigator.of(context).pop(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              child: DataTable(
                border: TableBorder.all(),
                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                columns: [
                  DataColumn(label: TextButton(child: const Text("PDGA #"), onPressed: () => _sortPlayers(0),)),
                  DataColumn(label: TextButton(child: const Text("Name"), onPressed: () => _sortPlayers(1),)),
                  DataColumn(label: TextButton(child: const Text("Rating"), onPressed: () => _sortPlayers(2),)),
                  DataColumn(label: TextButton(child: const Text("Date"), onPressed: () => _sortPlayers(3),)),
                  const DataColumn(label: Text("Actions"))
                ],
                rows: [
                  for (final player in players)
                    DataRow(
                      cells: [
                        DataCell(Text(player.pdgaNumber.toString())),
                        DataCell(
                          InkWell(
                            child: Text(player.name, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),),
                            onTap: () => launchUrl(player.url),
                          )
                        ),
                        DataCell(Text(player.getDisplayRating())),
                        DataCell(Text(player.getDisplayDate())),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removePlayer(player),
                          )
                        )
                      ]
                    )
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: FloatingActionButton(
                  backgroundColor: const Color.fromARGB(99, 119, 90, 177),
                  onPressed: _refreshPlayers,
                  tooltip: 'Update Player Data',
                  child: const Icon(Icons.refresh),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: FloatingActionButton(
                  onPressed: () async {
                    final pdgaNumberToAdd = await _openAddPlayerDialog();
                    if (pdgaNumberToAdd == null || pdgaNumberToAdd.isEmpty) return;
                    _addPlayer(int.parse(pdgaNumberToAdd));                     
                  },
                  tooltip: 'Add Player',
                  child: const Icon(Icons.add),
                ),
              )
            )
          ],
        ),
      ),
    );
  }
}
