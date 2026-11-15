import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'call_page.dart';
import 'ui.dart';

/// Recent calls. Tap a row to call that chat back.
class CallsPage extends StatefulWidget {
  const CallsPage({super.key, required this.session});
  final Session session;
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  List<Map<String, dynamic>> calls = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/calls') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          calls = (j['data'] as List).cast<Map<String, dynamic>>();
          error = null;
          loading = false;
        });
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    }
  }

  String _length(int s) => s <= 0 ? '' : (s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t_('Calls'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : calls.isEmpty
                ? ListView(children: [EmptyState(icon: Icons.call_outlined, title: error ?? 'No calls yet', hint: 'Start a call from any chat.')])
                : ListView.separated(
                    itemCount: calls.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = calls[i];
                      final incoming = c['direction'] == 'incoming';
                      final missed = incoming && (c['status'] == 'missed' || c['status'] == 'declined');
                      final video = c['kind'] == 'video';
                      final who = incoming ? (c['caller'] as Map)['name'] ?? (c['caller'] as Map)['username'] : c['title'];
                      return ListTile(
                        leading: Avatar(user: (c['caller'] as Map).cast<String, dynamic>()),
                        title: Text('${c['title'] ?? who}', style: TextStyle(color: missed ? scheme.error : null)),
                        subtitle: Row(children: [
                          Icon(incoming ? Icons.call_received : Icons.call_made, size: 14, color: missed ? scheme.error : scheme.outline),
                          const SizedBox(width: 4),
                          Text([missed ? 'Missed' : (c['status'] == 'answered' || c['status'] == 'ended' ? (incoming ? 'Incoming' : 'Outgoing') : (incoming ? 'Incoming' : 'No answer')), ago(c['created_at'] as String), _length((c['duration_s'] as num).toInt())].where((e) => e.isNotEmpty).join('  ')),
                        ]),
                        trailing: IconButton(
                          icon: Icon(video ? Icons.videocam_outlined : Icons.call_outlined),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CallPage(session: widget.session, conversationId: c['conversation_id'] as String, title: '${c['title'] ?? 'Call'}', video: video),
                          )),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Full screen ring for an incoming call.
class IncomingCallPage extends StatelessWidget {
  const IncomingCallPage({super.key, required this.session, required this.call});
  final Session session;
  final Map<String, dynamic> call;

  Future<void> _answer(BuildContext context, bool accept) async {
    final nav = Navigator.of(context);
    try {
      await session.call('POST', '/calls/${call['public_id']}/action', body: {'action': accept ? 'answer' : 'decline'});
    } catch (_) {}
    if (!accept) {
      nav.pop();
      return;
    }
    nav.pushReplacement(MaterialPageRoute(
      builder: (_) => CallPage(
        session: session,
        conversationId: call['conversation_id'] as String,
        title: '${call['title'] ?? 'Call'}',
        video: call['kind'] == 'video',
        callId: call['public_id'] as String,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final caller = (call['caller'] as Map).cast<String, dynamic>();
    final video = call['kind'] == 'video';
    return Scaffold(
      backgroundColor: const Color(0xFF14152E),
      body: SafeArea(
        child: Column(children: [
          const Spacer(flex: 2),
          Avatar(user: caller, radius: 56),
          const SizedBox(height: 20),
          Text('${caller['name'] ?? caller['username']}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(video ? 'Incoming video call' : 'Incoming voice call', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const Spacer(flex: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(72, 72)),
                  onPressed: () => _answer(context, false),
                  icon: const Icon(Icons.call_end, size: 32),
                ),
                const SizedBox(height: 8),
                const Text('Decline', style: TextStyle(color: Colors.white70)),
              ]),
              Column(children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF3BE276), foregroundColor: Colors.black, minimumSize: const Size(72, 72)),
                  onPressed: () => _answer(context, true),
                  icon: Icon(video ? Icons.videocam : Icons.call, size: 32),
                ),
                const SizedBox(height: 8),
                const Text('Accept', style: TextStyle(color: Colors.white70)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
