import 'session_bound_state.dart';
import 'dart:convert';
import 'wallet_transfer_store.dart';
import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'ui.dart';

/// Coin history and member transfers. Funding/payout availability comes from the server.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.session, this.transferStore = const SecureWalletTransferStore()});
  final WalletTransferStore transferStore;
  final Session session;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with WidgetsBindingObserver, SessionBoundState<WalletPage> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() {
    loadGeneration++; withdrawalGeneration++;
    entries = []; withdrawals = []; pendingTransfer = null;
    balance = 0; topup = {}; cashout = {}; pendingTopup = null;
    cashoutId = null; cashoutCoins = null;
    transferReplay = false; transferStoreReady = false;
  }
  int balance = 0;
  List<Map<String, dynamic>> entries = [];
  Map<String, dynamic> topup = {};
  Map<String, dynamic> cashout = {};
  List<Map<String, dynamic>> withdrawals = [];
  String? cashoutId; // reused on a retry of the same request so a lost reply cannot hold coins twice
  int? cashoutCoins;
  bool loading = true;
  bool loaded = false; // a failed first load must not show a made-up zero balance
  String? error;
  String? pendingTopup;
  bool refreshing = false;
  bool operationBusy = false;
  Map<String, dynamic>? pendingTransfer;
  String? transferStoreError;
  bool transferStoreReady = false;
  bool transferReplay = false;
  late final String? transferOwner = widget.session.user?['public_id'] as String?;
  String? get transferStoreKey => transferOwner == null ? null : 'wallet_transfer_v1_$transferOwner';
  bool checkingTopup = false;
  String? withdrawalError;
  int loadGeneration = 0;
  int withdrawalGeneration = 0;

  bool get canAct => sessionActive && widget.session.user?['public_id'] == transferOwner && loaded && !loading && !refreshing && !operationBusy && error == null;

  Future<void> _runOperation(Future<void> Function() operation) async {
    if (!canAct) return;
    setState(() => operationBusy = true);
    try {
      await operation();
    } finally {
      if (mounted && sessionActive) setState(() => operationBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreTransfer();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the payment page in the browser.
    if (sessionActive && state == AppLifecycleState.resumed && pendingTopup != null) _checkTopup();
  }

  Future<void> _restoreTransfer() async {
    if (!sessionActive) return;
    try {
      final key = transferStoreKey;
      if (key == null) throw const FormatException('Missing member identity');
      final store = widget.transferStore;
      final raw = await store.read(key);
      final data = raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (data != null && (data['client_id'] is! String || !RegExp(r'^[A-Za-z0-9_-]{16,80}$').hasMatch(data['client_id']) || data['username'] is! String || data['amount'] is! int || data['amount'] < 1 || data['amount'] > 100000 || (data['note'] != null && data['note'] is! String))) throw const FormatException('Invalid pending transfer');
      if (mounted && sessionActive) setState(() { pendingTransfer = data; transferStoreReady = true; transferStoreError = null; });
    } catch (_) {
      if (mounted && sessionActive) setState(() { transferStoreError = t_('Pending transfer could not be read. Sending is paused.'); transferStoreReady = false; });
    }
  }

  Future<void> _submitTransfer(Map<String, dynamic> body) async {
    if (!mounted || !sessionActive || !transferReplay || widget.session.user?['public_id'] != transferOwner) return;
    setState(() { pendingTransfer = Map.unmodifiable(body); transferStoreError = null; });
    var saved = false;
    try {
      final key = transferStoreKey;
      if (key == null) throw const FormatException('Missing member identity');
      final store = widget.transferStore;
      final existing = await store.read(key);
      if (existing != null && (jsonDecode(existing) as Map)['client_id'] != body['client_id']) {
        await _restoreTransfer();
        if (mounted) showInfo(context, t_('Resolve the saved original transfer first.'));
        return;
      }
      await store.write(key, jsonEncode(body));
      saved = true;
      if (!mounted || !sessionActive || widget.session.user?['public_id'] != transferOwner) return;
      final result = await widget.session.call('POST', '/wallet/transfer', body: body) as Map;
      final receipt = result['transfer'] as Map;
      if (receipt['status'] != 'completed' || receipt['client_id'] != body['client_id'] || receipt['amount'] != body['amount'] || receipt['public_id'] is! String) throw const FormatException('Unconfirmed transfer receipt');
      if (!mounted || !sessionActive) return;
      await store.remove(key);
      if (mounted && sessionActive) {
        setState(() => pendingTransfer = null);
        await _load();
        if (mounted && sessionActive) showInfo(context, t_('Transfer confirmed.'));
      }
    } catch (e) {
      if (!mounted || !sessionActive) return;
      final rejected = saved && e is ApiError && e.status != null && e.status! >= 400 && e.status! < 500 && e.status != 408 && e.status != 409;
      if (rejected) {
        try {
          final store = widget.transferStore;
          await store.remove(transferStoreKey!);
          if (mounted && sessionActive) setState(() => pendingTransfer = null);
        } catch (_) {
          if (mounted && sessionActive) setState(() => transferStoreError = t_('Pending transfer could not be saved. Sending is paused.'));
        }
      }
      if (mounted && sessionActive) {
        showError(context, rejected ? e : saved ? t_('Transfer result unconfirmed. Retry only this original transfer.') : t_('Transfer was not sent because its details could not be saved.'));
        await _load();
      }
    }
  }

  Future<void> _load() async {
    if (!mounted || !sessionActive) return;
    final generation = ++loadGeneration;
    withdrawalGeneration++;
    setState(() => refreshing = true);
    try {
      final j = await widget.session.call('GET', '/wallet') as Map<String, dynamic>;
      final nextBalance = (j['balance'] as num).toInt();
      final nextEntries = (j['entries'] as List).cast<Map<String, dynamic>>();
      final nextTopup = (j['topup'] as Map).cast<String, dynamic>();
      final nextCashout = ((j['cashout'] as Map?) ?? const {}).cast<String, dynamic>();
      if (!mounted || !sessionActive || generation != loadGeneration) return;
      setState(() {
        balance = nextBalance;
        entries = nextEntries;
        topup = nextTopup;
        cashout = nextCashout;
        transferReplay = j['transfer_replay'] == true && j['transfers_available'] == true;
        error = null;
        loaded = true;
        loading = false;
        refreshing = false;
      });
      _loadWithdrawals();
    } catch (e) {
      if (mounted && sessionActive && generation == loadGeneration) {
        setState(() {
          error = e is ApiError ? e.message : t_('Wallet could not be loaded.');
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  Future<void> _checkTopup() async {
    final id = pendingTopup;
    if (!sessionActive || id == null || checkingTopup) return;
    checkingTopup = true;
    try {
      final j = await widget.session.call('GET', '/wallet/topups/$id') as Map<String, dynamic>;
      if (!mounted || !sessionActive) return;
      if (j['status'] == 'completed') {
        pendingTopup = null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Added {amount} coins.').replaceAll('{amount}', '${j['amount']}'))));
      } else if (j['status'] == 'failed') {
        pendingTopup = null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('The payment did not go through. No coins were added.'))));
      }
      await _load();
    } catch (_) {
      // Keep the pending id: returning from the browser is not proof of payment.
    } finally {
      checkingTopup = false;
    }
  }

  Future<void> _topup() async {
    if (!sessionActive) return;
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => _WalletDialog(session: widget.session, initial: const ['100'], builder: (ctx, fields) {
        final c = fields[0];
        return AlertDialog(
        title: Text(t_('Add coins'), style: Theme.of(ctx).textTheme.titleMedium),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t_('Amount in NPR'), helperText: t_('1 rupee = 1 coin. Minimum 10.'), helperMaxLines: 4),
          ),
          if (topup['esewa_mode'] == 'test') Padding(padding: const EdgeInsets.only(top: 8), child: Text(t_('Test mode: no real money moves.'))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: Text(t_('Pay with eSewa'))),
        ],
      ); }),
    );
    if (!mounted || !sessionActive || amount == null) return;
    try {
      final j = await widget.session.call('POST', '/wallet/topups', body: {'amount': amount}) as Map<String, dynamic>;
      if (!mounted || !sessionActive) return;
      pendingTopup = j['topup_id'] as String;
      final ok = await launchUrl(Uri.parse(j['pay_url'] as String), mode: LaunchMode.externalApplication);
      if (!ok && mounted && sessionActive) showError(context, t_('Could not open the browser.'));
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
    }
  }

  Future<void> _send() async {
    if (!sessionActive || pendingTransfer != null || !transferReplay || !transferStoreReady || widget.session.user?['public_id'] != transferOwner) return;
    final form = GlobalKey<FormState>();
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _WalletDialog(session: widget.session, initial: const ['', '', ''], builder: (ctx, fields) {
        final user = fields[0], amt = fields[1], note = fields[2];
        return AlertDialog(
        title: Text(t_('Send coins'), style: Theme.of(ctx).textTheme.titleMedium),
        content: SingleChildScrollView(padding: const EdgeInsets.symmetric(vertical: 12), child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: user, autocorrect: false, decoration: InputDecoration(labelText: t_('Username'), floatingLabelBehavior: FloatingLabelBehavior.always), validator: (v) => (v ?? '').trim().isEmpty ? t_('Required') : null),
          TextFormField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t_('Coins'), floatingLabelBehavior: FloatingLabelBehavior.always, errorMaxLines: 4), validator: (v) { final n = int.tryParse((v ?? '').trim()); return n == null || n < 1 || n > 100000 || n > balance ? t_('Enter a whole coin amount within your balance.') : null; }),
          TextFormField(controller: note, maxLength: 140, decoration: InputDecoration(labelText: t_('Note (optional)'), floatingLabelBehavior: FloatingLabelBehavior.always)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, <String, dynamic>{'username': user.text.trim(), 'amount': int.parse(amt.text.trim()), 'client_id': newUploadIntent(), if (note.text.trim().isNotEmpty) 'note': note.text.trim()}); }, child: Text(t_('Send'))),
        ],
      ); }),
    );
    if (!mounted || !sessionActive || body == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => _WalletDialog(session: widget.session, initial: const [], builder: (ctx, fields) => AlertDialog(
      title: Text(t_('Review transfer'), style: Theme.of(ctx).textTheme.titleMedium),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t_('{amount} coins to @{member}').replaceAll('{amount}', '${body['amount']}').replaceAll('{member}', '${body['username']}')),
        if (body['note'] != null) ...[const SizedBox(height: 12), Text('${body['note']}')],
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t_('Cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t_('Confirm send')))],
    )));
    if (!mounted || !sessionActive || confirmed != true) return;
    await _submitTransfer(body);
  }

  Future<void> _loadWithdrawals() async {
    if (!sessionActive) return;
    final generation = ++withdrawalGeneration;
    try {
      final j = await widget.session.call('GET', '/wallet/withdrawals') as Map<String, dynamic>;
      final rows = ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted && sessionActive && generation == withdrawalGeneration) setState(() { withdrawals = rows; withdrawalError = null; });
    } catch (_) {
      if (mounted && sessionActive && generation == withdrawalGeneration) setState(() => withdrawalError = t_('Cash-out history could not be loaded.'));
    }
  }

  Future<void> _cancelWithdrawal(String id) async {
    if (!sessionActive) return;
    try {
      await widget.session.call('POST', '/wallet/withdrawals/$id/cancel');
      await _load();
      if (mounted && sessionActive) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Cash out canceled.'))));
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
      await _loadWithdrawals();
    }
  }

  String _wdStatus(String s) => switch (s) {
        'requested' => 'Requested',
        'processing' => 'Processing',
        'review' => 'Under review',
        'paid' => 'Paid',
        'failed' => 'Failed, coins returned',
        'canceled' => 'Canceled, coins returned',
        _ => s,
      };

  Future<void> _cashout() async {
    if (!sessionActive) return;
    final min = (cashout['min'] as num?)?.toInt() ?? 500;
    final coins = await showDialog<int>(
      context: context,
      builder: (ctx) => _WalletDialog(session: widget.session, initial: [cashoutCoins?.toString() ?? ''], builder: (ctx, fields) {
        final amt = fields[0];
        return AlertDialog(
        title: Text(t_('Cash out'), style: Theme.of(ctx).textTheme.titleMedium),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t_('Coins (at least {min})').replaceAll('{min}', '$min'))),
          const SizedBox(height: 10),
          Text(t_('The coins leave your balance now. If the payout fails, they come back.'), style: Theme.of(ctx).textTheme.bodySmall),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(amt.text.trim()) ?? 0), child: Text(t_('Cash out'))),
        ],
      ); }),
    );
    if (!mounted || !sessionActive || coins == null) return;
    if (cashoutId == null || cashoutCoins != coins) {
      cashoutId = 'co-${DateTime.now().microsecondsSinceEpoch}-$coins';
      cashoutCoins = coins;
    }
    try {
      await widget.session.call('POST', '/wallet/withdrawals', body: {'coins': coins, 'client_id': cashoutId});
      cashoutId = null;
      cashoutCoins = null;
      await _load();
      if (mounted && sessionActive) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Cash out requested.'))));
    } on ApiError catch (e) {
      if (!mounted || !sessionActive) return;
      // A refusal means nothing was held: the next try is a new request. Anything else may have landed: keep the id.
      if (e.status != null && e.status! >= 400 && e.status! < 500 && e.status != 408) {
        cashoutId = null;
        cashoutCoins = null;
      }
      if (mounted && sessionActive) showError(context, e);
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
    }
  }

  String _label(Map<String, dynamic> e) {
    final who = e['counterparty'] == null ? '' : '@${e['counterparty']}';
    return switch (e['kind']) {
      'topup' => t_('eSewa top up'),
      'transfer_in' => t_('From {member}').replaceAll('{member}', who),
      'transfer_out' => t_('To {member}').replaceAll('{member}', who),
      'gift_in' => t_('Gift from {member}').replaceAll('{member}', who),
      'gift_out' => t_('Gift to {member}').replaceAll('{member}', who),
      'withdraw_hold' => t_('Cash out'),
      'withdraw_release' => t_('Cash out returned'),
      _ => e['kind'].toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return Scaffold(
      appBar: AppBar(title: Text(t_('Wallet'))),
      body: ModalRoute.of(context)?.isCurrent == false ? const SizedBox.shrink() : SingleChildScrollView(
        padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t_('Your sign-in changed. This wallet has been closed.')),
          if (widget.session.user != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: () {
              if (widget.session.user == null) return;
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WalletPage(session: widget.session, transferStore: widget.transferStore)));
            }, child: Text(t_('Open current wallet'))),
          ],
        ]),
      ),
    );
    final esewa = topup['esewa'] == true;
    final canCash = cashout['available'] == true && balance >= ((cashout['min'] as num?)?.toInt() ?? 500);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t_('Wallet'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (error != null && !loaded)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () {
                        setState(() => loading = true);
                        _load();
                      }, child: Text(t_('Try again'))),
                    ]),
                  ),
                )
              : RefreshIndicator(
              onRefresh: () async { if (!operationBusy) await _load(); },
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
                if (refreshing || operationBusy) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(t_('Wallet action in progress.'))),
                if (error != null) ...[
                  Text(t_('Showing the last loaded balance. Refresh before making changes.')),
                  Text(error!),
                  TextButton(onPressed: refreshing || operationBusy ? null : _load, child: Text(t_('Try again'))),
                ],
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(28), border: Border.all(color: scheme.outlineVariant)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      PhIcon('coins', size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(t_('Coins'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('$balance', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1)))),
                  ]),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, constraints) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final labels = ['Add coins', 'Send', 'Cash out'].map(t_);
                  final slot = (constraints.maxWidth - 20) / 3 - 12;
                  final big = scaler.scale(14) / 14 > 1.3 || labels.any((label) {
                    final painter = TextPainter(text: TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge), textDirection: Directionality.of(context), textScaler: scaler)..layout();
                    return painter.width > slot;
                  });
                  final buttons = <Widget>[
                    FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 6)), onPressed: canAct && esewa ? () => _runOperation(_topup) : null, child: Text(t_('Add coins'), maxLines: 1, softWrap: false)),
                    OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 6)), onPressed: canAct && balance > 0 && transferReplay && transferStoreReady && pendingTransfer == null ? () => _runOperation(_send) : null, child: Text(t_('Send'), maxLines: 1, softWrap: false)),
                    OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 6)), onPressed: canAct && canCash ? () => _runOperation(_cashout) : null, child: Text(t_('Cash out'), maxLines: 1, softWrap: false)),
                  ];
                  if (big) return Column(children: [for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(width: double.infinity, child: b))]);
                  return Row(children: [for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: buttons[i])]]);
                }),
                if (!esewa || cashout['available'] != true)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outlineVariant)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      PhIcon('info', size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t_(!esewa && cashout['available'] != true ? 'Adding coins is not switched on yet. Cash out is not available.' : !esewa ? 'Adding coins is not switched on yet.' : 'Cash out is not available yet.'))),
                    ]),
                  ),
                if (!transferReplay) Padding(padding: const EdgeInsets.only(top: 12), child: Text(t_('Transfers are unavailable until live verification is complete.'))),
                if (transferStoreError != null) ...[
                  Text(transferStoreError!),
                  TextButton(onPressed: operationBusy ? null : _restoreTransfer, child: Text(t_('Reload pending transfer'))),
                ],
                if (pendingTransfer != null) Container(
                  margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t_('Original transfer needs confirmation.'), style: Theme.of(context).textTheme.titleSmall),
                    Text(t_('{amount} coins to @{member}').replaceAll('{amount}', '${pendingTransfer!['amount']}').replaceAll('{member}', '${pendingTransfer!['username']}')),
                    if (pendingTransfer!['note'] != null) Text('${pendingTransfer!['note']}'),
                    const SizedBox(height: 8),
                    Text(t_('Retrying checks the same transfer. It will not send it twice.')),
                    TextButton(onPressed: canAct && transferReplay && transferStoreReady ? () => _runOperation(() => _submitTransfer(pendingTransfer!)) : null, child: Text(t_('Retry original transfer'))),
                  ]),
                ),
                if (withdrawalError != null) ...[
                  const SizedBox(height: 12),
                  Text(withdrawalError!),
                  TextButton(onPressed: refreshing || operationBusy ? null : _loadWithdrawals, child: Text(t_('Retry cash-out history'))),
                ],
                if (withdrawals.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(t_('Cash outs'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  for (final w in withdrawals)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${w['coins']} ${t_('Coins')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([t_(_wdStatus(w['status'].toString())), ago((w['created_at'] ?? '').toString())].join('  ')),
                      trailing: w['status'] == 'requested' ? TextButton(onPressed: canAct ? () => _runOperation(() => _cancelWithdrawal(w['public_id'].toString())) : null, child: Text(t_('Cancel'))) : null,
                    ),
                ],
                const SizedBox(height: 22),
                Text(t_('Activity'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (entries.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t_('No activity yet.')), const SizedBox(height: 6), Text(t_('Your coin history appears here.'), style: Theme.of(context).textTheme.bodySmall)])),
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: scheme.surfaceContainerHigh, child: PhIcon((e['amount'] as num) > 0 ? 'arrow-down-left' : 'arrow-up-right', size: 20)),
                    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_label(e)),
                      if (MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3) Text('${(e['amount'] as num) > 0 ? '+' : ''}${e['amount']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    subtitle: Text([ago((e['created_at'] ?? '').toString()), if (e['note'] != null) e['note']].join('  ')),
                    trailing: MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3 ? null : Text('${(e['amount'] as num) > 0 ? '+' : ''}${e['amount']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
              ]),
            ),
    );
  }
}

// The route owns controllers until its closing animation actually disposes it.
class _WalletDialog extends StatefulWidget {
  const _WalletDialog({required this.session, required this.initial, required this.builder});
  final Session session;
  final List<String> initial;
  final Widget Function(BuildContext, List<TextEditingController>) builder;
  @override
  State<_WalletDialog> createState() => _WalletDialogState();
}
class _WalletDialogState extends State<_WalletDialog> with SessionBoundState<_WalletDialog> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() { for (final field in fields) { field.clear(); } }
  late final fields = widget.initial.map((s) => TextEditingController(text: s)).toList();
  @override
  void dispose() { for (final c in fields) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => sessionActive ? widget.builder(context, fields) : AlertDialog(
    scrollable: true, content: Text(t_('Your sign-in changed. Close this dialog to open your current wallet.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t_('Close')))],
  );
}
