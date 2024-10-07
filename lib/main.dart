import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:convert';

// TODO: fix bug where interactive scroller does not allow scrolling when switching to landscape orientation after scrolling to the right
// TODO: automatic update on PDGA ratings update (possibly with notification)
// TODO: deploy to app store (see https://medium.com/@magnigeeks3/deploying-flutter-apps-to-app-stores-a-step-by-step-guide-00dab049bea0)

void main() {
  runApp(const MyApp());
}

Future<String> get _localPath async {
  // Gets the documents directory for the device
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

Future<File> get _localFile async {
  // Gets the path to the JSON file where the player data gets stored
  final path = await _localPath;
  return File('$path/players.json');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'PDGA Player Ratings'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  // Home page for the app

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
  // Primary data class for PDGA players
  int pdgaNumber;
  String name;
  int? rating;
  int? ratingDifference;
  DateTime? ratingDate;
  Uri url;

  Player(this.pdgaNumber, this.name, this.rating, this.ratingDifference, this.ratingDate, this.url);

  factory Player.fromJson(Map<String, dynamic> json) {
    // Decodes JSON data for a single player and creates a new Player object
    String? ratingDateVal = json["ratingDate"];
    DateTime? ratingDate;
    if (ratingDateVal != null) {
      ratingDate = DateTime(
        int.parse(json["ratingDate"].split("-")[0]),
        int.parse(json["ratingDate"].split("-")[1]),
        int.parse(json["ratingDate"].split("-")[2])
      );
    } else {
      ratingDate = null;
    }
    final Uri url = Uri.parse(json["url"]);
    return Player(
      json["pdgaNumber"], json["name"], json["rating"], json["ratingDifference"], ratingDate, url
    );
  }

  Map<String, dynamic> toJson() {
    // Encodes the Player as a single JSON mapping
    final ratingDateVal = ratingDate;
    String? ratingDateAsString;
    if (ratingDateVal != null) {
      int year = ratingDateVal.year;
      int month = ratingDateVal.month;
      int day = ratingDateVal.day;
      ratingDateAsString = "$year-$month-$day";
    }
    Map<String, dynamic> jsonData = {
      "pdgaNumber": pdgaNumber,
      "name": name,
      "rating": rating,
      "ratingDifference": ratingDifference,
      "ratingDate": ratingDateAsString,
      "url": url.toString(),
    };
    return jsonData;
  }

  String getDisplayDate() {
    // Gets a display-friendly version of the most recent ratings update date for a player
    final value = ratingDate;
    if (value == null) {
      return "N/A";
    } else {
      return DateFormat.yMd().format(value);
    }
  }

  String getDisplayRating() {
    // Gets a display-friendly version of a player's current rating
    final value = rating;
    if (value == null) {
      return "Expired";
    } else {
      return rating.toString();
    }
  }

  Row getRatingDisplayWidget() {
    // Creates a text widget containing a player's rating and possibly an up/down arrow and rating difference
    final ratingVal = rating;
    final ratingDifferenceVal = ratingDifference;
    if (ratingVal == null || ratingDifferenceVal == null) {
      return Row(children: [Text(getDisplayRating())],);
    }
    if (ratingDifferenceVal < 0) {
      return Row(children: [Text(getDisplayRating()), const Icon(Icons.arrow_downward_rounded), Text(ratingDifferenceVal.toString())],);
    }
    if (ratingDifferenceVal > 0) {
      return Row(children: [Text(getDisplayRating()), const Icon(Icons.arrow_upward_rounded), Text(ratingDifferenceVal.toString())],);
    }
    throw Exception("Rating difference value cannot be zero");
  }
}

Uri getPlayerUrl(int pdgaNumber) {
  // Gets the URI path to a player's PDGA page
  String pdgaNumberString = pdgaNumber.toString();
  String url = 'https://pdga.com/player/$pdgaNumberString';
  final Uri uri = Uri.parse(url);
  return uri;
}

Future<String> getPlayerData(int pdgaNumber) async {
  // Fetches a player's data from their PDGA page
  Uri uri = getPlayerUrl(pdgaNumber);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    return response.body;
  }
  return "";
}

