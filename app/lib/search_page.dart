import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'feed_page.dart' show HashtagPage;
import 'profile_pages.dart';
import 'ui.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.session});
  final Session session;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
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
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        users = [];
        tags = [];
        searched = false;
        error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final q = input.text.trim();
    if (q.isEmpty) return;
    final seq = ++_seq;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await widget.session.call('GET', '/users/search', query: {'q': q}) as Map<String, dynamic>;
      if (!mounted || seq != _seq) return;
      setState(() {
        users = (j['users'] as List).cast<Map<String, dynamic>>();
        tags = (j['hashtags'] as List).map((e) => e.toString()).toList();
        searched = true;
      });
    } on ApiError catch (e) {
      if (mounted && seq == _seq) setState(() => error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: 'Search people and #tags', border: InputBorder.none, suffixIcon: loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
          onChanged: _changed,
          onSubmitted: (_) => _run(),
        ),
      ),
      body: error != null
          ? EmptyState(icon: Icons.cloud_off, title: error!)
          : !searched
              ? const EmptyState(icon: Icons.search, title: 'Find people to follow', hint: 'Type a name, a username or a hashtag.')
              : users.isEmpty && tags.isEmpty
                  ? const EmptyState(icon: Icons.search_off, title: 'No matches')
                  : ListView(children: [
                      for (final tg in tags)
                        ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.tag)),
                          title: Text('#$tg'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HashtagPage(session: widget.session, tag: tg))),
                        ),
                      for (final u in users)
                        ListTile(
                          leading: Avatar(user: u),
                          title: Text((u['name'] ?? '').toString().isEmpty ? '@${u['username']}' : u['name'].toString()),
                          subtitle: Text('@${u['username']}${u['following'] == true ? '  ·  Following' : ''}'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(session: widget.session, username: u['username'].toString()))),
                        ),
                    ]),
    );
  }
}
