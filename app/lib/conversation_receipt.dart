/// A direct-chat receipt must describe this selected pair before the caller
/// can hand it to a conversation screen. This is response consistency only.
Map<String, dynamic> checkedDirectConversation(
  dynamic response,
  String owner,
  Map<String, dynamic> recipient,
) {
  if (response is! Map || response['conversation'] is! Map) {
    throw const FormatException('Invalid conversation');
  }
  final conversation = (response['conversation'] as Map)
      .cast<String, dynamic>();
  final members = conversation['members'];
  if (conversation['public_id'] is! String ||
      (conversation['public_id'] as String).trim().isEmpty ||
      conversation['type'] != 'direct' ||
      members is! List ||
      members.length != 2 ||
      members.any(
        (member) =>
            member is! Map ||
            member['public_id'] is! String ||
            member['username'] is! String ||
            (member['username'] as String).trim().isEmpty,
      ) ||
      owner == recipient['public_id'] ||
      members.where((member) => member['public_id'] == owner).length != 1 ||
      members
              .where(
                (member) =>
                    member['public_id'] == recipient['public_id'] &&
                    member['username'] == recipient['username'],
              )
              .length !=
          1) {
    throw const FormatException('Conversation does not match selected member');
  }
  return conversation;
}
