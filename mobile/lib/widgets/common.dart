import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/money.dart';
import '../theme.dart';

class TestnetBanner extends StatelessWidget {
  const TestnetBanner({super.key, this.network = 'nile'});
  final String network;

  @override
  Widget build(BuildContext context) {
    if (network == 'mainnet') return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(children: [
        const Icon(Icons.science_outlined, size: 18, color: AppColors.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'TESTNET (${network.toUpperCase()}) — test tokens only, no real value.',
            style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class WarningCard extends StatelessWidget {
  const WarningCard({super.key, required this.text, this.icon = Icons.warning_amber_rounded});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
      ]),
    );
  }
}

/// Full address in monospace with first/last characters emphasised so users
/// compare the whole address, not just the start.
class AddressText extends StatelessWidget {
  const AddressText(this.address, {super.key, this.fontSize = 15});
  final String address;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: 'monospace', fontSize: fontSize, color: AppColors.ink, height: 1.4);
    const strong = TextStyle(fontWeight: FontWeight.w800, color: AppColors.brandDark);
    if (address.length < 12) return SelectableText(address, style: base);
    return SelectableText.rich(TextSpan(style: base, children: [
      TextSpan(text: address.substring(0, 5), style: strong),
      TextSpan(text: address.substring(5, address.length - 5)),
      TextSpan(text: address.substring(address.length - 5), style: strong),
    ]));
  }
}

Future<void> copyToClipboard(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$label copied')));
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.trailing});
  final String label;
  final String value;
  final bool bold;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Row(children: [
            Flexible(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            if (trailing != null) trailing!,
          ]),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = switch (status) {
      'confirmed' => (AppColors.incoming, const Color(0xFFECFDF5), 'Confirmed'),
      'failed' => (AppColors.danger, const Color(0xFFFEF2F2), 'Failed'),
      _ => (AppColors.warning, AppColors.warningBg, 'Pending'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class TxTile extends StatelessWidget {
  const TxTile(this.tx, {super.key, this.onTap});
  final TxItem tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tx.incoming ? AppColors.incoming : AppColors.outgoing;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(tx.incoming ? Icons.south_west : Icons.north_east, color: color, size: 20),
      ),
      title: Text(tx.incoming ? 'Received' : 'Sent', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${shortAddress(tx.counterparty)} · ${formatDateTime(tx.time)}',
          style: const TextStyle(fontSize: 12)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${tx.incoming ? '+' : '−'}${Usdt.format(tx.amountMicro)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          StatusChip(tx.status),
        ],
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      ),
    );
  }
}
