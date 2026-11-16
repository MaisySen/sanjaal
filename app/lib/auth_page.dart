import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'ui.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.session, this.initialRegister = false});
  final Session session;
  final bool initialRegister;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  late bool register = widget.initialRegister;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await widget.session.register(_email.text.trim(), _username.text.trim(), _password.text);
      } else {
        await widget.session.login(_email.text.trim(), _password.text);
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _social(String connection) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.loginSocial(connection);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: Alignment.centerLeft, child: Logo(size: 60)),
                    const SizedBox(height: 36),
                    Text(t_(register ? 'Make yourself at home' : 'Welcome back'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6)),
                    const SizedBox(height: 8),
                    Text(t_(register ? 'Create your place in the community.' : 'Sign in to pick up where you left off.'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: register ? 'Email' : 'Email or username', border: const OutlineInputBorder()),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Required';
                        if (register && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    if (register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(labelText: 'Username', helperText: '3 to 30 letters, numbers, dots or underscores', border: OutlineInputBorder()),
                        validator: (v) => RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch((v ?? '').trim()) ? null : 'Use 3 to 30 letters, numbers, dots or underscores',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                      validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
                      onFieldSubmitted: (_) => busy ? null : _submit(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(register ? t_('Create account') : t_('Sign in')),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => setState(() {
                        register = !register;
                        error = null;
                      }),
                      child: Text(t_(register ? 'I already have an account' : 'Create an account')),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    OutlinedButton(onPressed: busy ? null : () => _social('google-oauth2'), child: const Text('Continue with Google')),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Social sign in is in testing.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                    ),
                    if (busy) const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('The first request can take up to a minute while the server wakes up.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
