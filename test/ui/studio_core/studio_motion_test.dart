import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_number.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_presence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_drawer_motion.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_page_transition.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_reveal.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_spotlight_surface.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_metric_card.dart';

void main() {
  testWidgets('StudioReveal renders final state when animations are disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StudioReveal(
            child: Text('Ready'),
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    final reveal = find.byType(StudioReveal);
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: reveal, matching: find.byType(FadeTransition)),
    );
    final scale = tester.widget<ScaleTransition>(
      find.descendant(of: reveal, matching: find.byType(ScaleTransition)),
    );
    expect(fade.opacity.value, 1);
    expect(scale.scale.value, 1);
  });

  testWidgets('StudioPageTransition switches content by keyed child',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioPageTransition(
          transitionKey: ValueKey('one'),
          child: Text('One'),
        ),
      ),
    );

    expect(find.text('One'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: StudioPageTransition(
          transitionKey: ValueKey('two'),
          child: Text('Two'),
        ),
      ),
    );
    await tester.pump(StudioMotionTokens.fast);

    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('StudioPageTransition showcase reveal outlasts micro motion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioPageTransition(
          transitionKey: ValueKey('one'),
          child: Text('One'),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: StudioPageTransition(
          transitionKey: ValueKey('two'),
          child: Text('Two'),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 120));

    final fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('studio-page-transition')),
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
  });

  testWidgets('StudioPageTransition does not render a sweep during switches',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioPageTransition(
          transitionKey: ValueKey('one'),
          child: Text('One'),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: StudioPageTransition(
          transitionKey: ValueKey('two'),
          child: Text('Two'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey('studio-page-sweep')),
      findsNothing,
    );
  });

  testWidgets('StudioInteractiveSurface lifts only while hovered or pressed',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: StudioInteractiveSurface(
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );

    AnimatedScale scaleWidget() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));

    expect(scaleWidget().scale, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byType(SizedBox)));
    await tester.pump(StudioMotionTokens.fast);

    expect(scaleWidget().scale, greaterThan(1));

    await mouse.moveTo(Offset.zero);
    await tester.pump(StudioMotionTokens.fast);

    expect(scaleWidget().scale, 1);
  });

  testWidgets('StudioStaggeredReveal renders final state when disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StudioStaggeredReveal(
            index: 6,
            columns: 3,
            child: Text('Card'),
          ),
        ),
      ),
    );

    expect(find.text('Card'), findsOneWidget);
    final reveal = find.byType(StudioStaggeredReveal);
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: reveal, matching: find.byType(FadeTransition)),
    );
    final scale = tester.widget<ScaleTransition>(
      find.descendant(of: reveal, matching: find.byType(ScaleTransition)),
    );
    expect(fade.opacity.value, 1);
    expect(scale.scale.value, 1);
  });

  testWidgets('StudioStaggeredReveal uses bounded grid delays', (tester) async {
    expect(
      StudioStaggeredReveal.delayFor(
        index: 8,
        columns: 4,
        itemDelay: const Duration(milliseconds: 24),
        maxStaggeredItems: 10,
      ),
      const Duration(milliseconds: 48),
    );
    expect(
      StudioStaggeredReveal.delayFor(
        index: 80,
        columns: 4,
        itemDelay: const Duration(milliseconds: 24),
        maxStaggeredItems: 10,
      ),
      const Duration(milliseconds: 72),
    );
  });

  testWidgets('StudioAnimatedPresence keeps content for the exit motion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioAnimatedPresence(
          visible: true,
          child: Text('Optional section'),
        ),
      ),
    );

    expect(find.text('Optional section'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: StudioAnimatedPresence(
          visible: false,
          child: Text('Optional section'),
        ),
      ),
    );

    expect(find.text('Optional section'), findsOneWidget);

    await tester.pump(
      StudioMotionTokens.medium + const Duration(milliseconds: 1),
    );
    await tester.pump();

    expect(find.text('Optional section'), findsNothing);
  });

  testWidgets('StudioAnimatedPresence snaps to hidden when disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StudioAnimatedPresence(
            visible: true,
            child: Text('Instant section'),
          ),
        ),
      ),
    );

    expect(find.text('Instant section'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StudioAnimatedPresence(
            visible: false,
            child: Text('Instant section'),
          ),
        ),
      ),
    );

    expect(find.text('Instant section'), findsNothing);
  });

  testWidgets('StudioDrawerPushTransition uses horizontal drawer motion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioDrawerPushTransition(
          depth: 0,
          transitionKey: ValueKey('drawer-home'),
          child: Text('Home'),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: StudioDrawerPushTransition(
          depth: 1,
          transitionKey: ValueKey('drawer-detail'),
          child: Text('Detail'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final transition = tester.widget<SlideTransition>(
      find
          .descendant(
            of: find.byType(StudioDrawerPushTransition),
            matching: find.byType(SlideTransition),
          )
          .last,
    );
    expect(transition.position.value.dx, greaterThan(0));
    expect(transition.position.value.dy.abs(), lessThan(0.01));
  });

  testWidgets('StudioDrawerPushTransition clips switching layers to bounds',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 180,
          height: 80,
          child: StudioDrawerPushTransition(
            depth: 0,
            transitionKey: ValueKey('drawer-home'),
            child: SizedBox(width: 180, height: 80, child: Text('Home')),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 180,
          height: 80,
          child: StudioDrawerPushTransition(
            depth: 1,
            transitionKey: ValueKey('drawer-detail'),
            child: SizedBox(width: 180, height: 80, child: Text('Detail')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final stack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(StudioDrawerPushTransition),
        matching: find.byType(Stack),
      ),
    );
    expect(stack.clipBehavior, Clip.hardEdge);
    expect(stack.fit, StackFit.expand);
  });

  testWidgets('StudioInteractiveSurface lets hover chrome use reserved inset',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 48,
            child: StudioInteractiveSurface(
              hoverScale: 1.04,
              hoverBorderColor: Colors.yellow,
              hoverShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                ),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final stack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(StudioInteractiveSurface),
        matching: find.byType(Stack),
      ),
    );
    expect(stack.clipBehavior, Clip.none);
  });

  testWidgets('StudioMotionSequenceRegion maps drawer to horizontal entrance',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioMotionSequenceRegion(
          region: StudioMotionRegion.drawer,
          child: Text('Drawer'),
        ),
      ),
    );

    final reveal = tester.widget<StudioReveal>(
      find.descendant(
        of: find.byType(StudioMotionSequenceRegion),
        matching: find.byType(StudioReveal),
      ),
    );
    expect(find.text('Drawer'), findsOneWidget);
    expect(reveal.beginOffset.dx, lessThan(0));
    expect(reveal.beginOffset.dy, 0);
  });

  testWidgets('StudioAnimatedNumber counts to the target without overshoot',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioAnimatedNumber(value: 42),
      ),
    );

    Text animatedText() => tester.widget<Text>(
          find.descendant(
            of: find.byType(StudioAnimatedNumber),
            matching: find.byType(Text),
          ),
        );

    expect(animatedText().data, '0');
    await tester.pump(const Duration(milliseconds: 160));
    final middle = int.parse(animatedText().data!);
    expect(middle, inInclusiveRange(1, 41));
    await tester.pumpAndSettle();
    expect(animatedText().data, '42');
  });

  testWidgets('StudioAnimatedNumber respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StudioAnimatedNumber(value: 42),
        ),
      ),
    );

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets(
      'StudioAnimatedNumber animates from its displayed value on update',
      (tester) async {
    Widget buildNumber(int value) {
      return MaterialApp(home: StudioAnimatedNumber(value: value));
    }

    await tester.pumpWidget(buildNumber(12));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);

    await tester.pumpWidget(buildNumber(24));
    await tester.pump(const Duration(milliseconds: 160));
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(StudioAnimatedNumber),
        matching: find.byType(Text),
      ),
    );
    expect(int.parse(text.data!), inInclusiveRange(13, 23));
    await tester.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('StudioSpotlightSurface reveals its glow only on hover',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: StudioSpotlightSurface(child: SizedBox.expand()),
          ),
        ),
      ),
    );

    AnimatedOpacity spotlightOpacity() => tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(StudioSpotlightSurface),
            matching: find.byType(AnimatedOpacity),
          ),
        );

    expect(spotlightOpacity().opacity, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(StudioSpotlightSurface)),
    );
    await tester.pump();
    expect(spotlightOpacity().opacity, 1);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(spotlightOpacity().opacity, 0);
  });

  testWidgets('StudioMetricCard opts into numeric animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudioMetricCard(
          label: 'Assets',
          value: '12',
          icon: Icons.inventory_2_outlined,
          animateNumericValue: true,
        ),
      ),
    );

    expect(find.byType(StudioAnimatedNumber), findsOneWidget);
  });
}
