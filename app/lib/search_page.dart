import 'glass/glass_app_bar.dart';
import 'ph.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'session_bound_state.dart';
import 'feed_page.dart' show HashtagPage;
import 'profile_pages.dart';
import 'ui.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.session});
  final Session session;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SessionBoundState<SearchPage> {
  @override
  Session get viewSession => widget.session;
  @override
  void sessionRetired() {
    _debounce?.cancel();
    ++_seq;
    input.clear();
    users = [];
    tags = [];
    error = null;
    loading = false;
    searched = false;
  }
  final input = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> users = [];
  List<String> tags = [];
  bool loading = false;
  bool searched = false;
  String? error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  void _changed(String v) {
    if (!sessionActive) return;
    _debounce?.cancel();
    // Invalidate at edit time, not after the next debounce. A slow response
    // for the old query must not repopulate cleared or newly edited results.
    ++_seq;
    setState(() {
      users = [];
      tags = [];
      searched = false;
      error = null;
      loading = v.trim().isNotEmpty;
    });
    if (v.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    if (!sessionActive) return;
    _debounce?.cancel();
    final q = input.text.trim();
    if (q.isEmpty) return;
    final seq = ++_seq;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await widget.session.call('GET', '/users/search', query: {'q': q}) as Map<String, dynamic>;
      if (!mounted || !sessionActive || seq != _seq) return;
      final nextUsers=(j['users'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      final nextTags=(j['hashtags'] as List).cast<String>();
      if(nextUsers.any((u)=>u['username'] is! String || (u['username'] as String).trim().isEmpty) || nextTags.any((v)=>v.trim().isEmpty)) throw const FormatException('Invalid search results');
      setState(() {
        users = nextUsers;
        tags = nextTags;
        searched = true;
      });
    } catch (e) {
      if (mounted && sessionActive && seq == _seq) setState(() => error = e is ApiError ? t_(e.message) : t_('Search could not be loaded.'));
    } finally {
      if (mounted && sessionActive && seq == _seq) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    return Scaffold(
      appBar: ReviewedAppBar(
        title: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: t_('Search people and #tags'), border: InputBorder.none, suffixIcon: loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : input.text.isNotEmpty ? IconButton(tooltip:t_('Clear search'),onPressed:(){input.clear();_changed('');},icon:const PhIcon('x')) : null),
          onChanged: _changed,
          onSubmitted: (_) => _run(),
        ),
      ),
      body: error != null
          ? EmptyState(icon: widget.session.offline ? Ph.cloud_off : Ph.error_outline, title: error!, action: OutlinedButton(onPressed: _run, child: Text(t_('Try again'))))
          : !searched
              ? EmptyState(icon: Ph.search, title: t_('Find people to follow'), hint: t_('Type a name, a username or a hashtag.'))
              : users.isEmpty && tags.isEmpty
                  ? EmptyState(icon: Ph.search_off, title: t_('No matches'))
                  : ListView(children: [
                      for (final tg in tags)
                        ListTile(
                          leading: const CircleAvatar(child: PhIcon('hash')),
                          title: Text('#$tg'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HashtagPage(session: widget.session, tag: tg))),
                        ),
                      for (final u in users)
                        ListTile(
                          leading: Avatar(user: u),
                          title: Text((u['name'] ?? '').toString().isEmpty ? '@${u['username']}' : u['name'].toString()),
                          subtitle: Text('@${u['username']}${u['following'] == true ? '  ·  ${t_('Following')}' : ''}'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: u['username'].toString()))),
                        ),
                    ]),
    );
  }
}
