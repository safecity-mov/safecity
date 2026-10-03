import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/hazard_type.dart';
import '../data/models/severity.dart';
import 'widgets/severity_indicator.dart';
import 'labels.dart';

/// Ce que l'utilisateur a saisi. Le sheet ne connaît ni le réseau ni le device :
/// il renvoie une intention, l'écran de carte l'exécute.
class ReportDraft {
  const ReportDraft({
    required this.type,
    required this.severity,
    this.description,
  });

  final HazardType type;
  final Severity severity;
  final String? description;
}

/// Nouveau signalement (§9, écran 2).
///
/// Objectif affiché du produit : moins de 10 secondes entre l'ouverture et
/// l'envoi. D'où l'ordre des champs — le niveau, seule saisie obligatoire, est
/// en premier, et tout le reste est facultatif.
///
/// Le sélecteur de type est masqué tant qu'un seul type est activé (§3).
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.types,
    required this.address,
    this.allowDescription = true,
  });

  final List<HazardType> types;

  /// Adresse approchée du pin, si le géocodage inverse est disponible.
  /// Il ne l'est pas encore : Photon arrive plus tard.
  final String? address;

  /// La précision libre peut être coupée depuis la console (§4.3 amendé) : le
  /// champ disparaît alors, et le brouillon part sans texte.
  final bool allowDescription;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  late final List<HazardType> _selectable = widget.types.where((t) => t.enabled).toList();
  late HazardType? _type = _selectable.length == 1 ? _selectable.first : null;
  Severity? _severity;
  final _description = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  bool get _canSubmit => _type != null && _severity != null;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(ReportLabels.title, style: Theme.of(context).textTheme.titleLarge),
              if (widget.address != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.address!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),

              // Masqué tant qu'un seul type est activé : l'écran se réduit alors
              // à niveau + commentaire (§3).
              if (_selectable.length > 1) ...[
                const Text(ReportLabels.typeSection, style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in _selectable)
                      // L'icône seule (amendement) : le nom reste au lecteur
                      // d'écran et à l'appui long, par le tooltip.
                      ChoiceChip(
                        label: type.iconWidget(size: 24),
                        labelPadding: const EdgeInsets.all(4),
                        tooltip: type.label,
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              const Text(
                ReportLabels.severitySection,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _SeverityRow(
                value: _severity,
                onChanged: (s) => setState(() => _severity = s),
              ),
              const SizedBox(height: 20),

              if (widget.allowDescription) ...[
                TextField(
                  controller: _description,
                  maxLength: 140,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(140)],
                  decoration: const InputDecoration(
                    labelText: ReportLabels.descriptionLabel,
                    helperText: ReportLabels.descriptionHelper,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              FilledButton.icon(
                onPressed: _canSubmit
                    ? () => Navigator.of(context).pop(
                          ReportDraft(
                            type: _type!,
                            severity: _severity!,
                            description: !widget.allowDescription || _description.text.trim().isEmpty
                                ? null
                                : _description.text.trim(),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.send),
                label: const Text(ReportLabels.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeverityRow extends StatelessWidget {
  const _SeverityRow({required this.value, required this.onChanged});

  final Severity? value;
  final ValueChanged<Severity> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final severity in Severity.values) ...[
            Expanded(
              child: Semantics(
                button: true,
                selected: value == severity,
                label: ReportLabels.severityOption(severity.value),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onChanged(severity),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 76),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: value == severity ? severity.color.withValues(alpha: 0.12) : null,
                      border: Border.all(
                        color: value == severity ? severity.color : Theme.of(context).dividerColor,
                        width: value == severity ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SeverityIndicator(severity, height: 22),
                        const SizedBox(height: 6),
                        Text(
                          severity.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: value == severity ? severity.color : null,
                            fontWeight: value == severity ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (severity != Severity.values.last) const SizedBox(width: 8),
          ],
        ],
      );
}
