import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/money.dart';
import '../core/session.dart';
import '../core/tron_address.dart';
import '../theme.dart';
import 'confirm_send_screen.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.availableMicro});
  final int availableMicro;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _to = TextEditingController();
  final _amount = TextEditingController();
  final _api = ApiClient.instance;
  String? _toError;
  String? _amountError;
  String? _error;
  bool _busy = false;
  RemoteConfig? _config;
  List<String> _knownAddresses = const [];

  String get _me => WalletSession.instance.address ?? '';

  @override
  void initState() {
    super.initState();
    _prefetch();
  }

  Future<void> _prefetch() async {
    try {
      final config = await _api.config();
      final hist = await _api.history(_me, limit: 50);
      if (!mounted) return;
      setState(() {
        _config = config;
        _knownAddresses = hist.items.map((t) => t.counterparty).toSet().toList();
      });
    } on ApiException {
      // non-fatal: limits & poisoning check simply become unavailable
    }
  }

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    _to.text = text;
    _validateTo(text);
  }

  void _validateTo(String v) {
    setState(() {
      if (v.isEmpty) {
        _toError = null;
      } else if (!TronAddress.isValid(v)) {
        _toError = 'Not a valid TRON address';
      } else if (v == _me) {
        _toError = 'This is your own address';
      } else {
        _toError = null;
      }
    });
  }

  void _validateAmount(String v) {
    setState(() {
      final micro = Usdt.tryParse(v);
      if (v.isEmpty) {
        _amountError = null;
      } else if (micro == null || micro <= 0) {
        _amountError = 'Enter a valid amount (max 6 decimals)';
      } else if (micro > widget.availableMicro) {
        _amountError = 'Insufficient balance';
      } else {
        _amountError = null;
      }
    });
  }

  /// Address-poisoning check: a new address that looks like one you used before.
  String? _lookalike(String to) {
    for (final known in _knownAddresses) {
      if (TronAddress.looksSimilar(known, to)) return known;
    }
    return null;
  }

  Future<void> _continue() async {
    final to = _to.text.trim();
    _validateTo(to);
    _validateAmount(_amount.text);
    if (to.isEmpty || _amount.text.isEmpty || _toError != null || _amountError != null) return;

    final similar = _lookalike(to);
    if (similar != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.gpp_maybe_outlined, color: AppColors.danger),
          title: const Text('Possible scam address'),
          content: Text(
            'This address looks very similar to one in your history but is different:\n\n'
            'Entered:  $to\nPrevious: $similar\n\n'
            'Scammers create look-alike addresses. Check every character.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I checked it')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quote = await _api.quote(from: _me, to: to, amount: _amount.text.trim());
      if (!mounted) return;
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => ConfirmSendScreen(quote: quote)),
      );
      if (sent == true && mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('Send USDT')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Recipient TRON address', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _to,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'T…',
              errorText: _toError,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
            ),
            onChanged: (v) => _validateTo(v.trim()),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(
              child: Text('Amount (USDT)', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text('Available: ${Usdt.format(widget.availableMicro)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(
              hintText: '0.00',
              errorText: _amountError,
              suffixIcon: TextButton(
                onPressed: () {
                  _amount.text = Usdt.format(widget.availableMicro, minDecimals: 0).replaceAll(',', '');
                  _validateAmount(_amount.text);
                },
                child: const Text('MAX'),
              ),
            ),
            onChanged: _validateAmount,
          ),
          const SizedBox(height: 12),
          Text(
            c == null
                ? 'Fees are shown on the next screen before you confirm.'
                : 'Service fee ${c.serviceFeePercent}% (min ${c.minServiceFee}, max ${c.maxServiceFee} USDT) '
                    'plus a network resource fee. Fees are deducted from the amount and shown '
                    'in full before you confirm. Limits: ${c.minSend}–${c.maxSend} USDT.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _continue,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Review'),
          ),
        ]),
      ),
    );
  }
}
