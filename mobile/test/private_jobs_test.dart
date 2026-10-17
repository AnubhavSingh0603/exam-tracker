import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:exam_tracker/features/private_jobs/data.dart';
import 'package:exam_tracker/features/private_jobs/linkedin_import.dart';
import 'package:exam_tracker/features/private_jobs/matching.dart';
import 'package:exam_tracker/features/private_jobs/models.dart';
import 'package:exam_tracker/providers/workspace_providers.dart';
import 'package:exam_tracker/widgets/workspace_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<int> zipOf(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: body) in files.entries) {
    final bytes = utf8.encode(body);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  final now = DateTime(2026, 10, 17);

  group('LinkedIn export', () {
    final export = zipOf({
      'Basic_LinkedInDataExport_10-17-2026/Profile.csv':
          '﻿First Name,Last Name,Headline,Summary\nAsha,K,"Data analyst | SQL, Python",Hi\n',
      'Basic_LinkedInDataExport_10-17-2026/Education.csv': 'School Name,Start Date,End Date,Notes,Degree Name,Activities\n'
          'Delhi University,2018,2021,,Bachelor of Science - BSc,\n'
          'IGNOU,Jan 2022,Dec 2023,,"Bachelor of Education, B.Ed",\n',
      'Basic_LinkedInDataExport_10-17-2026/Positions.csv':
          'Company Name,Title,Description,Location,Started On,Finished On\n'
              'ABC School,Teacher,"Taught maths,\nran the ""quiz"" club",Delhi,Jan 2024,Dec 2024\n'
              'XYZ Ltd,Data Analyst,Dashboards,Gurugram,Jun 2024,\n',
      'Basic_LinkedInDataExport_10-17-2026/Skills.csv': 'Notes:\n"Exported skills"\n\nName\nSQL\nPython\nPublic Speaking\n',
    });

    test('reads headline, degrees, jobs and skills', () {
      final d = readLinkedInExport(export);
      expect(d.headline, 'Data analyst | SQL, Python');
      expect(d.degreeCodes(), ['B_SC', 'B_ED']);
      expect(d.positions.first.title, 'Teacher');
      expect(d.positions.last.end, isNull); // current job
      expect(d.skills, ['SQL', 'Python', 'Public Speaking']);
      expect(d.latestTitle, 'Data Analyst');
    });

    test('overlapping jobs count once; a current job runs to today', () {
      // Jan 2024 – Oct 2026 without double-counting Jun–Dec 2024: 33 months.
      expect(readLinkedInExport(export).monthsOfExperience(now), 33);
      expect(readLinkedInExport(export).yearsOfExperience(now), 2.5);
    });

    test('degree names as people write them', () {
      expect(degreeCodeFor('B.Tech - Computer Science'), 'B_TECH');
      expect(degreeCodeFor('Bachelor of Engineering - BE'), 'B_TECH');
      expect(degreeCodeFor('Master of Business Administration - MBA'), 'MBA');
      expect(degreeCodeFor('LLB'), 'LLB');
      expect(degreeCodeFor('Higher Secondary (12th)'), 'CLASS_12');
      expect(degreeCodeFor('Certificate in Yoga'), isNull);
    });

    test('wrong files are explained, not crashed on', () {
      expect(() => readLinkedInExport(utf8.encode('not a zip')), throwsA(isA<FormatException>()));
      expect(() => readLinkedInExport(zipOf({'photo.txt': 'x'})), throwsA(isA<FormatException>()));
    });
  });

  group('matching', () {
    PrivateJob job(String title,
            {int? min, List<String> skills = const [], List<String> at = const ['Bengaluru, India'], bool remote = false, String type = 'full_time'}) =>
        PrivateJob(
          id: title,
          company: 'Co',
          title: title,
          applyUrl: 'https://x',
          experienceMin: min,
          experienceFrom: min == null ? null : 'text',
          skills: skills,
          locations: at,
          remote: remote,
          employmentType: type,
          postedAt: now.subtract(const Duration(days: 2)),
        );
    const me = PrivateProfile(skills: ['sql', 'python'], targetRoles: ['Data Analyst'], experienceYears: 1, cities: ['Delhi NCR']);

    test('experience: one year of stretch, no more', () {
      expect(matchPrivateJob(job('Data Analyst', min: 2, at: ['Gurugram']), me, now).hiddenBecause, isNull);
      expect(matchPrivateJob(job('Data Analyst', min: 4, at: ['Gurugram']), me, now).hiddenBecause, 'Needs 4+ years');
    });

    test('cities: aliases, remote and India-wide roles fit', () {
      expect(inYourCities(job('x', at: ['Gurugram, Haryana']), ['Delhi NCR']), isTrue);
      expect(inYourCities(job('x', at: ['Bengaluru']), ['Delhi NCR']), isFalse);
      expect(inYourCities(job('x', at: ['India']), ['Delhi NCR']), isTrue);
      expect(inYourCities(job('x', at: ['Bengaluru'], remote: true), ['Delhi NCR']), isTrue);
    });

    test('field: your skills or roles, else hidden; internships only if wanted', () {
      expect(matchPrivateJob(job('Sales Manager', skills: ['sales'], at: ['Noida']), me, now).hiddenBecause, 'Not your field');
      expect(matchPrivateJob(job('Analyst Intern', skills: ['sql'], at: ['Noida'], type: 'internship'), me, now).hiddenBecause,
          'Internship');
    });

    test('best fit first', () {
      final r = rankPrivateJobs([
        job('Backend Engineer', skills: ['python'], at: ['Noida']),
        job('Senior Data Analyst', min: 1, skills: ['sql', 'python'], at: ['Gurugram']),
      ], me, now);
      expect(r.shown.first.job.title, 'Senior Data Analyst');
      expect(r.shown.first.sharedSkills, ['sql', 'python']);
    });

    test('LinkedIn search link carries role, city and level', () {
      final uri = linkedInSearch(me);
      expect(uri.host, 'www.linkedin.com');
      expect(uri.queryParameters['keywords'], 'Data Analyst');
      expect(uri.queryParameters['location'], 'Delhi, India');
      expect(uri.queryParameters['f_E'], '2,3');
    });
  });

  group('stores', () {
    setUpAll(sqfliteFfiInit);
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('applications live in their own database', () async {
      final store = await PrivateApplicationsStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final at = DateTime.utc(2026, 10, 17);
      final app = PrivateApplication(
          id: 'p1', company: 'Groww', title: 'Analyst', stage: PrivateStage.applied, createdAt: at, updatedAt: at);
      await store.save(app);
      await store.save(app.copyWith(stage: PrivateStage.interview));
      expect((await store.list()).single.stage, PrivateStage.interview);
      await store.close();
    });

    test('the private profile is saved under its own encrypted key', () async {
      final store = PrivateProfileStore();
      await store.write(const PrivateProfile(skills: ['sql'], experienceYears: 2));
      expect((await store.read()).skills, ['sql']);
      expect(await const FlutterSecureStorage().containsKey(key: 'profile.cache'), isFalse); // Govt untouched
    });

    test('roles load fresh, and from the last copy when offline', () async {
      final dir = await Directory.systemTemp.createTemp('pj');
      addTearDown(() => dir.delete(recursive: true));
      final body = jsonEncode({
        'generated_at': '2026-10-17T06:00:00Z',
        'jobs': [
          {'id': 'greenhouse:groww:1', 'company': 'Groww', 'title': 'Analyst', 'apply_url': 'https://x', 'experience_min': 2, 'experience_max': 4, 'experience_from': 'text'},
        ],
      });
      var online = true;
      final repo = PrivateJobsRepository(
        MockClient((_) async => online ? http.Response(body, 200) : throw const SocketException('offline')),
        dir: () async => dir,
        bases: ['https://jobsummit.github.io/JobSummit'],
      );
      final fresh = await repo.load();
      expect(fresh.fresh, isTrue);
      expect(fresh.jobs.single.experienceLabel, '2–4 yrs');
      online = false;
      final cached = await repo.load();
      expect(cached.fresh, isFalse);
      expect(cached.jobs.single.company, 'Groww');
    });
  });

  group('workspace switch', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('off by default; on, it remembers where you were; off again, back to Govt', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(workspaceProvider).shown, Workspace.govt);
      final ws = c.read(workspaceProvider.notifier);
      await ws.setPrivateEnabled(true);
      await ws.switchTo(Workspace.private);
      expect(c.read(workspaceProvider).shown, Workspace.private);
      await ws.setPrivateEnabled(false);
      expect(c.read(workspaceProvider).shown, Workspace.govt);
    });

    testWidgets('the switch is invisible until Private jobs is turned on', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: WorkspaceSwitch())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Private'), findsNothing);
      await c.read(workspaceProvider.notifier).setPrivateEnabled(true);
      await tester.pumpAndSettle();
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Govt'), findsOneWidget);
    });
  });
}
