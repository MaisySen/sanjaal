import 'api.dart';

/// Auth screens must never display identity-provider prose or platform details.
/// Even /auth/me can fail after a valid token grant, so this boundary applies
/// to the whole UI operation rather than just the token endpoint.
String authFailureMessage(Object error, {bool registering = false}) {
  const safe = {
    'Wrong email or password.',
    'Your account was created. Sign in to continue.',
    'The server took too long. Try again.',
    'No connection. Check your internet and try again.',
    'Could not save your sign-in securely. Try again.',
    'Sign in was cancelled.',
    'Please sign in again.',
    'Too many attempts. Wait a moment, then try again.',
    'That email or username is already taken.',
    'Your password does not meet the account security rules. Choose a stronger password.',
    'Could not send the reset link. Try again.',
    'Wait a minute before requesting another reset link.',
  };
  if (error is ApiError) {
    if (safe.contains(error.message)) return error.message;
    if (error.status == 429) {
      return 'Too many attempts. Wait a moment, then try again.';
    }
  }
  return registering
      ? 'Could not create your account. Try again.'
      : 'Sign in failed. Try again.';
}
