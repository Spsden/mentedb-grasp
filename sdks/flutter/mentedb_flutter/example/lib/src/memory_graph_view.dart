import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mentedb_flutter/mentedb_flutter.dart';

class MemoryGraphView extends StatefulWidget {
  const MemoryGraphView({
    super.key,
    required this.projection,
    required this.selectedNodeId,
    required this.onNodeSelected,
    this.isLoading = false,
  });

  final BridgeGraphProjection? projection;
  final String? selectedNodeId;
  final ValueChanged<String?> onNodeSelected;
  final bool isLoading;

  @override
  State<MemoryGraphView> createState() => _MemoryGraphViewState();
}

class _MemoryGraphViewState extends State<MemoryGraphView> {
  double _rotationX = -0.18;
  double _rotationY = 0.38;
  double _zoom = 1;
  double _scaleStartZoom = 1;

  @override
  Widget build(BuildContext context) {
    final projection = widget.projection;
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxWidth >= 900 ? 420.0 : 340.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onScaleStart: (_) {
                      _scaleStartZoom = _zoom;
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        _rotationY += details.focalPointDelta.dx * 0.008;
                        _rotationX =
                            (_rotationX - details.focalPointDelta.dy * 0.008)
                                .clamp(
                          -math.pi / 2,
                          math.pi / 2,
                        );
                        _zoom = (_scaleStartZoom * details.scale).clamp(
                          0.7,
                          2.4,
                        );
                      });
                    },
                    onTapUp: (details) {
                      if (projection == null) {
                        return;
                      }
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) {
                        return;
                      }
                      final localPosition =
                          box.globalToLocal(details.globalPosition);
                      final selected = _nearestNode(
                        projection,
                        localPosition,
                        Size(constraints.maxWidth, height),
                        _rotationX,
                        _rotationY,
                        _zoom,
                      );
                      widget.onNodeSelected(selected?.node.id);
                    },
                    child: CustomPaint(
                      painter: _GraphPainter(
                        projection: projection,
                        selectedNodeId: widget.selectedNodeId,
                        colorScheme: colorScheme,
                        rotationX: _rotationX,
                        rotationY: _rotationY,
                        zoom: _zoom,
                        isLoading: widget.isLoading,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _GraphNodeDetail(
              projection: projection,
              selectedNodeId: widget.selectedNodeId,
            ),
            const SizedBox(height: 10),
            _GraphRelationshipList(
              projection: projection,
              selectedNodeId: widget.selectedNodeId,
              onNodeSelected: widget.onNodeSelected,
            ),
          ],
        );
      },
    );
  }
}

class _GraphNodeDetail extends StatelessWidget {
  const _GraphNodeDetail({
    required this.projection,
    required this.selectedNodeId,
  });

  final BridgeGraphProjection? projection;
  final String? selectedNodeId;

