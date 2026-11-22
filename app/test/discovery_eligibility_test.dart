import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/discovery_eligibility.dart';

DiscoveryEligibility candidate({
  String kind = 'post',
  bool? consent = true,
  DiscoveryModeration? moderation = DiscoveryModeration.approved,
  bool? public = true,
  bool? private = false,
  bool? blocked = false,
  bool? deleted = false,
  bool? preview = true,
}) => DiscoveryEligibility(
  kind: kind,
  authorOptedIn: consent,
  moderation: moderation,
  publicPost: public,
  privateBytes: private,
  blockedEitherWay: blocked,
  deleted: deleted,
  hasPreview: preview,
);
void main() {
  test('explicit eligible photo/reel only', () {
    expect(candidate().canRecommend, isTrue);
    expect(candidate(kind: 'reel').canRecommend, isTrue);
    expect(candidate(kind: 'story').canRecommend, isFalse);
    expect(candidate(kind: 'chat').canRecommend, isFalse);
  });
  test('old public availability never backfills author consent', () {
    expect(candidate(consent: null).canRecommend, isFalse);
    expect(candidate(consent: false).canRecommend, isFalse);
  });
  test('missing, pending and rejected moderation are ineligible', () {
    for (final state in [
      null,
      DiscoveryModeration.pending,
      DiscoveryModeration.rejected,
    ]) {
      expect(candidate(moderation: state).canRecommend, isFalse);
    }
  });
  test(
    'unknown and denied audience/media/block/delete/preview facts fail closed',
    () {
      for (final value in [null, false]) {
        expect(candidate(public: value).canRecommend, isFalse);
        expect(candidate(preview: value).canRecommend, isFalse);
      }
      for (final value in [null, true]) {
        expect(candidate(private: value).canRecommend, isFalse);
        expect(candidate(blocked: value).canRecommend, isFalse);
        expect(candidate(deleted: value).canRecommend, isFalse);
      }
    },
  );
}
