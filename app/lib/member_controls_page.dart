import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'draft_exit_guard.dart';
import 'ph.dart';
import 'ui.dart';

/// These controls appear only when the signed-in server advertises enforcement.
/// They do not claim to make public links private or retract old messages.
class MemberControlsPage extends StatefulWidget {
  const MemberControlsPage({super.key, required this.session});
  final Session session;
  @override
  State<MemberControlsPage> createState() => _MemberControlsPageState();
}
class _MemberControlsPageState extends State<MemberControlsPage> {
  late final String? accountOwner;
  bool get active=>accountOwner!=null && widget.session.user?['public_id']==accountOwner;
  void accountChanged(){if(!active && mounted)setState((){current=null;saved=false;needsReload=true;error=t_("Sign in again to view this account's settings.");});}
  @override
  void dispose(){widget.session.removeListener(accountChanged);super.dispose();}
  Map<String, dynamic>? current;
  String audience = 'everyone';
  bool sharing = true;
  bool loading = false;
  bool saving = false;
  bool needsReload = false;
  bool saved = false;
  String? error;
  int generation = 0;
  bool get changed => current != null && (current!['comments_from'] != audience || current!['share_to_chat'] != sharing);
  @override
  void initState() { super.initState();accountOwner=widget.session.user?['public_id'] as String?;widget.session.addListener(accountChanged);load(); }
  Map<String,dynamic> parse(dynamic response) {
    final value = (response as Map)['controls'];
    if (value is! Map || !['everyone','following','nobody'].contains(value['comments_from']) || value['share_to_chat'] is! bool || value['revision'] is! int) throw const FormatException();
    return value.cast<String,dynamic>();
  }
  Future<void> load() async {
    if (!active || loading || saving) return;
    final request = ++generation;
    final owner = widget.session.user?['public_id'];
    setState(() { loading = true; error = null; });
    try {
      final value = parse(await widget.session.call('GET','/auth/me/controls'));
      if (!mounted || !active || request != generation || owner != widget.session.user?['public_id']) return;
      setState(() { current = value; audience = value['comments_from']; sharing = value['share_to_chat']; needsReload = false; saved = false; });
    } catch (e) {
      if (mounted && active && request == generation) setState(() => error = e is ApiError ? e.message : t_('Settings could not be loaded.'));
    } finally { if (mounted && request == generation) setState(() => loading = false); }
  }
  Future<void> save() async {
    if (!active || saving || loading || needsReload || !changed) return;
    final owner = widget.session.user?['public_id'];
    final body = {'revision':current!['revision'],'comments_from':audience,'share_to_chat':sharing};
    setState(() { saving = true; error = null; saved = false; });
    try {
      final value = parse(await widget.session.call('PATCH','/auth/me/controls',body:body));
      if (!mounted || !active || owner != widget.session.user?['public_id']) return;
      setState(() { current = value; audience = value['comments_from']; sharing = value['share_to_chat']; saved = true; });
    } catch (e) {
      if (mounted && active) setState(() { error = e is ApiError ? e.message : t_('Settings result is unconfirmed. Reload to check before changing them again.'); needsReload = true; });
    } finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final enabled = active && current != null && !loading && !saving && !needsReload;
    return DraftExitGuard(hasChanges: changed, busy: saving, busyMessage:'Your settings are still being saved.', child: Scaffold(
      appBar: AppBar(toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 110 : 56, title:Text(t_('Comments and sharing'),maxLines:3,style:const TextStyle(fontSize:18)),actions:[TextButton(onPressed:enabled && changed ? save : null,child:Text(t_('Save')))]),
      body: ListView(padding:const EdgeInsets.fromLTRB(16,8,16,32),children:[
        if (loading || saving) const LinearProgressIndicator(),
        if (error != null) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(error!),TextButton(onPressed:!active || loading || saving ? null : load,child:Text(t_(needsReload?'Reload current settings':'Try again')))])),
        if (saved) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(t_('Settings saved.'))),
        if (current != null) ...[
          Padding(padding:const EdgeInsets.only(top:16,bottom:8),child:Text(t_('Who can comment on your posts and reels'),style:Theme.of(context).textTheme.titleMedium)),
          Text(t_('This limits new comments and replies. Existing comments stay visible. You can still comment on your own posts.')),
          for (final item in [('everyone','Everyone'),('following','People you follow'),('nobody','Nobody else')]) ListTile(
            contentPadding:EdgeInsets.zero, title:Text(t_(item.$2)), trailing:PhIcon(audience==item.$1?'check-circle-fill':'circle',size:24),
            onTap:enabled?()=>setState(() { audience=item.$1;saved=false; }):null,
          ),
          const Divider(height:32),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(t_('Allow sharing to Sanjaal chats')),value:sharing,onChanged:enabled?(value)=>setState(() { sharing=value;saved=false; }):null),
          Text(t_('When off, other members cannot send new copies of your posts through Share to chat. You can still share your own posts. Public links and earlier messages are not removed.')),
        ],
      ]),
    ));
  }
}
