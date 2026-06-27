import 'dart:async';

import 'rust/api/memory.dart' as bridge;
import 'rust/frb_generated.dart';

const defaultNativeEmbeddingDimensions = 384;
const defaultNativeMemorySource = 'flutter_demo_memory_bank';
const defaultNativeConversationSource = 'recent_chat';
const defaultNativeMemoryChunkChars = 800;
const defaultNativeRecallLimit = 8;
const defaultNativeRecallContextChars = 2400;
const defaultNativeSleepMaxMemories = 1000;
const defaultNativeGraphLimit = 250;

abstract interface class MenteDbMemoryStore {
  String get databasePath;
  String get agentId;
  int get embeddingDimensions;

  Future<bridge.IngestMemoryBankResult> replaceMemoryBank(
    String text, {
    String source = defaultNativeMemorySource,
    bridge.BridgeMemoryType memoryType = bridge.BridgeMemoryType.semantic,
    int maxChunkChars = defaultNativeMemoryChunkChars,
  });

  Future<bridge.RecallMemoryContextResult> recallForPrompt(
    String query, {
    String? source,
    int limit = defaultNativeRecallLimit,
    int maxContextChars = defaultNativeRecallContextChars,
  });

  Future<bridge.ProcessTurnResult> processTurn(
    String userMessage, {
    String? assistantResponse,
    int turnId = 0,
    String? projectContext,
    String? agentId,
  });

  Future<bridge.StoreConversationTurnResult> storeConversationTurn({
    required String conversationId,
    required int turnIndex,
    required String userMessage,
    required String assistantMessage,
    String source = defaultNativeConversationSource,
  });

  Future<bridge.BridgeSleepMaintenanceResult> runSleepMaintenance({
    int maxMemories = defaultNativeSleepMaxMemories,
    bool applyDecay = true,
    bool evaluateArchival = true,
    bool applyArchivalDeletes = false,
    bool runConsolidation = true,
    int maxConsolidationClusters = 4,
    int consolidationMinClusterSize = 2,
    double consolidationSimilarityThreshold = 0.85,
    bool linkEntities = true,
  });

  Future<int> memoryCount();

  Future<bridge.BridgeGraphProjection> graphProjection({
    String? center,
    int depth = 2,
    int limit = defaultNativeGraphLimit,
    int labelChars = 64,
    int previewChars = 240,
    bool includeInvalidated = false,
    bool includeEdges = true,
  });

  Future<void> close();
}

final class RustMenteDbMemoryStore implements MenteDbMemoryStore {
  RustMenteDbMemoryStore._({
    required this.databasePath,
    required this.agentId,
    required this.embeddingDimensions,
    required int handle,
  }) : _handle = handle;

  final int _handle;
  bool _closed = false;

  @override
  final String databasePath;

  @override
  final String agentId;

  @override
  final int embeddingDimensions;

  static Future<RustMenteDbMemoryStore> open({
    required String path,
    int embeddingDimensions = defaultNativeEmbeddingDimensions,
    String? agentId,
  }) async {
    await MenteDbRustBridge.ensureInitialized();
    final opened = await bridge.openDatabase(
      request: bridge.OpenDatabaseRequest(
        path: path,
        embeddingDimensions: embeddingDimensions,
        agentId: agentId,
      ),
    );
    return RustMenteDbMemoryStore._(
      databasePath: opened.path,
      agentId: opened.agentId,
      embeddingDimensions: opened.embeddingDimensions,
      handle: opened.handle,
    );
  }

  @override
  Future<bridge.IngestMemoryBankResult> replaceMemoryBank(
    String text, {
    String source = defaultNativeMemorySource,
    bridge.BridgeMemoryType memoryType = bridge.BridgeMemoryType.semantic,
    int maxChunkChars = defaultNativeMemoryChunkChars,
  }) {
    _throwIfClosed();
    return bridge.ingestMemoryBank(
      request: bridge.IngestMemoryBankRequest(
        handle: _handle,
        text: text,
        source: source,
        memoryType: memoryType,
        maxChunkChars: maxChunkChars,
        replaceSource: true,
        flush: true,
      ),
    );
  }

  @override
  Future<bridge.RecallMemoryContextResult> recallForPrompt(
    String query, {
    String? source,
    int limit = defaultNativeRecallLimit,
    int maxContextChars = defaultNativeRecallContextChars,
  }) {
    _throwIfClosed();
    return bridge.recallMemoryContext(
      request: bridge.RecallMemoryContextRequest(
        handle: _handle,
        query: query,
        limit: limit,
        maxContextChars: maxContextChars,
        source: source,
      ),
    );
  }

  @override
  Future<bridge.ProcessTurnResult> processTurn(
    String userMessage, {
    String? assistantResponse,
    int turnId = 0,
    String? projectContext,
    String? agentId,
  }) {
    _throwIfClosed();
    return bridge.processTurn(
      request: bridge.ProcessTurnRequest(
        handle: _handle,
        userMessage: userMessage,
        assistantResponse: assistantResponse,
        turnId: turnId,
        projectContext: projectContext,
        agentId: agentId,
        flush: true,
      ),
    );
  }

  @override
  Future<bridge.StoreConversationTurnResult> storeConversationTurn({
    required String conversationId,
    required int turnIndex,
    required String userMessage,
    required String assistantMessage,
    String source = defaultNativeConversationSource,
  }) {
    _throwIfClosed();
    return bridge.storeConversationTurn(
      request: bridge.StoreConversationTurnRequest(
        handle: _handle,
        conversationId: conversationId,
        turnIndex: turnIndex,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        source: source,
        flush: true,
      ),
    );
  }

