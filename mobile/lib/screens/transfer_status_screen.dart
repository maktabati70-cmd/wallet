import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../core/api_client.dart';
import '../core/money.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Follows a submitted transfer until it is confirmed or fails.
class TransferStatusScreen extends StatefulWidget {
  const TransferStatusScreen({super.key, required this.initial});
  final TransferStatus initial;

  @override
  State<TransferStatusScreen> createState() => _TransferStatusScreenState();
}

class _TransferStatusScreenState extends State<TransferStatusScreen> {
  late TransferStatus _t = widget.initial;
  Timer? _timer;
  int _errors = 0;

  static const _steps = [
    ('providing', 'Preparing network resources'),
    ('sending_fee', 'Paying the fee'),
    ('sending', 'Sending to recipient'),
    ('done', 'Confirmed on the blockchain'),
  ];

  @override
  void initState() {
    super.initState();
    if (!_t.finished) _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final t = await ApiClient.instance.transferStatus(_t.transferId);
      if (!mounted) return;
      setState(() => _t = t);
      if (t.finished) _timer?.cancel();
    } on ApiException {
      if (++_errors > 40) _timer?.cancel();
    }
  }

  int get _stepIndex => switch (_t.step) {
        'queued' || 'activating' || 'providing_energy' => 0,
        'sending_fee' => 1,
        'sending' => 2,
        'done' => 4,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final done = _t.status == 'confirmed';
    final failed = _t.status == 'failed' || _t.status == 'expired';
    final refund = _t.status == 'refund_needed';
    return PopScope(
      canPop: _t.finished,
      child: Scaffold(
        appBar: AppBar(title: const Text('Transfer'), automaticallyImplyLeading: _t.finished),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const SizedBox(height: 12),
            Center(
              child: done
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.incoming, size: 72)
                  : (failed || refund)
                      ? const Icon(Icons.error_rounded, color: AppColors.danger, size: 72)
                      : const SizedBox(width: 56, height: 56, child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                done
                    ? 'Sent ${Usdt.format(_t.recipientMicro)} USDT'
                    : failed
                        ? 'Transfer failed'
                        : refund
                            ? 'Transfer needs attention'
                            : 'Sending ${Usdt.format(_t.recipientMicro)} USDT…',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text('to ${shortAddress(_t.toAddress)}', style: const TextStyle(color: AppColors.muted))),
            const SizedBox(height: 24),
            if (!failed && !refund)
              Card(
                child: Column(children: [
                  for (var i = 0; i < _steps.length; i++)
                    ListTile(
                      dense: true,
                      leading: i < _stepIndex || done
                          ? const Icon(Icons.check_circle, color: AppColors.incoming)
                          : i == _stepIndex
                              ? const SizedBox(
                                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.radio_button_unchecked, color: AppColors.muted),
                      title: Text(_steps[i].$2),
                    ),
                ]),
              ),
            if (failed)
              WarningCard(
                text: 'No funds were moved from your wallet.\n\n${_t.failureReason ?? ''}',
                icon: Icons.info_outline,
              ),
            if (refund)
              WarningCard(
                text: 'The fee was paid but the transfer to the recipient did not go through. '
                    'Please contact support (${AppConfig.supportEmail}) with this reference:\n'
                    '${_t.transferId}',
              ),
            const SizedBox(height: 16),
            if (done || refund)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(_t.mainExplorerUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('View on TRONSCAN'),
              ),
            const SizedBox(height: 12),
            if (_t.finished)
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Done'),
              )
            else
              const Text(
                'You can leave this screen; the transfer continues on the server.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
          ]),
        ),
      ),
    );
  }
}
