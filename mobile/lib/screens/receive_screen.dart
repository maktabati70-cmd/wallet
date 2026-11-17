import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key, required this.network});
  final String network;

  @override
  Widget build(BuildContext context) {
    final address = WalletSession.instance.address ?? '';
    final netLabel = network == 'mainnet' ? 'TRON' : 'TRON ${network.toUpperCase()} testnet';
    return Scaffold(
      appBar: AppBar(title: const Text('Receive USDT')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TestnetBanner(network: network),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                QrImageView(
                  data: address,
                  size: 220,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'Wallet address QR code',
                ),
                const SizedBox(height: 16),
                AddressText(address),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => copyToClipboard(context, address, 'Address'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy address'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          WarningCard(
            text: 'Send only USDT (TRC20) or TRX on the $netLabel network to this address. '
                'Keep some TRX here to pay network fees. Other tokens or networks '
                '(e.g. ERC20, BEP20) may be lost permanently.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Incoming transfers appear after they are confirmed on the blockchain.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ]),
      ),
    );
  }
}
