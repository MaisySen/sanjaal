import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/wallet_transfer_store.dart';

void main() {
 const store=SecureWalletTransferStore();
 setUp(()=>FlutterSecureStorage.setMockInitialValues({}));
 test('original transfer round-trips and clears through secure storage adapter',()async{
  await store.write('wallet_transfer_v1_fixture','synthetic-transfer-json');
  expect(await store.read('wallet_transfer_v1_fixture'),'synthetic-transfer-json');
  await store.remove('wallet_transfer_v1_fixture');
  expect(await store.read('wallet_transfer_v1_fixture'),isNull);
 });
 test('one member removal cannot erase another original transfer',()async{
  await store.write('wallet_transfer_v1_a','synthetic-a');await store.write('wallet_transfer_v1_b','synthetic-b');
  await store.remove('wallet_transfer_v1_a');expect(await store.read('wallet_transfer_v1_b'),'synthetic-b');
 });
}
