// Bounded synthetic public-thumbnail transport. Not native decoder acceptance.
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/discovery_route.dart';
import 'package:sanjaal/discovery_page.dart';
import 'package:sanjaal/discovery_contract.dart';
import 'package:sanjaal/discovery_preview.dart';
import 'package:sanjaal/discovery_paging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/discovery_network_image.dart';

final url = Uri.parse(
  'https://fixture.invalid/api/v1/media/00000000-0000-4000-8000-000000000001',
);
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump();
  }
}

void main() {
  test(
    'cache keys isolate result generations and retired keys reject reuse',
    () async {
      final a = DiscoveryImageScope(), b = DiscoveryImageScope();
      final first = DiscoveryNetworkImage(url, a),
          same = DiscoveryNetworkImage(url, a),
          next = DiscoveryNetworkImage(url, b);
      expect(first, same);
      expect(next, isNot(equals(first)));
      expect(NetworkImage(url.toString()), isNot(equals(first)));
      var aborted = 0;
      a.attach(() => aborted++);
      a.retire();
      expect(aborted, 1);
      expect(a.active, isFalse);
      expect(await first.obtainKey(ImageConfiguration.empty), first);
      await expectLater(a.acquire(), throwsStateError);
      expect(await next.obtainKey(ImageConfiguration.empty), next);
    },
  );
  test('scope allows four active requests, bounds its queue and cancels queued work', () async {
    final scope = DiscoveryImageScope();
    final releases = [for (var i = 0; i < 4; i++) await scope.acquire()];
    var admitted = false;
    final fifth = scope.acquire().then((release) {
      admitted = true;
      return release;
    });
    await Future<void>.delayed(Duration.zero);
    expect(admitted, isFalse);
    releases.first();
    final fifthRelease = await fifth;
    expect(admitted, isTrue);
    releases.first();
    final waiting = [
      for (var i = 0; i < 48; i++)
        expectLater(scope.acquire(), throwsStateError),
    ];
    await expectLater(scope.acquire(), throwsStateError);
    scope.retire();
    await Future.wait(waiting);
    for (final release in releases.skip(1)) {
      release();
    }
    fifthRelease();
  });
  for (final mode in [
    'valid',
    'redirect',
    'mime',
    'declared size',
    'stream size',
    'retired pending',
  ]) {
    testWidgets('thumbnail $mode is bounded and never follows a redirect', (
      t,
    ) async {
      final scope = DiscoveryImageScope(),
          pending = Completer<http.StreamedResponse>();
      var reads = 0, decoded = 0, errors = 0;
      final bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
          .readAsBytesSync();
      await http.runWithClient(
        () async {
          final provider = DiscoveryNetworkImage(url, scope);
          final stream = provider.resolve(ImageConfiguration.empty);
          final listener = ImageStreamListener(
            (image, sync) {
              decoded++;
              image.dispose();
            },
            onError: (Object e, StackTrace? s) {
              errors++;
            },
          );
          stream.addListener(listener);
          await flush(t);
          if (mode == 'retired pending') {
            scope.retire();
            pending.complete(
              http.StreamedResponse(
                Stream.value(bytes),
                200,
                headers: {'content-type': 'image/jpeg'},
              ),
            );
            await flush(t);
          }
          expect(reads, 1);
          expect(decoded, mode == 'valid' ? 1 : 0);
          expect(errors, mode == 'valid' ? 0 : 1);
          scope.retire();
          stream.removeListener(listener);
          await provider.evict();
        },
        () => MockClient.streaming((request, body) async {
          reads++;
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('authorization'), isFalse);
          if (mode == 'retired pending') return pending.future;
          if (mode == 'redirect') {
            return http.StreamedResponse(
              const Stream.empty(),
              302,
              headers: {'location': 'https://elsewhere.invalid/photo'},
            );
          }
          if (mode == 'mime') {
            return http.StreamedResponse(
              Stream.value(bytes),
              200,
              headers: {'content-type': 'video/mp4'},
            );
          }
          if (mode == 'declared size') {
            return http.StreamedResponse(
              const Stream.empty(),
              200,
              contentLength: 9999999,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          if (mode == 'stream size') {
            return http.StreamedResponse(
              Stream.value(List.filled(DiscoveryNetworkImage.maxBytes + 1, 0)),
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'withdrawal evicts real resized pixels and same URL needs a fresh scoped request',
    (t) async {
      final session = Session()..user = {'public_id': 'fixture'};
      var requests = 0;
      final bytes = File('/downloads/sanjaal-highfidelity/mountain.jpg')
          .readAsBytesSync();
      await http.runWithClient(
        () async {
          await t.pumpWidget(
            MaterialApp(
              home: DiscoveryRoute(
                session: session,
                read: (q, c) async => DiscoveryPageData(
                  items: [
                    DiscoveryTile(
                      id: 'fixture',
                      caption: 'Scoped preview',
                      preview: DiscoveryPreview(url: url, video: false),
                    ),
                  ],
                  nextCursor: null,
                  version: 'fixture',
                ),
              ),
            ),
          );
          await flush(t);
          await t.pumpAndSettle();
          expect(requests, 1);
          expect(find.byType(Image), findsOneWidget);
          final old = t.widget<Image>(find.byType(Image)).image;
          final oldKey = await old.obtainKey(ImageConfiguration.empty);
          expect(
            PaintingBinding.instance.imageCache.containsKey(oldKey),
            isTrue,
          );
          final pager = t
              .widget<DiscoveryPage>(find.byType(DiscoveryPage))
              .pager;
          pager.invalidate();
          await flush(t);
          expect(find.byType(Image), findsNothing);
          expect(
            PaintingBinding.instance.imageCache.containsKey(oldKey),
            isFalse,
          );
          await pager.reset(pager.query);
          await flush(t);
          await t.pumpAndSettle();
          expect(requests, 2);
          final next = t.widget<Image>(find.byType(Image)).image;
          expect(
            await next.obtainKey(ImageConfiguration.empty),
            isNot(equals(oldKey)),
          );
          session.user = null;
          session.notifyListeners();
          await flush(t);
          expect(find.byType(Image), findsNothing);
          expect(
            PaintingBinding.instance.imageCache.containsKey(oldKey),
            isFalse,
          );
          expect(requests, 2);
          await t.pumpWidget(const SizedBox());
        },
        () => MockClient((r) async {
          requests++;
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(t.takeException(), isNull);
      session.dispose();
    },
  );
}
