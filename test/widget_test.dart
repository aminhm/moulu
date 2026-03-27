import 'package:flutter_test/flutter_test.dart';
import 'package:moulu/main.dart';

void main() {
  testWidgets('renders Persian setup and reveal entry', (tester) async {
    await tester.pumpWidget(const MouluApp());

    expect(
      find.text('تقسیم نقش با ترتیب واقعی بیدار شدن نقش‌ها.'),
      findsOneWidget,
    );
    expect(find.text('ساخت کارت‌های نقش'), findsOneWidget);
    expect(find.text('اتاق نمایش نقش'), findsOneWidget);
  });
}
