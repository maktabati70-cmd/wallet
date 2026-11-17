import 'package:flutter/material.dart';

import '../core/wallet_crypto.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'verify_phrase_screen.dart';

/// Shows a newly generated recovery phrase. This replaces "account recovery":
/// the phrase is the only way to restore the wallet.
class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  late final String _mnemonic = WalletCrypto.generateMnemonic();
  final List<bool> _acks = [false, false, false];
  bool _revealed = false;

  static const _ackTexts = [
    'If I lose my recovery phrase, I lose access to my funds. No one can recover it for me.',
    'I will never share my recovery phrase. Support staff will never ask for it.',
    'I will write it down on paper and keep it somewhere safe and offline.',
  ];

  @override
  Widget build(BuildContext context) {
    final words = _mnemonic.split(' ');
    final allAcked = _acks.every((a) => a);
    return Scaffold(
      appBar: AppBar(title: const Text('Your recovery phrase')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
            'These 12 words are the master key to your wallet. Write them down in order.',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          if (!_revealed) ...[
            for (var i = 0; i < _ackTexts.length; i++)
              CheckboxListTile(
                value: _acks[i],
                onChanged: (v) => setState(() => _acks[i] = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(_ackTexts[i], style: const TextStyle(fontSize: 14)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: allAcked ? () => setState(() => _revealed = true) : null,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Show recovery phrase'),
            ),
          ] else ...[
            const WarningCard(
              text: 'Make sure no one is watching your screen. Screenshots are blocked for your safety.',
              icon: Icons.privacy_tip_outlined,
            ),
            const SizedBox(height: 16),
            PhraseGrid(words: words),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => VerifyPhraseScreen(mnemonic: _mnemonic),
              )),
              child: const Text('I have written it down'),
            ),
          ],
        ]),
      ),
    );
  }
}

class PhraseGrid extends StatelessWidget {
  const PhraseGrid({super.key, required this.words});
  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.6,
      children: [
        for (var i = 0; i < words.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(children: [
              SizedBox(
                width: 26,
                child: Text('${i + 1}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              Text(words[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
  }
}
