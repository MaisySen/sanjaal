import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'creator_draft_store.dart';
import 'creator_media_draft_store.dart';
import 'feed_page.dart' show ComposePage;
import 'ui.dart' show showError, t_;
import 'ph.dart';

class CreatorDraftsPage extends StatefulWidget {
  const CreatorDraftsPage({super.key, required this.session});
  final Session session;
  @override
  State<CreatorDraftsPage> createState() => _CreatorDraftsPageState();
}

class _CreatorDraftsPageState extends State<CreatorDraftsPage> {
  final store = const CreatorDraftStore();
  String? owner, error;
  List<CreatorDraft>? drafts;
  List<CreatorMediaDraft> mediaDrafts=[];
  final mediaStore=const CreatorMediaDraftStore();
  late final int generation;
  bool busy = false;
  bool get active =>
      owner != null && widget.session.user?['public_id'] == owner && widget.session.generation==generation;
  @override
  void initState() {
    super.initState();
    generation=widget.session.generation;
    owner = widget.session.user?['public_id'] as String?;
    widget.session.addListener(_account);
    _load();
  }

  void _account() {
    if (!active && mounted)
      setState(() {
        drafts = null;mediaDrafts=[];
        error = t_("Sign in again to view this account's local drafts.");
      });
  }

  Future<void> _load() async {
    if (!active) {
      if (mounted) setState(() => error = t_('Sign in to view saved drafts.'));
      return;
    }
    try {
      final list = await store.read(owner!);
      final media=await mediaStore.read(owner!);
      if (mounted && active)
        setState(() {
          drafts = list;mediaDrafts=media;
          error = null;
        });
    } catch (_) {
      if (mounted && active)
        setState(
          () => error = t_('Could not read saved drafts. Nothing was replaced.'),
        );
    }
  }

  Future<void> _delete(CreatorDraft draft) async {
    if (busy || !active) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t_('Delete this local draft?')),
        content: Text(t_(
          'This removes only the saved copy on this device, not any published post.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t_('Keep')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t_('Delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !active) return;
    setState(() => busy = true);
    try {
      await store.remove(owner!, draft.id, expectedRevision: draft.revision);
      if (active) await _load();
    } catch (e) {
      if (e is StateError && mounted && active) await _load();
      if (mounted && active) {
        showError(context, e is StateError ? t_(e.message.toString()) : e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openMedia(CreatorMediaDraft draft) async {
    if(busy || !active)return;
    setState(()=>busy=true);
    try{
      final files=await mediaStore.open(owner!,draft);
      if(!mounted || !active)return;
      await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>ComposePage(session:widget.session,backgroundUpload:true,initialMediaDraft:draft,savedMediaFiles:files)));
      if(mounted && active)await _load();
    }catch(e){if(mounted && active)showError(context,e);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _deleteMedia(CreatorMediaDraft draft)async{
    if(busy || !active)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(t_('Delete this local draft?')),content:Text(t_('This removes only the saved copy on this device, not any published post.')),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(t_('Keep'))),TextButton(onPressed:()=>Navigator.pop(c,true),child:Text(t_('Delete')))]));
    if(yes!=true || !mounted || !active)return;
    setState(()=>busy=true);
    try{await mediaStore.remove(owner!,draft);if(mounted && active)await _load();}
    catch(e){if(mounted && active){await _load();if(mounted)showError(context,e);}}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  void dispose() {
    widget.session.removeListener(_account);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t_('Saved drafts'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t_(
            'Text, polls, photos and videos saved only on this device for this account. Media drafts are encrypted. Nothing posts automatically.',
          ),
        ),
        const SizedBox(height: 16),
        if (error != null) ...[
          Text(error!),
          TextButton(
            onPressed: active ? _load : null,
            child: Text(t_('Try again')),
          ),
        ] else if (drafts == null)
          const Center(child: CircularProgressIndicator())
        else if (drafts!.isEmpty && mediaDrafts.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              t_(
                'No saved drafts yet. Use Save text draft while writing a post.',
              ),
            ),
          )
        else
          for (final draft in drafts!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                draft.text.trim().isEmpty ? t_('Untitled poll') : draft.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                t_(draft.options == null ? 'Text draft' : 'Poll draft'),
              ),
              trailing: IconButton(
                tooltip: t_('Delete draft'),
                onPressed: busy ? null : () => _delete(draft),
                icon: const PhIcon('trash'),
              ),
              onTap: busy
                  ? null
                  : () async {
                      if (!active) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComposePage(
                            session: widget.session,
                            backgroundUpload: true,
                            initialLocalDraft: draft,
                          ),
                        ),
                      );
                      if (mounted && active) await _load();
                    },
            ),
        if(active) for(final draft in mediaDrafts) ListTile(
          title:Text(draft.text.isEmpty?t_(draft.video?'Video draft':'Photo draft'):draft.text,maxLines:2,overflow:TextOverflow.ellipsis),
          subtitle:Text(t_(draft.attempted?'Check earlier upload before posting again':draft.video?'Video draft':'Photo draft')),
          onTap:busy?null:()=>_openMedia(draft),
          trailing:IconButton(tooltip:t_('Delete draft'),onPressed:busy?null:()=>_deleteMedia(draft),icon:const PhIcon('trash')),
        ),
        const SizedBox(height: 24),
        Text(
          t_(
            'Drafts never post automatically. Signing out hides them until this account returns. Delete drafts here to remove them from this device.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
