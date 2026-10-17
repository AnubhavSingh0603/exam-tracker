import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/qualification_taxonomy.dart';
import '../../models/user_profile.dart';
import '../../providers/account_providers.dart';
import '../../providers/providers.dart';
import '../../utils/system_actions.dart';
import 'linkedin_import.dart';
import 'models.dart';
import 'providers.dart';

/// The private profile: skills, experience, roles and cities pick the roles shown.
/// Kept apart from the Govt profile.
class PrivateProfileScreen extends ConsumerStatefulWidget {
  const PrivateProfileScreen({super.key});

  @override
  ConsumerState<PrivateProfileScreen> createState() => _PrivateProfileScreenState();
}

class _PrivateProfileScreenState extends ConsumerState<PrivateProfileScreen> {
  PrivateProfile? _p;
  final _headline = TextEditingController();
  final _role = TextEditingController();

  @override
  void dispose() {
    _headline.dispose();
    _role.dispose();
    super.dispose();
  }

  PrivateProfile get p => _p!;
  void _set(PrivateProfile next) => setState(() => _p = next);

  List<String> _toggle(List<String> list, String v) => list.contains(v) ? ([...list]..remove(v)) : [...list, v];

  Future<void> _save() async {
    await ref.read(privateProfileProvider.notifier).save(p.copyWith(headline: _headline.text.trim()));
    if (mounted) {
      Navigator.of(context).pop();
      showCalmSnack(context, 'Private profile saved.');
    }
  }

  void _addRole() {
    final role = _role.text.trim();
    if (role.isEmpty || p.targetRoles.contains(role)) return;
    _set(p.copyWith(targetRoles: [...p.targetRoles, role]));
    _role.clear();
  }

