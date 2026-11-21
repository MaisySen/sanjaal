/// The API's response body is data, never product copy. Keep only reviewed,
/// fixed domain messages. Unknown validation prose, framework diagnostics and
/// HTML never cross into the UI. Status and structured upload metadata remain
/// on the error for retry and uncertainty decisions.
const _domainMessages = <String>{
  'Amount must be between 1 and 100000 coins.',
  'Cash out between 500 and 100000 coins at a time.',
  'A group can have at most 50 members.',
  'A poll needs a question and 2 to 4 different options, without media.',
  'A post needs text or media.',
  'A reel needs exactly one video.',
  'Calls are not available yet.',
  'Cash out is not switched on yet.',
  'Live rooms are not available yet.',
  'Not enough coins.',
  'One or more users were not found.',
  'Only groups have a member list.',
  'Only groups have a name.',
  'Only the group owner can rename it.',
  'Only the host of a live room can do that.',
  'Safe upload retries are temporarily unavailable. Your draft is kept.',
  'Selected people changed. Find them again.',
  'That request id was already used for a different amount.',
  'The group name cannot be empty.',
  'The original upload was removed or expired. It will not be shared again.',
  'This cash out is already being processed and cannot be canceled.',
  'This draft was already submitted with different content. Check the original before sharing again.',
  'This room has ended.',
  'Top up is not switched on yet.',
  'Transfers are unavailable until verification is complete.',
  'Unknown gift.',
  'User not found.',
  'You already have a live room. End it first.',
  'You can only leave a group.',
  'You cannot message yourself.',
  'You cannot send coins to yourself.',
  'This transfer key already belongs to different details.',
  'No member with that username.',
};

String apiFailureMessage(int status, Iterable<Object?> candidates, {bool mutating = false}) {
  for (final value in candidates) {
    if (value is String && _domainMessages.contains(value)) return value;
  }
  return switch (status) {
    401 => 'Please sign in again.',
    403 => 'You do not have access to do that.',
    404 || 410 => 'This item is unavailable.',
    429 => 'Too many attempts. Wait a moment, then try again.',
    400 || 422 => 'Check the details and try again.',
    _ => mutating
        ? 'Could not confirm the result. Check before trying again.'
        : 'Could not load this.',
  };
}
