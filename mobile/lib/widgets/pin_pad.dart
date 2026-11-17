import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../theme.dart';

/// Numeric PIN entry with dot indicators. Calls [onCompleted] when
/// [AppConfig.pinLength] digits have been entered.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.onBiometric,
  });

  final Future<void> Function(String pin) onCompleted;
  final bool enabled;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  void clear() => setState(() => _pin = '');

  Future<void> _tap(String d) async {
    if (!widget.enabled || _busy || _pin.length >= AppConfig.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == AppConfig.pinLength) {
      setState(() => _busy = true);
      try {
        await widget.onCompleted(_pin);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _pin = '';
          });
        }
      }
    }
  }

  void _back() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _Key(label: d, onTap: () => _tap(d));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 24,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(AppConfig.pinLength, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.brand : Colors.transparent,
                      border: Border.all(color: filled ? AppColors.brand : AppColors.muted, width: 1.5),
                    ),
                  );
                }),
              ),
      ),
      const SizedBox(height: 28),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map(key).toList()),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        widget.onBiometric != null
            ? _Key(icon: Icons.fingerprint, onTap: widget.onBiometric!)
            : const SizedBox(width: 88, height: 72),
        key('0'),
        _Key(icon: Icons.backspace_outlined, onTap: _back),
      ]),
    ]);
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 76,
        height: 60,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Center(
            child: label != null
                ? Text(label!, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500))
                : Icon(icon, size: 26, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}
