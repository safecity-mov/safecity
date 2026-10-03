// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CachedTypesTable extends CachedTypes
    with TableInfo<$CachedTypesTable, CachedTypeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
      'code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _iconNameMeta =
      const VerificationMeta('iconName');
  @override
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
      'icon_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _resolvedLabelMeta =
      const VerificationMeta('resolvedLabel');
  @override
  late final GeneratedColumn<String> resolvedLabel = GeneratedColumn<String>(
      'resolved_label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dedupRadiusMMeta =
      const VerificationMeta('dedupRadiusM');
  @override
  late final GeneratedColumn<int> dedupRadiusM = GeneratedColumn<int>(
      'dedup_radius_m', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _iconPngMeta =
      const VerificationMeta('iconPng');
  @override
  late final GeneratedColumn<Uint8List> iconPng = GeneratedColumn<Uint8List>(
      'icon_png', aliasedName, true,
      type: DriftSqlType.blob, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        code,
        label,
        iconName,
        resolvedLabel,
        dedupRadiusM,
        enabled,
        sortOrder,
        iconPng
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_types';
  @override
  VerificationContext validateIntegrity(Insertable<CachedTypeRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
          _codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('icon_name')) {
      context.handle(_iconNameMeta,
          iconName.isAcceptableOrUnknown(data['icon_name']!, _iconNameMeta));
    } else if (isInserting) {
      context.missing(_iconNameMeta);
    }
    if (data.containsKey('resolved_label')) {
      context.handle(
          _resolvedLabelMeta,
          resolvedLabel.isAcceptableOrUnknown(
              data['resolved_label']!, _resolvedLabelMeta));
    } else if (isInserting) {
      context.missing(_resolvedLabelMeta);
    }
    if (data.containsKey('dedup_radius_m')) {
      context.handle(
          _dedupRadiusMMeta,
          dedupRadiusM.isAcceptableOrUnknown(
              data['dedup_radius_m']!, _dedupRadiusMMeta));
    } else if (isInserting) {
      context.missing(_dedupRadiusMMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('icon_png')) {
      context.handle(_iconPngMeta,
          iconPng.isAcceptableOrUnknown(data['icon_png']!, _iconPngMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  CachedTypeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTypeRow(
      code: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      iconName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon_name'])!,
      resolvedLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}resolved_label'])!,
      dedupRadiusM: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}dedup_radius_m'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      iconPng: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}icon_png']),
    );
  }

  @override
  $CachedTypesTable createAlias(String alias) {
    return $CachedTypesTable(attachedDatabase, alias);
  }
}

class CachedTypeRow extends DataClass implements Insertable<CachedTypeRow> {
  final String code;
  final String label;
  final String iconName;
  final String resolvedLabel;
  final int dedupRadiusM;
  final bool enabled;
  final int sortOrder;

  /// La silhouette de marqueur téléversée depuis la console (§4.3).
  ///
  /// Gardée avec le catalogue et non avec le cache de dangers : ce n'est pas une
  /// donnée de position, elle n'a rien à faire dans l'horizon d'oubli du §11.1.
  /// Quelques centaines d'octets par type.
  final Uint8List? iconPng;
  const CachedTypeRow(
      {required this.code,
      required this.label,
      required this.iconName,
      required this.resolvedLabel,
      required this.dedupRadiusM,
      required this.enabled,
      required this.sortOrder,
      this.iconPng});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['label'] = Variable<String>(label);
    map['icon_name'] = Variable<String>(iconName);
    map['resolved_label'] = Variable<String>(resolvedLabel);
    map['dedup_radius_m'] = Variable<int>(dedupRadiusM);
    map['enabled'] = Variable<bool>(enabled);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || iconPng != null) {
      map['icon_png'] = Variable<Uint8List>(iconPng);
    }
    return map;
  }

  CachedTypesCompanion toCompanion(bool nullToAbsent) {
    return CachedTypesCompanion(
      code: Value(code),
      label: Value(label),
      iconName: Value(iconName),
      resolvedLabel: Value(resolvedLabel),
      dedupRadiusM: Value(dedupRadiusM),
      enabled: Value(enabled),
      sortOrder: Value(sortOrder),
      iconPng: iconPng == null && nullToAbsent
          ? const Value.absent()
          : Value(iconPng),
    );
  }

  factory CachedTypeRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTypeRow(
      code: serializer.fromJson<String>(json['code']),
      label: serializer.fromJson<String>(json['label']),
      iconName: serializer.fromJson<String>(json['iconName']),
      resolvedLabel: serializer.fromJson<String>(json['resolvedLabel']),
      dedupRadiusM: serializer.fromJson<int>(json['dedupRadiusM']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      iconPng: serializer.fromJson<Uint8List?>(json['iconPng']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'label': serializer.toJson<String>(label),
      'iconName': serializer.toJson<String>(iconName),
      'resolvedLabel': serializer.toJson<String>(resolvedLabel),
      'dedupRadiusM': serializer.toJson<int>(dedupRadiusM),
      'enabled': serializer.toJson<bool>(enabled),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'iconPng': serializer.toJson<Uint8List?>(iconPng),
    };
  }

  CachedTypeRow copyWith(
          {String? code,
          String? label,
          String? iconName,
          String? resolvedLabel,
          int? dedupRadiusM,
          bool? enabled,
          int? sortOrder,
          Value<Uint8List?> iconPng = const Value.absent()}) =>
      CachedTypeRow(
        code: code ?? this.code,
        label: label ?? this.label,
        iconName: iconName ?? this.iconName,
        resolvedLabel: resolvedLabel ?? this.resolvedLabel,
        dedupRadiusM: dedupRadiusM ?? this.dedupRadiusM,
        enabled: enabled ?? this.enabled,
        sortOrder: sortOrder ?? this.sortOrder,
        iconPng: iconPng.present ? iconPng.value : this.iconPng,
      );
  CachedTypeRow copyWithCompanion(CachedTypesCompanion data) {
    return CachedTypeRow(
      code: data.code.present ? data.code.value : this.code,
      label: data.label.present ? data.label.value : this.label,
      iconName: data.iconName.present ? data.iconName.value : this.iconName,
      resolvedLabel: data.resolvedLabel.present
          ? data.resolvedLabel.value
          : this.resolvedLabel,
      dedupRadiusM: data.dedupRadiusM.present
          ? data.dedupRadiusM.value
          : this.dedupRadiusM,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      iconPng: data.iconPng.present ? data.iconPng.value : this.iconPng,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTypeRow(')
          ..write('code: $code, ')
          ..write('label: $label, ')
          ..write('iconName: $iconName, ')
          ..write('resolvedLabel: $resolvedLabel, ')
          ..write('dedupRadiusM: $dedupRadiusM, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('iconPng: $iconPng')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, label, iconName, resolvedLabel,
      dedupRadiusM, enabled, sortOrder, $driftBlobEquality.hash(iconPng));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTypeRow &&
          other.code == this.code &&
          other.label == this.label &&
          other.iconName == this.iconName &&
          other.resolvedLabel == this.resolvedLabel &&
          other.dedupRadiusM == this.dedupRadiusM &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder &&
          $driftBlobEquality.equals(other.iconPng, this.iconPng));
}

class CachedTypesCompanion extends UpdateCompanion<CachedTypeRow> {
  final Value<String> code;
  final Value<String> label;
  final Value<String> iconName;
  final Value<String> resolvedLabel;
  final Value<int> dedupRadiusM;
  final Value<bool> enabled;
  final Value<int> sortOrder;
  final Value<Uint8List?> iconPng;
  final Value<int> rowid;
  const CachedTypesCompanion({
    this.code = const Value.absent(),
    this.label = const Value.absent(),
    this.iconName = const Value.absent(),
    this.resolvedLabel = const Value.absent(),
    this.dedupRadiusM = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.iconPng = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTypesCompanion.insert({
    required String code,
    required String label,
    required String iconName,
    required String resolvedLabel,
    required int dedupRadiusM,
    required bool enabled,
    required int sortOrder,
    this.iconPng = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : code = Value(code),
        label = Value(label),
        iconName = Value(iconName),
        resolvedLabel = Value(resolvedLabel),
        dedupRadiusM = Value(dedupRadiusM),
        enabled = Value(enabled),
        sortOrder = Value(sortOrder);
  static Insertable<CachedTypeRow> custom({
    Expression<String>? code,
    Expression<String>? label,
    Expression<String>? iconName,
    Expression<String>? resolvedLabel,
    Expression<int>? dedupRadiusM,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<Uint8List>? iconPng,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (label != null) 'label': label,
      if (iconName != null) 'icon_name': iconName,
      if (resolvedLabel != null) 'resolved_label': resolvedLabel,
      if (dedupRadiusM != null) 'dedup_radius_m': dedupRadiusM,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (iconPng != null) 'icon_png': iconPng,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTypesCompanion copyWith(
      {Value<String>? code,
      Value<String>? label,
      Value<String>? iconName,
      Value<String>? resolvedLabel,
      Value<int>? dedupRadiusM,
      Value<bool>? enabled,
      Value<int>? sortOrder,
      Value<Uint8List?>? iconPng,
      Value<int>? rowid}) {
    return CachedTypesCompanion(
      code: code ?? this.code,
      label: label ?? this.label,
      iconName: iconName ?? this.iconName,
      resolvedLabel: resolvedLabel ?? this.resolvedLabel,
      dedupRadiusM: dedupRadiusM ?? this.dedupRadiusM,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      iconPng: iconPng ?? this.iconPng,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (iconName.present) {
      map['icon_name'] = Variable<String>(iconName.value);
    }
    if (resolvedLabel.present) {
      map['resolved_label'] = Variable<String>(resolvedLabel.value);
    }
    if (dedupRadiusM.present) {
      map['dedup_radius_m'] = Variable<int>(dedupRadiusM.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (iconPng.present) {
      map['icon_png'] = Variable<Uint8List>(iconPng.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTypesCompanion(')
          ..write('code: $code, ')
          ..write('label: $label, ')
          ..write('iconName: $iconName, ')
          ..write('resolvedLabel: $resolvedLabel, ')
          ..write('dedupRadiusM: $dedupRadiusM, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('iconPng: $iconPng, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedHazardsTable extends CachedHazards
    with TableInfo<$CachedHazardsTable, CachedHazardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedHazardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
      'lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _severityMeta =
      const VerificationMeta('severity');
  @override
  late final GeneratedColumn<int> severity = GeneratedColumn<int>(
      'severity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastConfirmedAtMeta =
      const VerificationMeta('lastConfirmedAt');
  @override
  late final GeneratedColumn<DateTime> lastConfirmedAt =
      GeneratedColumn<DateTime>('last_confirmed_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _confirmWeightMeta =
      const VerificationMeta('confirmWeight');
  @override
  late final GeneratedColumn<double> confirmWeight = GeneratedColumn<double>(
      'confirm_weight', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _resolveWeightMeta =
      const VerificationMeta('resolveWeight');
  @override
  late final GeneratedColumn<double> resolveWeight = GeneratedColumn<double>(
      'resolve_weight', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _resolveThresholdMeta =
      const VerificationMeta('resolveThreshold');
  @override
  late final GeneratedColumn<int> resolveThreshold = GeneratedColumn<int>(
      'resolve_threshold', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _reportedRemotelyMeta =
      const VerificationMeta('reportedRemotely');
  @override
  late final GeneratedColumn<bool> reportedRemotely = GeneratedColumn<bool>(
      'reported_remotely', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("reported_remotely" IN (0, 1))'));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        lat,
        lng,
        severity,
        status,
        description,
        address,
        createdAt,
        lastConfirmedAt,
        confirmWeight,
        resolveWeight,
        resolveThreshold,
        reportedRemotely,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_hazards';
  @override
  VerificationContext validateIntegrity(Insertable<CachedHazardRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
          _lngMeta, lng.isAcceptableOrUnknown(data['lng']!, _lngMeta));
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(_severityMeta,
          severity.isAcceptableOrUnknown(data['severity']!, _severityMeta));
    } else if (isInserting) {
      context.missing(_severityMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_confirmed_at')) {
      context.handle(
          _lastConfirmedAtMeta,
          lastConfirmedAt.isAcceptableOrUnknown(
              data['last_confirmed_at']!, _lastConfirmedAtMeta));
    } else if (isInserting) {
      context.missing(_lastConfirmedAtMeta);
    }
    if (data.containsKey('confirm_weight')) {
      context.handle(
          _confirmWeightMeta,
          confirmWeight.isAcceptableOrUnknown(
              data['confirm_weight']!, _confirmWeightMeta));
    } else if (isInserting) {
      context.missing(_confirmWeightMeta);
    }
    if (data.containsKey('resolve_weight')) {
      context.handle(
          _resolveWeightMeta,
          resolveWeight.isAcceptableOrUnknown(
              data['resolve_weight']!, _resolveWeightMeta));
    } else if (isInserting) {
      context.missing(_resolveWeightMeta);
    }
    if (data.containsKey('resolve_threshold')) {
      context.handle(
          _resolveThresholdMeta,
          resolveThreshold.isAcceptableOrUnknown(
              data['resolve_threshold']!, _resolveThresholdMeta));
    } else if (isInserting) {
      context.missing(_resolveThresholdMeta);
    }
    if (data.containsKey('reported_remotely')) {
      context.handle(
          _reportedRemotelyMeta,
          reportedRemotely.isAcceptableOrUnknown(
              data['reported_remotely']!, _reportedRemotelyMeta));
    } else if (isInserting) {
      context.missing(_reportedRemotelyMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedHazardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedHazardRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat'])!,
      lng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lng'])!,
      severity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}severity'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      lastConfirmedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_confirmed_at'])!,
      confirmWeight: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}confirm_weight'])!,
      resolveWeight: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}resolve_weight'])!,
      resolveThreshold: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}resolve_threshold'])!,
      reportedRemotely: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}reported_remotely'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedHazardsTable createAlias(String alias) {
    return $CachedHazardsTable(attachedDatabase, alias);
  }
}

class CachedHazardRow extends DataClass implements Insertable<CachedHazardRow> {
  final String id;
  final String type;
  final double lat;
  final double lng;
  final int severity;
  final String status;
  final String? description;
  final String? address;
  final DateTime createdAt;
  final DateTime lastConfirmedAt;
  final double confirmWeight;
  final double resolveWeight;
  final int resolveThreshold;
  final bool reportedRemotely;
  final DateTime cachedAt;
  const CachedHazardRow(
      {required this.id,
      required this.type,
      required this.lat,
      required this.lng,
      required this.severity,
      required this.status,
      this.description,
      this.address,
      required this.createdAt,
      required this.lastConfirmedAt,
      required this.confirmWeight,
      required this.resolveWeight,
      required this.resolveThreshold,
      required this.reportedRemotely,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    map['severity'] = Variable<int>(severity);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_confirmed_at'] = Variable<DateTime>(lastConfirmedAt);
    map['confirm_weight'] = Variable<double>(confirmWeight);
    map['resolve_weight'] = Variable<double>(resolveWeight);
    map['resolve_threshold'] = Variable<int>(resolveThreshold);
    map['reported_remotely'] = Variable<bool>(reportedRemotely);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedHazardsCompanion toCompanion(bool nullToAbsent) {
    return CachedHazardsCompanion(
      id: Value(id),
      type: Value(type),
      lat: Value(lat),
      lng: Value(lng),
      severity: Value(severity),
      status: Value(status),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      createdAt: Value(createdAt),
      lastConfirmedAt: Value(lastConfirmedAt),
      confirmWeight: Value(confirmWeight),
      resolveWeight: Value(resolveWeight),
      resolveThreshold: Value(resolveThreshold),
      reportedRemotely: Value(reportedRemotely),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedHazardRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedHazardRow(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      severity: serializer.fromJson<int>(json['severity']),
      status: serializer.fromJson<String>(json['status']),
      description: serializer.fromJson<String?>(json['description']),
      address: serializer.fromJson<String?>(json['address']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastConfirmedAt: serializer.fromJson<DateTime>(json['lastConfirmedAt']),
      confirmWeight: serializer.fromJson<double>(json['confirmWeight']),
      resolveWeight: serializer.fromJson<double>(json['resolveWeight']),
      resolveThreshold: serializer.fromJson<int>(json['resolveThreshold']),
      reportedRemotely: serializer.fromJson<bool>(json['reportedRemotely']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'severity': serializer.toJson<int>(severity),
      'status': serializer.toJson<String>(status),
      'description': serializer.toJson<String?>(description),
      'address': serializer.toJson<String?>(address),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastConfirmedAt': serializer.toJson<DateTime>(lastConfirmedAt),
      'confirmWeight': serializer.toJson<double>(confirmWeight),
      'resolveWeight': serializer.toJson<double>(resolveWeight),
      'resolveThreshold': serializer.toJson<int>(resolveThreshold),
      'reportedRemotely': serializer.toJson<bool>(reportedRemotely),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedHazardRow copyWith(
          {String? id,
          String? type,
          double? lat,
          double? lng,
          int? severity,
          String? status,
          Value<String?> description = const Value.absent(),
          Value<String?> address = const Value.absent(),
          DateTime? createdAt,
          DateTime? lastConfirmedAt,
          double? confirmWeight,
          double? resolveWeight,
          int? resolveThreshold,
          bool? reportedRemotely,
          DateTime? cachedAt}) =>
      CachedHazardRow(
        id: id ?? this.id,
        type: type ?? this.type,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        severity: severity ?? this.severity,
        status: status ?? this.status,
        description: description.present ? description.value : this.description,
        address: address.present ? address.value : this.address,
        createdAt: createdAt ?? this.createdAt,
        lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
        confirmWeight: confirmWeight ?? this.confirmWeight,
        resolveWeight: resolveWeight ?? this.resolveWeight,
        resolveThreshold: resolveThreshold ?? this.resolveThreshold,
        reportedRemotely: reportedRemotely ?? this.reportedRemotely,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedHazardRow copyWithCompanion(CachedHazardsCompanion data) {
    return CachedHazardRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      severity: data.severity.present ? data.severity.value : this.severity,
      status: data.status.present ? data.status.value : this.status,
      description:
          data.description.present ? data.description.value : this.description,
      address: data.address.present ? data.address.value : this.address,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastConfirmedAt: data.lastConfirmedAt.present
          ? data.lastConfirmedAt.value
          : this.lastConfirmedAt,
      confirmWeight: data.confirmWeight.present
          ? data.confirmWeight.value
          : this.confirmWeight,
      resolveWeight: data.resolveWeight.present
          ? data.resolveWeight.value
          : this.resolveWeight,
      resolveThreshold: data.resolveThreshold.present
          ? data.resolveThreshold.value
          : this.resolveThreshold,
      reportedRemotely: data.reportedRemotely.present
          ? data.reportedRemotely.value
          : this.reportedRemotely,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedHazardRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('severity: $severity, ')
          ..write('status: $status, ')
          ..write('description: $description, ')
          ..write('address: $address, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastConfirmedAt: $lastConfirmedAt, ')
          ..write('confirmWeight: $confirmWeight, ')
          ..write('resolveWeight: $resolveWeight, ')
          ..write('resolveThreshold: $resolveThreshold, ')
          ..write('reportedRemotely: $reportedRemotely, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      type,
      lat,
      lng,
      severity,
      status,
      description,
      address,
      createdAt,
      lastConfirmedAt,
      confirmWeight,
      resolveWeight,
      resolveThreshold,
      reportedRemotely,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedHazardRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.severity == this.severity &&
          other.status == this.status &&
          other.description == this.description &&
          other.address == this.address &&
          other.createdAt == this.createdAt &&
          other.lastConfirmedAt == this.lastConfirmedAt &&
          other.confirmWeight == this.confirmWeight &&
          other.resolveWeight == this.resolveWeight &&
          other.resolveThreshold == this.resolveThreshold &&
          other.reportedRemotely == this.reportedRemotely &&
          other.cachedAt == this.cachedAt);
}

class CachedHazardsCompanion extends UpdateCompanion<CachedHazardRow> {
  final Value<String> id;
  final Value<String> type;
  final Value<double> lat;
  final Value<double> lng;
  final Value<int> severity;
  final Value<String> status;
  final Value<String?> description;
  final Value<String?> address;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastConfirmedAt;
  final Value<double> confirmWeight;
  final Value<double> resolveWeight;
  final Value<int> resolveThreshold;
  final Value<bool> reportedRemotely;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedHazardsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.severity = const Value.absent(),
    this.status = const Value.absent(),
    this.description = const Value.absent(),
    this.address = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastConfirmedAt = const Value.absent(),
    this.confirmWeight = const Value.absent(),
    this.resolveWeight = const Value.absent(),
    this.resolveThreshold = const Value.absent(),
    this.reportedRemotely = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedHazardsCompanion.insert({
    required String id,
    required String type,
    required double lat,
    required double lng,
    required int severity,
    required String status,
    this.description = const Value.absent(),
    this.address = const Value.absent(),
    required DateTime createdAt,
    required DateTime lastConfirmedAt,
    required double confirmWeight,
    required double resolveWeight,
    required int resolveThreshold,
    required bool reportedRemotely,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        lat = Value(lat),
        lng = Value(lng),
        severity = Value(severity),
        status = Value(status),
        createdAt = Value(createdAt),
        lastConfirmedAt = Value(lastConfirmedAt),
        confirmWeight = Value(confirmWeight),
        resolveWeight = Value(resolveWeight),
        resolveThreshold = Value(resolveThreshold),
        reportedRemotely = Value(reportedRemotely),
        cachedAt = Value(cachedAt);
  static Insertable<CachedHazardRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<int>? severity,
    Expression<String>? status,
    Expression<String>? description,
    Expression<String>? address,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastConfirmedAt,
    Expression<double>? confirmWeight,
    Expression<double>? resolveWeight,
    Expression<int>? resolveThreshold,
    Expression<bool>? reportedRemotely,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (severity != null) 'severity': severity,
      if (status != null) 'status': status,
      if (description != null) 'description': description,
      if (address != null) 'address': address,
      if (createdAt != null) 'created_at': createdAt,
      if (lastConfirmedAt != null) 'last_confirmed_at': lastConfirmedAt,
      if (confirmWeight != null) 'confirm_weight': confirmWeight,
      if (resolveWeight != null) 'resolve_weight': resolveWeight,
      if (resolveThreshold != null) 'resolve_threshold': resolveThreshold,
      if (reportedRemotely != null) 'reported_remotely': reportedRemotely,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedHazardsCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<double>? lat,
      Value<double>? lng,
      Value<int>? severity,
      Value<String>? status,
      Value<String?>? description,
      Value<String?>? address,
      Value<DateTime>? createdAt,
      Value<DateTime>? lastConfirmedAt,
      Value<double>? confirmWeight,
      Value<double>? resolveWeight,
      Value<int>? resolveThreshold,
      Value<bool>? reportedRemotely,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return CachedHazardsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      description: description ?? this.description,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
      confirmWeight: confirmWeight ?? this.confirmWeight,
      resolveWeight: resolveWeight ?? this.resolveWeight,
      resolveThreshold: resolveThreshold ?? this.resolveThreshold,
      reportedRemotely: reportedRemotely ?? this.reportedRemotely,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (severity.present) {
      map['severity'] = Variable<int>(severity.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastConfirmedAt.present) {
      map['last_confirmed_at'] = Variable<DateTime>(lastConfirmedAt.value);
    }
    if (confirmWeight.present) {
      map['confirm_weight'] = Variable<double>(confirmWeight.value);
    }
    if (resolveWeight.present) {
      map['resolve_weight'] = Variable<double>(resolveWeight.value);
    }
    if (resolveThreshold.present) {
      map['resolve_threshold'] = Variable<int>(resolveThreshold.value);
    }
    if (reportedRemotely.present) {
      map['reported_remotely'] = Variable<bool>(reportedRemotely.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedHazardsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('severity: $severity, ')
          ..write('status: $status, ')
          ..write('description: $description, ')
          ..write('address: $address, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastConfirmedAt: $lastConfirmedAt, ')
          ..write('confirmWeight: $confirmWeight, ')
          ..write('resolveWeight: $resolveWeight, ')
          ..write('resolveThreshold: $resolveThreshold, ')
          ..write('reportedRemotely: $reportedRemotely, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedAreasTable extends CachedAreas
    with TableInfo<$CachedAreasTable, CachedAreaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAreasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _minLatMeta = const VerificationMeta('minLat');
  @override
  late final GeneratedColumn<double> minLat = GeneratedColumn<double>(
      'min_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _minLngMeta = const VerificationMeta('minLng');
  @override
  late final GeneratedColumn<double> minLng = GeneratedColumn<double>(
      'min_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _maxLatMeta = const VerificationMeta('maxLat');
  @override
  late final GeneratedColumn<double> maxLat = GeneratedColumn<double>(
      'max_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _maxLngMeta = const VerificationMeta('maxLng');
  @override
  late final GeneratedColumn<double> maxLng = GeneratedColumn<double>(
      'max_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, minLat, minLng, maxLat, maxLng, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_areas';
  @override
  VerificationContext validateIntegrity(Insertable<CachedAreaRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('min_lat')) {
      context.handle(_minLatMeta,
          minLat.isAcceptableOrUnknown(data['min_lat']!, _minLatMeta));
    } else if (isInserting) {
      context.missing(_minLatMeta);
    }
    if (data.containsKey('min_lng')) {
      context.handle(_minLngMeta,
          minLng.isAcceptableOrUnknown(data['min_lng']!, _minLngMeta));
    } else if (isInserting) {
      context.missing(_minLngMeta);
    }
    if (data.containsKey('max_lat')) {
      context.handle(_maxLatMeta,
          maxLat.isAcceptableOrUnknown(data['max_lat']!, _maxLatMeta));
    } else if (isInserting) {
      context.missing(_maxLatMeta);
    }
    if (data.containsKey('max_lng')) {
      context.handle(_maxLngMeta,
          maxLng.isAcceptableOrUnknown(data['max_lng']!, _maxLngMeta));
    } else if (isInserting) {
      context.missing(_maxLngMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedAreaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAreaRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      minLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}min_lat'])!,
      minLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}min_lng'])!,
      maxLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}max_lat'])!,
      maxLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}max_lng'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}fetched_at'])!,
    );
  }

  @override
  $CachedAreasTable createAlias(String alias) {
    return $CachedAreasTable(attachedDatabase, alias);
  }
}

class CachedAreaRow extends DataClass implements Insertable<CachedAreaRow> {
  final int id;
  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;
  final DateTime fetchedAt;
  const CachedAreaRow(
      {required this.id,
      required this.minLat,
      required this.minLng,
      required this.maxLat,
      required this.maxLng,
      required this.fetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['min_lat'] = Variable<double>(minLat);
    map['min_lng'] = Variable<double>(minLng);
    map['max_lat'] = Variable<double>(maxLat);
    map['max_lng'] = Variable<double>(maxLng);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CachedAreasCompanion toCompanion(bool nullToAbsent) {
    return CachedAreasCompanion(
      id: Value(id),
      minLat: Value(minLat),
      minLng: Value(minLng),
      maxLat: Value(maxLat),
      maxLng: Value(maxLng),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CachedAreaRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAreaRow(
      id: serializer.fromJson<int>(json['id']),
      minLat: serializer.fromJson<double>(json['minLat']),
      minLng: serializer.fromJson<double>(json['minLng']),
      maxLat: serializer.fromJson<double>(json['maxLat']),
      maxLng: serializer.fromJson<double>(json['maxLng']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'minLat': serializer.toJson<double>(minLat),
      'minLng': serializer.toJson<double>(minLng),
      'maxLat': serializer.toJson<double>(maxLat),
      'maxLng': serializer.toJson<double>(maxLng),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CachedAreaRow copyWith(
          {int? id,
          double? minLat,
          double? minLng,
          double? maxLat,
          double? maxLng,
          DateTime? fetchedAt}) =>
      CachedAreaRow(
        id: id ?? this.id,
        minLat: minLat ?? this.minLat,
        minLng: minLng ?? this.minLng,
        maxLat: maxLat ?? this.maxLat,
        maxLng: maxLng ?? this.maxLng,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  CachedAreaRow copyWithCompanion(CachedAreasCompanion data) {
    return CachedAreaRow(
      id: data.id.present ? data.id.value : this.id,
      minLat: data.minLat.present ? data.minLat.value : this.minLat,
      minLng: data.minLng.present ? data.minLng.value : this.minLng,
      maxLat: data.maxLat.present ? data.maxLat.value : this.maxLat,
      maxLng: data.maxLng.present ? data.maxLng.value : this.maxLng,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAreaRow(')
          ..write('id: $id, ')
          ..write('minLat: $minLat, ')
          ..write('minLng: $minLng, ')
          ..write('maxLat: $maxLat, ')
          ..write('maxLng: $maxLng, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, minLat, minLng, maxLat, maxLng, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAreaRow &&
          other.id == this.id &&
          other.minLat == this.minLat &&
          other.minLng == this.minLng &&
          other.maxLat == this.maxLat &&
          other.maxLng == this.maxLng &&
          other.fetchedAt == this.fetchedAt);
}

class CachedAreasCompanion extends UpdateCompanion<CachedAreaRow> {
  final Value<int> id;
  final Value<double> minLat;
  final Value<double> minLng;
  final Value<double> maxLat;
  final Value<double> maxLng;
  final Value<DateTime> fetchedAt;
  const CachedAreasCompanion({
    this.id = const Value.absent(),
    this.minLat = const Value.absent(),
    this.minLng = const Value.absent(),
    this.maxLat = const Value.absent(),
    this.maxLng = const Value.absent(),
    this.fetchedAt = const Value.absent(),
  });
  CachedAreasCompanion.insert({
    this.id = const Value.absent(),
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    required DateTime fetchedAt,
  })  : minLat = Value(minLat),
        minLng = Value(minLng),
        maxLat = Value(maxLat),
        maxLng = Value(maxLng),
        fetchedAt = Value(fetchedAt);
  static Insertable<CachedAreaRow> custom({
    Expression<int>? id,
    Expression<double>? minLat,
    Expression<double>? minLng,
    Expression<double>? maxLat,
    Expression<double>? maxLng,
    Expression<DateTime>? fetchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (minLat != null) 'min_lat': minLat,
      if (minLng != null) 'min_lng': minLng,
      if (maxLat != null) 'max_lat': maxLat,
      if (maxLng != null) 'max_lng': maxLng,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
    });
  }

  CachedAreasCompanion copyWith(
      {Value<int>? id,
      Value<double>? minLat,
      Value<double>? minLng,
      Value<double>? maxLat,
      Value<double>? maxLng,
      Value<DateTime>? fetchedAt}) {
    return CachedAreasCompanion(
      id: id ?? this.id,
      minLat: minLat ?? this.minLat,
      minLng: minLng ?? this.minLng,
      maxLat: maxLat ?? this.maxLat,
      maxLng: maxLng ?? this.maxLng,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (minLat.present) {
      map['min_lat'] = Variable<double>(minLat.value);
    }
    if (minLng.present) {
      map['min_lng'] = Variable<double>(minLng.value);
    }
    if (maxLat.present) {
      map['max_lat'] = Variable<double>(maxLat.value);
    }
    if (maxLng.present) {
      map['max_lng'] = Variable<double>(maxLng.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedAreasCompanion(')
          ..write('id: $id, ')
          ..write('minLat: $minLat, ')
          ..write('minLng: $minLng, ')
          ..write('maxLat: $maxLat, ')
          ..write('maxLng: $maxLng, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }
}

class $MeasurementsTable extends Measurements
    with TableInfo<$MeasurementsTable, MeasurementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeasurementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
      'count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalMsMeta =
      const VerificationMeta('totalMs');
  @override
  late final GeneratedColumn<int> totalMs = GeneratedColumn<int>(
      'total_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _minMsMeta = const VerificationMeta('minMs');
  @override
  late final GeneratedColumn<int> minMs = GeneratedColumn<int>(
      'min_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _maxMsMeta = const VerificationMeta('maxMs');
  @override
  late final GeneratedColumn<int> maxMs = GeneratedColumn<int>(
      'max_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [key, count, totalMs, minMs, maxMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'measurements';
  @override
  VerificationContext validateIntegrity(Insertable<MeasurementRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
          _countMeta, count.isAcceptableOrUnknown(data['count']!, _countMeta));
    }
    if (data.containsKey('total_ms')) {
      context.handle(_totalMsMeta,
          totalMs.isAcceptableOrUnknown(data['total_ms']!, _totalMsMeta));
    }
    if (data.containsKey('min_ms')) {
      context.handle(
          _minMsMeta, minMs.isAcceptableOrUnknown(data['min_ms']!, _minMsMeta));
    }
    if (data.containsKey('max_ms')) {
      context.handle(
          _maxMsMeta, maxMs.isAcceptableOrUnknown(data['max_ms']!, _maxMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MeasurementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeasurementRow(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      count: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}count'])!,
      totalMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_ms'])!,
      minMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}min_ms']),
      maxMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_ms']),
    );
  }

  @override
  $MeasurementsTable createAlias(String alias) {
    return $MeasurementsTable(attachedDatabase, alias);
  }
}

class MeasurementRow extends DataClass implements Insertable<MeasurementRow> {
  final String key;
  final int count;
  final int totalMs;
  final int? minMs;
  final int? maxMs;
  const MeasurementRow(
      {required this.key,
      required this.count,
      required this.totalMs,
      this.minMs,
      this.maxMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['count'] = Variable<int>(count);
    map['total_ms'] = Variable<int>(totalMs);
    if (!nullToAbsent || minMs != null) {
      map['min_ms'] = Variable<int>(minMs);
    }
    if (!nullToAbsent || maxMs != null) {
      map['max_ms'] = Variable<int>(maxMs);
    }
    return map;
  }

  MeasurementsCompanion toCompanion(bool nullToAbsent) {
    return MeasurementsCompanion(
      key: Value(key),
      count: Value(count),
      totalMs: Value(totalMs),
      minMs:
          minMs == null && nullToAbsent ? const Value.absent() : Value(minMs),
      maxMs:
          maxMs == null && nullToAbsent ? const Value.absent() : Value(maxMs),
    );
  }

  factory MeasurementRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeasurementRow(
      key: serializer.fromJson<String>(json['key']),
      count: serializer.fromJson<int>(json['count']),
      totalMs: serializer.fromJson<int>(json['totalMs']),
      minMs: serializer.fromJson<int?>(json['minMs']),
      maxMs: serializer.fromJson<int?>(json['maxMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'count': serializer.toJson<int>(count),
      'totalMs': serializer.toJson<int>(totalMs),
      'minMs': serializer.toJson<int?>(minMs),
      'maxMs': serializer.toJson<int?>(maxMs),
    };
  }

  MeasurementRow copyWith(
          {String? key,
          int? count,
          int? totalMs,
          Value<int?> minMs = const Value.absent(),
          Value<int?> maxMs = const Value.absent()}) =>
      MeasurementRow(
        key: key ?? this.key,
        count: count ?? this.count,
        totalMs: totalMs ?? this.totalMs,
        minMs: minMs.present ? minMs.value : this.minMs,
        maxMs: maxMs.present ? maxMs.value : this.maxMs,
      );
  MeasurementRow copyWithCompanion(MeasurementsCompanion data) {
    return MeasurementRow(
      key: data.key.present ? data.key.value : this.key,
      count: data.count.present ? data.count.value : this.count,
      totalMs: data.totalMs.present ? data.totalMs.value : this.totalMs,
      minMs: data.minMs.present ? data.minMs.value : this.minMs,
      maxMs: data.maxMs.present ? data.maxMs.value : this.maxMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementRow(')
          ..write('key: $key, ')
          ..write('count: $count, ')
          ..write('totalMs: $totalMs, ')
          ..write('minMs: $minMs, ')
          ..write('maxMs: $maxMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, count, totalMs, minMs, maxMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeasurementRow &&
          other.key == this.key &&
          other.count == this.count &&
          other.totalMs == this.totalMs &&
          other.minMs == this.minMs &&
          other.maxMs == this.maxMs);
}

class MeasurementsCompanion extends UpdateCompanion<MeasurementRow> {
  final Value<String> key;
  final Value<int> count;
  final Value<int> totalMs;
  final Value<int?> minMs;
  final Value<int?> maxMs;
  final Value<int> rowid;
  const MeasurementsCompanion({
    this.key = const Value.absent(),
    this.count = const Value.absent(),
    this.totalMs = const Value.absent(),
    this.minMs = const Value.absent(),
    this.maxMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeasurementsCompanion.insert({
    required String key,
    this.count = const Value.absent(),
    this.totalMs = const Value.absent(),
    this.minMs = const Value.absent(),
    this.maxMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<MeasurementRow> custom({
    Expression<String>? key,
    Expression<int>? count,
    Expression<int>? totalMs,
    Expression<int>? minMs,
    Expression<int>? maxMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (count != null) 'count': count,
      if (totalMs != null) 'total_ms': totalMs,
      if (minMs != null) 'min_ms': minMs,
      if (maxMs != null) 'max_ms': maxMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeasurementsCompanion copyWith(
      {Value<String>? key,
      Value<int>? count,
      Value<int>? totalMs,
      Value<int?>? minMs,
      Value<int?>? maxMs,
      Value<int>? rowid}) {
    return MeasurementsCompanion(
      key: key ?? this.key,
      count: count ?? this.count,
      totalMs: totalMs ?? this.totalMs,
      minMs: minMs ?? this.minMs,
      maxMs: maxMs ?? this.maxMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (totalMs.present) {
      map['total_ms'] = Variable<int>(totalMs.value);
    }
    if (minMs.present) {
      map['min_ms'] = Variable<int>(minMs.value);
    }
    if (maxMs.present) {
      map['max_ms'] = Variable<int>(maxMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementsCompanion(')
          ..write('key: $key, ')
          ..write('count: $count, ')
          ..write('totalMs: $totalMs, ')
          ..write('minMs: $minMs, ')
          ..write('maxMs: $maxMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedTypesTable cachedTypes = $CachedTypesTable(this);
  late final $CachedHazardsTable cachedHazards = $CachedHazardsTable(this);
  late final $CachedAreasTable cachedAreas = $CachedAreasTable(this);
  late final $MeasurementsTable measurements = $MeasurementsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedTypes, cachedHazards, cachedAreas, measurements];
}

typedef $$CachedTypesTableCreateCompanionBuilder = CachedTypesCompanion
    Function({
  required String code,
  required String label,
  required String iconName,
  required String resolvedLabel,
  required int dedupRadiusM,
  required bool enabled,
  required int sortOrder,
  Value<Uint8List?> iconPng,
  Value<int> rowid,
});
typedef $$CachedTypesTableUpdateCompanionBuilder = CachedTypesCompanion
    Function({
  Value<String> code,
  Value<String> label,
  Value<String> iconName,
  Value<String> resolvedLabel,
  Value<int> dedupRadiusM,
  Value<bool> enabled,
  Value<int> sortOrder,
  Value<Uint8List?> iconPng,
  Value<int> rowid,
});

class $$CachedTypesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTypesTable> {
  $$CachedTypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconName => $composableBuilder(
      column: $table.iconName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resolvedLabel => $composableBuilder(
      column: $table.resolvedLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dedupRadiusM => $composableBuilder(
      column: $table.dedupRadiusM, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get iconPng => $composableBuilder(
      column: $table.iconPng, builder: (column) => ColumnFilters(column));
}

class $$CachedTypesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTypesTable> {
  $$CachedTypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconName => $composableBuilder(
      column: $table.iconName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resolvedLabel => $composableBuilder(
      column: $table.resolvedLabel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dedupRadiusM => $composableBuilder(
      column: $table.dedupRadiusM,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get iconPng => $composableBuilder(
      column: $table.iconPng, builder: (column) => ColumnOrderings(column));
}

class $$CachedTypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTypesTable> {
  $$CachedTypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get iconName =>
      $composableBuilder(column: $table.iconName, builder: (column) => column);

  GeneratedColumn<String> get resolvedLabel => $composableBuilder(
      column: $table.resolvedLabel, builder: (column) => column);

  GeneratedColumn<int> get dedupRadiusM => $composableBuilder(
      column: $table.dedupRadiusM, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<Uint8List> get iconPng =>
      $composableBuilder(column: $table.iconPng, builder: (column) => column);
}

class $$CachedTypesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedTypesTable,
    CachedTypeRow,
    $$CachedTypesTableFilterComposer,
    $$CachedTypesTableOrderingComposer,
    $$CachedTypesTableAnnotationComposer,
    $$CachedTypesTableCreateCompanionBuilder,
    $$CachedTypesTableUpdateCompanionBuilder,
    (
      CachedTypeRow,
      BaseReferences<_$AppDatabase, $CachedTypesTable, CachedTypeRow>
    ),
    CachedTypeRow,
    PrefetchHooks Function()> {
  $$CachedTypesTableTableManager(_$AppDatabase db, $CachedTypesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> code = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<String> iconName = const Value.absent(),
            Value<String> resolvedLabel = const Value.absent(),
            Value<int> dedupRadiusM = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<Uint8List?> iconPng = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTypesCompanion(
            code: code,
            label: label,
            iconName: iconName,
            resolvedLabel: resolvedLabel,
            dedupRadiusM: dedupRadiusM,
            enabled: enabled,
            sortOrder: sortOrder,
            iconPng: iconPng,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String code,
            required String label,
            required String iconName,
            required String resolvedLabel,
            required int dedupRadiusM,
            required bool enabled,
            required int sortOrder,
            Value<Uint8List?> iconPng = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTypesCompanion.insert(
            code: code,
            label: label,
            iconName: iconName,
            resolvedLabel: resolvedLabel,
            dedupRadiusM: dedupRadiusM,
            enabled: enabled,
            sortOrder: sortOrder,
            iconPng: iconPng,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedTypesTable, CachedTypeRow>(table),
                    BaseReferences<_$AppDatabase, $CachedTypesTable,
                        CachedTypeRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedTypesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedTypesTable,
    CachedTypeRow,
    $$CachedTypesTableFilterComposer,
    $$CachedTypesTableOrderingComposer,
    $$CachedTypesTableAnnotationComposer,
    $$CachedTypesTableCreateCompanionBuilder,
    $$CachedTypesTableUpdateCompanionBuilder,
    (
      CachedTypeRow,
      BaseReferences<_$AppDatabase, $CachedTypesTable, CachedTypeRow>
    ),
    CachedTypeRow,
    PrefetchHooks Function()>;
typedef $$CachedHazardsTableCreateCompanionBuilder = CachedHazardsCompanion
    Function({
  required String id,
  required String type,
  required double lat,
  required double lng,
  required int severity,
  required String status,
  Value<String?> description,
  Value<String?> address,
  required DateTime createdAt,
  required DateTime lastConfirmedAt,
  required double confirmWeight,
  required double resolveWeight,
  required int resolveThreshold,
  required bool reportedRemotely,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$CachedHazardsTableUpdateCompanionBuilder = CachedHazardsCompanion
    Function({
  Value<String> id,
  Value<String> type,
  Value<double> lat,
  Value<double> lng,
  Value<int> severity,
  Value<String> status,
  Value<String?> description,
  Value<String?> address,
  Value<DateTime> createdAt,
  Value<DateTime> lastConfirmedAt,
  Value<double> confirmWeight,
  Value<double> resolveWeight,
  Value<int> resolveThreshold,
  Value<bool> reportedRemotely,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$CachedHazardsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedHazardsTable> {
  $$CachedHazardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lng => $composableBuilder(
      column: $table.lng, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get severity => $composableBuilder(
      column: $table.severity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastConfirmedAt => $composableBuilder(
      column: $table.lastConfirmedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get confirmWeight => $composableBuilder(
      column: $table.confirmWeight, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get resolveWeight => $composableBuilder(
      column: $table.resolveWeight, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get resolveThreshold => $composableBuilder(
      column: $table.resolveThreshold,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get reportedRemotely => $composableBuilder(
      column: $table.reportedRemotely,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedHazardsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedHazardsTable> {
  $$CachedHazardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lng => $composableBuilder(
      column: $table.lng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get severity => $composableBuilder(
      column: $table.severity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastConfirmedAt => $composableBuilder(
      column: $table.lastConfirmedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get confirmWeight => $composableBuilder(
      column: $table.confirmWeight,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get resolveWeight => $composableBuilder(
      column: $table.resolveWeight,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get resolveThreshold => $composableBuilder(
      column: $table.resolveThreshold,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get reportedRemotely => $composableBuilder(
      column: $table.reportedRemotely,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedHazardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedHazardsTable> {
  $$CachedHazardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<int> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConfirmedAt => $composableBuilder(
      column: $table.lastConfirmedAt, builder: (column) => column);

  GeneratedColumn<double> get confirmWeight => $composableBuilder(
      column: $table.confirmWeight, builder: (column) => column);

  GeneratedColumn<double> get resolveWeight => $composableBuilder(
      column: $table.resolveWeight, builder: (column) => column);

  GeneratedColumn<int> get resolveThreshold => $composableBuilder(
      column: $table.resolveThreshold, builder: (column) => column);

  GeneratedColumn<bool> get reportedRemotely => $composableBuilder(
      column: $table.reportedRemotely, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedHazardsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedHazardsTable,
    CachedHazardRow,
    $$CachedHazardsTableFilterComposer,
    $$CachedHazardsTableOrderingComposer,
    $$CachedHazardsTableAnnotationComposer,
    $$CachedHazardsTableCreateCompanionBuilder,
    $$CachedHazardsTableUpdateCompanionBuilder,
    (
      CachedHazardRow,
      BaseReferences<_$AppDatabase, $CachedHazardsTable, CachedHazardRow>
    ),
    CachedHazardRow,
    PrefetchHooks Function()> {
  $$CachedHazardsTableTableManager(_$AppDatabase db, $CachedHazardsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedHazardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedHazardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedHazardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> lat = const Value.absent(),
            Value<double> lng = const Value.absent(),
            Value<int> severity = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> lastConfirmedAt = const Value.absent(),
            Value<double> confirmWeight = const Value.absent(),
            Value<double> resolveWeight = const Value.absent(),
            Value<int> resolveThreshold = const Value.absent(),
            Value<bool> reportedRemotely = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedHazardsCompanion(
            id: id,
            type: type,
            lat: lat,
            lng: lng,
            severity: severity,
            status: status,
            description: description,
            address: address,
            createdAt: createdAt,
            lastConfirmedAt: lastConfirmedAt,
            confirmWeight: confirmWeight,
            resolveWeight: resolveWeight,
            resolveThreshold: resolveThreshold,
            reportedRemotely: reportedRemotely,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            required double lat,
            required double lng,
            required int severity,
            required String status,
            Value<String?> description = const Value.absent(),
            Value<String?> address = const Value.absent(),
            required DateTime createdAt,
            required DateTime lastConfirmedAt,
            required double confirmWeight,
            required double resolveWeight,
            required int resolveThreshold,
            required bool reportedRemotely,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedHazardsCompanion.insert(
            id: id,
            type: type,
            lat: lat,
            lng: lng,
            severity: severity,
            status: status,
            description: description,
            address: address,
            createdAt: createdAt,
            lastConfirmedAt: lastConfirmedAt,
            confirmWeight: confirmWeight,
            resolveWeight: resolveWeight,
            resolveThreshold: resolveThreshold,
            reportedRemotely: reportedRemotely,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedHazardsTable, CachedHazardRow>(table),
                    BaseReferences<_$AppDatabase, $CachedHazardsTable,
                        CachedHazardRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedHazardsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedHazardsTable,
    CachedHazardRow,
    $$CachedHazardsTableFilterComposer,
    $$CachedHazardsTableOrderingComposer,
    $$CachedHazardsTableAnnotationComposer,
    $$CachedHazardsTableCreateCompanionBuilder,
    $$CachedHazardsTableUpdateCompanionBuilder,
    (
      CachedHazardRow,
      BaseReferences<_$AppDatabase, $CachedHazardsTable, CachedHazardRow>
    ),
    CachedHazardRow,
    PrefetchHooks Function()>;
typedef $$CachedAreasTableCreateCompanionBuilder = CachedAreasCompanion
    Function({
  Value<int> id,
  required double minLat,
  required double minLng,
  required double maxLat,
  required double maxLng,
  required DateTime fetchedAt,
});
typedef $$CachedAreasTableUpdateCompanionBuilder = CachedAreasCompanion
    Function({
  Value<int> id,
  Value<double> minLat,
  Value<double> minLng,
  Value<double> maxLat,
  Value<double> maxLng,
  Value<DateTime> fetchedAt,
});

class $$CachedAreasTableFilterComposer
    extends Composer<_$AppDatabase, $CachedAreasTable> {
  $$CachedAreasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get minLat => $composableBuilder(
      column: $table.minLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get minLng => $composableBuilder(
      column: $table.minLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get maxLat => $composableBuilder(
      column: $table.maxLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get maxLng => $composableBuilder(
      column: $table.maxLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedAreasTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedAreasTable> {
  $$CachedAreasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get minLat => $composableBuilder(
      column: $table.minLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get minLng => $composableBuilder(
      column: $table.minLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get maxLat => $composableBuilder(
      column: $table.maxLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get maxLng => $composableBuilder(
      column: $table.maxLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedAreasTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedAreasTable> {
  $$CachedAreasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get minLat =>
      $composableBuilder(column: $table.minLat, builder: (column) => column);

  GeneratedColumn<double> get minLng =>
      $composableBuilder(column: $table.minLng, builder: (column) => column);

  GeneratedColumn<double> get maxLat =>
      $composableBuilder(column: $table.maxLat, builder: (column) => column);

  GeneratedColumn<double> get maxLng =>
      $composableBuilder(column: $table.maxLng, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CachedAreasTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedAreasTable,
    CachedAreaRow,
    $$CachedAreasTableFilterComposer,
    $$CachedAreasTableOrderingComposer,
    $$CachedAreasTableAnnotationComposer,
    $$CachedAreasTableCreateCompanionBuilder,
    $$CachedAreasTableUpdateCompanionBuilder,
    (
      CachedAreaRow,
      BaseReferences<_$AppDatabase, $CachedAreasTable, CachedAreaRow>
    ),
    CachedAreaRow,
    PrefetchHooks Function()> {
  $$CachedAreasTableTableManager(_$AppDatabase db, $CachedAreasTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAreasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAreasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedAreasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> minLat = const Value.absent(),
            Value<double> minLng = const Value.absent(),
            Value<double> maxLat = const Value.absent(),
            Value<double> maxLng = const Value.absent(),
            Value<DateTime> fetchedAt = const Value.absent(),
          }) =>
              CachedAreasCompanion(
            id: id,
            minLat: minLat,
            minLng: minLng,
            maxLat: maxLat,
            maxLng: maxLng,
            fetchedAt: fetchedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required double minLat,
            required double minLng,
            required double maxLat,
            required double maxLng,
            required DateTime fetchedAt,
          }) =>
              CachedAreasCompanion.insert(
            id: id,
            minLat: minLat,
            minLng: minLng,
            maxLat: maxLat,
            maxLng: maxLng,
            fetchedAt: fetchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedAreasTable, CachedAreaRow>(table),
                    BaseReferences<_$AppDatabase, $CachedAreasTable,
                        CachedAreaRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedAreasTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedAreasTable,
    CachedAreaRow,
    $$CachedAreasTableFilterComposer,
    $$CachedAreasTableOrderingComposer,
    $$CachedAreasTableAnnotationComposer,
    $$CachedAreasTableCreateCompanionBuilder,
    $$CachedAreasTableUpdateCompanionBuilder,
    (
      CachedAreaRow,
      BaseReferences<_$AppDatabase, $CachedAreasTable, CachedAreaRow>
    ),
    CachedAreaRow,
    PrefetchHooks Function()>;
typedef $$MeasurementsTableCreateCompanionBuilder = MeasurementsCompanion
    Function({
  required String key,
  Value<int> count,
  Value<int> totalMs,
  Value<int?> minMs,
  Value<int?> maxMs,
  Value<int> rowid,
});
typedef $$MeasurementsTableUpdateCompanionBuilder = MeasurementsCompanion
    Function({
  Value<String> key,
  Value<int> count,
  Value<int> totalMs,
  Value<int?> minMs,
  Value<int?> maxMs,
  Value<int> rowid,
});

class $$MeasurementsTableFilterComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get count => $composableBuilder(
      column: $table.count, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalMs => $composableBuilder(
      column: $table.totalMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minMs => $composableBuilder(
      column: $table.minMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxMs => $composableBuilder(
      column: $table.maxMs, builder: (column) => ColumnFilters(column));
}

class $$MeasurementsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get count => $composableBuilder(
      column: $table.count, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalMs => $composableBuilder(
      column: $table.totalMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minMs => $composableBuilder(
      column: $table.minMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxMs => $composableBuilder(
      column: $table.maxMs, builder: (column) => ColumnOrderings(column));
}

class $$MeasurementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<int> get totalMs =>
      $composableBuilder(column: $table.totalMs, builder: (column) => column);

  GeneratedColumn<int> get minMs =>
      $composableBuilder(column: $table.minMs, builder: (column) => column);

  GeneratedColumn<int> get maxMs =>
      $composableBuilder(column: $table.maxMs, builder: (column) => column);
}

class $$MeasurementsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MeasurementsTable,
    MeasurementRow,
    $$MeasurementsTableFilterComposer,
    $$MeasurementsTableOrderingComposer,
    $$MeasurementsTableAnnotationComposer,
    $$MeasurementsTableCreateCompanionBuilder,
    $$MeasurementsTableUpdateCompanionBuilder,
    (
      MeasurementRow,
      BaseReferences<_$AppDatabase, $MeasurementsTable, MeasurementRow>
    ),
    MeasurementRow,
    PrefetchHooks Function()> {
  $$MeasurementsTableTableManager(_$AppDatabase db, $MeasurementsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeasurementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeasurementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeasurementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<int> count = const Value.absent(),
            Value<int> totalMs = const Value.absent(),
            Value<int?> minMs = const Value.absent(),
            Value<int?> maxMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MeasurementsCompanion(
            key: key,
            count: count,
            totalMs: totalMs,
            minMs: minMs,
            maxMs: maxMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            Value<int> count = const Value.absent(),
            Value<int> totalMs = const Value.absent(),
            Value<int?> minMs = const Value.absent(),
            Value<int?> maxMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MeasurementsCompanion.insert(
            key: key,
            count: count,
            totalMs: totalMs,
            minMs: minMs,
            maxMs: maxMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MeasurementsTable, MeasurementRow>(table),
                    BaseReferences<_$AppDatabase, $MeasurementsTable,
                        MeasurementRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MeasurementsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MeasurementsTable,
    MeasurementRow,
    $$MeasurementsTableFilterComposer,
    $$MeasurementsTableOrderingComposer,
    $$MeasurementsTableAnnotationComposer,
    $$MeasurementsTableCreateCompanionBuilder,
    $$MeasurementsTableUpdateCompanionBuilder,
    (
      MeasurementRow,
      BaseReferences<_$AppDatabase, $MeasurementsTable, MeasurementRow>
    ),
    MeasurementRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedTypesTableTableManager get cachedTypes =>
      $$CachedTypesTableTableManager(_db, _db.cachedTypes);
  $$CachedHazardsTableTableManager get cachedHazards =>
      $$CachedHazardsTableTableManager(_db, _db.cachedHazards);
  $$CachedAreasTableTableManager get cachedAreas =>
      $$CachedAreasTableTableManager(_db, _db.cachedAreas);
  $$MeasurementsTableTableManager get measurements =>
      $$MeasurementsTableTableManager(_db, _db.measurements);
}
