import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'glass/glass_app_bar.dart';
import 'ui.dart' show t_;

/// Leave retired routes without signing out, clearing or replacing the current
/// session. The application root decides between its live account and sign-in.
class SessionRecoveryView extends StatelessWidget {
  const SessionRecoveryView({
    super.key,
    required this.session,
    this.embedded = false,
  });
  final Session session;
  final bool embedded;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final signedIn = session.user?['public_id'] != null;
      void leave() => Navigator.of(context).popUntil((route) => route.isFirst);
      final body = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t_(
                signedIn
                    ? 'This screen is from an earlier sign-in. Go back to continue.'
                    : "You're signed out. Go back to sign in.",
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: leave,
              child: Text(t_(signedIn ? 'Back to account' : 'Back to sign in')),
            ),
          ],
        ),
      );
      return embedded
          ? body
          : Scaffold(
              appBar: ReviewedAppBar(leading: BackButton(onPressed: leave)),
              body: body,
            );
    },
  );
}
