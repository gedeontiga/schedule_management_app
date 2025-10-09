import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'dart:io';
import 'core/utils/firebase_manager.dart';
import 'core/services/offline_sync_service.dart';
import 'screens/auth_wrapper.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_creation_screen.dart';
import 'screens/schedule_management_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone data for notifications
  tz.initializeTimeZones();

  // Initialize local notifications
  const androidSettings = AndroidInitializationSettings('schedulo_logo');
  const iosSettings = DarwinInitializationSettings();
  const linuxSettings = LinuxInitializationSettings(
    defaultActionName: 'Open notification',
  );
  const initializationSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
    macOS: iosSettings,
    linux: linuxSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Initialize sqflite for desktop platforms
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Hive for offline operations
  await Hive.initFlutter();
  await Hive.openBox('offline_operations');
  await Hive.openBox('offline_cache');
  await Hive.openBox('alarms');

  // Check connectivity
  final connectivityResult = await Connectivity().checkConnectivity();
  final isOffline = connectivityResult.contains(ConnectivityResult.none);

  try {
    if (!isOffline) {
      // Initialize Firebase when online
      await FirebaseManager.initialize();
    } else {}

    // Initialize offline sync service
    final offlineSync = OfflineSyncService();
    await offlineSync.initialize();

    // Start auto-sync when connection is restored
    if (!isOffline) {
      await offlineSync.syncPendingOperations();
    }
  } catch (e) {
    // Fallback to offline queue
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Schedulo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.oswaldTextTheme(
          Theme.of(context).textTheme,
        ),
        primaryTextTheme: GoogleFonts.oswaldTextTheme(
          Theme.of(context).primaryTextTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A90E2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          titleTextStyle: GoogleFonts.oswald(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
      // Use AuthWrapper as initial screen
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegistrationScreen(),
        '/home': (context) => const HomeScreen(),
        '/create-schedule': (context) => const ScheduleCreationScreen(),
        '/manage-schedule': (context) => const ScheduleManagementScreen(),
      },
    );
  }
}
