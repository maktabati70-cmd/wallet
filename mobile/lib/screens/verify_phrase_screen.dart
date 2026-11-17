import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'set_pin_screen.dart';

/// Confirms the user really wrote the phrase down by asking for 3 random words.
class VerifyPhraseScreen extends StatefulWidget {
  const VerifyPhraseScreen({super.key, required this.mnemonic});
  final String mnemonic;

  @override
  State<VerifyPhraseScreen> createState() => _VerifyPhraseScreenState();
}

class _VerifyPhraseScreenState extends State<VerifyPhraseScreen> {
  final _rng = Random.secure();
  late final List<String> _words = widget.mnemonic.split(' ');
  late final List<int> _positions;
  late final Map<int, List<String>> _options;
  final Map<int, String> _picked = {};
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    final idx = List<int>.generate(_words.length, (i) => i)..shuffle(_rng);
    _positions = idx.take(3).toList()..sort();
    _options = {
      for (final p in _positions) p: _choicesFor(p),
    };
  }

  List<String> _choicesFor(int position) {
    final others = _words.where((w) => w != _words[position]).toSet().toList()..shuffle(_rng);
    return ([_words[position], ...others.take(3)])..shuffle(_rng);
  }

  void _continue() {
    final ok = _positions.every((p) => _picked[p] == _words[p]);
    if (!ok) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SetPinScreen(mnemonic: widget.mnemonic),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final complete = _picked.length == _positions.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your phrase')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Select the correct word for each position.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          for (final p in _positions) ...[
            Text('Word #${p + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final w in _options[p]!)
                ChoiceChip(
                  label: Text(w),
                  selected: _picked[p] == w,
                  onSelected: (_) => setState(() {
                    _picked[p] = w;
                    _showError = false;
                  }),
                ),
            ]),
            const SizedBox(height: 20),
          ],
          if (_showError)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('One or more words are wrong. Check your written copy.',
                  style: TextStyle(color: AppColors.danger)),
            ),
          FilledButton(onPressed: complete ? _continue : null, child: const Text('Continue')),
        ]),
      ),
    );
  }
}
