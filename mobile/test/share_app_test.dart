import 'package:exam_tracker/widgets/share_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return ShareResult.unavailable;
  }
}

void main() {
  testWidgets('the share button opens the share sheet with a note and the download link', (tester) async {
    final fake = _FakeShare();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ShareAppButton(share: SharePlus.custom(fake)))));
    await tester.tap(find.text('Share JobSummit with friends'));
    expect(fake.shared, hasLength(1));
    expect(fake.shared.single.text, contains('JobSummit'));
    expect(fake.shared.single.text, endsWith(kShareLink));
  });
}
