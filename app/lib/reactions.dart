import 'glass/glass_sheet.dart';
import 'ph.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'session_bound_state.dart';
import 'ui.dart';

const reactionKinds = ['like', 'love', 'laugh', 'wow', 'sad', 'angry'];
const reactionEmoji = {
  'like': '\u{1F44D}',
  'love': '\u{2764}\u{FE0F}',
  'laugh': '\u{1F602}',
  'wow': '\u{1F62E}',
  'sad': '\u{1F622}',
  'angry': '\u{1F621}',
};

/// Tap to react with a heart (tap again to remove). Long press to pick one of six reactions.
class ReactionButton extends StatefulWidget {
  const ReactionButton({super.key, required this.session, required this.post, this.dark = false});
  final Session session;
  final Map<String, dynamic> post;
  final bool dark;

  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton> with SessionBoundState<ReactionButton> {
  @override Session get viewSession=>widget.session;
  late final String _openingPost=widget.post['public_id'] as String;
  Route<dynamic>? _picker;
  void _closePicker(){final route=_picker;_picker=null;Future.microtask((){if(route!=null && route.isActive)route.navigator?.removeRoute(route);});}
  @override void sessionRetired(){_closePicker();}
  @override void dispose(){_closePicker();super.dispose();}
  @override bool get sessionActive=>super.sessionActive && id==_openingPost;
  late String? mine = widget.post['my_reaction'] as String? ?? (widget.post['liked'] == true ? 'like' : null);
  late int count = (widget.post['likes_count'] as num?)?.toInt() ?? 0;
  bool busy = false;

  String get id => widget.post['public_id'] as String;

  Future<void> _set(String? type) async {
    if (!mounted || !sessionActive || busy) return;
    busy = true;
    HapticFeedback.lightImpact();
    final oldMine = mine;
    final oldCount = count;
    setState(() {
      if (oldMine == null && type != null) count += 1;
      if (oldMine != null && type == null) count -= 1;
      mine = type;
    });
    try {
      final j = await widget.session.call(type == null ? 'DELETE' : 'POST', '/posts/$id/reaction',
          body: type == null ? null : {'type': type}) as Map<String, dynamic>;
      if (mounted && sessionActive) {
        setState(() {
          mine = j['my_reaction'] as String?;
          count = (j['likes_count'] as num?)?.toInt() ?? count;
        });
      }
    } catch (e) {
      if (mounted && sessionActive) {
        setState(() {
          mine = oldMine;
          count = oldCount;
        });
        showError(context, e);
      }
    } finally {
      busy = false;
    }
  }

  Future<void> _pick() async {
    if(!mounted || !sessionActive || busy)return;
    HapticFeedback.mediumImpact();
    final chosen = await showReviewedGlassSheet<String>(
      context: context,
      builder: (ctx) {
        _picker=ModalRoute.of(ctx);
        return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final k in reactionKinds)
                InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () => Navigator.pop(ctx, k),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(reactionEmoji[k]!, style: TextStyle(fontSize: mine == k ? 40 : 32)),
                  ),
                ),
            ],
          ),
        ),
      );},
    );
    _picker=null;
    if (chosen != null && mounted && sessionActive) _set(chosen);
  }

  @override
  Widget build(BuildContext context) {
    if(!sessionActive)return const SizedBox.shrink();
    final color = widget.dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final icon = mine == null
        ? PhIcon('heart', color: color, size: widget.dark ? 30 : 22)
        : Text(reactionEmoji[mine] ?? reactionEmoji['love']!, style: TextStyle(fontSize: widget.dark ? 28 : 21));
    final label = Text('$count', style: TextStyle(color: color, fontSize: widget.dark ? 12 : 14));
    return GestureDetector(
      onLongPress: _pick,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _set(mine == null ? 'love' : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: widget.dark
              ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 2), label])
              : Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 6), label]),
        ),
      ),
    );
  }
}
