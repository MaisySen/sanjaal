import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'draft_exit_guard.dart';
import 'glass/glass_app_bar.dart';
import 'session_bound_state.dart';
import 'ui.dart';

/// A text-only message to this story's owner. No story media is copied to chat.
class StoryReplyPage extends StatefulWidget {
  const StoryReplyPage({
    super.key,
    required this.session,
    required this.storyId,
    required this.authorName,
  });
  final Session session;
  final String storyId, authorName;
  @override
  State<StoryReplyPage> createState() => _StoryReplyPageState();
}

class _StoryReplyPageState extends State<StoryReplyPage>
    with SessionBoundState<StoryReplyPage> {
  @override
  Session get viewSession => widget.session;
  final input = TextEditingController();
  final clientId = newUploadIntent();
  String? attemptedText;
  String? error;
  bool sending = false, sent = false;
  bool get available => sessionActive && widget.session.storyRepliesEnabled;
  @override
  void sessionRetired() {
    input.clear();
    attemptedText = null;
    error = null;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!available || sending || sent) return;
    final text = attemptedText ?? input.text.trim();
    if (text.isEmpty || text.length > 4000) return;
    setState(() {
      attemptedText = text;
      sending = true;
      error = null;
    });
    try {
      final result = await widget.session.call(
        'POST',
        '/stories/${widget.storyId}/reply',
        body: {'body': text, 'client_id': clientId},
      );
      if (!mounted || !sessionActive) return;
      if (result is! Map ||
          result['message'] is! Map ||
          (result['message'] as Map)['client_id'] != clientId ||
          (result['message'] as Map)['kind'] != 'storyreply') {
        throw StateError('Reply was not confirmed.');
      }
      setState(() {
        sent = true;
        sending = false;
        input.clear();
        attemptedText = null;
      });
    } catch (_) {
      if (mounted && sessionActive) {
        setState(() {
          sending = false;
          error = t_(
            'Delivery is unconfirmed. Retry checks the same message, not a second copy. The story or its audience may no longer be available.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    final uncertain = attemptedText != null;
    return DraftExitGuard(
      hasChanges: !sent && (input.text.isNotEmpty || uncertain),
      busy: sending,
      busyMessage: 'Your message is still sending.',
      title: uncertain ? 'Leave an unconfirmed reply?' : 'Discard this draft?',
      message: uncertain
          ? 'This message may already be in the chat. Leaving removes this retry copy. Check the chat before sending it again.'
          : 'Leaving will remove this draft from this screen.',
      keepLabel: uncertain ? 'Stay here' : 'Keep editing',
      discardLabel: uncertain ? 'Leave' : 'Discard',
      child: Scaffold(
        appBar: ReviewedAppBar(title: Text(t_('Reply to story'))),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.authorName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  t_(
                    'Only your message goes to this person. The story photo, video and caption are not copied.',
                  ),
                ),
                const SizedBox(height: 16),
                if (sent) ...[
                  Text(t_('Reply sent. Find it in your chat.')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(t_('Done')),
                  ),
                ] else ...[
                  if (!available)
                    Text(t_('Story replies are not available on this server.')),
                  TextField(
                    controller: input,
                    enabled: available && !sending && !uncertain,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 4000,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: t_('Your message')),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        available &&
                            !sending &&
                            (attemptedText ?? input.text.trim()).isNotEmpty
                        ? send
                        : null,
                    child: Text(
                      t_(
                        sending
                            ? 'Sending'
                            : uncertain
                            ? 'Try again'
                            : 'Send reply',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