  @override
  Widget build(BuildContext context) {
    final projection = this.projection;
    if (projection == null || projection.nodes.isEmpty) {
      return const SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No graph loaded'),
        ),
      );
    }

    BridgeGraphProjectionNode? selected;
    for (final node in projection.nodes) {
      if (node.id == selectedNodeId) {
        selected = node;
        break;
      }
    }
    final node = selected ?? projection.nodes.first;
    final tags = node.tags.take(4).toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              node.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            SelectableText(node.preview),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.category_outlined, size: 16),
                  label: Text(node.memoryType.name),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(Icons.bubble_chart_outlined, size: 16),
                  label: Text('Salience ${node.salience.toStringAsFixed(2)}'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(Icons.verified_outlined, size: 16),
                  label:
                      Text('Confidence ${node.confidence.toStringAsFixed(2)}'),
                  visualDensity: VisualDensity.compact,
                ),
                if (node.embeddingDim > 0)
                  Chip(
                    avatar: const Icon(Icons.functions, size: 16),
                    label: Text('Embedding ${node.embeddingDim}d'),
                    visualDensity: VisualDensity.compact,
                  ),
                for (final tag in tags)
                  Chip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: Text(_compactText(tag, 28)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphRelationshipList extends StatelessWidget {
  const _GraphRelationshipList({
    required this.projection,
    required this.selectedNodeId,
    required this.onNodeSelected,
  });

  final BridgeGraphProjection? projection;
  final String? selectedNodeId;
  final ValueChanged<String?> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final projection = this.projection;
    if (projection == null || projection.edges.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedId = selectedNodeId;
    final byId = {for (final node in projection.nodes) node.id: node};
    final edges = selectedId == null
        ? projection.edges.take(8).toList(growable: false)
        : projection.edges
            .where((edge) =>
                edge.source == selectedId || edge.target == selectedId)
            .take(12)
            .toList(growable: false);

    if (edges.isEmpty) {
      return Text(
        'No relationships for selected memory',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Relationships',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final edge in edges) ...[
              _RelationshipRow(
                edge: edge,
                source: byId[edge.source],
                target: byId[edge.target],
                onNodeSelected: onNodeSelected,
              ),
              if (edge != edges.last) const Divider(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelationshipRow extends StatelessWidget {
  const _RelationshipRow({
    required this.edge,
    required this.source,
    required this.target,
    required this.onNodeSelected,
  });

  final BridgeGraphProjectionEdge edge;
  final BridgeGraphProjectionNode? source;
  final BridgeGraphProjectionNode? target;
  final ValueChanged<String?> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = _compactText(source?.label ?? edge.source, 36);
    final targetLabel = _compactText(target?.label ?? edge.target, 36);
    final relation = _edgeDisplayName(edge);
    final color = _edgeColor(edge.edgeType, Theme.of(context).colorScheme);

    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => onNodeSelected(edge.source),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(sourceLabel, overflow: TextOverflow.ellipsis),
          ),
        ),
        Chip(
          avatar: Icon(Icons.arrow_forward, size: 15, color: color),
          label: Text(relation),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: TextButton(
            onPressed: () => onNodeSelected(edge.target),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(targetLabel, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.projection,
    required this.selectedNodeId,
    required this.colorScheme,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.isLoading,
  });

  final BridgeGraphProjection? projection;
  final String? selectedNodeId;
  final ColorScheme colorScheme;
  final double rotationX;
  final double rotationY;
  final double zoom;
  final bool isLoading;

  @override
  void paint(Canvas canvas, Size size) {
    final projection = this.projection;
    if (isLoading) {
      _drawCenteredText(canvas, size, 'Loading graph', colorScheme.onSurface);
      return;
    }
    if (projection == null || projection.nodes.isEmpty) {
      _drawCenteredText(canvas, size, 'Run comparison to load graph',
          colorScheme.onSurfaceVariant);
      return;
    }

    final projected = _projectNodes(
      projection,
      size,
      rotationX,
      rotationY,
      zoom,
    );
    final byId = {for (final node in projected) node.node.id: node};
    final edgePaint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..color = colorScheme.outline.withValues(alpha: 0.36);

    for (final edge in projection.edges) {
      final source = byId[edge.source];
      final target = byId[edge.target];
      if (source == null || target == null) {
        continue;
      }
      final selectedEdge =
          edge.source == selectedNodeId || edge.target == selectedNodeId;
      final alpha = selectedEdge
          ? 0.92
          : ((source.depth + target.depth) / 2).clamp(0.26, 0.72);
      edgePaint.color = _edgeColor(edge.edgeType, colorScheme).withValues(
        alpha: alpha,
      );
      edgePaint.strokeWidth = selectedEdge ? 2.2 : 1.2;
      final endpoints = _edgeEndpoints(source, target);
      canvas.drawLine(endpoints.start, endpoints.end, edgePaint);
      _drawArrowHead(canvas, endpoints.start, endpoints.end, edgePaint.color);
      if (projection.edges.length <= 80 || selectedEdge) {
        _drawEdgeLabel(
          canvas,
          edge,
          endpoints.start,
          endpoints.end,
          edgePaint.color,
          colorScheme,
          selectedEdge,
        );
      }
    }

    projected.sort((a, b) => a.depth.compareTo(b.depth));
    for (final node in projected) {
      final selected = node.node.id == selectedNodeId;
      final fill = _nodeColor(node.node.memoryType, colorScheme);
      final radius = selected ? node.radius + 3 : node.radius;
      final shadowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withValues(alpha: 0.12 * node.depth);
      canvas.drawCircle(
        node.offset.translate(0, 2),
        radius + 2,
        shadowPaint,
      );
      canvas.drawCircle(
        node.offset,
        radius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fill.withValues(alpha: 0.72 + 0.2 * node.depth),
      );
      canvas.drawCircle(
        node.offset,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.8 : 1.2
          ..color = selected ? colorScheme.primary : colorScheme.outline,
      );
    }
    for (final node in projected) {
      final selected = node.node.id == selectedNodeId;
      if (selected || projection.nodes.length <= 80 || node.depth > 0.62) {
        _drawNodeLabel(canvas, size, node, colorScheme, selected);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.projection != projection ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.isLoading != isLoading;
  }
}

_EdgeEndpoints _edgeEndpoints(_ProjectedNode source, _ProjectedNode target) {
  final delta = target.offset - source.offset;
  final distance = delta.distance;
  if (distance <= 0.01) {
    return _EdgeEndpoints(start: source.offset, end: target.offset);
  }

  final unit = Offset(delta.dx / distance, delta.dy / distance);
  return _EdgeEndpoints(
    start: source.offset + unit * (source.radius + 2),
    end: target.offset - unit * (target.radius + 5),
  );
}

void _drawArrowHead(Canvas canvas, Offset start, Offset end, Color color) {
  final delta = end - start;
  final distance = delta.distance;
  if (distance <= 10) {
    return;
  }

  final unit = Offset(delta.dx / distance, delta.dy / distance);
  final normal = Offset(-unit.dy, unit.dx);
  final tip = end;
  final base = tip - unit * 9;
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo((base + normal * 4.5).dx, (base + normal * 4.5).dy)
    ..lineTo((base - normal * 4.5).dx, (base - normal * 4.5).dy)
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.fill
      ..color = color,
  );
}

void _drawEdgeLabel(
  Canvas canvas,
  BridgeGraphProjectionEdge edge,
  Offset start,
  Offset end,
  Color color,
  ColorScheme colorScheme,
  bool selected,
) {
  final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
  final text = _compactText(_edgeDisplayName(edge), selected ? 34 : 22);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color:
            selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        fontSize: selected ? 12 : 10.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '...',
  )..layout(maxWidth: selected ? 190 : 140);
  final rect = Rect.fromCenter(
    center: midpoint,
    width: painter.width + 12,
    height: painter.height + 6,
  );
  final background = selected
      ? colorScheme.primaryContainer.withValues(alpha: 0.94)
      : colorScheme.surface.withValues(alpha: 0.88);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    Paint()
      ..style = PaintingStyle.fill
      ..color = background,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.2 : 0.8
      ..color = color.withValues(alpha: selected ? 0.85 : 0.55),
  );
  painter.paint(
    canvas,
    Offset(rect.left + 6, rect.top + 3),
  );
}

void _drawNodeLabel(
  Canvas canvas,
  Size size,
  _ProjectedNode node,
  ColorScheme colorScheme,
  bool selected,
) {
  final label = _compactText(node.node.label, selected ? 42 : 30);
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color:
            selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        fontSize: selected ? 13 : 11.5,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '...',
  )..layout(maxWidth: selected ? 220 : 170);

  final preferredLeft = node.offset.dx + node.radius + 8;
  final preferredTop = node.offset.dy - painter.height / 2;
  final left = preferredLeft
      .clamp(8.0, math.max(8.0, size.width - painter.width - 18))
      .toDouble();
  final top = preferredTop
      .clamp(8.0, math.max(8.0, size.height - painter.height - 18))
      .toDouble();
  final rect = Rect.fromLTWH(
    left - 5,
    top - 4,
    painter.width + 10,
    painter.height + 8,
  );
  final fill = selected
      ? colorScheme.primaryContainer.withValues(alpha: 0.96)
      : colorScheme.surface.withValues(alpha: 0.9);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    Paint()
      ..style = PaintingStyle.fill
      ..color = fill,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.2 : 0.7
      ..color = _nodeColor(node.node.memoryType, colorScheme).withValues(
        alpha: selected ? 0.9 : 0.52,
      ),
  );
  painter.paint(canvas, Offset(left, top));
}

_ProjectedNode? _nearestNode(
  BridgeGraphProjection projection,
  Offset position,
  Size size,
  double rotationX,
  double rotationY,
  double zoom,
) {
  final nodes = _projectNodes(projection, size, rotationX, rotationY, zoom);
  _ProjectedNode? best;
  double bestDistance = double.infinity;
  for (final node in nodes) {
    final distance = (node.offset - position).distance;
    if (distance < bestDistance && distance <= node.radius + 14) {
      best = node;
      bestDistance = distance;
    }
  }
  return best;
}

List<_ProjectedNode> _projectNodes(
  BridgeGraphProjection projection,
  Size size,
  double rotationX,
  double rotationY,
  double zoom,
) {
  final count = projection.nodes.length;
  if (count == 0) {
    return const [];
  }

  final radius = math.min(size.width, size.height) * 0.36 * zoom;
  final center = Offset(size.width / 2, size.height / 2);
  final goldenAngle = math.pi * (3 - math.sqrt(5));
  final sinX = math.sin(rotationX);
  final cosX = math.cos(rotationX);
  final sinY = math.sin(rotationY);
  final cosY = math.cos(rotationY);

  return List.generate(count, (index) {
    final node = projection.nodes[index];
    final offset = index + 0.5;
    final z0 = 1 - 2 * offset / count;
    final ring = math.sqrt(math.max(0, 1 - z0 * z0));
    final theta = index * goldenAngle;
    var x = math.cos(theta) * ring;
    var y = math.sin(theta) * ring;
    var z = z0;

    final y1 = y * cosX - z * sinX;
    final z1 = y * sinX + z * cosX;
    final x2 = x * cosY + z1 * sinY;
    final z2 = -x * sinY + z1 * cosY;
    x = x2;
    y = y1;
    z = z2;

    final perspective = 0.72 + (z + 1) * 0.18;
    final salience = node.salience.clamp(0.2, 1.0);
    final nodeRadius = (5.5 + salience * 7) * perspective;
    return _ProjectedNode(
      node: node,
      offset: Offset(
        center.dx + x * radius * perspective,
        center.dy + y * radius * perspective,
      ),
      depth: ((z + 1) / 2).clamp(0, 1),
      radius: nodeRadius,
    );
  });
}

void _drawCenteredText(Canvas canvas, Size size, String text, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 14),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: size.width - 32);
  painter.paint(
    canvas,
    Offset(
      (size.width - painter.width) / 2,
      (size.height - painter.height) / 2,
    ),
  );
}

