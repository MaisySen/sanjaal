import 'group_ownership_page.dart';
import 'media_visibility.dart';
import 'glass/glass_sheet.dart';
import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'dart:async';
import 'draft_exit_guard.dart';
import 'group_draft_store.dart';
import 'dart:convert' show jsonEncode;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'call_page.dart';
import 'profile_pages.dart' show UserProfilePage;
import 'calls_page.dart';
import 'rooms_page.dart';
import 'ui.dart';
import 'voice.dart';
import 'share_post.dart';
import 'post_page.dart';
import 'private_media_image.dart';
import 'conversation_receipt.dart';

String kindLabel(Object? kind, Object? body) {
  if (kind == 'image') return 'Photo';
  if (kind == 'voice') return 'Voice message';
  if (kind == 'post') return 'Shared a post';
  return '${body ?? ''}';
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, required this.session, this.active = true});
  final Session session;
  final bool active;
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late final Session _session;
  late final String? _owner;
  late final int _sessionGeneration;
  bool _retired = false;
  bool _opening = false;
  bool _settingsBusy = false;
  bool _settingsNeedRead = false;
  bool _settingsRetryingRead = false;
  bool _creationNeedRead = false;
  static const _settingKeys = ['pinned', 'muted', 'archived'];
  bool get _active=>mounted && !_retired && identical(widget.session,_session) && _owner!=null && widget.session.user?['public_id']==_owner && widget.session.generation==_sessionGeneration;
  bool get _canEnter=>_active && widget.active && ModalRoute.of(context)?.isCurrent==true;
  int? _entryReadVersion;
  bool get _entryReading=>(_entryReadVersion==_loadVersion || _creationNeedRead) && _readingArchive!=null;
  BuildContext? _menuContext;
  void _accountChanged(){if(!_active && mounted){
    _retired = true;
    ++_loadVersion;timer?.cancel();
    final menu=_menuContext;
    if(menu!=null && menu.mounted && ModalRoute.of(menu)?.isCurrent==true)Navigator.of(menu).pop();
    setState(() { convos=[];error=null;_settingsBusy=false;_settingsNeedRead=false;_settingsRetryingRead=false;_entryReadVersion=null;_creationNeedRead=false; });
  }}
  List<Map<String, dynamic>> convos = [];
  bool loading = true;
  String? error;
  Timer? timer;
  bool showArchived = false;
  int _loadVersion = 0;
  bool? _readingArchive;

  @override
  void initState() {
    super.initState();
    _session=widget.session;_owner=widget.session.user?['public_id'] as String?;_sessionGeneration=widget.session.generation;
    widget.session.addListener(_accountChanged);
    _load();
    timer = Timer.periodic(const Duration(seconds: 12), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (_active && widget.active && ModalRoute.of(context)?.isCurrent == true &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        _load(quiet: true);
      }
    });
  }

  @override
  void didUpdateWidget(ChatsPage old) {
    super.didUpdateWidget(old);
    _accountChanged();
    if (widget.active && !old.active) _load(quiet: true);
  }

  @override
  void dispose() {
    _session.removeListener(_accountChanged);
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false, bool force = false, bool afterSetting = false}) async {
    if(!mounted || !_active || (_settingsBusy && !afterSetting) || (!force && _readingArchive==showArchived)) return;
    final archived=showArchived;
    _readingArchive=archived;
    final version = ++_loadVersion;
    if (_creationNeedRead) setState(() => loading = convos.isEmpty);
    if (_settingsNeedRead && !_settingsBusy) setState(() => _settingsRetryingRead = true);
    try {
      final j = await widget.session.call('GET', '/conversations', query: showArchived ? {'archived': '1'} : null) as Map<String, dynamic>;
      if (!mounted || !_active || version != _loadVersion) return;
      final rows=(j['data'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(rows.any((c)=>c['public_id'] is! String || (c['public_id'] as String).trim().isEmpty || (c['last_message']!=null && c['last_message'] is! Map) || (c['unread']!=null && c['unread'] is! num) ||
          _settingKeys.any((key) => (_settingsNeedRead || c[key] != null) && c[key] is! bool))) {
        throw const FormatException('Invalid inbox');
      }
      setState(() { convos=rows; error=null; _settingsNeedRead=false; if(!archived)_creationNeedRead=false; });
    } catch (e) {
      if (mounted && _active && version == _loadVersion && !quiet) setState(() => error=e is ApiError?t_(e.message):t_('Chats could not be loaded.'));
    } finally {
      if(version==_loadVersion) _readingArchive=null;
      if (mounted && _active && version == _loadVersion && _settingsRetryingRead) setState(() => _settingsRetryingRead = false);
      if (mounted && _active && version == _loadVersion && loading) setState(() => loading = false);
    }
  }

  String _preview(Map<String, dynamic>? last) {
    if (last == null) return t_('No messages yet');
    if(['image','voice','post'].contains(last['kind'])) return t_(kindLabel(last['kind'],last['body']));
    return (last['body']??'').toString();
  }

  Future<void> _changeSetting(String id, Map<String, dynamic> body) async {
    if (!_active || _settingsBusy || _settingsNeedRead) return;
    // Retire reads begun before the change. Other reads wait for reconciliation.
    ++_loadVersion;
    _readingArchive = null;
    setState(() { _settingsBusy = true; _settingsNeedRead = true; });
    try {
      try {
        await widget.session.call('PATCH', '/conversations/$id/settings', body: body);
      } catch (e) {
        if (mounted && _active) showError(context, e);
      }
      // A failed/lost reply is not proof that the setting stayed unchanged.
      if (_active) await _load(force: true, afterSetting: true);
    } finally {
      if (_active) setState(() => _settingsBusy = false);
    }
  }

  Future<void> _menu(Map<String, dynamic> c) async {
    if (!_canEnter || _opening || _settingsBusy || _settingsNeedRead || !convos.any((row) => identical(row, c))) return;
    _opening = true;
    var submitted = false;
    final id = c['public_id'];
    try {
      await showReviewedGlassSheet<void>(
        context: context,
        builder: (ctx) {
          _menuContext = ctx;
          Future<void> change(Map<String, dynamic> body) async {
            if (!_active || submitted || _settingsBusy || _settingsNeedRead || !ctx.mounted ||
                ModalRoute.of(ctx)?.isCurrent != true ||
                !convos.any((row) => identical(row, c))) {
              return;
            }
            submitted = true;
            Navigator.of(ctx).pop();
            await _changeSetting(id as String, body);
          }
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: PhIcon(c['pinned'] == true ? Ph.push_pin : Ph.push_pin_outlined), title: Text(t_(c['pinned'] == true ? 'Unpin' : 'Pin to top')), onTap: () => change({'pinned': c['pinned'] != true})),
              ListTile(leading: PhIcon(c['muted'] == true ? Ph.notifications_off : Ph.notifications_off_outlined), title: Text(t_(c['muted'] == true ? 'Unmute' : 'Mute')), onTap: () => change({'muted': c['muted'] != true})),
              ListTile(leading: PhIcon(c['archived'] == true ? Ph.unarchive_outlined : Ph.archive_outlined), title: Text(t_(c['archived'] == true ? 'Unarchive' : 'Archive')), onTap: () => change({'archived': c['archived'] != true})),
            ]),
          );
        },
      );
    } finally {
      _menuContext = null;
      _opening = false;
    }
  }

  Future<void> _openAux(Widget page) async {
    if (!_canEnter || _opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } finally {
      _opening = false;
    }
  }

  Future<void> _refreshAfterEntry() async {
    if (!_active) return;
    setState(() => _entryReadVersion = _loadVersion + 1);
    await _load(force: true);
  }

  Future<void> _open(Map<String, dynamic> c) async {
    if (!_canEnter || _opening || !convos.any((row) => identical(row, c))) return;
    await _openAux(ChatPage(session: widget.session, convo: c));
    if (_active) _refreshAfterEntry();
  }

  Future<void> _new() async {
    if (!_canEnter || _opening || _entryReading || _creationNeedRead) return;
    final route = ModalRoute.of(context)!;
    var checkInbox = false;
    var receivedConversation = false;
    _opening = true;
    try {
      final c = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => NewChatPage(session: widget.session, onUncertain: () => checkInbox = true)));
      receivedConversation = c != null;
      if (!mounted || !_canEnter || !route.isCurrent || !identical(ModalRoute.of(context), route) || c == null) return;
      // The child checked its receipt. An inbox read need not delay opening it.
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(session: widget.session, convo: c)));
    } finally {
      _opening = false;
      // Reconcile a returned receipt or uncertainty, not an untouched cancel.
      if (_active && (receivedConversation || checkInbox)) {
        if (checkInbox) {
          setState(() {
            _creationNeedRead = true;
            if (showArchived) {
              showArchived = false;
              convos = [];
              error = null;
              loading = true;
            }
          });
        }
        _refreshAfterEntry();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!_active)return Scaffold(appBar:ReviewedAppBar(title:Text(t_('Chats'))),body:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This chat belongs to another signed-in session. Close it and sign in again to continue.'))));
    return Scaffold(
      appBar: ReviewedAppBar(
        title: Text(t_(showArchived ? 'Archived' : 'Chats')),
        actions: [
          IconButton(tooltip: t_('New chat'), icon: const PhIcon('note-pencil'), onPressed: _entryReading || _creationNeedRead ? null : _new),
          PopupMenuButton<String>(
            tooltip: t_('More'),
            enabled: !_settingsBusy && !_settingsRetryingRead && !_creationNeedRead,
            onSelected: (_) {
              if(!_canEnter || _opening || _settingsBusy || _settingsRetryingRead || _creationNeedRead)return;
              setState(() {
                showArchived = !showArchived;
                convos = [];
                error = null;
                loading = true;
              });
              _load();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(t_(showArchived ? 'Back to chats' : 'Archived chats'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_settingsBusy || _settingsRetryingRead) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Semantics(liveRegion: true, child: Text(t_('Updating chat settings')))),
        ])),
        if (_entryReading) const LinearProgressIndicator(),
        if(error!=null && convos.isNotEmpty) RefreshReadNotice(onRetry:_settingsBusy || _settingsRetryingRead || (_creationNeedRead && _entryReading) ? null : ()=>_load()),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton.icon(
              onPressed: () => _openAux(CallsPage(session: widget.session)),
              icon: const PhIcon('phone', size: 20), label: Text(t_('Calls')),
            ),
            TextButton.icon(
              onPressed: () => _openAux(RoomsPage(session: widget.session)),
              icon: const PhIcon('waveform', size: 20), label: Text(t_('Live rooms')),
            ),
          ])),
        ),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(physics:const AlwaysScrollableScrollPhysics(),children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : convos.isEmpty
                ? ListView(physics:const AlwaysScrollableScrollPhysics(),padding: const EdgeInsets.only(bottom: 100), children: [EmptyState(
                    icon: error != null ? Ph.error_outline : Ph.forum,
                    title: error ?? t_(showArchived ? 'No archived chats' : 'Start a conversation'),
                    hint: error != null || showArchived ? null : t_('Find someone by name or username.'),
                    action: error != null
                        ? OutlinedButton(onPressed: _load, child: Text(t_('Try again')))
                        : showArchived ? null : FilledButton.icon(onPressed: _entryReading || _creationNeedRead ? null : _new, icon: const PhIcon('note-pencil', size: 18), label: Text(t_('New chat'))),
                  )])
                : ListView.separated(
                    physics:const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: convos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = convos[i];
                      final last = c['last_message'] as Map<String, dynamic>?;
                      final unread = (c['unread'] as num?)?.toInt() ?? 0;
                      final title = (c['title'] ?? 'Chat').toString();
                      final scheme = Theme.of(context).colorScheme;
                      return InkWell(
                        onTap: () => _open(c),
                        onLongPress: _settingsBusy || _settingsNeedRead ? null : () => _menu(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(children: [
                            c['type'] == 'group'
                                ? CircleAvatar(radius: 24, backgroundColor: scheme.surfaceContainerHigh, child: PhIcon('users-three', color: scheme.onSurfaceVariant))
                                : Avatar(user: {'name': title, 'username': title, 'avatar_url': c['avatar_url']}, radius: 24),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600))),
                                  if (c['pinned'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: PhIcon('push-pin-fill', size: 13, color: scheme.onSurfaceVariant)),
                                  if (c['muted'] == true) Padding(padding: const EdgeInsets.only(left: 4), child: PhIcon('bell-slash', size: 13, color: scheme.onSurfaceVariant)),
                                ]),
                                const SizedBox(height: 2),
                                Text(_preview(last), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? scheme.onSurface : scheme.onSurfaceVariant, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              if (last != null) Text(ago(last['created_at'].toString()), style: TextStyle(fontSize: 12, color: unread > 0 ? scheme.primary : scheme.onSurfaceVariant)),
                              if (unread > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Badge(label: Text('$unread'), backgroundColor: c['muted'] == true ? scheme.outline : scheme.primary, textColor: scheme.onPrimary)),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key, required this.session, this.onUncertain});
  final Session session;
  final VoidCallback? onUncertain;
  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final q = TextEditingController();
  final title = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> results = [];
  final picked = <String, Map<String, dynamic>>{};
  bool group = false, busy = false, searched = false, searching = false;
  bool _completed = false, _uncertain = false;
  void _noteUncertain() { _uncertain = true; widget.onUncertain?.call(); }
  bool _storing=false;
  BuildContext? _groupDraftDialog;
  GroupDraft? _savedGroup;
  String? _savedGroupFingerprint;
  String get _groupFingerprint=>jsonEncode([title.text,picked.values.map((p)=>[p['public_id'],p['username'],p['name']??'']).toList()]);
  Future<void> _saveGroup()async{
    if(_locked || !group || _storing)return;
    final text=title.text;final people=picked.values.map((p)=><String,dynamic>{'public_id':p['public_id'],'username':p['username'],'name':p['name']??''}).toList();final fingerprint=_groupFingerprint;
    setState(()=>_storing=true);
    try{
      final saved=await const GroupDraftStore().save(_owner!,title:text,people:people,expectedRevision:_savedGroup?.revision);
      if(mounted && _active){setState((){_savedGroup=saved;_savedGroupFingerprint=fingerprint;});showInfo(context,t_('Group draft saved on this device. No group was created.'));}
    }catch(e){if(mounted && _active)showError(context,e);}
    finally{if(mounted)setState(()=>_storing=false);}
  }
  Future<void> _openGroup()async{
    if(_locked || _storing)return;
    if(picked.isNotEmpty || title.text.isNotEmpty){showInfo(context,t_('Save or clear this group before opening the saved copy.'));return;}
    setState(()=>_storing=true);
    try{
      final saved=await const GroupDraftStore().read(_owner!);
      if(!mounted || !_active)return;
      if(saved==null){showInfo(context,t_('No saved group draft.'));return;}
      setState((){group=true;title.text=saved.title;picked.clear();for(final p in saved.people){picked[p['username'] as String]=p;}_savedGroup=saved;_savedGroupFingerprint=_groupFingerprint;_uncertain=saved.attempted;if(_uncertain)widget.onUncertain?.call();startError=saved.attempted?t_('This group may already exist. Check Chats before starting it again.'):null;});
    }catch(e){if(mounted && _active)showError(context,e);}
    finally{if(mounted)setState(()=>_storing=false);}
  }
  Future<void> _deleteGroupDraft()async{
    final draft=_savedGroup;if(draft==null || !_active || busy || _storing)return;
    final yes=await showDialog<bool>(context:context,builder:(c){_groupDraftDialog=c;return AlertDialog(scrollable:true,title:Text(t_('Delete saved group draft?')),content:Text(t_('This removes only the local plan, not a group that may already exist. Check Chats before starting it again.')),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(t_('Keep'))),TextButton(onPressed:()=>Navigator.pop(c,true),child:Text(t_('Delete')))]);});
    _groupDraftDialog=null;
    if(yes!=true || !mounted || !_active || _savedGroup!=draft)return;
    setState(()=>_storing=true);
    try{await const GroupDraftStore().remove(_owner!,draft);if(mounted && _active)setState((){_savedGroup=null;_savedGroupFingerprint=null;title.clear();picked.clear();_uncertain=false;startError=null;});}
    catch(e){if(mounted && _active)showError(context,e);}
    finally{if(mounted)setState(()=>_storing=false);}
  }

  String? searchError, startError;
  int _seq = 0;
  late final Session _session;
  late final String? _owner;
  late final int _sessionGeneration;
  bool get _active=>identical(widget.session,_session) && _owner!=null && widget.session.user?['public_id']==_owner && widget.session.generation==_sessionGeneration;
  bool get _locked => !mounted || !_active || busy || _storing || _uncertain || _completed || ModalRoute.of(context)?.isCurrent != true;
  @override void initState(){
    super.initState();_session=widget.session;_owner=widget.session.user?['public_id'] as String?;_sessionGeneration=widget.session.generation;
    widget.session.addListener(_accountChanged);
  }
  void _accountChanged(){
    if(_active || !mounted)return;
    ++_seq;_debounce?.cancel();
    final dialog=_groupDraftDialog;_groupDraftDialog=null;
    if(dialog!=null && dialog.mounted && ModalRoute.of(dialog)?.isCurrent==true)Navigator.of(dialog).pop();
    setState((){results=[];picked.clear();q.clear();title.clear();searching=false;busy=false;startError=null;searchError=null;_savedGroup=null;_savedGroupFingerprint=null;});
  }

  @override
  void dispose() {
    _session.removeListener(_accountChanged);
    ++_seq;
    _debounce?.cancel();
    q.dispose();
    title.dispose();
    super.dispose();
  }

  void _changed(String value) {
    if(_locked)return;
    final seq = ++_seq; // Invalidate immediately, not when the debounce fires.
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      results = [];
      searchError = null;
      searched = false;
      searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query, seq));
  }

  Future<void> _search(String query, int seq) async {
    if(!_active)return;
    try {
      final response = await widget.session.call('GET', '/users/search', query: {'q': query});
      final users = ((response as Map)['users'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(users.any((u)=>u['public_id'] is! String || (u['public_id'] as String).trim().isEmpty || u['username'] is! String || (u['username'] as String).trim().isEmpty) || users.map((u)=>u['public_id']).toSet().length!=users.length || users.map((u)=>u['username']).toSet().length!=users.length) throw const FormatException('Invalid member identity');
      if (!mounted || !_active || seq != _seq) return;
      setState(() { results = users; searched = true; searching = false; searchError = null; });
    } catch (e) {
      if (!mounted || !_active || seq != _seq) return;
      setState(() {
        searching = false;
        searchError = e is ApiError ? t_(e.message) : t_('Could not load members. Try again.');
      });
    }
  }

  Future<void> _leave([Map<String, dynamic>? conversation]) async {
    if (!mounted || !_active || _completed) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      if (conversation != null) {
        setState(() {
          busy = false;
          _noteUncertain();
          startError = t_('The chat may already exist. Check Chats before starting it again.');
        });
      }
      return;
    }
    // This route owns one completion, not whichever route is on top later.
    setState(() { _completed = true; busy = false; });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_active) return;
    if (!route.isCurrent) {
      setState(() {
        _completed = false;
        if (conversation != null) {
          _noteUncertain();
          startError = t_('The chat may already exist. Check Chats before starting it again.');
        }
      });
      return;
    }
    Navigator.of(context).pop(conversation);
  }

  Future<void> _start(Map<String, dynamic> body, {Map<String, dynamic>? directRecipient}) async {
    if (_locked) return;
    if (body['type'] == 'direct' && (directRecipient == null || body['username'] != directRecipient['username'] || !results.any((user) => identical(user, directRecipient)))) return;
    final groupRecipients = [for (final person in picked.values) Map<String, dynamic>.from(person)];
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    ++_seq;
    setState(() { busy = true; searching = false; startError = null; });
    var handedToServer=false;
    try {
      if(body['type']=='group' && _savedGroup!=null){
        final saved=_savedGroup!;
        if(!widget.session.groupMemberRefsEnabled)throw const _GroupDraftServerNotReady();
        body={...body,'member_refs':saved.people.map((p)=>{'public_id':p['public_id'],'username':p['username']}).toList()};
        if(_savedGroupFingerprint!=_groupFingerprint)throw const _GroupDraftNotReady();
        // A stored username can be renamed or reassigned. Never silently add the
        // current owner of an old username in place of the originally picked ID.
        for(final person in saved.people){
          if(!mounted || !_active)return;
          final response=await widget.session.call('GET','/users/search',query:{'q':person['username'] as String}) as Map;
          if(!mounted || !_active)return;
          final matches=(response['users'] as List).whereType<Map>().where((u)=>u['username']==person['username'] && u['public_id']==person['public_id']);
          if(matches.length!=1)throw const _GroupDraftMemberChanged();
        }
        final marked=await const GroupDraftStore().markAttempt(_owner!,saved);
        if(!mounted || !_active)return;
        setState(()=>_savedGroup=marked);
      }
      if(!mounted || !_active)return;
      handedToServer=true;
      final response = await widget.session.call('POST', '/conversations', body: body);
      final conversation = body['type'] == 'direct'
          ? checkedDirectConversation(response, _owner!, directRecipient!)
          : checkedGroupConversation(response, _owner!, groupRecipients, body['title'] as String);
      if (conversation['public_id'] is! String || (conversation['public_id'] as String).isEmpty) throw const FormatException();
      if (mounted && _active) await _leave(conversation);
    } catch (e) {
      if (!mounted || !_active) return;
      if(e is _GroupDraftNotReady || e is _GroupDraftMemberChanged || e is _GroupDraftServerNotReady){
        setState((){busy=false;startError=t_(e is _GroupDraftServerNotReady?'Saved groups need the member-check server update. Your draft is still here.':e is _GroupDraftNotReady?'Save group changes before creating it.':'A selected person changed or is unavailable. Remove and find them again before creating this group.');});return;
      }
      if(!handedToServer && _savedGroup?.attempted!=true){setState((){busy=false;startError=t_('Could not verify the saved group. Nothing was created. Try again.');});return;}
      // Groups have no server replay key. A lost/malformed success is not a
      // rejected creation, so do not offer another POST as ordinary retry.
      final rejected = e is ApiError && e.status != null && e.status! >= 400 && e.status! < 500;
      if(rejected && _savedGroup?.attempted==true){
        try{final reset=await const GroupDraftStore().markAttempt(_owner!,_savedGroup!,attempted:false);if(!mounted || !_active)return;_savedGroup=reset;}
        catch(_){if(mounted && _active)setState((){busy=false;_noteUncertain();startError=t_('This group may already exist. Check Chats before starting it again.');});return;}
      }
      if(!mounted || !_active)return;
      setState(() {
        busy = false;
        _uncertain = !rejected;
        if (_uncertain) widget.onUncertain?.call();
        startError = rejected ? t_(e.message) : t_('The chat may already exist. Check Chats before starting it again.');
      });
    }
  }

  void _tap(Map<String, dynamic> user) {
    if (_locked || searching || searchError != null || !results.any((current) => identical(current, user))) return;
    final name = user['username'].toString();
    if (!group) { _start({'type': 'direct', 'username': name}, directRecipient: user); return; }
    if (!picked.containsKey(name) && picked.length >= 49) {
      showInfo(context, t_('Choose up to 49 people.'));
      return;
    }
    setState(() => picked.containsKey(name) ? picked.remove(name) : picked[name] = user);
  }

  Future<void> _switchMode() async {
    if (_locked) return;
    if (group && (picked.isNotEmpty || title.text.trim().isNotEmpty)) {
      final discard = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(t_('Discard this group?')),
        content: Text(t_('The name and selected people will be cleared.')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Keep editing'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Discard')))],
      ));
      if (discard != true || !mounted || !_active) return;
    }
    setState(() { group = !group; picked.clear(); title.clear(); startError = null;_savedGroup=null;_savedGroupFingerprint=null; });
  }

  @override
  Widget build(BuildContext context) {
   if(!_active)return Scaffold(appBar:ReviewedAppBar(title:Text(t_('New chat'))),body:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This chat belongs to another signed-in session. Close it and sign in again to continue.'))));
   return DraftExitGuard(
    hasChanges: !_completed && (picked.isNotEmpty || title.text.trim().isNotEmpty) && _savedGroupFingerprint!=_groupFingerprint,
    busy: (busy || _storing) && !_completed,
    busyMessage: 'Starting the conversation. Please wait.',
    child: Scaffold(
      appBar: ReviewedAppBar(title: Text(t_(group ? 'New group' : 'New chat')), actions: [
        IconButton(tooltip:t_('Open saved group draft'),onPressed:_locked?null:_openGroup,icon:const PhIcon('archive')),
        IconButton(onPressed: _locked ? null : _switchMode, icon: PhIcon(group ? Ph.person : Ph.groups), tooltip: t_(group ? 'One to one' : 'New group')),
      ]),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if(group)Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Wrap(spacing:8,children:[Tooltip(message:t_('Save group draft'),child:TextButton.icon(onPressed:_locked?null:_saveGroup,icon:const PhIcon('bookmark-simple'),label:Text(t_('Save group draft')))),if(_savedGroup!=null)Tooltip(message:t_('Delete saved group draft'),child:TextButton.icon(onPressed:busy || _storing?null:_deleteGroupDraft,icon:const PhIcon('trash'),label:Text(t_('Delete saved group draft'))))])),
          if(_savedGroup!=null)Padding(padding:const EdgeInsets.all(16),child:Text(t_('Local group plan. People are checked again before creation. Nothing starts automatically.'))),
          if(_storing)const LinearProgressIndicator(),
          if (group) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: TextField(controller: title, enabled: !_locked, onChanged: (_) => setState(() {}), maxLength: 80, decoration: InputDecoration(labelText: t_('Group name'), border: const OutlineInputBorder()))),
          if (group && picked.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [for (final entry in picked.entries) Padding(padding: const EdgeInsets.only(right: 6), child: InputChip(label: Text('@${entry.key}'), onDeleted: _locked ? null : () => setState(() => picked.remove(entry.key))))])),
          Padding(padding: const EdgeInsets.all(16), child: TextField(controller: q, enabled: !_locked, autofocus: true, onChanged: _changed, decoration: InputDecoration(prefixIcon: const Center(widthFactor: 1, heightFactor: 1, child: PhIcon('magnifying-glass', size: 22)), hintText: t_('Search by name or username'), border: const OutlineInputBorder()))),
          if (busy) Padding(padding: const EdgeInsets.all(16), child: Text(t_('Starting the conversation. Please wait.'))),
          if (startError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(startError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_uncertain) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton(onPressed: _leave, child: Text(t_('Back to Chats')))),
          if (searchError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [Text(searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)), OutlinedButton(onPressed: _locked ? null : () => _changed(q.text), child: Text(t_('Try again')))])),
        ])),
        if (searching) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
        if (!searching && searchError == null && !searched) SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Ph.person_search, title: t_('Find someone to chat with'), hint: t_('Search for a member, then tap them.'))),
        if (!searching && searchError == null && searched && results.isEmpty) SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Ph.search_off, title: t_('No matches'))),
        if (!searching && results.isNotEmpty) SliverList(delegate: SliverChildBuilderDelegate((c, index) {
          final user = results[index];
          return ListTile(enabled: !_locked, leading: Avatar(user: user), title: Text((user['name'] ?? '').toString().isEmpty ? '@${user['username']}' : user['name'].toString()), subtitle: Text('@${user['username']}'), trailing: group ? Checkbox(value: picked.containsKey(user['username'].toString()), onChanged: _locked ? null : (_) => _tap(user)) : null, onTap: _locked ? null : () => _tap(user));
        }, childCount: results.length)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
      bottomNavigationBar: group && picked.isNotEmpty ? Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(
        onPressed: _locked ? null : () {
          if (title.text.trim().isEmpty) { setState(() => startError = t_('Enter a group name.')); return; }
          _start({'type': 'group', 'title': title.text.trim(), 'usernames': picked.keys.toList()});
        }, icon: const PhIcon('check'), label: Text('${t_('Create group')} (${picked.length})'),
      )))) : null,
    ),
  );
  }
}

