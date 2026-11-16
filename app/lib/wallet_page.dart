import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'ui.dart';

/// Coin wallet. 1 coin = NPR 1 of verified top up. Coins move between members. There is no cash out.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.session});
  final Session session;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with WidgetsBindingObserver {
  int balance = 0;
  List<Map<String, dynamic>> entries = [];
  Map<String, dynamic> topup = {};
  Map<String, dynamic> cashout = {};
  List<Map<String, dynamic>> withdrawals = [];
  String? cashoutId; // reused on a retry of the same request so a lost reply cannot hold coins twice
  int? cashoutCoins;
  bool loading = true;
  String? error;
  String? pendingTopup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (state == AppLifecycleState.resumed && pendingTopup != null) _checkTopup();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/wallet') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        balance = (j['balance'] as num).toInt();
        entries = (j['entries'] as List).cast<Map<String, dynamic>>();
        topup = (j['topup'] as Map).cast<String, dynamic>();
        cashout = ((j['cashout'] as Map?) ?? const {}).cast<String, dynamic>();
        error = null;
        loading = false;
      });
      _loadWithdrawals();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    }
  }

  Future<void> _checkTopup() async {
    final id = pendingTopup;
    if (id == null) return;
    try {
      final j = await widget.session.call('GET', '/wallet/topups/$id') as Map<String, dynamic>;
      if (!mounted) return;
      if (j['status'] == 'completed') {
        pendingTopup = null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${j['amount']} coins.')));
      } else if (j['status'] == 'failed') {
        pendingTopup = null;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The payment did not go through. No coins were added.')));
      }
      await _load();
    } on ApiError catch (_) {}
  }

  Future<void> _topup() async {
    final c = TextEditingController(text: '100');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t_('Add coins')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount in NPR', helperText: '1 rupee = 1 coin. Minimum 10.'),
          ),
          if (topup['esewa_mode'] == 'test') const Padding(padding: EdgeInsets.only(top: 8), child: Text('Test mode: no real money moves.')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Pay with eSewa')),
        ],
      ),
    );
    if (amount == null) return;
    try {
      final j = await widget.session.call('POST', '/wallet/topups', body: {'amount': amount}) as Map<String, dynamic>;
      pendingTopup = j['topup_id'] as String;
      final ok = await launchUrl(Uri.parse(j['pay_url'] as String), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showError(context, 'Could not open the browser.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _send() async {
    final user = TextEditingController();
    final amt = TextEditingController();
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t_('Send coins')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Coins')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t_('Send'))),
        ],
      ),
    );
    if (go != true) return;
    try {
      await widget.session.call('POST', '/wallet/transfer', body: {
        'username': user.text.trim(),
        'amount': int.tryParse(amt.text.trim()) ?? 0,
        if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
      });
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent.')));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _loadWithdrawals() async {
    try {
      final j = await widget.session.call('GET', '/wallet/withdrawals') as Map<String, dynamic>;
      if (mounted) setState(() => withdrawals = ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } catch (_) {
      // The list is secondary: the wallet still works without it.
    }
  }

  Future<void> _cancelWithdrawal(String id) async {
    try {
      await widget.session.call('POST', '/wallet/withdrawals/$id/cancel');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Cash out canceled.'))));
    } catch (e) {
      if (mounted) showError(context, e);
      await _loadWithdrawals();
    }
  }

  String _wdStatus(String s) => switch (s) {
        'requested' => 'Requested',
        'processing' => 'Processing',
        'paid' => 'Paid',
        'failed' => 'Failed, coins returned',
        'canceled' => 'Canceled, coins returned',
        _ => s,
      };

  Future<void> _cashout() async {
    final min = (cashout['min'] as num?)?.toInt() ?? 500;
    final amt = TextEditingController(text: cashoutCoins?.toString() ?? '');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t_('Cash out')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Coins (at least $min)')),
          const SizedBox(height: 10),
          Text(t_('The coins leave your balance now. If the payout fails, they come back.'), style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t_('Cash out'))),
        ],
      ),
    );
    if (go != true) return;
    final coins = int.tryParse(amt.text.trim()) ?? 0;
    if (cashoutId == null || cashoutCoins != coins) {
      cashoutId = 'co-${DateTime.now().microsecondsSinceEpoch}-$coins';
      cashoutCoins = coins;
    }
    try {
      await widget.session.call('POST', '/wallet/withdrawals', body: {'coins': coins, 'client_id': cashoutId});
      cashoutId = null;
      cashoutCoins = null;
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t_('Cash out requested.'))));
    } on ApiError catch (e) {
      // A refusal means nothing was held: the next try is a new request. Anything else may have landed: keep the id.
      if (e.status != null && e.status! >= 400 && e.status! < 500) {
        cashoutId = null;
        cashoutCoins = null;
      }
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _label(Map<String, dynamic> e) {
    final who = e['counterparty'] == null ? '' : '@${e['counterparty']}';
    return switch (e['kind']) {
      'topup' => 'eSewa top up',
      'transfer_in' => 'From $who',
      'transfer_out' => 'To $who',
      'gift_in' => 'Gift from $who',
      'gift_out' => 'Gift to $who',
      'withdraw_hold' => 'Cash out',
      'withdraw_release' => 'Cash out returned',
      _ => e['kind'].toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final esewa = topup['esewa'] == true;
    final canCash = cashout['available'] == true && balance >= ((cashout['min'] as num?)?.toInt() ?? 500);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t_('Wallet'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (error != null) Text(error!),
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
                    Text('$balance', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.1)),
                  ]),
                ),
                const SizedBox(height: 14),
                Builder(builder: (context) {
                  final big = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
                  final buttons = <Widget>[
                    FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 6)), onPressed: esewa ? _topup : null, child: Text(t_('Add coins'), maxLines: 1, softWrap: false)),
                    OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 6)), onPressed: balance > 0 ? _send : null, child: Text(t_('Send'), maxLines: 1, softWrap: false)),
                    OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 6)), onPressed: canCash ? _cashout : null, child: Text(t_('Cash out'), maxLines: 1, softWrap: false)),
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
                      Expanded(child: Text(!esewa && cashout['available'] != true ? 'Adding coins is not switched on yet. Cash out is not available.' : !esewa ? 'Adding coins is not switched on yet.' : 'Cash out is not available yet.')),
                    ]),
                  ),
                if (withdrawals.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(t_('Cash outs'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  for (final w in withdrawals)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${w['coins']} coins', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([_wdStatus(w['status'].toString()), ago((w['created_at'] ?? '').toString())].join('  ')),
                      trailing: w['status'] == 'requested' ? TextButton(onPressed: () => _cancelWithdrawal(w['public_id'].toString()), child: Text(t_('Cancel'))) : null,
                    ),
                ],
                const SizedBox(height: 22),
                Text(t_('Activity'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (entries.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No activity yet.')),
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: scheme.surfaceContainerHigh, child: PhIcon((e['amount'] as num) > 0 ? 'arrow-down-left' : 'arrow-up-right', size: 20)),
                    title: Text(_label(e)),
                    subtitle: Text([ago((e['created_at'] ?? '').toString()), if (e['note'] != null) e['note']].join('  ')),
                    trailing: Text('${(e['amount'] as num) > 0 ? '+' : ''}${e['amount']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
              ]),
            ),
    );
  }
}
