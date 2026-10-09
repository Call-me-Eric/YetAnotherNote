import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_page/src/ui/text_box_view.dart';

void main() {
  testWidgets('markdown renderer draws headings, emphasis, and formulas', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            source: '# 标题\n\n- 一项\n2. 第二\n\n这是 *斜体* 和 **强调**\n\n'
                r'值 $\frac12$ 和 $\frac{a}{b}$',
            width: 320,
          ),
        ),
      ),
    );

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('一项'), findsOneWidget);
    expect(find.textContaining('2.'), findsOneWidget);
    expect(find.textContaining('斜体'), findsOneWidget);
    expect(find.textContaining('强调'), findsOneWidget);
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'\frac'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });
}
