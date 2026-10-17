import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/branches.dart';
import '../domain/qualification_taxonomy.dart';
import '../domain/urgency.dart';
import '../models/user_profile.dart';
import '../providers/account_providers.dart';
import '../services/fx.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';

/// Opens the profile form as a near-full-height sheet. Returns true when saved.
/// Never a trap: it can always be dismissed, and the dashboard offers it again.
Future<bool> showProfileSetupSheet(BuildContext context,
    {UserProfileData? initial, String? suggestedName}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: ProfileSetupScreen(initial: initial, suggestedName: suggestedName),
    ),
  );
  return saved ?? false;
}

/// Collects exactly what the eligibility engine needs, and nothing else:
/// date of birth, category, highest qualification, experience, PwBD/ESM.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.initial, this.suggestedName});

  final UserProfileData? initial;
  final String? suggestedName;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  late DateTime? _dob = widget.initial?.dateOfBirth;
  late ReservationCategory? _category = widget.initial?.category;
  // Old profiles (free-text streams) have no valid degree: start the picker empty.
  late String? _degree = widget.initial?.isComplete == true ? widget.initial!.degreeTitle : null;
  late String? _othersTier = widget.initial?.isOthers == true ? widget.initial!.qualificationTier : null;
  late final Set<String> _otherDegrees = {...?widget.initial?.otherDegrees};
  late final _othersText = TextEditingController(text: widget.initial?.customQualificationText ?? '');
  late double _experience = widget.initial?.experienceYears.clamp(0, kMaxExperienceYears).toDouble() ?? 0;
  late bool _pwbd = widget.initial?.isPwbd ?? false;
  late bool _exsm = widget.initial?.isExServiceman ?? false;
  late int _exsmYears = widget.initial?.exServicemanServiceYears ?? 0;
  late String? _branch = widget.initial?.branch;
  late final Set<String> _alsoBranches = {...?widget.initial?.alsoBranches};
  bool _saving = false;
  String? _error;

  bool get _isOthers => _degree == kOthersDegreeCode;

  /// A B.Tech, M.Tech or Diploma among the degrees picked: ask for the branch.
  bool get _hasBranchDegree => {if (_degree != null) _degree!, ..._otherDegrees}.any(kEngineeringDegrees.contains);

  void _pickBranch(Branch? b) => setState(() {
        _branch = b?.key;
        _alsoBranches
          ..clear()
          ..addAll([for (final o in b?.usuallyAlso ?? const <Branch>{}) o.key]);
      });

  @override
  void dispose() {
    _othersText.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(today.year - 24, 1, 1),
      firstDate: DateTime(today.year - kMaxApplicantAge - 1),
      lastDate: DateTime(today.year - kMinApplicantAge, today.month, today.day),
      initialDatePickerMode: DatePickerMode.year, // jump straight to the birth year
      helpText: 'Date of birth',
      fieldHintText: 'dd/mm/yyyy',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  /// First problem only: one thing to fix at a time.
  String? _validate() {
    final dobError = validateDob(_dob, DateTime.now());
    if (dobError != null) return dobError;
    if (_category == null) return 'Choose your reservation category.';
    if (_degree == null) return 'Pick your highest qualification.';
    if (_isOthers) {
      if (_othersText.text.trim().length < 2) return 'Type your qualification, e.g. B.Des.';
      if (_othersTier == null) return 'Choose which level your qualification is.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // Your level is the highest among all the degrees you hold.
    final others = {..._otherDegrees}..remove(_degree);
    var tier = _isOthers ? _othersTier! : degreeByCode(_degree)!.level;
    for (final code in others) {
      final level = degreeByCode(code)?.level;
      if (level != null && (levelByCode(level)?.rank ?? 0) > (levelByCode(tier)?.rank ?? 0)) tier = level;
    }
    try {
      await ref.read(profileProvider.notifier).save(UserProfileData(
            displayName: widget.initial?.displayName ?? widget.suggestedName ?? 'Me',
            dateOfBirth: _dob!,
            category: _category!,
            qualificationTier: tier,
            degreeTitle: _degree!,
            customQualificationText: _isOthers ? _othersText.text.trim() : null,
            otherDegrees: [for (final d in kDegrees) if (others.contains(d.code)) d.code],
            experienceYears: _experience,
            isPwbd: _pwbd,
            isExServiceman: _exsm,
            exServicemanServiceYears: _exsm ? _exsmYears : 0,
            branch: _hasBranchDegree ? _branch : null,
            alsoBranches: [
              if (_hasBranchDegree && _branch != null)
                for (final b in Branch.values)
                  if (_alsoBranches.contains(b.key) && b.key != _branch) b.key,
            ],
          ));
      Fx.done();
      if (!mounted) return;
      // Capture before popping: this sheet's context is gone once it closes.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved. Finding jobs that fit you…')));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save right now. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.urgencyColors;
    final today = DateTime.now();
    final dob = _dob;
    final dobError = dob == null ? null : validateDob(dob, today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About you', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Used only to work out which jobs you can apply for and how many seats you can reach. '
                'You can change it any time.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _Section(
                title: 'Date of birth',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDob,
                      icon: const DuoIcon(AppIcon.birthday, size: 18),
                      label: Text(dob == null ? 'Pick your date of birth' : _formatDob(dob)),
                    ),
                    if (dob != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dobError ??
                            'You are ${ageOn(dob, today)} today. Each job checks your age on its own cut-off date.',
                        style: text.bodySmall?.copyWith(color: dobError == null ? null : colors.warning),
                      ),
                    ],
                  ],
                ),
              ),
              _Section(
                title: 'Reservation category',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in ReservationCategory.values)
                      ChoiceChip(
                        label: Text(c.wire),
                        tooltip: c.label,
                        selected: _category == c,
                        showCheckmark: false,
                        selectedColor: colors.info.withValues(alpha: 0.22),
                        onSelected: (_) => setState(() => _category = c),
                      ),
                  ],
                ),
              ),
              _Section(
                title: 'Highest qualification',
                subtitle: 'The highest one you hold, or will hold by the cut-off date. '
                    '“Any graduate” jobs match every degree.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DegreePicker(value: _degree, onChanged: (code) => setState(() => _degree = code)),
                    Fold(
                      child: _isOthers
                          ? _OthersFields(
                              controller: _othersText,
                              tier: _othersTier,
                              onTier: (t) => setState(() => _othersTier = t),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Other degrees you hold',
                subtitle: 'Optional. A B.Ed with your B.Sc, an LL.B after a B.A.: jobs that ask for any of '
                    'them will show up too.',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in kDegrees)
                      if (d.level != 'MATRIC' && d.level != 'INTERMEDIATE' && d.code != _degree)
                        FilterChip(
                          label: Text(d.label),
                          selected: _otherDegrees.contains(d.code),
                          onSelected: (on) => setState(() => on ? _otherDegrees.add(d.code) : _otherDegrees.remove(d.code)),
                        ),
                  ],
                ),
              ),
              Fold(
                child: _hasBranchDegree
                    ? _Section(
                        title: 'Your engineering branch',
                        subtitle: 'Jobs that name only other branches are hidden (you can still see them under '
                            'Hidden jobs). Jobs for any branch stay, and ones that don’t say get a “Check branch” tag.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('Don’t filter'),
                                  selected: _branch == null,
                                  showCheckmark: false,
                                  selectedColor: colors.info.withValues(alpha: 0.22),
                                  onSelected: (_) => _pickBranch(null),
                                ),
                                for (final b in Branch.values)
                                  ChoiceChip(
                                    label: Text(b.label),
                                    selected: _branch == b.key,
                                    showCheckmark: false,
                                    selectedColor: colors.info.withValues(alpha: 0.22),
                                    onSelected: (_) => _pickBranch(b),
                                  ),
                              ],
                            ),
                            if (_branch != null) ...[
                              const SizedBox(height: 16),
                              Text('Also show jobs for', style: text.titleSmall),
                              const SizedBox(height: 4),
                              Text('Branches you can usually apply for too.', style: text.bodySmall),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final b in Branch.values)
                                    if (b.key != _branch)
                                      FilterChip(
                                        label: Text(b.label),
                                        selected: _alsoBranches.contains(b.key),
                                        onSelected: (on) => setState(
                                            () => on ? _alsoBranches.add(b.key) : _alsoBranches.remove(b.key)),
                                      ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      )
                    : null,
              ),
              _Section(
                title: 'Work experience',
                subtitle: 'Full-time work after your qualification. Leave at Fresher if none.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(experienceLabel(_experience), style: text.titleMedium?.copyWith(color: colors.info)),
                    Slider(
                      value: _experience,
                      max: kMaxExperienceYears,
                      divisions: (kMaxExperienceYears * 2).toInt(), // half-year steps
                      label: experienceLabel(_experience),
                      semanticFormatterCallback: experienceLabel,
                      onChanged: (v) => setState(() => _experience = v),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Also applies to me',
                child: Column(
                  children: [
                    CheckboxListTile(
                      value: _pwbd,
                      onChanged: (v) => setState(() => _pwbd = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Person with Benchmark Disability (PwBD, 40% or more)'),
                    ),
                    CheckboxListTile(
                      value: _exsm,
                      onChanged: (v) => setState(() => _exsm = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Ex-Serviceman'),
                    ),
                    if (_exsm)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Row(
                          children: [
                            Expanded(child: Text('Years of military service', style: text.bodyMedium)),
                            IconButton(
                              tooltip: 'Fewer years',
                              onPressed: _exsmYears > 0 ? () => setState(() => _exsmYears--) : null,
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            SizedBox(
                              width: 32,
                              child:
                                  Text('$_exsmYears', textAlign: TextAlign.center, style: text.titleMedium),
                            ),
                            IconButton(
                              tooltip: 'More years',
                              onPressed: _exsmYears < 40 ? () => setState(() => _exsmYears++) : null,
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppPalette.surface,
            border: Border(top: BorderSide(color: AppPalette.outline)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: text.bodyMedium?.copyWith(color: colors.urgent)),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save and show my jobs'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// "Mon 14 Jun 1998"
  static String _formatDob(DateTime d) =>
      '${formatDue(DateTime(d.year, d.month, d.day, 12)).split(',').first} ${d.year}';
}

/// One dropdown, degrees grouped under muted headings, "Others" last.
class _DegreePicker extends StatelessWidget {
  const _DegreePicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final items = <DropdownMenuItem<String>>[];
    String? group;
    for (final d in kDegrees) {
      if (d.group != group) {
        group = d.group;
        items.add(DropdownMenuItem<String>(
          enabled: false,
          value: '__group_$group',
          child: Text(group.toUpperCase(), style: text.labelSmall?.copyWith(color: AppPalette.textMuted)),
        ));
      }
      items.add(DropdownMenuItem(value: d.code, child: Text(d.label)));
    }
    items
      ..add(DropdownMenuItem<String>(
        enabled: false,
        value: '__group_others',
        child: Text('NOT LISTED', style: text.labelSmall?.copyWith(color: AppPalette.textMuted)),
      ))
      ..add(const DropdownMenuItem(value: kOthersDegreeCode, child: Text('Others…')));

    return InputDecorator(
      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: const Text('Choose your degree'),
          dropdownColor: AppPalette.surfaceVariant,
          menuMaxHeight: 420,
          // Show just the degree once chosen, not the group heading styling.
          selectedItemBuilder: (_) => [
            for (final item in items)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.value == kOthersDegreeCode ? 'Others' : (degreeByCode(item.value)?.label ?? ''),
                ),
              ),
          ],
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Revealed when "Others" is picked: the degree name and its level.
class _OthersFields extends StatelessWidget {
  const _OthersFields({required this.controller, required this.tier, required this.onTier});

  final TextEditingController controller;
  final String? tier;
  final ValueChanged<String> onTier;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = context.urgencyColors.info;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Your qualification',
              hintText: 'e.g., B.Des, BVSc, BAMS, CA',
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We search each notification for this text. Separate alternatives with “/”, e.g. CA/CMA.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 14),
          Text('Which level is it?', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final level in kQualificationLevels)
                ChoiceChip(
                  label: Text(level.label),
                  selected: tier == level.code,
                  showCheckmark: false,
                  selectedColor: info.withValues(alpha: 0.22),
                  onSelected: (_) => onTier(level.code),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: text.titleMedium)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: text.bodySmall),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
