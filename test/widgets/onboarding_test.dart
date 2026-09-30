import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/request_failure.dart';
import 'package:haqor/src/tutor/onboarding.dart';

void _fail(String request, String message) {
  assignRustSignal['RequestFailed']!(
    RequestFailed(
      request: request,
      key: '',
      message: message,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(home: TutorEntryPage(sendRequest: sent.add)),
    );
    return sent;
  }

  testWidgets('an unreadable onboarding status is an error, not a skip', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.single, isA<GetOnboardingStatus>());

    _fail(requestOnboardingStatus, 'disk I/O error');
    await tester.pump();
    expect(find.textContaining('disk I/O error'), findsOneWidget);
    expect(find.text('Do you already know the Hebrew alphabet?'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetOnboardingStatus>(), hasLength(2));

    assignRustSignal['OnboardingStatus']!(
      const OnboardingStatus(needed: true, tierCount: 5).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    expect(
      find.text('Do you already know the Hebrew alphabet?'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a status that never comes offers a retry', (tester) async {
    await pump(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed calibration probe can be asked again', (tester) async {
    final sent = await pump(tester);
    assignRustSignal['OnboardingStatus']!(
      const OnboardingStatus(needed: true, tierCount: 5).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    await tester.tap(find.text('Yes, I can already read Hebrew'));
    await tester.pump();
    final probe = sent.whereType<GetCalibrationProbe>().single;

    _fail(requestCalibrationProbe, 'no probe');
    await tester.pump();
    expect(find.textContaining('no probe'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    final probes = sent.whereType<GetCalibrationProbe>().toList();
    expect(probes, hasLength(2));
    expect(probes.last.tier, probe.tier);
    await tester.pumpWidget(const SizedBox());
  });
}
