import 'graph_projection.dart';

enum SleepMaintenanceStage {
  decay,
  archival,
  consolidation,
  entityLinking;

  static SleepMaintenanceStage fromJson(String value) {
    return switch (value) {
      'Decay' => SleepMaintenanceStage.decay,
      'Archival' => SleepMaintenanceStage.archival,
      'Consolidation' => SleepMaintenanceStage.consolidation,
      'EntityLinking' => SleepMaintenanceStage.entityLinking,
      _ => throw FormatException('Unknown maintenance stage: $value'),
    };
  }
}

final class SleepMaintenanceConfig {
  const SleepMaintenanceConfig({
    this.maxMemories = 1000,
    this.applyDecay = true,
    this.decayWriteEpsilon = 0.001,
    this.evaluateArchival = true,
    this.applyArchivalDeletes = false,
    this.runConsolidation = true,
    this.maxConsolidationClusters = 4,
    this.consolidationMinClusterSize = 2,
    this.consolidationSimilarityThreshold = 0.85,
    this.linkEntities = true,
  });

  final int maxMemories;
  final bool applyDecay;
  final double decayWriteEpsilon;
  final bool evaluateArchival;
  final bool applyArchivalDeletes;
  final bool runConsolidation;
  final int maxConsolidationClusters;
  final int consolidationMinClusterSize;
  final double consolidationSimilarityThreshold;
  final bool linkEntities;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'max_memories': maxMemories,
      'apply_decay': applyDecay,
      'decay_write_epsilon': decayWriteEpsilon,
      'evaluate_archival': evaluateArchival,
      'apply_archival_deletes': applyArchivalDeletes,
      'run_consolidation': runConsolidation,
      'max_consolidation_clusters': maxConsolidationClusters,
      'consolidation_min_cluster_size': consolidationMinClusterSize,
      'consolidation_similarity_threshold': consolidationSimilarityThreshold,
      'link_entities': linkEntities,
    };
  }
}

final class SleepMaintenanceResult {
  const SleepMaintenanceResult({
    required this.processedMemories,
    required this.decayUpdated,
    required this.archivalEvaluated,
    required this.archivalKeep,
    required this.archivalArchive,
    required this.archivalDelete,
    required this.archivalConsolidate,
    required this.archivalDeleteApplied,
    required this.consolidationCandidates,
    required this.consolidated,
    required this.consolidatedMemoryIds,
    required this.entityPairsLinked,
    required this.entityEdgesCreated,
    required this.entityPairsAmbiguous,
    required this.enrichmentPending,
    required this.enrichmentCandidates,
    required this.issues,
  });

  final int processedMemories;
  final int decayUpdated;
  final int archivalEvaluated;
  final int archivalKeep;
  final int archivalArchive;
  final int archivalDelete;
  final int archivalConsolidate;
  final int archivalDeleteApplied;
  final int consolidationCandidates;
  final int consolidated;
  final List<MemoryId> consolidatedMemoryIds;
  final int entityPairsLinked;
  final int entityEdgesCreated;
  final int entityPairsAmbiguous;
  final bool enrichmentPending;
  final int enrichmentCandidates;
  final List<SleepMaintenanceIssue> issues;

  factory SleepMaintenanceResult.fromJson(Map<String, Object?> json) {
    return SleepMaintenanceResult(
      processedMemories: _readInt(
        json['processed_memories'],
        'processed_memories',
      ),
      decayUpdated: _readInt(json['decay_updated'], 'decay_updated'),
      archivalEvaluated: _readInt(
        json['archival_evaluated'],
        'archival_evaluated',
      ),
      archivalKeep: _readInt(json['archival_keep'], 'archival_keep'),
      archivalArchive: _readInt(json['archival_archive'], 'archival_archive'),
      archivalDelete: _readInt(json['archival_delete'], 'archival_delete'),
      archivalConsolidate: _readInt(
        json['archival_consolidate'],
        'archival_consolidate',
      ),
      archivalDeleteApplied: _readInt(
        json['archival_delete_applied'],
        'archival_delete_applied',
      ),
      consolidationCandidates: _readInt(
        json['consolidation_candidates'],
        'consolidation_candidates',
      ),
      consolidated: _readInt(json['consolidated'], 'consolidated'),
      consolidatedMemoryIds: _readStringList(
        json['consolidated_memory_ids'],
        'consolidated_memory_ids',
      ),
      entityPairsLinked: _readInt(
        json['entity_pairs_linked'],
        'entity_pairs_linked',
      ),
      entityEdgesCreated: _readInt(
        json['entity_edges_created'],
        'entity_edges_created',
      ),
      entityPairsAmbiguous: _readInt(
        json['entity_pairs_ambiguous'],
        'entity_pairs_ambiguous',
      ),
      enrichmentPending: _readBool(
        json['enrichment_pending'],
        'enrichment_pending',
      ),
      enrichmentCandidates: _readInt(
        json['enrichment_candidates'],
        'enrichment_candidates',
      ),
      issues: _readIssueList(json['issues'], 'issues'),
    );
  }
}

final class SleepMaintenanceIssue {
  const SleepMaintenanceIssue({
    required this.stage,
    required this.memoryId,
    required this.message,
  });

  final SleepMaintenanceStage stage;
  final MemoryId? memoryId;
  final String message;

  factory SleepMaintenanceIssue.fromJson(Map<String, Object?> json) {
    return SleepMaintenanceIssue(
      stage: SleepMaintenanceStage.fromJson(
        _readString(json['stage'], 'stage'),
      ),
      memoryId: _readNullableString(json['memory_id'], 'memory_id'),
      message: _readString(json['message'], 'message'),
    );
  }
}

List<SleepMaintenanceIssue> _readIssueList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('Expected issue list for $field');
  }
  return value
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw FormatException('Expected issue object for $field');
        }
        return SleepMaintenanceIssue.fromJson(item);
      })
      .toList(growable: false);
}

List<String> _readStringList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('Expected string list for $field');
  }
  return value.map((item) => _readString(item, field)).toList(growable: false);
}

String _readString(Object? value, String field) {
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string for $field');
}

String? _readNullableString(Object? value, String field) {
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException('Expected string or null for $field');
}

int _readInt(Object? value, String field) {
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $field');
}

bool _readBool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool for $field');
}
