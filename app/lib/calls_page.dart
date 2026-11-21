import 'glass/glass_app_bar.dart';
import 'session_bound_state.dart';
import 'dart:async';
import 'ph.dart';
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

class _CallsPageState extends State<CallsPage> with SessionBoundState<CallsPage> {
  @override Session get viewSession => widget.session;

  List<Map<String, dynamic>> calls = [];
  bool loading = true;
  bool reading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if(!sessionActive || reading || !mounted) return;
    setState(()=>reading=true);
    try {
      final j = await widget.session.call('GET', '/calls') as Map<String, dynamic>;
      final rows=(j['data'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(rows.any((v)=>v['conversation_id'] is! String || (v['conversation_id'] as String).trim().isEmpty || v['created_at'] is! String || v['duration_s'] is! num || (v['direction']=='incoming' && v['caller'] is! Map))) throw const FormatException('Invalid calls');
      if (mounted && sessionActive) setState(() { calls=rows; error=null; });
    } catch (e) {
      if (mounted && sessionActive) setState(() => error=e is ApiError?t_(e.message):t_('Calls could not be loaded.'));
    } finally {
      if(mounted && sessionActive) setState((){loading=false;reading=false;});
    }
  }

  @override void sessionRetired(){calls=[];error=null;}
  String _length(int s) => s <= 0 ? '' : (s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s');

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return retiredSessionView();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Calls')), actions:[IconButton(tooltip:t_('Refresh'),onPressed:reading?null:_load,icon:const PhIcon('arrow-clockwise'))]),
      body: Column(children:[
        if(error!=null && calls.isNotEmpty) RefreshReadNotice(onRetry:reading?null:_load),
        Expanded(child:RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(physics:const AlwaysScrollableScrollPhysics(),children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : calls.isEmpty
                ? ListView(physics:const AlwaysScrollableScrollPhysics(),children: [EmptyState(icon: Ph.call_outlined, title: error ?? t_('No calls yet'), hint: error == null ? t_('Start a call from any chat.') : null, action: error == null ? null : OutlinedButton(onPressed: reading?null:_load, child: Text(t_('Try again'))))])
                : ListView.separated(
                    physics:const AlwaysScrollableScrollPhysics(),
                    itemCount: calls.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = calls[i];
                      final incoming = c['direction'] == 'incoming';
                      final missed = incoming && (c['status'] == 'missed' || c['status'] == 'declined');
                      final video = c['kind'] == 'video';
                      final who = incoming ? (c['caller'] as Map)['name'] ?? (c['caller'] as Map)['username'] : c['title'];
                      return ListTile(
                        leading: Avatar(user: incoming ? (c['caller'] as Map).cast<String, dynamic>() : {'name': c['title'] ?? 'Call'}),
                        title: Text('${c['title'] ?? who}', style: TextStyle(color: missed ? scheme.error : null)),
                        subtitle: Row(children: [
                          PhIcon(incoming ? Ph.call_received : Ph.call_made, size: 14, color: missed ? scheme.error : scheme.outline),
                          const SizedBox(width: 4),
                          Expanded(child: Text([t_(missed ? 'Missed' : (c['status'] == 'answered' || c['status'] == 'ended' ? (incoming ? 'Incoming' : 'Outgoing') : (incoming ? 'Incoming' : 'No answer'))), ago(c['created_at'] as String), _length((c['duration_s'] as num).toInt())].where((e) => e.isNotEmpty).join('  '))),
                        ]),
                        trailing: IconButton(
                          icon: PhIcon(video ? Ph.videocam_outlined : Ph.call_outlined),
                          tooltip: video ? t_('Video call') : t_('Voice call'),
                          onPressed: () async {
                            if(!sessionActive)return;
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => CallPage(session: widget.session, conversationId: c['conversation_id'] as String, title: '${c['title'] ?? 'Call'}', video: video),
                            ));
                            if (mounted && sessionActive) _load();
                          },
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}

/// Full screen ring for an incoming call.
class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key, required this.session, required this.call});
  final Session session;
  final Map<String, dynamic> call;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> with SessionBoundState<IncomingCallPage> {
  @override Session get viewSession => widget.session;
  bool busy = false;
  bool checking = false;
  String phase = 'ringing';
  bool? requestedAccept;
  Timer? expiry;
  String? error;

  @override void initState() {
    super.initState();
    final end = _deadline(widget.call);
    if (widget.call['status'] != 'ringing' || end == null || !end.isAfter(DateTime.now())) {
      phase = 'unknown';
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && sessionActive) _checkStatus(); });
    } else {
      _armExpiry(widget.call);
    }
  }
  @override void dispose() { expiry?.cancel(); super.dispose(); }
  @override void sessionRetired() { expiry?.cancel(); phase = 'unknown'; error = null; }

  DateTime? _deadline(Map<String, dynamic> row) => DateTime.tryParse('${row['ring_expires_at'] ?? ''}') ??
      DateTime.tryParse('${row['created_at'] ?? ''}')?.add(const Duration(seconds: 40));

  void _armExpiry(Map<String, dynamic> row) {
    expiry?.cancel();
    final end = _deadline(row);
    if (end == null) return;
    final wait = end.difference(DateTime.now());
    expiry = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (mounted && sessionActive && !busy) _checkStatus();
    });
  }

