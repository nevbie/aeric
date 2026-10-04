import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'services/logbook.dart';
import 'ui/common.dart';
import 'ui/flight_screen.dart';
import 'ui/fly_screen.dart';
import 'ui/logbook_screen.dart';
import 'ui/map_screen.dart';
import 'ui/thermal_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppState.instance.loadFavourites();
  Logbook.instance.load();
  runApp(const AericApp());
  AppState.instance.refreshForecasts();
}

class AericApp extends StatelessWidget {
  const AericApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) =>
        ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: aericBlue, brightness: b), useMaterial3: true);
    return MaterialApp(
      title: 'aeric',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Tabs are built on first visit (the map would otherwise load tiles at start-up) and kept alive.
  final _visited = <int>{};

  static const _tabs = 5;

  static Widget _tab(int i) => switch (i) {
        0 => const FlyScreen(),
        1 => const MapScreen(),
        2 => const ThermalScreen(),
        3 => const FlightScreen(),
        _ => const LogbookScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: app.tab,
            children: [
              for (var i = 0; i < _tabs; i++) (_visited..add(app.tab)).contains(i) ? _tab(i) : const SizedBox.shrink(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: app.tab,
          onDestinationSelected: app.setTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.paragliding), label: 'Fly'),
            NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Thermals'),
            NavigationDestination(icon: Icon(Icons.speed), label: 'Flight'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Logbook'),
          ],
        ),
      ),
    );
  }
}
