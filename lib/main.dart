import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/archive_test_screen.dart';

// إنشاء نظام الإشعارات المحلية
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// إعداد قناة الإشعارات
const AndroidNotificationChannel notificationChannel =
    AndroidNotificationChannel(
      'movies_notifications',
      'Movies Notifications',
      description: 'Notifications for the Movies app',
      importance: Importance.max,
    );

// استقبال الإشعارات في الخلفية
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('Background Message: ${message.messageId}');
}

// تهيئة الإشعارات المحلية
Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  // إنشاء قناة الإشعارات
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(notificationChannel);

  // طلب إذن الإشعارات
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}

// عرض الإشعار على الهاتف
Future<void> showLocalNotification(RemoteMessage message) async {
  final String title =
      message.notification?.title ??
      message.data['title']?.toString() ??
      'Movies';

  final String body =
      message.notification?.body ??
      message.data['body']?.toString() ??
      'You have a new notification';

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'movies_notifications',
    'Movies Notifications',
    channelDescription: 'Notifications for the Movies app',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title: title,
    body: body,
    notificationDetails: notificationDetails,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تشغيل Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // تسجيل معالج إشعارات الخلفية
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MoviesApp());
  unawaited(_initializeMessaging());
}

Future<void> _initializeMessaging() async {
  try {
    await initializeLocalNotifications();
  } catch (error) {
    debugPrint('Local notifications could not be initialized: $error');
  }

  FirebaseMessaging.onMessage.listen((message) async {
    try {
      await showLocalNotification(message);
    } catch (error) {
      debugPrint('Foreground notification could not be shown: $error');
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    debugPrint('Notification Opened: ${message.notification?.title}');
  });

  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  } catch (error) {
    debugPrint('Notification permission could not be requested: $error');
  }

  try {
    final registrationIdFuture = FirebaseMessaging.instance.onRegistered.first;
    await FirebaseMessaging.instance.register();
    final registrationId = await registrationIdFuture;
    debugPrint('FCM registration ID: $registrationId');
  } catch (error) {
    debugPrint('FCM registration could not be completed: $error');
  }

  try {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
        'App Opened From Notification: ${initialMessage.notification?.title}',
      );
    }
  } catch (error) {
    debugPrint('Initial notification could not be retrieved: $error');
  }
}

class MoviesApp extends StatelessWidget {
  const MoviesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Movies',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const AuthGate(),
      onGenerateRoute: (settings) {
        final isAuthenticated = FirebaseAuth.instance.currentUser != null;
        final initialGenre = settings.arguments is String
            ? settings.arguments! as String
            : settings.arguments is Map
                ? (settings.arguments as Map)['genre']?.toString()
                : null;
        final initialSort = settings.arguments is Map
            ? (settings.arguments as Map)['sortBy']?.toString()
            : null;
        final WidgetBuilder? builder = switch (settings.name) {
          '/home' =>
            isAuthenticated
                ? (_) => const HomeScreen()
                : (_) => const LoginScreen(),
          '/search' =>
            isAuthenticated
                ? (_) => const SearchScreen()
                : (_) => const LoginScreen(),
          '/browse' =>
            isAuthenticated
                ? (_) => BrowseScreen(
                    initialGenre: initialGenre,
                    initialSort: initialSort,
                  )
                : (_) => const LoginScreen(),
          '/profile' =>
            isAuthenticated
                ? (_) => const ProfileScreen()
                : (_) => const LoginScreen(),
          '/login' =>
            isAuthenticated
                ? (_) => const HomeScreen()
                : (_) => const LoginScreen(),
          '/archive-test' => (_) => const ArchiveTestScreen(),
          _ => null,
        };
        if (builder == null) return null;
        return MaterialPageRoute<void>(settings: settings, builder: builder);
      },
    );
  }
}

/// Uses Firebase Authentication as the source of truth for the initial route.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.authStateChanges});

  final Stream<User?>? authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authStateChanges ?? FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC400)),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Unable to check your session. Please restart the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        return snapshot.data == null
            ? const OnboardingScreen()
            : const HomeScreen();
      },
    );
  }
}
