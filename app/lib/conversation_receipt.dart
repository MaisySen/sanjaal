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

/// A new group receipt must match the requested creator, title and member set.
/// Checking a reply does not prevent or undo server-side creation.
Map<String, dynamic> checkedGroupConversation(
  dynamic response,
  String owner,
  List<Map<String, dynamic>> recipients,
  String title,
) {
  if (response is! Map || response['conversation'] is! Map) {
    throw const FormatException('Invalid group conversation');
  }
  final conversation = (response['conversation'] as Map)
      .cast<String, dynamic>();
  final members = conversation['members'];
  if (owner.trim().isEmpty ||
      title.trim().isEmpty ||
      recipients.isEmpty ||
      recipients.length > 49 ||
      recipients.any(
        (person) =>
            person['public_id'] is! String ||
            (person['public_id'] as String).trim().isEmpty ||
            person['public_id'] == owner ||
            person['username'] is! String ||
            (person['username'] as String).trim().isEmpty,
      ) ||
      recipients.map((person) => person['public_id']).toSet().length !=
          recipients.length ||
      recipients.map((person) => person['username']).toSet().length !=
          recipients.length ||
      conversation['public_id'] is! String ||
      (conversation['public_id'] as String).trim().isEmpty ||
      conversation['type'] != 'group' ||
      conversation['title'] != title ||
      conversation['my_role'] != 'owner' ||
      members is! List ||
      members.length != recipients.length + 1 ||
      members.any(
        (person) =>
            person is! Map ||
            person['public_id'] is! String ||
            (person['public_id'] as String).trim().isEmpty ||
            person['username'] is! String ||
            (person['username'] as String).trim().isEmpty,
      ) ||
      members.where((person) => person['public_id'] == owner).length != 1 ||
      recipients.any(
        (expected) =>
            members
                .where(
                  (person) =>
                      person['public_id'] == expected['public_id'] &&
                      person['username'] == expected['username'],
                )
                .length !=
            1,
      )) {
    throw const FormatException('Group does not match selected people');
  }
  return conversation;
}
