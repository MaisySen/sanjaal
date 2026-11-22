import 'glass/glass_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show TextInput;
import 'api.dart';
import 'auth_failure.dart';
import 'password_recovery_page.dart';
import 'language_settings_page.dart';
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
  bool showPassword = false;
  String? error;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !_form.currentState!.validate()) return;
    final email = _email.text.trim(), username = _username.text.trim(), password = _password.text;
    final creating = register;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (creating) {
        await widget.session.register(email, username, password);
      } else {
        await widget.session.login(email, password);
      }
      // Only a completed credential sign-in may offer to save credentials.
      // Leaving a failed or abandoned form must cancel its autofill context.
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (creating && e is AccountCreatedSignInRequired) {
            register = false;
            showPassword = false;
          }
          error = t_(authFailureMessage(e, registering: creating));
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _social(String connection) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.loginSocial(connection);
    } catch (e) {
      if (mounted) setState(() => error = t_(authFailureMessage(e)));
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
              child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment:Alignment.centerRight,child:TextButton(
                      onPressed:busy?null:() async {
                        setState(() {showPassword=false;error=null;});
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const LanguageSettingsPage()));
                      },child:Text(t_('Language')))),
                    const Center(child: Logo(size: 84)),
                    const SizedBox(height: 16),
                    Text('Sanjaal', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(t_('Your Nepali community'), textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      enabled: !busy,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: [register ? AutofillHints.email : AutofillHints.username],
                      textCapitalization: TextCapitalization.none,
                      enableSuggestions: false,
                      decoration: InputDecoration(labelText: t_(register ? 'Email' : 'Email or username'), floatingLabelBehavior: FloatingLabelBehavior.always, errorMaxLines: 4, border: const OutlineInputBorder()),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return t_('Required');
                        if (register && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return t_('Enter a valid email');
                        return null;
                      },
                    ),
                    if (register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        autofillHints: const [AutofillHints.newUsername],
                        textCapitalization: TextCapitalization.none,
                        enableSuggestions: false,
                        enabled: !busy,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(labelText: t_('Username'), helperText: t_('3 to 30 letters, numbers, dots or underscores'), helperMaxLines: 4, errorMaxLines: 4, floatingLabelBehavior: FloatingLabelBehavior.always, border: const OutlineInputBorder()),
                        validator: (v) => RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch((v ?? '').trim()) ? null : t_('Use 3 to 30 letters, numbers, dots or underscores'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      obscureText: !showPassword,
                      autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(labelText: t_('Password'), errorMaxLines: 4, floatingLabelBehavior: FloatingLabelBehavior.always, border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: busy ? null : () => setState(() => showPassword = !showPassword), tooltip: t_(showPassword ? 'Hide password' : 'Show password'), icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility))),
                      validator: (v) => register
                          ? ((v ?? '').length < 8 ? t_('At least 8 characters') : null)
                          : ((v ?? '').isEmpty ? t_('Required') : null),
                      onFieldSubmitted: (_) => busy ? null : _submit(),
                    ),
                    if (!register) Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => PasswordRecoveryPage(session: widget.session, initialEmail: _email.text),
                        )),
                        child: Text(t_('Forgot password?')),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(liveRegion: true, child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                    ],
                    const SizedBox(height: 20),
                    GlassAction(
                      onPressed: busy ? null : _submit,
                      busy: busy,
                      label: register ? t_('Create account') : t_('Sign in'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => setState(() {
                        register = !register;
                        error = null;
                        showPassword = false;
                      }),
                      child: Text(t_(register ? 'I already have an account' : 'Create an account')),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    GlassAction(onPressed: busy ? null : () => _social('google-oauth2'), primary: false, label: t_('Continue with Google')),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(t_('Social sign in is in testing.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    ),
                    if (busy) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t_('The first request can take up to a minute while the server wakes up.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
