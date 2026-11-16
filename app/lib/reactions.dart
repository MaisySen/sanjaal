import 'ph.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
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

class _ReactionButtonState extends State<ReactionButton> {
  late String? mine = widget.post['my_reaction'] as String? ?? (widget.post['liked'] == true ? 'like' : null);
  late int count = (widget.post['likes_count'] as num?)?.toInt() ?? 0;
  bool busy = false;

  String get id => widget.post['public_id'] as String;

  Future<void> _set(String? type) async {
    if (busy) return;
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
      if (mounted) {
        setState(() {
          mine = j['my_reaction'] as String?;
          count = (j['likes_count'] as num?)?.toInt() ?? count;
        });
      }
    } catch (e) {
      if (mounted) {
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
    HapticFeedback.mediumImpact();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
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
      ),
    );
    if (chosen != null) _set(chosen);
  }

  @override
  Widget build(BuildContext context) {
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
