import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentedb_flutter/mentedb_flutter.dart';
import 'package:mentedb_memory_demo/src/memory_graph_view.dart';

void main() {
  testWidgets('renders selected node and relationship metadata',
      (tester) async {
    final projection = BridgeGraphProjection(
      nodes: const [
        BridgeGraphProjectionNode(
          id: 'user-1',
          label: 'User: What should I remember for Alex?',
          preview: 'What should I remember for Alex?',
          memoryType: BridgeMemoryType.episodic,
          salience: 0.8,
          confidence: 0.9,
          tags: ['recent_chat', 'role:user'],
          createdAtMicros: 1,
          accessedAtMicros: 1,
          embeddingDim: 384,
        ),
        BridgeGraphProjectionNode(
          id: 'assistant-1',
          label: 'Assistant: Avoid peanuts and suggest mushrooms.',
          preview: 'Avoid peanuts and suggest mushrooms.',
          memoryType: BridgeMemoryType.episodic,
          salience: 0.85,
          confidence: 0.92,
          tags: ['recent_chat', 'role:assistant'],
          createdAtMicros: 2,
          accessedAtMicros: 2,
          embeddingDim: 384,
        ),
      ],
      edges: const [
        BridgeGraphProjectionEdge(
          source: 'user-1',
          target: 'assistant-1',
          edgeType: BridgeEdgeType.before,
          weight: 1,
          label: 'assistant_response',
          createdAtMicros: 3,
        ),
      ],
      availableNodes: 2,
      truncated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MemoryGraphView(
              projection: projection,
              selectedNodeId: 'user-1',
              onNodeSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('User: What should I remember for Alex?'), findsOneWidget);
    expect(find.textContaining('What should I remember'), findsWidgets);
    expect(find.text('Relationships'), findsOneWidget);
    expect(find.text('assistant response / before'), findsOneWidget);
    expect(find.textContaining('Assistant: Avoid peanuts'), findsOneWidget);
  });
}
