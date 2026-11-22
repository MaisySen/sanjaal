/// Provisional local-only Discovery policy, not owner-approved for activation.
/// This is not a moderation service or a substitute for server authorization.
/// No existing post is opted in, migrated or amplified by this predicate.
enum DiscoveryModeration { approved, pending, rejected }

class DiscoveryEligibility {
  const DiscoveryEligibility({
    required this.kind,
    required this.authorOptedIn,
    required this.moderation,
    required this.publicPost,
    required this.privateBytes,
    required this.blockedEitherWay,
    required this.deleted,
    required this.hasPreview,
  });
  final String kind;
  final bool? authorOptedIn,
      publicPost,
      privateBytes,
      blockedEitherWay,
      deleted,
      hasPreview;
  final DiscoveryModeration? moderation;

  /// Unknown policy, audience or media classification fails closed. A producer
  /// must actually establish each fact; this predicate invents none of them.
  bool get canRecommend =>
      (kind == 'post' || kind == 'reel') &&
      authorOptedIn == true &&
      moderation == DiscoveryModeration.approved &&
      publicPost == true &&
      privateBytes == false &&
      blockedEitherWay == false &&
      deleted == false &&
      hasPreview == true;
}