class _GroupDraftServerNotReady { const _GroupDraftServerNotReady(); }
class _GroupDraftNotReady { const _GroupDraftNotReady(); }
class _GroupDraftMemberChanged { const _GroupDraftMemberChanged(); }

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.session, required this.convo});
  final Session session;
  final Map<String, dynamic> convo;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with MediaVisibility<ChatPage> {
  late final Session _session;
  late final String? _owner;
  late final int _sessionGeneration;
  bool get _active=>identical(widget.session,_session) && _owner!=null && widget.session.user?['public_id']==_owner && widget.session.generation==_sessionGeneration;
  void _accountChanged(){
    if(_active || !mounted)return;
    _closed=true;timer?.cancel();_wakeVisible();
    setState((){msgs.clear();input.clear();replyTo=null;typing=[];recording=false;pickingMedia=false;});
  }
  final msgs = <Map<String, dynamic>>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  Timer? timer;
  bool loading = true;
  bool fetching = false;
  bool loadingOlder = false;
  bool hasOlder = false;
  int? historyBoundary;
  String? olderError;
  int unseen = 0;
  final historyCenter = const ValueKey('chat-recent-center');
  bool get nearEnd => !scroll.hasClients || scroll.position.extentAfter < 80;
  int get firstSeq => msgs.where((m) => m['seq'] != null).fold(1 << 62, (a, m) => (m['seq'] as num).toInt() < a ? (m['seq'] as num).toInt() : a);

  String? error;
  Map<String, dynamic>? replyTo;
  bool recording = false;
  bool pickingMedia = false;
  List<String> typing = [];
  DateTime _lastTypingPing = DateTime.fromMillisecondsSinceEpoch(0);

  String get id => widget.convo['public_id'] as String;
  int get lastSeq => msgs.where((m) => m['seq'] != null).fold(0, (a, m) => (m['seq'] as num).toInt() > a ? (m['seq'] as num).toInt() : a);

  @override
  void initState() {
    super.initState();
    _session=widget.session;_owner=widget.session.user?['public_id'] as String?;_sessionGeneration=widget.session.generation;
    widget.session.addListener(_accountChanged);
    input.addListener(_composerChanged);
    scroll.addListener(() { if (unseen > 0 && nearEnd && mounted) setState(() => unseen = 0); });
    _loop();
  }

  void _composerChanged(){if(mounted && _active)setState((){});}

  bool _closed = false;
  Completer<void>? _visibilityWait;
  void _wakeVisible() {
    final pending = _visibilityWait;
    _visibilityWait = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
  @override
  void mediaVisibilityChanged(bool visible) { if (visible) _wakeVisible(); }
  Future<void> _awaitVisible() async {
    while (mounted && !_closed && !mediaVisible) {
      final pending = _visibilityWait ??= Completer<void>();
      await pending.future;
    }
  }
  bool get _readingVisible => mediaVisible && ModalRoute.of(context)?.isCurrent == true;

  // Realtime by long poll: the server holds each request until a new message
  // arrives, so delivery is near instant without a separate socket server.
  Future<void> _loop() async {
    await _awaitVisible();
    if (!mounted || _closed || !_active) return;
    await _fetch();
    if (!mounted || _closed) return;
    // Do not immediately hide a first-load error behind a second read.
    if (error != null) await Future<void>.delayed(const Duration(seconds: 2));
    while (mounted && !_closed) {
      await _awaitVisible();
      if (!mounted || _closed || !_active) break;
      final before = DateTime.now();
      await _fetch(wait: true);
      if (!mounted || _closed) break;
      if (DateTime.now().difference(before) < const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _wakeVisible();
    _session.removeListener(_accountChanged);
    timer?.cancel();
    scroll.dispose();
    input.dispose();
    super.dispose();
  }

  void _sortMessages() {
    msgs.sort((a, b) {
      final sa = (a['seq'] as num?)?.toInt();
      final sb = (b['seq'] as num?)?.toInt();
      if (sa != null && sb != null) return sa.compareTo(sb);
      if (sa != null) return -1;
      if (sb != null) return 1;
      return a['created_at'].toString().compareTo(b['created_at'].toString());
    });
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        if (unseen != 0) setState(() => unseen = 0);
      }
    });
  }

  Future<void> _older() async {
    if (!_active || loadingOlder || !hasOlder || historyBoundary == null) return;
    final before = firstSeq;
    setState(() { loadingOlder = true; olderError = null; });
    try {
      final j = await widget.session.call('GET', '/conversations/$id/messages', query: {'before_seq': '$before'}) as Map<String, dynamic>;
      final page = (j['data'] as List).cast<Map<String, dynamic>>();
      if (page.any((m) => m['seq'] is! num || (m['seq'] as num) >= before)) throw const FormatException('Invalid history cursor');
      if (!mounted || !_active) return;
      setState(() {
        final known = msgs.map((m) => m['public_id']).toSet();
        msgs.addAll(page.where((m) => known.add(m['public_id'])));
        _sortMessages();
        hasOlder = page.length >= 50;
      });
      // Older rows grow in the sliver before the center. Its offset stays fixed
      // without guessing text/image heights or moving a user reading history.
    } catch (e) {
      if (mounted && _active) setState(() => olderError = e is ApiError ? t_(e.message) : t_('Earlier messages could not be loaded.'));
    } finally { if (mounted && _active) setState(() => loadingOlder = false); }
  }

  Future<void> _fetch({bool wait = false}) async {
    if (!mounted || _closed || !_active || !_readingVisible || fetching) return;
    fetching = true;
    try {
      final first = historyBoundary == null;
      final j = await widget.session.call('GET', '/conversations/$id/messages', query: first ? null : {'after_seq': '$lastSeq', if (wait) 'wait': '20', 'typing': typing.join(',')}) as Map<String, dynamic>;
      // The reply may arrive after navigation or backgrounding. Leave the
      // cursor, rows and acknowledgement unchanged for a hidden completion.
      if (!mounted || _closed || !_active || !_readingVisible) return;
      final nowTyping = ((j['typing'] as List?) ?? const []).map((e) => e.toString()).toList();
      if (mounted && _active && nowTyping.join(',') != typing.join(',')) setState(() => typing = nowTyping);
      final items = (j['data'] as List).cast<Map<String, dynamic>>();
      if (!mounted || !_active) return;
      final follow = nearEnd;
      if (first) {
        final seqs = items.map((m) => (m['seq'] as num?)?.toInt()).whereType<int>();
        historyBoundary = seqs.isEmpty ? 0 : seqs.reduce((a, b) => a < b ? a : b);
        hasOlder = items.length >= 50;
      }
      if (error != null) setState(() => error = null);
      final known = msgs.map((m) => m['public_id']).toSet();
      final fresh = items.where((m) => known.add(m['public_id'])).toList();
      // A server copy replaces the local pending copy that has the same client id.
      final before = msgs.length;
      msgs.removeWhere((m) => (m['pending'] == true || m['failed'] == true) && items.any((s) => s['client_id'] == m['client_id'] && (s['sender'] as Map?)?['public_id'] == (m['sender'] as Map?)?['public_id']));
      if (fresh.isNotEmpty || first || before != msgs.length) {
        setState(() {
          msgs.addAll(fresh);
          _sortMessages();
          error = null;
        });
        if (first || follow) {
          _toEnd();
        } else if (fresh.isNotEmpty) {
          setState(() => unseen += fresh.length);
        }
        widget.session.call('POST', '/conversations/$id/read').catchError((_) => null);
      }
    } catch (e) {
      if (mounted && !_closed && _active && _readingVisible) setState(() => error = e is ApiError ? t_(e.message) : t_('Messages could not be loaded.'));
    } finally {
      fetching = false;
      if (mounted && !_closed && _active && _readingVisible && loading) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    final t = input.text.trim();
    if (!_active || t.isEmpty) return;
    input.clear();
    final cid = newUploadIntent();
    final me = widget.session.user!;
    final local = <String, dynamic>{
      'public_id': 'local-$cid',
      'body': t,
      'client_id': cid,
      'pending': true,
      'sender': {'public_id': me['public_id'], 'username': me['username']},
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'kind': 'text',
      if (replyTo != null) 'reply_to': {'public_id': replyTo!['public_id'], 'sender': ((replyTo!['sender'] as Map)['username']).toString(), 'kind': replyTo!['kind'] ?? 'text', 'body': replyTo!['body']},
    };
    replyTo = null;
    setState(() => msgs.add(local));
    _toEnd();
    await _deliver(local);
  }

  Future<void> _deliver(Map<String, dynamic> local) async {
    if (!_active || local['pending'] != true) return;
    final cid = local['client_id'];
    final replyId = (local['reply_to'] as Map?)?['public_id'];
    try {
      final file = local['_file'] as UploadFile?;
      final j = file == null
          ? await widget.session.call('POST', '/conversations/$id/messages', body: {'body': local['body'], 'client_id': cid, if (replyId != null) 'reply_to': replyId}) as Map<String, dynamic>
          : await widget.session.upload('/conversations/$id/messages', fields: {'client_id': '$cid', if (replyId != null) 'reply_to': '$replyId'}, file: file);
      final server = (j['message'] as Map).cast<String, dynamic>();
      if (server['public_id'] is! String || server['sender'] is! Map || server['body'] is! String) throw const FormatException('Incomplete message response');
      if (!mounted || !_active) return;
      final follow = nearEnd;
      setState(() {
        msgs.removeWhere((m) => m['client_id'] == cid && (m['sender'] as Map?)?['public_id'] == widget.session.user?['public_id']);
        if (!msgs.any((m) => m['public_id'] == server['public_id'])) msgs.add(server);
        _sortMessages();
      });
      if (follow) _toEnd();
    } catch (e) {
      if (!mounted || !_active || !msgs.contains(local)) return;
      setState(() {
        local['pending'] = false;
        local['failed'] = true;
        local['unavailable'] = e is ApiError && e.status == 410;
      });
      showError(context, e is ApiError ? e : ApiError(t_('Delivery could not be confirmed.')));
    }
  }

  Future<void> _attach() async {
    if (!_active || hasLocalMedia || pickingMedia) return;
    setState(() => pickingMedia = true);
    try {
      final x = await guardPick(context, () => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 78));
      if (x == null || !mounted || !_active) return;
      final bytes = await x.readAsBytes();
      if (mounted && _active) {
        setState(() => pickingMedia = false);
        await _sendFile(UploadFile(bytes, mimeFor(x.name), x.name));
      }
    } catch (e) { if (mounted && _active) showError(context, e); }
    finally { if (mounted && _active) setState(() => pickingMedia = false); }
  }

  Future<void> _sendVoice(List<int> bytes) async {
    if (!mounted || !_active) return;
    setState(() => recording = false);
    await _sendFile(UploadFile(bytes, 'audio/mp4', 'voice.m4a'));
  }

  bool get hasLocalMedia => msgs.any((m) => m['_file'] is UploadFile);

  Future<void> _sendFile(UploadFile file) async {
    if (!mounted || !_active || hasLocalMedia) return;
    final cid = newUploadIntent();
    final me = widget.session.user!;
    final local = <String, dynamic>{
      'public_id': 'local-$cid', 'body': '', 'client_id': cid, 'pending': true,
      'sender': {'public_id': me['public_id'], 'username': me['username']},
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'kind': file.mime.startsWith('audio/') ? 'voice' : 'image',
      // Never persist private attachment bytes or put them into a public URL.
      '_file': UploadFile(Uint8List.fromList(file.bytes).asUnmodifiableView(), file.mime, file.name),
      if (replyTo != null) 'reply_to': {'public_id': replyTo!['public_id'], 'sender': ((replyTo!['sender'] as Map)['username']).toString(), 'kind': replyTo!['kind'] ?? 'text', 'body': replyTo!['body']},
    };
    setState(() { replyTo = null; msgs.add(local); });
    _toEnd();
    await _deliver(local);
  }

  Future<void> _removeMediaCopy(Map<String, dynamic> local) async {
    if(!_active)return;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      scrollable: true, title: Text(t_('Remove retry copy?')),
      content: Text(t_('This removes only the attachment kept on this screen. It does not delete a message that may already be delivered.')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))), TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Remove retry copy')))],
    ));
    if (yes == true && mounted && _active && local['failed'] == true) setState(() => msgs.remove(local));
  }

  void _typingPing() {
    if(!_active)return;
    final now = DateTime.now();
    if (now.difference(_lastTypingPing) < const Duration(seconds: 4)) return;
    _lastTypingPing = now;
    widget.session.call('POST', '/conversations/$id/typing').catchError((_) => null);
  }

  Future<void> _messageMenu(Map<String, dynamic> m) async {
    if (!_active || m['pending'] == true || m['failed'] == true) return;
    await showReviewedGlassSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const PhIcon('arrow-bend-up-left'),
            title: Text(t_('Reply')),
            onTap: () {
              Navigator.pop(ctx);
              if(mounted && _active)setState(() => replyTo = m);
            },
          ),
          if ((m['body'] ?? '').toString().isNotEmpty)
            ListTile(
              leading: const PhIcon('copy'),
              title: Text(t_('Copy')),
              onTap: () {
                Navigator.pop(ctx);
                if(!mounted || !_active)return;
                Clipboard.setData(ClipboardData(text: m['body'].toString()));
                showInfo(context, 'Copied');
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _retry(Map<String, dynamic> m) async {
    if (!mounted || !_active || !msgs.contains(m) || m['failed'] != true || m['pending'] == true || m['unavailable'] == true) return;
    // Retry the immutable original, never the newer composer or its reply.
    setState(() { m['failed'] = false; m['pending'] = true; });
    await _deliver(m);
  }

  void _call(bool video) {
    if(!_active)return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallPage(session: widget.session, conversationId: id, title: (widget.convo['title'] ?? 'Call').toString(), video: video),
    ));
  }

  Widget _messageTile(Map<String, dynamic> m, {required bool group, required String? myId}) {
    final mine = (m['sender'] as Map)['public_id'] == myId;
    final failed = m['failed'] == true;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      key: ValueKey(m['public_id']),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: failed && m['unavailable'] != true ? () => _retry(m) : null,
        onLongPress: () => _messageMenu(m),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: failed ? scheme.errorContainer : (mine ? brandRed : scheme.surfaceContainerHighest),
            borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(mine ? 20 : 6), bottomRight: Radius.circular(mine ? 6 : 20)),
          ),
          child: DefaultTextStyle.merge(style: TextStyle(color: failed ? scheme.onErrorContainer : (mine ? Colors.white : scheme.onSurface)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (group && !mine) Text('@${(m['sender'] as Map)['username']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            if (m['reply_to'] is Map)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: failed ? scheme.onErrorContainer : mine ? Colors.white : scheme.primary, width: 3)),
                  color: failed ? scheme.onErrorContainer.withValues(alpha: .08) : mine ? Colors.white.withValues(alpha: .14) : scheme.onSurface.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(4)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(m['reply_to'] as Map)['sender']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(kindLabel((m['reply_to'] as Map)['kind'], (m['reply_to'] as Map)['body']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            if (m['_file'] is UploadFile) ...[
              if (m['kind'] == 'image') ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory((m['_file'] as UploadFile).bytes as Uint8List, width: 220, height: 160, fit: BoxFit.cover, errorBuilder: (context, error, stack) => const PhIcon('image-broken'))),
              Text(t_(m['kind'] == 'voice' ? 'Voice message' : 'Photo')),
              if (failed) TextButton(onPressed: () => _removeMediaCopy(m), style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer), child: Text(t_('Remove retry copy'))),
            ],
            if (m['kind'] == 'image' && m['media_url'] is String && widget.session.supportsPrivateMedia(m['media_url'] as String))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrivatePhotoViewer(session:widget.session,urls: [m['media_url'] as String]))),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image(image: PrivateMediaImage(widget.session,m['media_url'] as String), width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const PhIcon('image-broken'))),
                ),
              ),
            if (m['kind'] == 'image' && m['media_url'] != null && (m['media_url'] is! String || !widget.session.supportsPrivateMedia(m['media_url'] as String))) Text(t_('This photo is unavailable.')),
            if (m['kind'] == 'storyreply') Text(t_('Story reply'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (m['kind'] == 'post') SharedPostCard(post: (m['shared_post'] as Map?)?.cast<String, dynamic>(), onOpenPost: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostPage(session: widget.session, postId: id))), onOpenAuthor: (u) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: u)))),
            if (m['kind'] == 'voice' && m['media_url'] != null) VoiceBubble(url: m['media_url'] as String, session: widget.session),
            if ((m['body'] ?? '').toString().isNotEmpty) Text(m['body'].toString()),
            Text(failed ? (m['unavailable'] == true ? t_('Original message unavailable.') : t_('Delivery unconfirmed. Tap to retry.')) : (m['pending'] == true ? 'Sending' : ago(m['created_at'].toString())), style: TextStyle(fontSize: 11, color: failed ? scheme.onErrorContainer : (mine ? Colors.white.withValues(alpha: 0.78) : scheme.onSurfaceVariant))),
          ])),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if(!_active)return Scaffold(appBar:ReviewedAppBar(title:Text(t_('Chat'))),body:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This chat belongs to another signed-in session. Close it and sign in again to continue.'))));
    final myId = widget.session.user?['public_id'];
    final group = widget.convo['type'] == 'group';
    return DraftExitGuard(
      hasChanges: hasLocalMedia || input.text.trim().isNotEmpty || replyTo!=null || recording || msgs.any((m)=>m['failed']==true || m['pending']==true),
      busy: pickingMedia || recording || msgs.any((m)=>m['pending']==true),
      title: 'Leave chat?', message: 'Leaving removes unsent text and local retry copies, not messages that may have arrived.',
      keepLabel: 'Stay here', discardLabel: 'Leave', busyMessage: recording?'Finish or cancel the recording before leaving.':pickingMedia?'Wait for the media picker to close before leaving.':'Your message is still sending.',
      child: Scaffold(
      appBar: ReviewedAppBar(
        toolbarHeight: (MediaQuery.textScalerOf(context).scale(16) * 2.4).clamp(56.0, 112.0),
        title: InkWell(
          onTap: group ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupInfoPage(session: widget.session, convo: widget.convo))) : null,
          child: Row(children: [
            if (MediaQuery.textScalerOf(context).scale(14) < 20) ...[
              CircleAvatar(radius: 16, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: PhIcon(group ? 'users-three' : 'user', size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 10),
            ],
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((widget.convo['title'] ?? 'Chat').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
              if (typing.isNotEmpty) Text(group ? '${typing.join(', ')} typing...' : 'typing...', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal))
              else if (group) Text(tf_('{n} members', {'n': (widget.convo['members'] as List?)?.length ?? 0}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])),
          ]),
        ),
        actions: [
          IconButton(tooltip: t_('Voice call'), icon: const PhIcon('phone-fill'), onPressed: () => _call(false)),
          IconButton(tooltip: t_('Video call'), icon: const PhIcon('video-camera'), onPressed: () => _call(true)),
        ],
      ),
      body: Column(children: [
        if (error != null && msgs.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
          Expanded(child: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: fetching ? null : () => _fetch(), child: Text(t_('Try again'))),
        ])),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : msgs.isEmpty
                  ? error == null ? Center(child: Text(t_('Say hello.'))) : EmptyState(icon: Ph.cloud_off, title: error!, action: OutlinedButton(onPressed: fetching ? null : () => _fetch(), child: Text(t_('Try again'))))
                  : Builder(builder: (context) {
                      final older = msgs.where((m) => m['seq'] is num && (m['seq'] as num) < (historyBoundary ?? 0)).toList().reversed.toList();
                      final recent = msgs.where((m) => m['seq'] is! num || (m['seq'] as num) >= (historyBoundary ?? 0)).toList();
                      SliverList rows(List<Map<String, dynamic>> data, {Key? key}) => SliverList(key: key, delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(key: ValueKey(data[i]['public_id']), padding: const EdgeInsets.symmetric(horizontal: 12), child: _messageTile(data[i], group: group, myId: myId)),
                        childCount: data.length,
                        findChildIndexCallback: (key) { final i = data.indexWhere((m) => ValueKey(m['public_id']) == key); return i < 0 ? null : i; },
                      ));
                      return Stack(children: [
                        CustomScrollView(key: const ValueKey('chat-history-scroll'), controller: scroll, center: historyCenter, slivers: [
                          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                            if (olderError != null) Text(olderError!),
                            if (loadingOlder) const Center(child: CircularProgressIndicator())
                            else if (hasOlder) TextButton(onPressed: _older, child: Text(t_(olderError == null ? 'Load earlier messages' : 'Try again')))
                            else Text(t_('Start of conversation'), style: Theme.of(context).textTheme.labelMedium),
                          ]))),
                          rows(older),
                          rows(recent, key: historyCenter),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        ]),
                        if (unseen > 0) Positioned(bottom: 8, left: 0, right: 0, child: Center(child: FilledButton.tonalIcon(
                          onPressed: _toEnd, icon: const PhIcon('arrow-down', size: 18), label: Text(t_('New messages')),
                        ))),
                      ]);
                    }),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (replyTo != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(child: Text('${t_('Replying to')} @${(replyTo!['sender'] as Map)['username']}: ${kindLabel(replyTo!['kind'], replyTo!['body'])}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => replyTo = null), icon: const PhIcon('x', size: 18)),
                  ]),
                ),
              if (recording)
                VoiceRecorderBar(
                  onDone: _sendVoice,
                  onCancel: () {
                    if (mounted && _active) setState(() => recording = false);
                  },
                  onError: (msg) {
                    if (mounted && _active) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  },
                )
              else
              Row(children: [
                IconButton(tooltip: t_('Attach photo'), onPressed: hasLocalMedia || pickingMedia ? null : _attach, icon: const PhIcon('image')),
                Expanded(child: TextField(controller: input, onChanged: (_) => _typingPing(), minLines: 1, maxLines: 4, maxLength: 4000, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: 'Message', hintMaxLines: 1, counterText: '', filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHigh, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
                IconButton(onPressed: hasLocalMedia || pickingMedia ? null : () => setState(() => recording = true), icon: const PhIcon('microphone'), tooltip: 'Voice message'),
                IconButton.filled(tooltip: t_('Send message'), onPressed: _send, icon: PhIcon('paper-plane-tilt-fill', color: Theme.of(context).colorScheme.onPrimary)),
              ]),
            ]),
          ),
        ),
      ]),
    ));
  }
}

