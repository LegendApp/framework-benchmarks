import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:chat_history_flutter/markdown_style.dart';

void main() {
  testWidgets(
    'dense lists retain formatted content, block gaps, and highlighted code',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                width: 700,
                child: MarkdownBody(
                  data: 'Intro\n\n- **first**\n- second\n- third\n\nAfter\n\n```js\nconst answer = 42;\n```',
                  bulletBuilder: transcriptBullet,
                  listItemCrossAxisAlignment:
                      MarkdownListItemCrossAxisAlignment.start,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  styleSheet: transcriptMarkdownStyle(Theme.of(context)),
                  builders: {'pre': CodePaneBuilder()},
                ),
              ),
            ),
          ),
        ),
      );
      Finder text(String value) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == value,
      );
      expect(text('first'), findsOneWidget);
      expect(
        tester.getTopLeft(text('second')).dy -
            tester.getTopLeft(text('first')).dy,
        closeTo(22, 0.1),
      );
      expect(
        tester.getTopLeft(text('third')).dy -
            tester.getTopLeft(text('second')).dy,
        closeTo(22, 0.1),
      );
      expect(
        tester.getTopLeft(text('After')).dy -
            tester.getTopLeft(text('third')).dy,
        closeTo(38, 0.1),
      );
      final code = tester.widget<RichText>(text('const answer = 42;')).text;
      bool colored(InlineSpan s) =>
          s.style?.color == const Color(0xffff7b72) ||
          (s is TextSpan && (s.children?.any(colored) ?? false));
      expect(colored(code), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('nested lists keep 22-point lines and 24-point nesting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MarkdownBody(
              data: '# Heading\n\n- parent\n  - nested\n- sibling',
              bulletBuilder: transcriptBullet,
              listItemCrossAxisAlignment:
                  MarkdownListItemCrossAxisAlignment.start,
              styleSheet: transcriptMarkdownStyle(Theme.of(context)),
            ),
          ),
        ),
      ),
    );
    Finder text(String value) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == value,
    );
    final parent = tester.getTopLeft(text('parent'));
    final nested = tester.getTopLeft(text('nested'));
    expect(nested.dy - parent.dy, closeTo(22, 0.1));
    expect(nested.dx - parent.dx, closeTo(24, 0.1));
    expect(parent.dy - tester.getTopLeft(text('Heading')).dy, closeTo(36, 0.1));
  });
}
