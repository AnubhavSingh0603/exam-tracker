import 'package:exam_tracker/config/env.dart';
import 'package:exam_tracker/services/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fields: stars, text with the app and phone under it, email only when given', () {
    final f = ReviewService.fields(stars: 4, text: '  Add MBA jobs ', about: 'JobSummit 0.16.0 · Android 15');
    expect(f[Env.reviewRatingEntry], '4');
    expect(f[Env.reviewTextEntry], 'Add MBA jobs\n\n[JobSummit 0.16.0 · Android 15]');
    expect(f.containsKey(Env.reviewEmailEntry), isFalse);
    expect(ReviewService.fields(stars: 5, text: '', email: ' a@b.in ')[Env.reviewEmailEntry], 'a@b.in');
  });

  test('posts to the form; anything but 200 is an error', () async {
    late http.Request sent;
    await ReviewService(client: MockClient((r) async {
      sent = r;
      return http.Response('ok', 200);
    })).send(stars: 3, text: 'Fine');
    expect(sent.method, 'POST');
    expect(sent.url, ReviewService.endpoint);
    expect(sent.bodyFields[Env.reviewRatingEntry], '3');

    final failing = ReviewService(client: MockClient((_) async => http.Response('closed', 400)));
    expect(failing.send(stars: 1, text: ''), throwsA(isA<http.ClientException>()));
  });
}
