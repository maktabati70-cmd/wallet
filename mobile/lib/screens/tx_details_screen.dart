import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/money.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TxDetailsScreen extends StatelessWidget {
  const TxDetailsScreen({super.key, required this.tx});
  final TxItem tx;

  @override
  Widget build(BuildContext context) {
    final color = tx.incoming ? AppColors.incoming : AppColors.outgoing;
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction details')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: Column(children: [
              Icon(tx.incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
                  color: color, size: 36),
              const SizedBox(height: 8),
              Text('${tx.incoming ? '+' : '−'}${Usdt.format(tx.amountMicro)} USDT',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 8),
              StatusChip(tx.status),
            ]),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InfoRow('Type', tx.incoming ? 'Received' : 'Sent'),
                InfoRow('Date', formatDateTime(tx.time)),
                const Divider(),
                _Field(label: 'From', value: tx.from),
                _Field(label: 'To', value: tx.to),
                _Field(label: 'Transaction ID (TXID)', value: tx.txid),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(tx.explorerUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('View on TRONSCAN'),
          ),
        ]),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 4),
            SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () => copyToClipboard(context, value, label),
        ),
      ]),
    );
  }
}
