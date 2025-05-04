import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'dart:io';
import 'core/utils/supabase_manager.dart';
import 'core/services/db_manager_service.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_creation_screen.dart';
import 'screens/schedule_management_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // Initialize timezone database

  // Initialize platform-specific notification settings
  const androidSettings = AndroidInitializationSettings('schedule_app_logo');
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
  // try {
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  // } catch (e) {
  //   print('Failed to initialize notifications: $e');
  // }

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    // try {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // } catch (e) {}
  }
  await Hive.initFlutter();
  await Hive.openBox('offline_operations');
  await Hive.openBox('alarms');
  await dotenv.load(fileName: '.env.v2');
  // try {
  await SupabaseManager.initialize();
  // } catch (e) {}
  final connectivityResult = await Connectivity().checkConnectivity();
  final isOffline = connectivityResult.contains(ConnectivityResult.none);
  if (isOffline) {
    // try {
    final dbManager = DbManagerService();
    await dbManager.initializeDatabases(isLocalOnly: true);
    // } catch (e) {}
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scheduling App',
      theme: ThemeData(
        textTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context).textTheme,
        ),
        primaryTextTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context).primaryTextTheme,
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/login',
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
