import 'package:flutter/material.dart';

import '../core/wallet_crypto.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'set_pin_screen.dart';

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final phrase = WalletCrypto.normalize(_controller.text);
    if (!WalletCrypto.isValidMnemonic(phrase)) {
      setState(() => _error = 'This is not a valid 12 or 24-word recovery phrase.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SetPinScreen(mnemonic: phrase),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import wallet')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Enter your 12 or 24-word recovery phrase, separated by spaces.',
              style: TextStyle(color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false, // incognito keyboard
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(hintText: 'word1 word2 word3 …', errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          const WarningCard(
            text: 'Only enter your phrase inside this app. Never type it into a website, '
                'chat or email — anyone with it can take your funds.',
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _continue, child: const Text('Continue')),
        ]),
      ),
    );
  }
}
