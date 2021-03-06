// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:test/test.dart';

void main() {
  group('$FirebaseDatabase', () {
    const MethodChannel channel = const MethodChannel(
      'plugins.flutter.io/firebase_database',
    );

    int mockHandleId = 0;
    final List<MethodCall> log = <MethodCall>[];
    final FirebaseDatabase database = FirebaseDatabase.instance;

    setUp(() async {
      channel.setMockMethodCallHandler((MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'Query#observe':
            return mockHandleId++;
          case 'FirebaseDatabase#setPersistenceEnabled':
            return true;
          case 'FirebaseDatabase#setPersistenceCacheSizeBytes':
            return true;
          default:
            return null;
        }
      });
      log.clear();
    });

    test('setPersistenceEnabled', () async {
      expect(await database.setPersistenceEnabled(false), true);
      expect(await database.setPersistenceEnabled(true), true);
      expect(
        log,
        equals(<MethodCall>[
          const MethodCall('FirebaseDatabase#setPersistenceEnabled', false),
          const MethodCall('FirebaseDatabase#setPersistenceEnabled', true),
        ]),
      );
    });

    test('setPersistentCacheSizeBytes', () async {
      expect(await database.setPersistenceCacheSizeBytes(42), true);
      expect(
        log,
        equals(<MethodCall>[
          const MethodCall('FirebaseDatabase#setPersistenceCacheSizeBytes', 42),
        ]),
      );
    });

    test('goOnline', () async {
      await database.goOnline();
      expect(
        log,
        equals(<MethodCall>[
          const MethodCall('FirebaseDatabase#goOnline'),
        ]),
      );
    });

    test('goOffline', () async {
      await database.goOffline();
      expect(
        log,
        equals(<MethodCall>[
          const MethodCall('FirebaseDatabase#goOffline'),
        ]),
      );
    });

    test('purgeOutstandingWrites', () async {
      await database.purgeOutstandingWrites();
      expect(
        log,
        equals(<MethodCall>[
          const MethodCall('FirebaseDatabase#purgeOutstandingWrites'),
        ]),
      );
    });

    group('$DatabaseReference', () {
      test('set', () async {
        final dynamic value = <String, dynamic>{'hello': 'world'};
        final int priority = 42;
        await database.reference().child('foo').set(value);
        await database.reference().child('bar').set(value, priority: priority);
        expect(
          log,
          equals(<MethodCall>[
            new MethodCall(
              'DatabaseReference#set',
              <String, dynamic>{
                'path': 'foo',
                'value': value,
                'priority': null
              },
            ),
            new MethodCall(
              'DatabaseReference#set',
              <String, dynamic>{
                'path': 'bar',
                'value': value,
                'priority': priority
              },
            ),
          ]),
        );
      });
      test('update', () async {
        final dynamic value = <String, dynamic>{'hello': 'world'};
        await database.reference().child("foo").update(value);
        expect(
          log,
          equals(<MethodCall>[
            new MethodCall(
              'DatabaseReference#update',
              <String, dynamic>{'path': 'foo', 'value': value},
            ),
          ]),
        );
      });

      test('setPriority', () async {
        final int priority = 42;
        await database.reference().child('foo').setPriority(priority);
        expect(
          log,
          equals(<MethodCall>[
            new MethodCall(
              'DatabaseReference#setPriority',
              <String, dynamic>{'path': 'foo', 'priority': priority},
            ),
          ]),
        );
      });
    });

    group('$Query', () {
      // TODO(jackson): Write more tests for queries
      test('keepSynced, simple query', () async {
        final String path = 'foo';
        final Query query = database.reference().child(path);
        await query.keepSynced(true);
        expect(
          log,
          equals(<MethodCall>[
            new MethodCall(
              'Query#keepSynced',
              <String, dynamic>{
                'path': path,
                'parameters': <String, dynamic>{},
                'value': true
              },
            ),
          ]),
        );
      });
      test('keepSynced, complex query', () async {
        final int startAt = 42;
        final String path = 'foo';
        final String childKey = 'bar';
        final bool endAt = true;
        final String endAtKey = 'baz';
        final Query query = database
            .reference()
            .child(path)
            .orderByChild(childKey)
            .startAt(startAt)
            .endAt(endAt, key: endAtKey);
        await query.keepSynced(false);
        final Map<String, dynamic> expectedParameters = <String, dynamic>{
          'orderBy': 'child',
          'orderByChildKey': childKey,
          'startAt': startAt,
          'endAt': endAt,
          'endAtKey': endAtKey,
        };
        expect(
          log,
          equals(<MethodCall>[
            new MethodCall(
              'Query#keepSynced',
              <String, dynamic>{
                'path': path,
                'parameters': expectedParameters,
                'value': false
              },
            ),
          ]),
        );
      });
      test('observing value events', () async {
        mockHandleId = 87;
        final String path = 'foo';
        final Query query = database.reference().child(path);
        Future<Null> simulateEvent(String value) async {
          await BinaryMessages.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              new MethodCall('Event', <String, dynamic>{
                'handle': 87,
                'snapshot': <String, dynamic>{
                  'key': path,
                  'value': value,
                },
              }),
            ),
            (_) {},
          );
        }

        final AsyncQueue<Event> events = new AsyncQueue<Event>();

        // Subscribe and allow subscription to complete.
        final StreamSubscription<Event> subscription =
            query.onValue.listen(events.add);
        await new Future<Null>.delayed(const Duration(seconds: 0));

        await simulateEvent('1');
        await simulateEvent('2');
        final Event event1 = await events.remove();
        final Event event2 = await events.remove();
        expect(event1.snapshot.key, path);
        expect(event1.snapshot.value, '1');
        expect(event2.snapshot.key, path);
        expect(event2.snapshot.value, '2');

        // Cancel subscription and allow cancellation to complete.
        subscription.cancel();
        await new Future<Null>.delayed(const Duration(seconds: 0));

        expect(
          log,
          equals(<MethodCall>[
            new MethodCall(
              'Query#observe',
              <String, dynamic>{
                'path': path,
                'parameters': <String, dynamic>{},
                'eventType': '_EventType.value'
              },
            ),
            new MethodCall(
              'Query#removeObserver',
              <String, dynamic>{
                'path': path,
                'parameters': <String, dynamic>{},
                'handle': 87,
              },
            ),
          ]),
        );
      });
    });
  });
}

/// Queue whose remove operation is asynchronous, awaiting a corresponding add.
class AsyncQueue<T> {
  Map<int, Completer<T>> _completers = <int, Completer<T>>{};
  int _nextToRemove = 0;
  int _nextToAdd = 0;

  void add(T element) {
    _completer(_nextToAdd++).complete(element);
  }

  Future<T> remove() {
    final Future<T> result = _completer(_nextToRemove++).future;
    return result;
  }

  Completer<T> _completer(int index) {
    if (_completers.containsKey(index)) {
      return _completers.remove(index);
    } else {
      return _completers[index] = new Completer<T>();
    }
  }
}
