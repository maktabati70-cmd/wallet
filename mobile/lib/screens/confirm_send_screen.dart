import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/send_flow.dart';
import '../core/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'transfer_status_screen.dart';
import 'unlock_screen.dart';

/// Shows the full fee breakdown and requires explicit confirmation.
/// After PIN re-entry the phone verifies, signs and submits the transfer.
class ConfirmSendScreen extends StatefulWidget {
  const ConfirmSendScreen({super.key, required this.quote});
  final FeeQuote quote;

  @override
  State<ConfirmSendScreen> createState() => _ConfirmSendScreenState();
}

class _ConfirmSendScreenState extends State<ConfirmSendScreen> {
  bool _checked = false;
  bool _sending = false;
  String? _stage;
  String? _error;
  late Duration _left;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _left = _remaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Duration _remaining() {
    final left = widget.quote.expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _left = _remaining());
    if (_left == Duration.zero) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showResourceInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Network resource fee'),
        content: Text(widget.quote.disclosure),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _confirm() async {
    if (!widget.quote.sendingEnabled) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.info_outline),
          title: const Text('Sending not available yet'),
          content: const Text(
            'Sending is not enabled on the server yet. No funds were moved.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (!await requirePin(context, title: 'Enter PIN to send')) return;
    if (!mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _timer?.cancel(); // the quote is locked in once we start
    try {
      final status = await executeSend(
        quote: widget.quote,
        myAddress: WalletSession.instance.address ?? '',
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<bool>(
        builder: (_) => TransferStatusScreen(initial: status),
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    final expired = _left == Duration.zero;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm transfer')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('To', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 6),
                AddressText(q.toAddress),
                if (q.recipientIsNew) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'This address has no activity on the blockchain yet. Double-check it.',
                    style: TextStyle(color: AppColors.warning, fontSize: 13),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                InfoRow('Amount', '${q.amount} USDT'),
                InfoRow('Service fee (${q.serviceFeePercent}%)', '− ${q.serviceFee} USDT'),
                InfoRow(
                  'Network resource fee',
                  '− ${q.resourceFee} USDT',
                  trailing: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.info_outline, size: 18),
                    onPressed: _showResourceInfo,
                  ),
                ),
                const Divider(),
                InfoRow('Total fees', '${q.totalFee} USDT'),
                InfoRow('Recipient receives', '${q.recipientReceives} USDT', bold: true),
                InfoRow('Total deducted from you', '${q.amount} USDT'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'You will not need TRX: we provide the network resources (Energy/Bandwidth) for '
            'this transfer. Blockchain transfers cannot be reversed.',
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _checked,
            onChanged: (v) => setState(() => _checked = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I have checked the recipient address and the amounts.'),
          ),
          const SizedBox(height: 8),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: (_checked && !expired && !_sending) ? _confirm : null,
            child: _sending
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(_stage ?? 'Working…'),
                  ])
                : Text(expired ? 'Quote expired — go back' : 'Confirm & send (${_left.inSeconds}s)'),
          ),
        ]),
      ),
    );
  }
}