int? getPlayerRating(String responseBody) {
  // Parses a player's rating from the raw fetched HTML. Returns null if
  // there is no rating data or the player's membership has expired.
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

int? getPlayerRatingDifference(String responseBody) {
  // Parses a player's rating difference from the raw fetched HTML. Returns
  // null if the player's rating has not been updated recently.
  if (!responseBody.contains("rating-difference")) {
    return null;
  }
  String split_1 = responseBody.split("rating-difference")[1];
  String split_2 = split_1.split("</a>")[0];
  String ratingDifference = split_2.split(">")[1];
  return int.parse(ratingDifference);
}

DateTime? getPlayerRatingDate(String responseBody) {
  // Parses the date of the player's last ratings update from the raw
  // fethced HTML. Returns null if the player's membership has expired.
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
  // Parses the player's name from the raw fetched HTML.
  String split_1 = responseBody.split('page-title">')[1];
  String split_2 = split_1.split("</h1>")[0];
  String split_3 = split_2.split("#")[0];
  String name = split_3.trim();
  return name;
}

class _MyHomePageState extends State<MyHomePage> {
  // Primary state for the app
  late TextEditingController controller; // Used for pop-up dialog
  List<Player> players = [];
  Color alternateRowColor = const Color.fromARGB(255, 213, 222, 219);
  Color gradientEndColor = const Color.fromARGB(255, 30, 154, 212);
  Color notificationBoxColor = const Color.fromARGB(255, 55, 55, 55);
  bool playersUpdated = false;
  bool sortTableAscending = true;
  int lastSortColumn = 0;

  @override
  void initState() {
    super.initState();
    // Add a postframe callback that reads the players from the file if the file exists
    WidgetsBinding.instance.addPostFrameCallback((_) {readPlayersFromFile();});
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> readPlayersFromFile() async {
    // Decodes the data from players.json and uses it to re-create
    // the list of Player objects.
    final file = await _localFile;
    String? contents;
    try {
      contents = await file.readAsString();
    } on PathNotFoundException {
      return;
    }
    
    var jsonResponse = jsonDecode(contents);

    setState(() {
      for (var p in jsonResponse) {
        Player player = Player.fromJson(p);
        players.add(player);
      }
    });
  }

  void writePlayersToFile() async {
    // Encodes the data for all the Player objects into the players.json
    // file
    final file = await _localFile;
    file.writeAsStringSync(
      json.encode(players.map((player) => player.toJson(),).toList())
    );
  }

  void _addPlayer(int pdgaNumber) {
    // Adds a new Player object given the PDGA number input from the pop-up dialog
    getPlayerData(pdgaNumber).then((responseBody) {
      setState(() {

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
        int? ratingDifference = getPlayerRatingDifference(responseBody);
        String name = getPlayerName(responseBody);
        DateTime? ratingDate = getPlayerRatingDate(responseBody);
        Uri url = getPlayerUrl(pdgaNumber);
        Player player = Player(pdgaNumber, name, rating, ratingDifference, ratingDate, url);
        players.add(player);
        writePlayersToFile();
      });
    });
  }

  void _removePlayer(Player player) {
    // Removes a player from the list (probably due to the user pressing the trash can icon)
    setState(() {
      players.remove(player);
      writePlayersToFile();
    });
  }

  void _refreshPlayers() {
    // Refreshs the ratings, rating differences, and rating dates for all the currently loaded players
    for (final player in players) {
      getPlayerData(player.pdgaNumber).then((responseBody) {
        setState(() {
          int? rating = getPlayerRating(responseBody);
          int? ratingDifference = getPlayerRatingDifference(responseBody);
          DateTime? ratingDate = getPlayerRatingDate(responseBody);
          player.rating = rating;
          player.ratingDifference = ratingDifference;
          player.ratingDate = ratingDate;
          writePlayersToFile();
          notifyPlayersUpdated();
        });
      });
    }
  }

  void _sortPlayers(int column) {
    // Sorts the players by the data in the given column either in descending order
    // (if the last sort was in ascending order) and vice versa.
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

  void notifyPlayersUpdated() {
    // Notifies the main widget that the refresh button was pressed and the players
    // were updated so that a notification widget can be temporarily shown
    setState(() {
      playersUpdated = true;
    });
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        playersUpdated = false;
      });
    });
  }

  Future<String?> _openAddPlayerDialog() => showDialog<String>(
    // Opens a numeric input dialog that, when accepted, creates a new Player
    // object with the given PDGA number
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
    // Main widget scaffold
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft, // Start direction
                end: Alignment.topRight, // End direction
                colors: [
                  Theme.of(context).colorScheme.inversePrimary, // Start Color
                  gradientEndColor,// End Color
                ], // Customize your colors here
              ),
            ),
        ),
        title: Text(widget.title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),),
      ),
      body: Center(
        child: Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              scaleEnabled: false,
              child: DataTable(
                headingRowColor: WidgetStateColor.resolveWith((Set<WidgetState> states) {
                    return Theme.of(context).colorScheme.onInverseSurface;
                  }),
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
                  for (var playerIdx = 0; playerIdx < players.length; playerIdx += 1)
                    DataRow.byIndex(
                      color: WidgetStateColor.resolveWith((Set<WidgetState> states) {
                        if (playerIdx % 2 == 0) {
                          return alternateRowColor;
                        }
                        return Theme.of(context).colorScheme.onInverseSurface;
                      }),
                      index: playerIdx,
                      cells: [
                        DataCell(Text(players[playerIdx].pdgaNumber.toString())),
                        DataCell(
                          InkWell(
                            child: Text(players[playerIdx].name, style: TextStyle(color: gradientEndColor, decoration: TextDecoration.underline),),
                            onTap: () => launchUrl(players[playerIdx].url),
                          )
                        ),
                        DataCell(players[playerIdx].getRatingDisplayWidget()),
                        DataCell(Text(players[playerIdx].getDisplayDate())),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removePlayer(players[playerIdx]),
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
                  backgroundColor: Theme.of(context).colorScheme.inversePrimary.withOpacity(0.8),
                  onPressed: _refreshPlayers,
                  tooltip: 'Update Player Data',
                  child: const Icon(Icons.refresh),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: AnimatedOpacity(
                  opacity: playersUpdated ? 0.8 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    width: 200,
                    height: 55,
                    decoration: BoxDecoration(
                      color: notificationBoxColor,
                      border: Border.all(),
                      borderRadius: BorderRadius.circular(20)
                    ),
                    child: const Center(child: Text("Updated Ratings", style: TextStyle(color: Colors.white, fontSize: 18),)),
                  ),
                ),
              )
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: FloatingActionButton(
                  backgroundColor: gradientEndColor.withOpacity(0.8),
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
