import 'package:exam_tracker/services/fx.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final played = <String>[];
  final haptics = <String>[];

  setUp(() {
    played.clear();
    haptics.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('jobsummit/fx'), (call) async {
      played.add((call.arguments as Map)['name'] as String);
      return true;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
  });

  test('defaults on; each moment plays its sound and buzz', () async {
    SharedPreferences.setMockInitialValues({});
    await Fx.load();
    expect((Fx.sound, Fx.vibration), (true, true));

    Fx.applied();
    Fx.dismiss();
    Fx.error();
    await pumpEventQueue();
    expect(played, ['fx_success', 'fx_swoosh', 'fx_soft_error']);
    expect(haptics, ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.lightImpact']);
  });

  test('the switches silence sounds and buzzes, and are remembered', () async {
    SharedPreferences.setMockInitialValues({});
    await Fx.load();
    await Fx.setSound(false);
    await Fx.setVibration(false);
    played.clear();
    haptics.clear();

    Fx.applied();
    Fx.levelUp();
    await pumpEventQueue();
    expect(played, isEmpty);
    expect(haptics, isEmpty);

    Fx.sound = true;
    Fx.vibration = true;
    await Fx.load();
    expect((Fx.sound, Fx.vibration), (false, false));
  });

  test('a phone without the channel (tests, old builds) does not throw', () async {
    SharedPreferences.setMockInitialValues({});
    await Fx.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jobsummit/fx'), null);
    Fx.xp();
    await pumpEventQueue();
  });
}
