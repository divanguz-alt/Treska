import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(
  DraggableScrollableController controller, {
  required VoidCallback onCollapse,
  required VoidCallback onRestore,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DraggableScrollableSheet(
              controller: controller,
              minChildSize: 0,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0, 0.3, 0.6, 0.9],
              builder: (context, scrollController) => ListView(
                controller: scrollController,
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 40, child: Text('row $i')),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: onCollapse,
                  child: const Text('collapse'),
                ),
                ElevatedButton(
                  onPressed: onRestore,
                  child: const Text('restore'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('sheet collapses to zero and restores', (tester) async {
    final controller = DraggableScrollableController();
    await tester.pumpWidget(app(
      controller,
      onCollapse: () => controller.animateTo(0,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut),
      onRestore: () => controller.animateTo(0.6,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut),
    ));
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);
    expect(controller.size, closeTo(0.6, 0.01));

    await tester.tap(find.text('collapse'));
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);
    expect(controller.size, closeTo(0, 0.01));

    await tester.tap(find.text('restore'));
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);
    expect(controller.size, closeTo(0.6, 0.01));
  });
}
