typedef MemoryId = String;

enum MenteMemoryType {
  episodic,
  semantic,
  procedural,
  antiPattern,
  reasoning,
  correction;

  static MenteMemoryType fromJson(String value) {
    return switch (value) {
      'Episodic' => MenteMemoryType.episodic,
      'Semantic' => MenteMemoryType.semantic,
      'Procedural' => MenteMemoryType.procedural,
      'AntiPattern' => MenteMemoryType.antiPattern,
      'Reasoning' => MenteMemoryType.reasoning,
      'Correction' => MenteMemoryType.correction,
      _ => throw FormatException('Unknown memory type: $value'),
    };
  }

  String toJson() {
    return switch (this) {
      MenteMemoryType.episodic => 'Episodic',
      MenteMemoryType.semantic => 'Semantic',
      MenteMemoryType.procedural => 'Procedural',
      MenteMemoryType.antiPattern => 'AntiPattern',
      MenteMemoryType.reasoning => 'Reasoning',
      MenteMemoryType.correction => 'Correction',
    };
  }
}

enum MenteEdgeType {
  caused,
  before,
  related,
  contradicts,
  supports,
  supersedes,
  derived,
  partOf;

  static MenteEdgeType fromJson(String value) {
    return switch (value) {
      'Caused' => MenteEdgeType.caused,
      'Before' => MenteEdgeType.before,
      'Related' => MenteEdgeType.related,
      'Contradicts' => MenteEdgeType.contradicts,
      'Supports' => MenteEdgeType.supports,
      'Supersedes' => MenteEdgeType.supersedes,
      'Derived' => MenteEdgeType.derived,
      'PartOf' => MenteEdgeType.partOf,
      _ => throw FormatException('Unknown edge type: $value'),
    };
  }

  String toJson() {
    return switch (this) {
      MenteEdgeType.caused => 'Caused',
      MenteEdgeType.before => 'Before',
      MenteEdgeType.related => 'Related',
      MenteEdgeType.contradicts => 'Contradicts',
      MenteEdgeType.supports => 'Supports',
      MenteEdgeType.supersedes => 'Supersedes',
      MenteEdgeType.derived => 'Derived',
      MenteEdgeType.partOf => 'PartOf',
    };
  }
}

final class GraphProjectionConfig {
  const GraphProjectionConfig({
    this.center,
    this.depth = 2,
    this.limit = 500,
    this.labelChars = 64,
    this.previewChars = 240,
    this.includeInvalidated = false,
    this.includeEdges = true,
  });

  final MemoryId? center;
  final int depth;
  final int limit;
  final int labelChars;
  final int previewChars;
  final bool includeInvalidated;
  final bool includeEdges;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'center': center,
      'depth': depth,
      'limit': limit,
      'label_chars': labelChars,
      'preview_chars': previewChars,
      'include_invalidated': includeInvalidated,
      'include_edges': includeEdges,
    };
  }
}

final class GraphProjection {
  const GraphProjection({
    required this.nodes,
    required this.edges,
    required this.availableNodes,
    required this.truncated,
  });

  final List<GraphProjectionNode> nodes;
  final List<GraphProjectionEdge> edges;
  final int availableNodes;
  final bool truncated;

  factory GraphProjection.fromJson(Map<String, Object?> json) {
    return GraphProjection(
      nodes: _readList(
        json['nodes'],
        (value) => GraphProjectionNode.fromJson(value),
      ),
      edges: _readList(
        json['edges'],
        (value) => GraphProjectionEdge.fromJson(value),
      ),
      availableNodes: _readInt(json['available_nodes'], 'available_nodes'),
      truncated: _readBool(json['truncated'], 'truncated'),
    );
  }
}

final class GraphProjectionNode {
  const GraphProjectionNode({
    required this.id,
    required this.label,
    required this.preview,
    required this.memoryType,
    required this.salience,
    required this.confidence,
    required this.tags,
    required this.createdAt,
    required this.accessedAt,
    required this.validUntil,
    required this.embeddingDim,
  });

  final MemoryId id;
  final String label;
  final String preview;
  final MenteMemoryType memoryType;
  final double salience;
  final double confidence;
  final List<String> tags;
  final int createdAt;
  final int accessedAt;
  final int? validUntil;
  final int embeddingDim;

  factory GraphProjectionNode.fromJson(Map<String, Object?> json) {
    return GraphProjectionNode(
      id: _readString(json['id'], 'id'),
      label: _readString(json['label'], 'label'),
      preview: _readString(json['preview'], 'preview'),
      memoryType: MenteMemoryType.fromJson(
        _readString(json['memory_type'], 'memory_type'),
      ),
      salience: _readDouble(json['salience'], 'salience'),
      confidence: _readDouble(json['confidence'], 'confidence'),
      tags: _readStringList(json['tags'], 'tags'),
      createdAt: _readInt(json['created_at'], 'created_at'),
      accessedAt: _readInt(json['accessed_at'], 'accessed_at'),
      validUntil: _readNullableInt(json['valid_until'], 'valid_until'),
      embeddingDim: _readInt(json['embedding_dim'], 'embedding_dim'),
    );
  }
}

final class GraphProjectionEdge {
  const GraphProjectionEdge({
    required this.source,
    required this.target,
    required this.edgeType,
    required this.weight,
    required this.label,
    required this.createdAt,
    required this.validUntil,
  });

  final MemoryId source;
  final MemoryId target;
  final MenteEdgeType edgeType;
  final double weight;
  final String? label;
  final int createdAt;
  final int? validUntil;

  factory GraphProjectionEdge.fromJson(Map<String, Object?> json) {
    return GraphProjectionEdge(
      source: _readString(json['source'], 'source'),
      target: _readString(json['target'], 'target'),
      edgeType: MenteEdgeType.fromJson(
        _readString(json['edge_type'], 'edge_type'),
      ),
      weight: _readDouble(json['weight'], 'weight'),
      label: _readNullableString(json['label'], 'label'),
      createdAt: _readInt(json['created_at'], 'created_at'),
      validUntil: _readNullableInt(json['valid_until'], 'valid_until'),
    );
  }
}

List<T> _readList<T>(
  Object? value,
  T Function(Map<String, Object?> value) convert,
) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON list');
  }
  return value
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw const FormatException('Expected a JSON object');
        }
        return convert(item);
      })
      .toList(growable: false);
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

List<String> _readStringList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('Expected string list for $field');
  }
  return value.map((item) => _readString(item, field)).toList(growable: false);
}

int _readInt(Object? value, String field) {
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $field');
}

int? _readNullableInt(Object? value, String field) {
  if (value == null || value is int) {
    return value as int?;
  }
  throw FormatException('Expected int or null for $field');
}

double _readDouble(Object? value, String field) {
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected number for $field');
}

bool _readBool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool for $field');
}
