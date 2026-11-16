import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped original transfer details, not a balance or a payment credential.
/// Failure to persist/read back must prevent a new request, never discard its key.
abstract class WalletTransferStore {
  const WalletTransferStore();
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}
class SecureWalletTransferStore extends WalletTransferStore {
  const SecureWalletTransferStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
    if (await _storage.read(key: key) != value) throw StateError('Pending transfer write unverified');
  }
  @override
  Future<void> remove(String key) async {
    await _storage.delete(key: key);
    if (await _storage.read(key: key) != null) throw StateError('Pending transfer removal unverified');
  }
}
