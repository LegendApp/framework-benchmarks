import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Keep Flutter's real GFM table cells, with the same content width bounds as RN.
class TranscriptColumnWidth extends IntrinsicColumnWidth {
  const TranscriptColumnWidth();
  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super.minIntrinsicWidth(cells, containerWidth).clamp(60, 316);
  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super.maxIntrinsicWidth(cells, containerWidth).clamp(60, 316);
}

class CodePaneBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final language =
        code?.attributes['class']?.replaceFirst('language-', '') ?? 'Code';
    final text = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.isEmpty
                      ? ''
                      : '${language[0].toUpperCase()}${language.substring(1)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 24),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  child: const Text('Copy'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              text,
              softWrap: false,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12,
                height: 1.5,
                color: Color(0xfff5f5f5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Flutter Markdown re-parses when the stylesheet identity changes. Keep it stable
// for a given ThemeData while retaining the package's full GFM renderer.
final _styles = Expando<MarkdownStyleSheet>();
MarkdownStyleSheet transcriptMarkdownStyle(ThemeData theme) {
  return _styles[theme] ??= MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: const TextStyle(fontSize: 15, height: 22 / 15),
    h1: const TextStyle(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.bold,
    ),
    h2: const TextStyle(
      fontSize: 19,
      height: 25 / 19,
      fontWeight: FontWeight.bold,
    ),
    h3: const TextStyle(
      fontSize: 20,
      height: 28 / 20,
      fontWeight: FontWeight.bold,
    ),
    h4: const TextStyle(
      fontSize: 18,
      height: 26 / 18,
      fontWeight: FontWeight.bold,
    ),
    h5: const TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.bold,
    ),
    h6: const TextStyle(
      fontSize: 14,
      height: 22 / 14,
      fontWeight: FontWeight.bold,
    ),
    tableBody: const TextStyle(fontSize: 14, height: 20 / 14),
    tableHead: const TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.bold,
    ),
    blockSpacing: 16,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    blockquoteDecoration: BoxDecoration(
      color: theme.brightness == Brightness.dark
          ? const Color(0xff202122)
          : const Color(0xfff8fafc),
      border: Border(
        left: BorderSide(
          width: 3,
          color: theme.brightness == Brightness.dark
              ? const Color(0xff6f7377)
              : const Color(0xff94a3b8),
        ),
      ),
    ),
    tableBorder: TableBorder.all(color: theme.dividerColor),
    tablePadding: EdgeInsets.zero,
    tableHeadCellsDecoration: BoxDecoration(
      color: theme.brightness == Brightness.dark
          ? const Color(0xff2a2b2d)
          : const Color(0xfff3f4f6),
    ),
    tableColumnWidth: const TranscriptColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    code: TextStyle(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      fontFamily: 'Menlo',
      fontSize: 13,
      color: theme.brightness == Brightness.dark
          ? const Color(0xffeb5757)
          : const Color(0xff111827),
    ),
    codeblockDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(7),
    ),
  );
}
