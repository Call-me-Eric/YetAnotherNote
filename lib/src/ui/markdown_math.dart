import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';

/// LaTeX syntax from markdown_widget's own example.
SpanNodeGeneratorWithTag latexGenerator = SpanNodeGeneratorWithTag(
  tag: _latexTag,
  generator: (element, config, visitor) =>
      LatexNode(element.attributes, element.textContent, config),
);

const _latexTag = 'latex';

class LatexSyntax extends m.InlineSyntax {
  LatexSyntax() : super(r'(\$\$[\s\S]+\$\$)|(\$.+?\$)');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final input = match.input;
    final matchValue = input.substring(match.start, match.end);
    var content = '';
    var isInline = true;
    const blockSyntax = '\$\$';
    const inlineSyntax = '\$';
    if (matchValue.startsWith(blockSyntax) &&
        matchValue.endsWith(blockSyntax) &&
        matchValue != blockSyntax) {
      content = matchValue.substring(2, matchValue.length - 2);
      isInline = false;
    } else if (matchValue.startsWith(inlineSyntax) &&
        matchValue.endsWith(inlineSyntax) &&
        matchValue != inlineSyntax) {
      content = matchValue.substring(1, matchValue.length - 1);
    }
    final element = m.Element.text(_latexTag, matchValue);
    element.attributes['content'] = content;
    element.attributes['isInline'] = '$isInline';
    parser.addNode(element);
    return true;
  }
}

class LatexNode extends SpanNode {
  LatexNode(this.attributes, this.textContent, this.config);

  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? '';
    final isInline = attributes['isInline'] == 'true';
    final style = parentStyle ?? config.p.textStyle;
    if (content.isEmpty) {
      return TextSpan(style: style, text: textContent);
    }
    final latex = Math.tex(
      content,
      mathStyle: isInline ? MathStyle.text : MathStyle.display,
      textStyle: style.copyWith(color: Colors.black),
      onErrorFallback: (error) {
        return Text(textContent, style: style.copyWith(color: Colors.red));
      },
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: isInline
          ? latex
          : Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: latex,
            ),
    );
  }
}
