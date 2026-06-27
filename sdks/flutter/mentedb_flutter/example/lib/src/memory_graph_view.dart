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
              ],
            ),
          ],
        ),
      ),
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
      final alpha = ((source.depth + target.depth) / 2).clamp(0.22, 0.78);
      edgePaint.color = _edgeColor(edge.edgeType, colorScheme).withValues(
        alpha: alpha,
      );
      canvas.drawLine(source.offset, target.offset, edgePaint);
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
