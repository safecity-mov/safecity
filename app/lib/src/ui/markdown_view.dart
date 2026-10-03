import 'package:flutter/material.dart';

/// Affichage du sous-ensemble de Markdown utilisé par `assets/privacy.md`.
///
/// Une centaine de lignes plutôt qu'une dépendance : `flutter_markdown` est
/// abandonné depuis 2025, et ce qu'on a à rendre tient en six règles — titres,
/// paragraphes, gras, listes, filets, tableaux. Les tableaux deviennent des
/// blocs empilés : trois colonnes sur un écran de téléphone ne se lisent pas.
///
/// Ce qui n'est pas géré est rendu tel quel plutôt qu'avalé : mieux vaut une
/// étoile visible qu'une phrase manquante dans un texte qui engage.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = <Widget>[];
    final lines = source.split('\n');

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (trimmed == '---') {
        blocks.add(const Divider(height: 32));
        i++;
        continue;
      }

      if (trimmed.startsWith('#')) {
        final level = trimmed.indexOf(' ');
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 24, bottom: 8),
          child: Text(
            trimmed.substring(level + 1),
            style: switch (level) {
              1 => theme.textTheme.headlineSmall,
              2 => theme.textTheme.titleLarge,
              _ => theme.textTheme.titleMedium,
            },
          ),
        ),);
        i++;
        continue;
      }

      // Tableau : une ligne d'en-tête, un séparateur, puis les lignes. Chacune
      // devient un bloc « colonne : valeur », lisible en portrait.
      if (trimmed.startsWith('|') &&
          i + 1 < lines.length &&
          lines[i + 1].trim().startsWith('|-')) {
        final headers = _cells(lines[i]);
        i += 2;
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final cells = _cells(lines[i]);
          blocks.add(_TableRow(headers: headers, cells: cells));
          i++;
        }
        continue;
      }

      if (trimmed.startsWith('- ') || RegExp(r'^\d+\. ').hasMatch(trimmed)) {
        final bullet = trimmed.startsWith('- ')
            ? '•'
            : '${trimmed.substring(0, trimmed.indexOf('.'))}.';
        final content = trimmed.startsWith('- ')
            ? trimmed.substring(2)
            : trimmed.substring(trimmed.indexOf('. ') + 2);
        // Une entrée de liste peut se poursuivre sur les lignes indentées.
        final buffer = StringBuffer(content);
        i++;
        while (i < lines.length &&
            lines[i].startsWith('  ') &&
            lines[i].trim().isNotEmpty &&
            !lines[i].trim().startsWith('- ')) {
          buffer.write(' ${lines[i].trim()}');
          i++;
        }
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text(bullet, style: theme.textTheme.bodyMedium)),
              Expanded(child: _RichLine(buffer.toString())),
            ],
          ),
        ),);
        continue;
      }

      // Paragraphe : les lignes suivantes lui appartiennent jusqu'à une vide.
      final buffer = StringBuffer(trimmed);
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].trim().startsWith('#') &&
          !lines[i].trim().startsWith('- ') &&
          !lines[i].trim().startsWith('|') &&
          lines[i].trim() != '---') {
        buffer.write(' ${lines[i].trim()}');
        i++;
      }
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _RichLine(buffer.toString()),
      ),);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  static List<String> _cells(String row) => row
      .trim()
      .split('|')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.headers, required this.cells});

  final List<String> headers;
  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < cells.length; c++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c < headers.length && headers.length > 1)
                    SizedBox(
                      width: 110,
                      child: Text(
                        headers[c],
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  Expanded(child: _RichLine(cells[c])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Gras (`**…**`), italique (`*…*`) et `code`, dans une seule passe.
class _RichLine extends StatelessWidget {
  const _RichLine(this.text);

  final String text;

  static final _pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    final spans = <TextSpan>[];
    var last = 0;

    for (final match in _pattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),);
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),);
      } else {
        spans.add(TextSpan(
          text: match.group(3),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: base.fontSize! * 0.92,
          ),
        ),);
      }
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return Text.rich(TextSpan(style: base.copyWith(height: 1.45), children: spans));
  }
}
