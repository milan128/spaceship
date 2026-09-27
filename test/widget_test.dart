import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_anti_gravity/anti_gravity_game.dart';

void main() {
  testWidgets('AntiGravityGameApp loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const AntiGravityGameApp());
    expect(find.byType(AntiGravityGameApp), findsOneWidget);
  });
}
