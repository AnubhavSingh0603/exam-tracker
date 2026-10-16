import 'package:exam_tracker/services/auth_service.dart';
import 'package:exam_tracker/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asks Google for the picture at the size shown', () {
    expect(AccountPhoto.sized('https://lh3.googleusercontent.com/a/abc=s96-c', 144),
        'https://lh3.googleusercontent.com/a/abc=s144-c');
    expect(AccountPhoto.sized('https://lh3.googleusercontent.com/a/abc=s96', 144),
        'https://lh3.googleusercontent.com/a/abc=s144-c');
    expect(AccountPhoto.sized('https://example.com/me.png', 144), 'https://example.com/me.png');
  });

  testWidgets('without a picture the first letter of the name shows', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AccountPhoto(GoogleUser(email: 'asha@gmail.com', name: 'asha k')))));
    expect(find.text('A'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isNull);
  });

  testWidgets('with a picture it is loaded over the letter', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AccountPhoto(GoogleUser(
                email: 'asha@gmail.com', name: 'Asha', photoUrl: 'https://lh3.googleusercontent.com/a/x=s96-c')))));
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isA<NetworkImage>());
    expect(find.text('A'), findsOneWidget); // stays underneath while loading / offline
  });
}