  Future<void> _pickResume() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx']);
    final file = picked?.files.single;
    if (file?.path == null) return;
    final dir = await getApplicationSupportDirectory();
    final copy = await File(file!.path!).copy(paths.join(dir.path, 'resume${paths.extension(file.name)}'));
    _set(p.copyWith(resumePath: copy.path, resumeName: file.name));
  }

  Future<void> _importLinkedIn() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: true);
    final bytes = picked?.files.single.bytes ??
        (picked?.files.single.path == null ? null : await File(picked!.files.single.path!).readAsBytes());
    if (bytes == null || !mounted) return;
    final LinkedInData data;
    try {
      data = readLinkedInExport(bytes);
    } on FormatException catch (e) {
      showCalmSnack(context, e.message);
      return;
    }
    final applied = await showModalBottomSheet<PrivateProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LinkedInReview(data: data, current: p.copyWith(headline: _headline.text.trim())),
    );
    if (applied == null) return;
    _headline.text = applied.headline;
    _set(applied);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(privateProfileProvider).dataOrNull;
    if (_p == null && loaded != null) {
      _p = loaded;
      _headline.text = loaded.headline;
    }
    final text = Theme.of(context).textTheme;
    if (_p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final skills = [...p.skills, ...kPrivateSkills.where((s) => !p.skills.contains(s))];

    Widget section(String title, String? note, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              if (note != null) ...[const SizedBox(height: 2), Text(note, style: text.bodySmall)],
              const SizedBox(height: 10),
              child,
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Private profile'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          OutlinedButton.icon(
            onPressed: _importLinkedIn,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(p.linkedinImportedAt == null ? 'Fill in from LinkedIn' : 'Fill in from LinkedIn again'),
          ),
          const SizedBox(height: 4),
          Text(
            'In LinkedIn: Settings › Data privacy › Get a copy of your data. Pick the ZIP it emails you. '
            'It’s read on this phone only.',
            style: text.bodySmall,
          ),
          section(
            'Headline',
            null,
            TextField(controller: _headline, decoration: const InputDecoration(hintText: 'e.g. Backend developer, 2 yrs')),
          ),
          section(
            'Experience: ${p.experienceYears == 0 ? 'fresher' : '${p.experienceYears} years'}',
            'Roles asking for more than a year beyond this are hidden.',
            Slider(
              value: p.experienceYears.clamp(0, 20),
              max: 20,
              divisions: 40,
              label: '${p.experienceYears}',
              onChanged: (v) => _set(p.copyWith(experienceYears: v)),
            ),
          ),
          section(
            'Roles you want',
            'A role matches titles with all its words: “Backend Engineer”, “Data Analyst”.',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in p.targetRoles)
                      InputChip(label: Text(r), onDeleted: () => _set(p.copyWith(targetRoles: _toggle(p.targetRoles, r)))),
                  ],
                ),
                TextField(
                  controller: _role,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addRole(),
                  decoration: InputDecoration(
                    hintText: 'Add a role',
                    suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _addRole),
                  ),
                ),
              ],
            ),
          ),
          section(
            'Skills',
            'Roles that name none of your skills or roles are hidden.',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in skills)
                  FilterChip(
                    label: Text(s),
                    selected: p.skills.contains(s),
                    onSelected: (_) => _set(p.copyWith(skills: _toggle(p.skills, s))),
                  ),
              ],
            ),
          ),
          section(
            'Cities',
            'None picked: anywhere in India.',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in [...kPrivateCities.keys, 'Remote'])
                  FilterChip(
                    label: Text(c),
                    selected: p.cities.contains(c),
                    onSelected: (_) => _set(p.copyWith(cities: _toggle(p.cities, c))),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show internships'),
            value: p.includeInternships,
            onChanged: (v) => _set(p.copyWith(includeInternships: v)),
          ),
          section(
            'Resume',
            'Kept in the app’s own files, ready to share when you apply.',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (p.resumePath != null && File(p.resumePath!).existsSync()) ...[
                  Text(p.resumeName ?? 'Resume', style: text.bodyMedium),
                  OutlinedButton(
                    onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(p.resumePath!)])),
                    child: const Text('Share'),
                  ),
                ],
                TextButton(
                  onPressed: _pickResume,
                  child: Text(p.resumePath == null ? 'Add your resume' : 'Replace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the LinkedIn export found, and where to use it. Nothing changes until "Use".
class _LinkedInReview extends ConsumerStatefulWidget {
  const _LinkedInReview({required this.data, required this.current});

  final LinkedInData data;
  final PrivateProfile current;

  @override
  ConsumerState<_LinkedInReview> createState() => _LinkedInReviewState();
}

class _LinkedInReviewState extends ConsumerState<_LinkedInReview> {
  bool _private = true;
  bool _govtDegrees = true;
  bool _govtExperience = false; // Govt posts usually want specific experience

  LinkedInData get d => widget.data;

  Future<void> _use() async {
    final now = DateTime.now();
    final years = d.yearsOfExperience(now);
    var next = widget.current;
    if (_private) {
      final known = {for (final s in kPrivateSkills) s.toLowerCase(): s};
      final skills = {
        ...next.skills,
        for (final s in d.skills)
          if (known[s.toLowerCase()] case final k?) k,
      }.toList();
      next = next.copyWith(
        headline: d.headline.isNotEmpty ? d.headline : next.headline,
        skills: skills,
        experienceYears: years,
        targetRoles: next.targetRoles.isEmpty && d.latestTitle != null ? [d.latestTitle!] : next.targetRoles,
        linkedinImportedAt: now,
      );
    }
    final govt = ref.read(profileProvider).dataOrNull;
    final codes = d.degreeCodes();
    if (govt != null && ((_govtDegrees && codes.isNotEmpty) || _govtExperience)) {
      final others = {...govt.otherDegrees, if (_govtDegrees) ...codes}..remove(govt.degreeTitle);
      var tier = govt.qualificationTier;
      for (final c in others) {
        final level = degreeByCode(c)?.level;
        if (level != null && (levelByCode(level)?.rank ?? 0) > (levelByCode(tier)?.rank ?? 0)) tier = level;
      }
      await ref.read(profileProvider.notifier).save(UserProfileData(
            displayName: govt.displayName,
            dateOfBirth: govt.dateOfBirth,
            category: govt.category,
            qualificationTier: tier,
            degreeTitle: govt.degreeTitle,
            customQualificationText: govt.customQualificationText,
            otherDegrees: [for (final o in kDegrees) if (others.contains(o.code)) o.code],
            experienceYears: _govtExperience ? years : govt.experienceYears,
            isPwbd: govt.isPwbd,
            isExServiceman: govt.isExServiceman,
            exServicemanServiceYears: govt.exServicemanServiceYears,
            subjects: govt.subjects,
          ));
    }
    if (mounted) Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final years = d.yearsOfExperience(DateTime.now());
    final codes = d.degreeCodes();
    final hasGovt = ref.watch(profileProvider).dataOrNull != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Found in your LinkedIn export', style: text.titleLarge),
            const SizedBox(height: 12),
            if (d.headline.isNotEmpty) Text('“${d.headline}”', style: text.bodyMedium),
            const SizedBox(height: 8),
            Text('Degrees: ${d.education.isEmpty ? 'none listed' : d.education.map((e) => e.degree.isEmpty ? e.school : e.degree).join(', ')}',
                style: text.bodyMedium),
            Text('Experience: ${years == 0 ? 'none listed' : '$years years'} '
                '(${d.positions.length} ${d.positions.length == 1 ? 'job' : 'jobs'})', style: text.bodyMedium),
            Text('Skills: ${d.skills.isEmpty ? 'none listed' : '${d.skills.length}'}', style: text.bodyMedium),
            const Divider(height: 28),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _private,
              onChanged: (v) => setState(() => _private = v!),
              title: const Text('Use for my Private profile'),
              subtitle: const Text('Headline, skills, experience and your latest role.'),
            ),
            if (hasGovt) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _govtDegrees && codes.isNotEmpty,
                onChanged: codes.isEmpty ? null : (v) => setState(() => _govtDegrees = v!),
                title: const Text('Add these degrees to my Govt profile'),
                subtitle: Text(codes.isEmpty
                    ? 'None we recognise.'
                    : '${codes.map((c) => degreeByCode(c)?.label ?? c).join(', ')}. Only adds; nothing is removed.'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _govtExperience,
                onChanged: (v) => setState(() => _govtExperience = v!),
                title: Text('Use $years years as my Govt experience'),
                subtitle: const Text('Govt posts often want specific experience; check before ticking.'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _use, child: const Text('Use these')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
