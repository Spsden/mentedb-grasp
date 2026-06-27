import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mentedb_flutter/mentedb_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('processes, stores, recalls, and maintains native MenteDB memories',
      () async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databasePath = [
      supportDirectory.path,
      'mentedb-integration-${DateTime.now().microsecondsSinceEpoch}',
    ].join(Platform.pathSeparator);

    final store = await RustMenteDbMemoryStore.open(
      path: databasePath,
      embeddingDimensions: 64,
    );
    addTearDown(store.close);

    final ingest = await store.replaceMemoryBank(
      'Alex avoids peanuts.\nAlex prefers mushrooms on weekdays.',
      source: 'integration_bank',
      maxChunkChars: 160,
    );
    expect(ingest.stored, greaterThan(0));

    final recall = await store.recallForPrompt(
      'What should I remember for Alex?',
      source: 'integration_bank',
      limit: 4,
      maxContextChars: 512,
    );
    expect(recall.memories, isNotEmpty);
    expect(recall.context, contains('Alex'));

    final processed = await store.processTurn(
      'Deploy the dinner plan without peanut sauce.',
      assistantResponse: 'Use mushrooms, Thai basil, and no nut sauces.',
      turnId: 1,
      projectContext: 'integration_project',
    );
    expect(processed.stored, 1);
    expect(processed.episodicId, isNotNull);
    expect(processed.contextText, contains('Alex'));
    expect(
      processed.detectedActions.any(
        (action) => action.actionType == 'deployment',
      ),
      isTrue,
    );

    final turn = await store.storeConversationTurn(
      conversationId: 'integration_chat',
      turnIndex: 2,
      userMessage: 'What should I remember for Alex?',
      assistantMessage: 'Avoid peanuts and suggest mushrooms.',
    );
    expect(turn.stored, 2);

    final graph = await store.graphProjection(limit: 50);
    expect(graph.nodes.length, greaterThanOrEqualTo(4));
    expect(
      graph.edges.any(
        (edge) =>
            edge.source == turn.userMemoryId &&
            edge.target == turn.assistantMemoryId,
      ),
      isTrue,
    );

    final sleep = await store.runSleepMaintenance(maxMemories: 100);
    expect(sleep.leaseAcquired, isTrue);
    expect(sleep.processedMemories, greaterThan(0));
  });

  test('opens with the docs style MenteDB facade', () async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databasePath = [
      supportDirectory.path,
      'mentedb-facade-${DateTime.now().microsecondsSinceEpoch}',
    ].join(Platform.pathSeparator);

    final db = await MenteDB.open(databasePath, embeddingDimensions: 64);
    addTearDown(db.close);

    final result = await db.processTurn(
      'I prefer Flutter for mobile memory apps.',
      assistantResponse: 'Noted, I will keep Flutter in mind.',
      turnId: 1,
      projectContext: 'facade_test',
    );

    expect(result.stored, 1);
    expect(result.storedIds, isNotEmpty);
    expect(result.memoryCount, greaterThanOrEqualTo(1));
  });
}
