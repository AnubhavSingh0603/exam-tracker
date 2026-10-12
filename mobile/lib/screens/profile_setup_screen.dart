import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/urgency.dart';
import '../models/user_profile.dart';
import '../providers/account_providers.dart';
import '../theme/app_theme.dart';

/// Opens the profile form as a near-full-height sheet. Returns true when saved.
/// Never a trap: it can always be dismissed, and the dashboard offers it again.
Future<bool> showProfileSetupSheet(BuildContext context, {UserProfileData? initial, String? suggestedName}) async {
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

/// Collects exactly what the eligibility engine needs, and nothing else.
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
  late final Set<String> _streams = {...?widget.initial?.streams};
  late bool _pwbd = widget.initial?.isPwbd ?? false;
  late bool _exsm = widget.initial?.isExServiceman ?? false;
  late int _exsmYears = widget.initial?.exServicemanServiceYears ?? 0;
  final _otherStream = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _otherStream.dispose();
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

  void _addOtherStream() {
    final value = _otherStream.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _streams.add(value);
      _otherStream.clear();
    });
  }

  /// First problem only: one thing to fix at a time.
  String? _validate() {
    final dobError = validateDob(_dob, DateTime.now());
    if (dobError != null) return dobError;
    if (_category == null) return 'Choose your reservation category.';
    if (_streams.isEmpty) return 'Pick at least one degree or stream.';
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
    try {
      await ref.read(profileProvider.notifier).save(UserProfileData(
            displayName: widget.initial?.displayName ?? widget.suggestedName ?? 'Me',
            dateOfBirth: _dob!,
            category: _category!,
            streams: _streams.toList(),
            isPwbd: _pwbd,
            isExServiceman: _exsm,
            exServicemanServiceYears: _exsm ? _exsmYears : 0,
          ));
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      // Capture before popping: this sheet's context is gone once it closes.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved. Finding jobs that fit you…')));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save right now. Check your connection and try again.');
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
    final customStreams = _streams.where((s) => !kStreamPresets.contains(s)).toList();

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
                      icon: const Icon(Icons.cake_outlined, size: 18),
                      label: Text(dob == null ? 'Pick your date of birth' : _formatDob(dob)),
                    ),
                    if (dob != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dobError ?? 'You are ${ageOn(dob, today)} today. Each job checks your age on its own cut-off date.',
                        style: text.bodySmall?.copyWith(color: dobError == null ? null : colors.warning),
                      ),
                    ],
                  ],
                ),
              ),
              _Section(
                title: 'Reservation category',
                child: InputDecorator(
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReservationCategory>(
                      value: _category,
                      isExpanded: true,
                      hint: const Text('Choose one'),
                      dropdownColor: AppPalette.surfaceVariant,
                      items: [
                        for (final c in ReservationCategory.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) => setState(() => _category = c),
                    ),
                  ),
                ),
              ),
              _Section(
                title: 'Degrees / streams',
                subtitle: 'Pick every one you hold or will hold by the cut-off date.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in [...kStreamPresets, ...customStreams])
                          FilterChip(
                            label: Text(s),
                            selected: _streams.contains(s),
                            showCheckmark: true,
                            selectedColor: colors.info.withValues(alpha: 0.22),
                            checkmarkColor: colors.info,
                            onSelected: (on) => setState(() => on ? _streams.add(s) : _streams.remove(s)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otherStream,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addOtherStream(),
                            decoration: const InputDecoration(
                              labelText: 'Something else?',
                              hintText: 'e.g. B.Tech Mining',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Add',
                          onPressed: _addOtherStream,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
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
                              child: Text('$_exsmYears', textAlign: TextAlign.center, style: text.titleMedium),
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
          decoration: const BoxDecoration(
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