/// Group membership, owner-only rename, invitations and leaving.
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({super.key, required this.session, required this.convo});
  final Session session;
  final Map<String, dynamic> convo;
  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late final Session _session;
  late final String? _owner;
  late final int _sessionGeneration;
  bool get _active=>identical(widget.session,_session) && _owner!=null && widget.session.user?['public_id']==_owner && widget.session.generation==_sessionGeneration;
  BuildContext? _dialog;
  @override void initState(){super.initState();_session=widget.session;_owner=widget.session.user?['public_id'] as String?;_sessionGeneration=widget.session.generation;widget.session.addListener(_accountChanged);}
  void _accountChanged(){
    if(_active || !mounted)return;
    final dialog=_dialog;
    if(dialog!=null && dialog.mounted && ModalRoute.of(dialog)?.isCurrent==true)Navigator.of(dialog).pop();
    setState((){members=[];title='';busy=false;});
  }
  @override void dispose(){_session.removeListener(_accountChanged);super.dispose();}
  late List<Map<String, dynamic>> members = ((widget.convo['members'] as List?) ?? const []).cast<Map<String, dynamic>>();
  bool busy = false;
  late String title = (widget.convo['title'] ?? 'Group').toString();
  late bool isOwner = widget.convo['my_role'] == 'owner';

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _ownership() async {
    if (!_active || busy || !widget.session.groupOwnershipEnabled || ModalRoute.of(context)?.isCurrent != true) return;
    final groupId = widget.convo['public_id'] as String;
    setState(() { busy = true; isOwner = false; });
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupOwnershipPage(session: widget.session, groupId: groupId)));
      if (!mounted || !_active || widget.convo['public_id'] != groupId) return;
      final value = await widget.session.call('GET', '/conversations/$groupId');
      final current = GroupOwnershipSnapshot(value is Map ? value['conversation'] : null, groupId, widget.session.user?['public_id'] ?? '');
      if (mounted && _active && widget.convo['public_id'] == groupId) {
        setState(() {
          title = current.title;
          members = current.members;
          isOwner = current.isOwner;
        });
      }
    } catch (_) {
      if (mounted && _active && ModalRoute.of(context)?.isCurrent == true) { _say(t_('Could not load group ownership. Try again.')); }
    } finally {
      if (mounted && _active) setState(() => busy = false);
    }
  }

  Future<void> _add() async {
    if(!_active || busy)return;
    final ctrl = TextEditingController();
    final names = await showDialog<List<String>>(
      context: context,
      builder: (c) {_dialog=c;return AlertDialog(
        title: Text(t_('Add people')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: t_('Usernames, separated by commas'))),
          const SizedBox(height: 12),
          Text(t_('New members see messages from when they join, not earlier ones.'), style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t_('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, [for (final n in ctrl.text.split(RegExp(r'[,\s]+'))) if (n.trim().isNotEmpty) n.trim().replaceFirst('@', '')]),
            child: Text(t_('Add')),
          ),
        ],
      );},
    );
    _dialog=null;
    if (!mounted || !_active)return;
    if (names == null || names.isEmpty) return;
    setState(() => busy = true);
    try {
      final j = await widget.session.call('POST', '/conversations/${widget.convo['public_id']}/members', body: {'usernames': names}) as Map<String, dynamic>;
      final c = j['conversation'] as Map<String, dynamic>;
      if (mounted && _active) setState(() => members = ((c['members'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } on ApiError catch (e) {
      if (mounted && _active) _say(t_(e.message));
    } finally {
      if (mounted && _active) setState(() => busy = false);
    }
  }

  Future<void> _rename() async {
    if(!_active || busy)return;
    final ctrl = TextEditingController(text: title);
    final name = await showDialog<String>(
      context: context,
      builder: (c) {_dialog=c;return AlertDialog(
        title: Text(t_('Rename group')),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 80, decoration: InputDecoration(hintText: t_('Group name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(t_('Save'))),
        ],
      );},
    );
    _dialog=null;
    if (!mounted || !_active)return;
    if (name == null || name.isEmpty || name == title) return;
    setState(() => busy = true);
    try {
      final j = await widget.session.call('PATCH', '/conversations/${widget.convo['public_id']}', body: {'title': name}) as Map<String, dynamic>;
      final c = j['conversation'] as Map<String, dynamic>;
      if (mounted && _active) setState(() => title = (c['title'] ?? name).toString());
    } on ApiError catch (e) {
      if (mounted && _active) _say(t_(e.message));
    } finally {
      if (mounted && _active) setState(() => busy = false);
    }
  }

  Future<void> _leave() async {
    if(!_active || busy)return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {_dialog=c;return AlertDialog(
        title: Text(t_('Leave this group?')),
        content: Text(t_('You will stop getting its messages. Someone has to add you again to rejoin.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Leave'))),
        ],
      );},
    );
    _dialog=null;
    if (!mounted || !_active)return;
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await widget.session.call('POST', '/conversations/${widget.convo['public_id']}/leave');
      if (mounted && _active) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted && _active) {
        setState(() => busy = false);
        _say(t_(e.message));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!_active)return Scaffold(appBar:ReviewedAppBar(title:Text(t_('Group info'))),body:Padding(padding:const EdgeInsets.all(20),child:Text(t_('This chat belongs to another signed-in session. Close it and sign in again to continue.'))));
    final scheme = Theme.of(context).colorScheme;
    final session = widget.session;
    return Scaffold(
      appBar: ReviewedAppBar(title: Text(t_('Group info'))),
      body: ListView(children: [
        const SizedBox(height: 16),
        Center(child: CircleAvatar(radius: 44, backgroundColor: scheme.surfaceContainerHigh, child: PhIcon('users-three', size: 40, color: scheme.onSurfaceVariant))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        Text(tf_('{n} members', {'n': members.length}), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (isOwner)
          ListTile(
            leading: CircleAvatar(radius: 22, backgroundColor: scheme.surfaceContainerHigh, child: const PhIcon('note-pencil', size: 20)),
            title: Text(t_('Rename group'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: busy ? null : _rename,
          ),
        if (widget.session.groupOwnershipEnabled)
          ListTile(
            leading: CircleAvatar(radius: 22, backgroundColor: scheme.surfaceContainerHigh, child: const PhIcon('users-three', size: 20)),
            title: Text(t_('Group ownership'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: busy ? null : _ownership,
          ),
        ListTile(
          leading: CircleAvatar(radius: 22, backgroundColor: scheme.surfaceContainerHigh, child: const PhIcon('plus', size: 20)),
          title: Text(t_('Add people'), style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: busy ? null : _add,
        ),
        for (final m in members)
          ListTile(
            leading: Avatar(user: m, radius: 22),
            title: Text((m['name'] ?? '').toString().isEmpty ? '@${m['username']}' : m['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('@${m['username']}'),
            onTap: m['public_id'] == session.user?['public_id'] ? null : () {if(!_active)return;Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: session, username: m['username'].toString())));},
          ),
        const SizedBox(height: 8),
        ListTile(
          leading: PhIcon('sign-out', color: scheme.error),
          title: Text(t_('Leave group'), style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
          onTap: busy ? null : _leave,
        ),
        const SizedBox(height: 96),
      ]),
    );
  }
}
