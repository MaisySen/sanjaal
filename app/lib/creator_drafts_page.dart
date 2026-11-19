import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'stories_page.dart' show StoryComposePage;
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
  String? owner, error, textError, mediaError;
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
    List<CreatorDraft> list=[];
    List<CreatorMediaDraft> media=[];
    String? textProblem,mediaProblem;
    try{list=await store.read(owner!);}
    catch(_){textProblem=t_('Text drafts could not be read. Nothing was replaced.');}
    try{media=await mediaStore.read(owner!);}
    catch(_){mediaProblem=t_('Media drafts could not be read. Nothing was replaced.');}
    if(mounted && active)setState((){
      drafts=list;mediaDrafts=media;textError=textProblem;mediaError=mediaProblem;error=null;
    });
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
      await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>draft.story
        ? StoryComposePage(session:widget.session,file:files.single,isVideo:draft.video,backgroundUpload:true,initialMediaDraft:draft)
        : ComposePage(session:widget.session,backgroundUpload:true,initialMediaDraft:draft,savedMediaFiles:files)));
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
        ],
        if(active && (textError!=null || mediaError!=null))...[
          if(textError!=null)Text(textError!),
          if(mediaError!=null)Text(mediaError!),
          TextButton(onPressed:busy?null:_load,child:Text(t_('Try again'))),
        ],
        if(error==null && drafts == null)
          const Center(child: CircularProgressIndicator())
        else if (error==null && textError==null && mediaError==null && drafts!.isEmpty && mediaDrafts.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              t_(
                'No saved drafts yet. Use the bookmark while writing a post or story.',
              ),
            ),
          ),
        if(active)
          for (final draft in drafts??<CreatorDraft>[])
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
          title:Text(draft.text.isEmpty?t_(draft.story?'Story draft':draft.video?'Video draft':'Photo draft'):draft.text,maxLines:2,overflow:TextOverflow.ellipsis),
          subtitle:Text(t_(draft.attempted?'Check earlier upload before posting again':draft.story?'Story draft':draft.video?'Video draft':'Photo draft')),
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
