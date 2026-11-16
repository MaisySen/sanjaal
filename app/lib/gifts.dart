import 'ph.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart';

const _giftIcons = <String, PhData>{
  'rose': Ph.local_florist,
  'heart': Ph.favorite,
  'momo': Ph.ramen_dining,
  'crown': Ph.workspace_premium,
  'himal': Ph.landscape,
  'rocket': Ph.rocket_launch,
};

/// Bottom sheet that lists gifts and sends one to the creator of a post or reel.
Future<void> showGiftSheet(BuildContext context, Session session, String postId, String username, {String? path, void Function(Map<String, dynamic> gift)? onSent}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _GiftSheet(session: session, postId: postId, username: username, path: path ?? '/posts/$postId/gifts', onSent: onSent),
  );
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({required this.session, required this.postId, required this.username, required this.path, this.onSent});
  final String path;
  final void Function(Map<String, dynamic> gift)? onSent;
  final Session session;
  final String postId;
  final String username;
  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  List<Map<String, dynamic>> gifts = [];
  int? balance;
  String? sending;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await widget.session.call('GET', '/gifts');
      final w = await widget.session.call('GET', '/wallet');
      if (!mounted) return;
      setState(() {
        gifts = ((g['data'] as List).cast<Map<String, dynamic>>());
        balance = (w['balance'] as num).toInt();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showError(context, e);
    }
  }

  bool _affords(Map<String, dynamic> g) => balance == null || (g['coins'] as num) <= balance!;

  void _short(Map<String, dynamic> g) {
    final need = (g['coins'] as num).toInt() - (balance ?? 0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not enough coins. You need $need more. Add coins from your wallet.')));
  }

  Future<void> _send(Map<String, dynamic> g) async {
    if (sending != null) return;
    setState(() => sending = g['key'] as String);
    try {
      final r = await widget.session.call('POST', widget.path, body: {'gift': g['key']});
      if (!mounted) return;
      setState(() => balance = (r['balance'] as num).toInt());
      widget.onSent?.call((r['gift'] as Map).cast<String, dynamic>());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent ${g['name']} to @${widget.username}')));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Send a gift to @${widget.username}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(balance == null ? '' : 'Your balance: $balance coins'),
          const SizedBox(height: 12),
          if (loading)
            const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: [
                for (final g in gifts)
                  Opacity(
                    opacity: _affords(g) ? 1 : 0.45,
                    child: Card(
                    child: InkWell(
                      onTap: _affords(g) ? () => _send(g) : () => _short(g),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        sending == g['key']
                            ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                            : PhIcon(_giftIcons[g['key']] ?? Ph.card_giftcard, size: 32),
                        const SizedBox(height: 4),
                        Text(g['name'].toString()),
                        Text('${g['coins']} coins', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}
