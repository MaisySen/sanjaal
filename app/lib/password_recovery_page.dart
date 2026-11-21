import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'auth_failure.dart';
import 'ui.dart' show t_;

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key, required this.session, this.initialEmail = ''});
  final Session session;
  final String initialEmail;

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.initialEmail.trim();
    _email = TextEditingController(text: value.contains('@') ? value : '');
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      await widget.session.requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) setState(() => _error = t_(authFailureMessage(error)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t_('Account recovery'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t_(_sent ? 'Check your inbox' : 'Forgot password?'),
                  style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                if (_sent) ...[
                  Semantics(liveRegion: true, child: Text(t_(
                    'If an account uses that email, you will receive a link to reset your password.',
                  ))),
                  const SizedBox(height: 16),
                  Text(t_('Check your spam folder too. Only the newest reset link can be used.')),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => Navigator.of(context).pop(),
                    child: Text(t_('Back to sign in'), textAlign: TextAlign.center)),
                  TextButton(onPressed: () => setState(() { _sent = false; _error = null; }),
                    child: Text(t_('Use a different email'), textAlign: TextAlign.center)),
                ] else ...[
                  Text(t_('Enter the email you use for Sanjaal.')),
                  const SizedBox(height: 24),
                  Form(key: _form, child: TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(labelText: t_('Email'), errorMaxLines: 4),
                    validator: (value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((value ?? '').trim())
                        ? null : t_('Enter a valid email'),
                    onFieldSubmitted: (_) => _submit(),
                  )),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(liveRegion: true, child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _busy ? null : _submit,
                    child: _busy
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
                            strokeWidth: 2, semanticsLabel: t_('Sending reset link')))
                        : Text(t_('Send reset link'), textAlign: TextAlign.center)),
                ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text(t_('Used a sign-in provider instead? Reset your password with that provider.')),
              ],
            ),
          )),
        ),
      ),
    );
  }
}
