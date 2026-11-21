import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'glass/glass_button.dart';
import 'glass/glass_card.dart';
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
        error = null;
        loading = false;
      });
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

  String _label(Map<String, dynamic> e) {
    final who = e['counterparty'] == null ? '' : '@${e['counterparty']}';
    return switch (e['kind']) {
      'topup' => 'eSewa top up',
      'transfer_in' => 'From $who',
      'transfer_out' => 'To $who',
      'gift_in' => 'Gift from $who',
      'gift_out' => 'Gift to $who',
      _ => e['kind'].toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final esewa = topup['esewa'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Coin wallet')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                if (error != null) Text(error!),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t_('Balance'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.6)),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Text('$balance', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.1)),
                      const SizedBox(width: 8),
                      Text('coins', style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      GlassButton(label: t_('Add coins'), icon: Icons.add, onPressed: esewa ? _topup : null),
                      const SizedBox(width: 10),
                      GlassButton(label: t_('Send'), icon: Icons.north_east, primary: false, onPressed: balance > 0 ? _send : null),
                    ]),
                    if (!esewa) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Adding coins is not switched on yet.')),
                    const Padding(padding: EdgeInsets.only(top: 6), child: Text('Cash out is not available.', style: TextStyle(fontSize: 12))),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                if (entries.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No activity yet.')),
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: (e['amount'] as num) > 0 ? brandRed.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        switch (e['kind']) {
                          'topup' => Icons.add,
                          'transfer_in' || 'gift_in' => Icons.south_west,
                          _ => Icons.north_east,
                        },
                        size: 20,
                        color: (e['amount'] as num) > 0 ? brandRed : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(_label(e)),
                    subtitle: Text([ago((e['created_at'] ?? '').toString()), if (e['note'] != null) e['note']].join('  ')),
                    trailing: Text(
                      '${(e['amount'] as num) > 0 ? '+' : ''}${e['amount']}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: (e['amount'] as num) > 0 ? brandRed : Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
              ]),
            ),
    );
  }
}