  Map<String, dynamic> _validated(Object? value) {
    if (value is! Map || value['call'] is! Map) throw const FormatException('Missing call');
    final row = (value['call'] as Map).cast<String, dynamic>();
    if (row['public_id'] != widget.call['public_id'] ||
        row['conversation_id'] != widget.call['conversation_id'] ||
        row['kind'] != widget.call['kind'] ||
        !const ['ringing', 'answered', 'declined', 'missed', 'ended'].contains(row['status'])) {
      throw const FormatException('Mismatched call state');
    }
    if (row['status'] == 'ringing') {
      final end = DateTime.tryParse('${row['ring_expires_at'] ?? ''}');
      if (end == null || !end.isAfter(DateTime.now())) {
        throw const FormatException('Stale ringing snapshot');
      }
    }
    return row;
  }

  Future<void> _checkStatus() async {
    if (!mounted || !sessionActive || busy) return;
    expiry?.cancel();
    setState(() { busy = true; checking = true; phase = 'unknown'; error = null; });
    try {
      final value = await widget.session.call('GET', '/calls/${widget.call['public_id']}');
      final row = _validated(value);
      if (!mounted || !sessionActive) return;
      setState(() { phase = row['status'] as String; error = null; });
      if (phase == 'ringing') _armExpiry(row);
    } catch (_) {
      if (mounted && sessionActive) setState(() {
        phase = 'unknown';
        error = t_('Call status could not be checked. No action was repeated.');
      });
    } finally {
      if (mounted && sessionActive) setState(() { busy = false; checking = false; });
    }
  }

  void _join() {
    if (!mounted || !sessionActive || phase != 'answered' || requestedAccept != true) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => CallPage(
        session: widget.session,
        conversationId: widget.call['conversation_id'] as String,
        title: '${widget.call['title'] ?? 'Call'}',
        video: widget.call['kind'] == 'video',
        callId: widget.call['public_id'] as String,
      ),
    ));
  }

  Future<void> _answer(bool accept) async {
    if (!sessionActive || busy || phase != 'ringing') return;
    expiry?.cancel();
    requestedAccept = accept;
    setState(() { busy = true; error = null; });
    try {
      final value = await widget.session.call('POST', '/calls/${widget.call['public_id']}/action',
        body: {'action': accept ? 'answer' : 'decline'});
      final row = _validated(value);
      if (!mounted || !sessionActive) return;
      setState(() { busy = false; phase = row['status'] as String; });
      if (accept && phase == 'answered') { _join(); return; }
      if (!accept && phase == 'declined') { Navigator.of(context).pop(); return; }
      // HTTP success is not proof that the requested transition happened.
      await _checkStatus();
    } catch (_) {
      if (!mounted || !sessionActive) return;
      setState(() { busy = false; phase = 'unknown'; });
      // Check once, read-only for this exact call. Never resend the action.
      await _checkStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    final caller = (widget.call['caller'] as Map).cast<String, dynamic>();
    final video = widget.call['kind'] == 'video';
    final description = checking ? 'Checking call status'
        : phase == 'ringing' ? (video ? 'Incoming video call' : 'Incoming voice call')
        : phase == 'answered' ? 'This call was answered.'
        : phase == 'declined' ? 'This call was declined.'
        : phase == 'missed' ? 'This call was missed.'
        : phase == 'ended' ? 'This call has ended.'
        : 'Call status is unknown.';
    return Scaffold(
      backgroundColor: const Color(0xFF14152E),
      body: SafeArea(child: Column(children: [
        Expanded(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Avatar(user: caller, radius: 56),
            const SizedBox(height: 20),
            Text('${caller['name'] ?? caller['username']}', textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(t_(description), textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16))),
            if (phase == 'answered') Padding(padding: const EdgeInsets.only(top: 16),
              child: Text(t_('You are not connected on this screen.'), textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white))),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 16),
              child: Semantics(liveRegion: true, child: Text(error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)))),
            if (busy) const Padding(padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: Colors.white)),
          ]),
        ))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: phase == 'ringing' ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final accept in [false, true]) Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: [
              IconButton.filled(
                tooltip: t_(accept ? 'Accept' : 'Decline'),
                style: IconButton.styleFrom(backgroundColor: accept ? const Color(0xFF3BE276) : Colors.red,
                  foregroundColor: accept ? Colors.black : Colors.white, minimumSize: const Size(72, 72)),
                onPressed: busy ? null : () => _answer(accept),
                icon: PhIcon(accept ? (video ? Ph.videocam : Ph.call) : 'phone-x-fill', size: 32),
              ),
              const SizedBox(height: 8),
              Text(t_(accept ? 'Accept' : 'Decline'), textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            ])),
          ]) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (phase == 'unknown') FilledButton(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), onPressed: busy ? null : _checkStatus,
              child: Text(t_('Check call status'), textAlign: TextAlign.center)),
            if (phase == 'answered' && requestedAccept == true) FilledButton(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), onPressed: busy ? null : _join,
              child: Text(t_('Join this call'), textAlign: TextAlign.center)),
            TextButton(onPressed: () => Navigator.of(context).pop(),
              child: Text(t_('Close'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
          ]),
        ),
      ])),
    );
  }
}
