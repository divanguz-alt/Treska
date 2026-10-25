import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(DraggableScrollableController controller) {
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
              builder: (context, scrollController) => Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _Header(),
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              for (var i = 0; i < 2; i++)
                                SizedBox(height: 40, child: Text('row $i')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Header extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 124;

  @override
  double get maxExtent => 124;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: Colors.white,
      child: const Center(child: Text('HEADER')),
    );
  }

  @override
  bool shouldRebuild(covariant _Header oldDelegate) => false;
}

void main() {
  testWidgets('dragging the pinned header down shrinks the sheet',
      (tester) async {
    final controller = DraggableScrollableController();
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.6, 0.01));

    // The sheet starts 40% down the screen. Drag its header down by 30% of the
    // screen height and check that the sheet actually follows.
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final start = Offset(200, screen * 0.42);
    await tester.dragFrom(start, Offset(0, screen * 0.3));
    await tester.pumpAndSettle();

    expect(controller.size, lessThan(0.45),
        reason: 'sheet should shrink when the header is dragged down');
  });
}