  @override
  Future<bridge.BridgeSleepMaintenanceResult> runSleepMaintenance({
    int maxMemories = defaultNativeSleepMaxMemories,
    bool applyDecay = true,
    bool evaluateArchival = true,
    bool applyArchivalDeletes = false,
    bool runConsolidation = true,
    int maxConsolidationClusters = 4,
    int consolidationMinClusterSize = 2,
    double consolidationSimilarityThreshold = 0.85,
    bool linkEntities = true,
  }) {
    _throwIfClosed();
    return bridge.runSleepMaintenance(
      request: bridge.RunSleepMaintenanceRequest(
        handle: _handle,
        maxMemories: maxMemories,
        applyDecay: applyDecay,
        evaluateArchival: evaluateArchival,
        applyArchivalDeletes: applyArchivalDeletes,
        runConsolidation: runConsolidation,
        maxConsolidationClusters: maxConsolidationClusters,
        consolidationMinClusterSize: consolidationMinClusterSize,
        consolidationSimilarityThreshold: consolidationSimilarityThreshold,
        linkEntities: linkEntities,
      ),
    );
  }

  @override
  Future<int> memoryCount() {
    _throwIfClosed();
    return bridge.memoryCount(handle: _handle);
  }

  @override
  Future<bridge.BridgeGraphProjection> graphProjection({
    String? center,
    int depth = 2,
    int limit = defaultNativeGraphLimit,
    int labelChars = 64,
    int previewChars = 240,
    bool includeInvalidated = false,
    bool includeEdges = true,
  }) {
    _throwIfClosed();
    return bridge.graphProjection(
      request: bridge.GraphProjectionRequest(
        handle: _handle,
        center: center,
        depth: depth,
        limit: limit,
        labelChars: labelChars,
        previewChars: previewChars,
        includeInvalidated: includeInvalidated,
        includeEdges: includeEdges,
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await bridge.closeDatabase(handle: _handle);
  }

  void _throwIfClosed() {
    if (_closed) {
      throw StateError('MenteDB memory store is closed.');
    }
  }
}

// ignore: camel_case_types
final class MenteDB {
  MenteDB._(this._store);

  final RustMenteDbMemoryStore _store;

  String get databasePath => _store.databasePath;
  String get agentId => _store.agentId;
  int get embeddingDimensions => _store.embeddingDimensions;

  static Future<MenteDB> open(
    String path, {
    int embeddingDimensions = defaultNativeEmbeddingDimensions,
    String? agentId,
  }) async {
    final store = await RustMenteDbMemoryStore.open(
      path: path,
      embeddingDimensions: embeddingDimensions,
      agentId: agentId,
    );
    return MenteDB._(store);
  }

  Future<bridge.ProcessTurnResult> processTurn(
    String userMessage, {
    String? assistantResponse,
    int turnId = 0,
    String? projectContext,
    String? agentId,
  }) {
    return _store.processTurn(
      userMessage,
      assistantResponse: assistantResponse,
      turnId: turnId,
      projectContext: projectContext,
      agentId: agentId,
    );
  }

  Future<bridge.IngestMemoryBankResult> storeTextMemoryBank(
    String text, {
    String source = defaultNativeMemorySource,
    bridge.BridgeMemoryType memoryType = bridge.BridgeMemoryType.semantic,
    int maxChunkChars = defaultNativeMemoryChunkChars,
  }) {
    return _store.replaceMemoryBank(
      text,
      source: source,
      memoryType: memoryType,
      maxChunkChars: maxChunkChars,
    );
  }

  Future<bridge.BridgeSleepMaintenanceResult> runSleepMaintenance({
    int maxMemories = defaultNativeSleepMaxMemories,
    bool applyDecay = true,
    bool evaluateArchival = true,
    bool applyArchivalDeletes = false,
    bool runConsolidation = true,
    int maxConsolidationClusters = 4,
    int consolidationMinClusterSize = 2,
    double consolidationSimilarityThreshold = 0.85,
    bool linkEntities = true,
  }) {
    return _store.runSleepMaintenance(
      maxMemories: maxMemories,
      applyDecay: applyDecay,
      evaluateArchival: evaluateArchival,
      applyArchivalDeletes: applyArchivalDeletes,
      runConsolidation: runConsolidation,
      maxConsolidationClusters: maxConsolidationClusters,
      consolidationMinClusterSize: consolidationMinClusterSize,
      consolidationSimilarityThreshold: consolidationSimilarityThreshold,
      linkEntities: linkEntities,
    );
  }

  Future<bridge.BridgeGraphProjection> graphProjection({
    String? center,
    int depth = 2,
    int limit = defaultNativeGraphLimit,
    int labelChars = 64,
    int previewChars = 240,
    bool includeInvalidated = false,
    bool includeEdges = true,
  }) {
    return _store.graphProjection(
      center: center,
      depth: depth,
      limit: limit,
      labelChars: labelChars,
      previewChars: previewChars,
      includeInvalidated: includeInvalidated,
      includeEdges: includeEdges,
    );
  }

  Future<int> memoryCount() => _store.memoryCount();

  Future<void> close() => _store.close();

  RustMenteDbMemoryStore get nativeStore => _store;
}

final class MenteDbRustBridge {
  MenteDbRustBridge._();

  static Future<void>? _initializing;
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    final initializing = _initializing ??= RustLib.init();
    await initializing;
    _initialized = true;
  }
}
