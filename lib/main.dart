import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'ui/common.dart';
import 'ui/fly_screen.dart';
import 'ui/thermal_screen.dart';

void main() {
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

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(index: app.tab, children: const [FlyScreen(), ThermalScreen()]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: app.tab,
          onDestinationSelected: app.setTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.paragliding), label: 'Fly'),
            NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Thermals'),
          ],
        ),
      ),
    );
  }
}
