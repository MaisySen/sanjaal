import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'glass/glass_button.dart';
import 'ui.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.session});
  final Session session;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool register = false;
  bool busy = false;
  String? error;

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
                    const Center(child: Logo(size: 84)),
                    const SizedBox(height: 16),
                    Text('Sanjaal', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(t_('Your Nepali community'), textAlign: TextAlign.center),
                    const SizedBox(height: 32),
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
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: GlassButton(label: busy ? 'Signing in' : (register ? t_('Create account') : t_('Sign in')), onPressed: busy ? null : _submit),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => setState(() {
                        register = !register;
                        error = null;
                      }),
                      child: Text(register ? 'I already have an account' : 'Create an account'),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: GlassButton(label: 'Continue with Google', primary: false, onPressed: busy ? null : () => _social('google-oauth2')),
                    ),
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
