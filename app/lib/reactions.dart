import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_sheet.dart';
import 'ui.dart';

const reactionKinds = ['like', 'love', 'laugh', 'wow', 'sad', 'angry'];

/// One proper icon per reaction. No emoji anywhere in the UI: the picker and
/// the button both render Material icons, and the reacted state is a crimson
/// icon, the same way Instagram colours a liked heart red.
const reactionIcons = {
  'like': Icons.thumb_up,
  'love': Icons.favorite,
  'laugh': Icons.emoji_emotions,
  'wow': Icons.sentiment_very_satisfied,
  'sad': Icons.sentiment_dissatisfied,
  'angry': Icons.sentiment_very_dissatisfied,
};

/// Tap to react with a heart (tap again to remove). Long press to pick one of six reactions.
/// Double tap on a post or reel calls [like] through the button key, so the
/// feed and reels can like from the media without duplicating this state.
class ReactionButton extends StatefulWidget {
  const ReactionButton({super.key, required this.session, required this.post, this.dark = false});
  final Session session;
  final Map<String, dynamic> post;
  final bool dark;

  @override
  State<ReactionButton> createState() => ReactionButtonState();
}

class ReactionButtonState extends State<ReactionButton> {
  late String? mine = widget.post['my_reaction'] as String? ?? (widget.post['liked'] == true ? 'like' : null);
  late int count = (widget.post['likes_count'] as num?)?.toInt() ?? 0;
  bool busy = false;
  bool _popping = false;

  String get id => widget.post['public_id'] as String;

  /// True when the viewer has any reaction on this post.
  bool get hasReaction => mine != null;

  /// Adds the heart reaction when there is none. A double tap never removes
  /// a reaction, it only adds one, which is the TikTok and Instagram rule.
  Future<void> like() async {
    if (mine == null) await _set('love');
  }

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
      _popping = type != null;
    });
    if (_popping) Future.delayed(const Duration(milliseconds: 150), () => mounted ? setState(() => _popping = false) : null);
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
    final chosen = await showGlassSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final k in reactionKinds)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, k),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mine == k ? brandRed.withValues(alpha: 0.14) : Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(reactionIcons[k], size: mine == k ? 40 : 32, color: mine == k ? brandRed : Theme.of(context).colorScheme.onSurface),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _set(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final icon = mine == null
        ? Icon(Icons.favorite_border, color: color, size: widget.dark ? 30 : 22)
        : Icon(reactionIcons[mine] ?? Icons.favorite, color: brandRed, size: widget.dark ? 30 : 22);
    final label = Text('$count', style: TextStyle(color: color, fontSize: widget.dark ? 12 : 14));
    return GestureDetector(
      onLongPress: _pick,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _set(mine == null ? 'love' : null),
        // The like pop: scale 1 to 1.3 to 1 over 300ms, the TikTok timing.
        child: AnimatedScale(
          scale: _popping ? 1.3 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: widget.dark
                ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 2), label])
                : Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 6), label]),
          ),
        ),
      ),
    );
  }
}
