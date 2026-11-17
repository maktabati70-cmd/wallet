/// In-memory state for the unlocked wallet. Holds the public address only —
/// the recovery phrase is read from secure storage when (and only when)
/// it is needed, after the PIN is re-entered.
class WalletSession {
  WalletSession._();
  static final WalletSession instance = WalletSession._();

  String? address;
  bool unlocked = false;
  DateTime? backgroundedAt;

  void lock() => unlocked = false;

  void clear() {
    address = null;
    unlocked = false;
    backgroundedAt = null;
  }
}