Color _nodeColor(BridgeMemoryType type, ColorScheme colorScheme) {
  return switch (type) {
    BridgeMemoryType.episodic => colorScheme.primary,
    BridgeMemoryType.semantic => colorScheme.tertiary,
    BridgeMemoryType.procedural => colorScheme.secondary,
    BridgeMemoryType.antiPattern => colorScheme.error,
    BridgeMemoryType.reasoning => colorScheme.inversePrimary,
    BridgeMemoryType.correction => colorScheme.errorContainer,
  };
}

Color _edgeColor(BridgeEdgeType type, ColorScheme colorScheme) {
  return switch (type) {
    BridgeEdgeType.before => colorScheme.primary,
    BridgeEdgeType.related => colorScheme.secondary,
    BridgeEdgeType.supports => colorScheme.tertiary,
    BridgeEdgeType.contradicts => colorScheme.error,
    BridgeEdgeType.supersedes => colorScheme.error,
    BridgeEdgeType.caused => colorScheme.primary,
    BridgeEdgeType.derived => colorScheme.secondary,
    BridgeEdgeType.partOf => colorScheme.tertiary,
  };
}

String _edgeDisplayName(BridgeGraphProjectionEdge edge) {
  final type = _edgeTypeName(edge.edgeType);
  final label = edge.label?.trim();
  if (label == null || label.isEmpty) {
    return type;
  }

  final normalized = _friendlyLabel(label);
  if (normalized.toLowerCase() == type.toLowerCase()) {
    return type;
  }
  return '$normalized / $type';
}

String _edgeTypeName(BridgeEdgeType type) {
  return switch (type) {
    BridgeEdgeType.caused => 'caused',
    BridgeEdgeType.before => 'before',
    BridgeEdgeType.related => 'related',
    BridgeEdgeType.contradicts => 'contradicts',
    BridgeEdgeType.supports => 'supports',
    BridgeEdgeType.supersedes => 'supersedes',
    BridgeEdgeType.derived => 'derived',
    BridgeEdgeType.partOf => 'part of',
  };
}

String _friendlyLabel(String value) {
  return value.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
}

String _compactText(String value, int maxChars) {
  final normalized = _friendlyLabel(value);
  if (normalized.length <= maxChars) {
    return normalized;
  }
  if (maxChars <= 3) {
    return normalized.substring(0, maxChars);
  }
  return '${normalized.substring(0, maxChars - 3)}...';
}

final class _EdgeEndpoints {
  const _EdgeEndpoints({required this.start, required this.end});

  final Offset start;
  final Offset end;
}

final class _ProjectedNode {
  const _ProjectedNode({
    required this.node,
    required this.offset,
    required this.depth,
    required this.radius,
  });

  final BridgeGraphProjectionNode node;
  final Offset offset;
  final double depth;
  final double radius;
}
