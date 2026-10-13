import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

/// Phone notifications for exam-watcher findings. Works in the background
/// isolate too (WorkManager), so no server push is needed.
abstract final class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationChannel(
    'exam_updates',
    'Exam updates',
    description: 'Admit cards, exam dates, answer keys and results for exams you track',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  /// A notification tapped while the app was closed: open its link once the app is up.
  static Future<void> openLaunchLink() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) await _open(details!.notificationResponse?.payload);
  }

  /// [key] keeps one notification per exam + milestone (a newer one replaces it).
  static Future<void> show({required String key, required String title, required String body, String? url}) async {
    await init();
    await _plugin.show(
      key.hashCode & 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: url,
    );
  }

  static Future<void> _open(String? url) async {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri != null && uri.hasScheme) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
