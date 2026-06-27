import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mentedb_flutter/mentedb_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'src/demo_scenarios.dart';
import 'src/memory_activity_view.dart';
import 'src/memory_graph_view.dart';
import 'src/memory_prompt.dart';
import 'src/openai_compatible_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MemoryDemoApp(memoryStoreFactory: _openNativeMemoryStore),
  );
}

typedef MemoryStoreFactory = Future<MenteDbMemoryStore> Function();

Future<MenteDbMemoryStore> _openNativeMemoryStore() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final databasePath =
      '${supportDirectory.path}${Platform.pathSeparator}mentedb-memory-demo';
  return RustMenteDbMemoryStore.open(path: databasePath);
}

class MemoryDemoApp extends StatelessWidget {
  const MemoryDemoApp({
    super.key,
    OpenAiCompatibleChatClient? client,
    MemoryStoreFactory? memoryStoreFactory,
  })  : _client = client,
        _memoryStoreFactory = memoryStoreFactory;

  final OpenAiCompatibleChatClient? _client;
  final MemoryStoreFactory? _memoryStoreFactory;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff1f7a65),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'MenteDB Memory Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: MemoryDemoScreen(
        client: _client ?? OpenAiCompatibleChatClient(),
        memoryStoreFactory: _memoryStoreFactory ?? _openNativeMemoryStore,
      ),
    );
  }
}

class MemoryDemoScreen extends StatefulWidget {
  const MemoryDemoScreen({
    super.key,
    required this.client,
    required this.memoryStoreFactory,
  });

  final OpenAiCompatibleChatClient client;
  final MemoryStoreFactory memoryStoreFactory;

  @override
  State<MemoryDemoScreen> createState() => _MemoryDemoScreenState();
}

class _MemoryDemoScreenState extends State<MemoryDemoScreen> {
  final _endpointController = TextEditingController(
    text: defaultOpenRouterEndpoint,
  );
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: defaultOpenRouterModel);
  final _refererController = TextEditingController(
    text: defaultOpenRouterReferer,
  );
  final _appTitleController = TextEditingController(
    text: defaultOpenRouterTitle,
  );
  final _systemController = TextEditingController(text: defaultSystemPrompt);
  final _promptController = TextEditingController(
    text: demoPersonas.first.scenario.steps.first.userPrompt,
  );
  final _memoryController = TextEditingController(
    text: demoPersonas.first.memoryBank,
  );

  double _temperature = 0.2;
  bool _hideApiKey = true;
  bool _isRunning = false;
  bool _isMaintaining = false;
  bool _isLoadingGraph = false;
  bool _runSleepMaintenance = true;
  String _conversationId = _newConversationId();
  String _selectedPersonaId = demoPersonas.first.id;
  int _scenarioStepIndex = 0;
  int _turnIndex = 0;
  Future<MenteDbMemoryStore>? _memoryStoreFuture;
  MenteDbMemoryStore? _memoryStore;
  String? _error;
  String? _databasePath;
  int? _memoryCount;
  IngestMemoryBankResult? _ingestResult;
  RecallMemoryContextResult? _recallResult;
  BridgeSleepMaintenanceResult? _sleepResult;
  StoreConversationTurnResult? _conversationTurnResult;
  ProcessTurnResult? _processTurnResult;
  BridgeGraphProjection? _graphProjection;
  String? _selectedGraphNodeId;
  ChatCompletionResult? _withoutMemory;
  ChatCompletionResult? _withMemory;

  static String _newConversationId() {
    return 'demo-${DateTime.now().microsecondsSinceEpoch}';
  }

  DemoPersona get _selectedPersona => demoPersonaById(_selectedPersonaId);

  String get _projectContext =>
      '${_selectedPersona.projectContext}:$_conversationId';

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _refererController.dispose();
    _appTitleController.dispose();
    _systemController.dispose();
    _promptController.dispose();
    _memoryController.dispose();
    final memoryStore = _memoryStore;
    if (memoryStore != null) {
      unawaited(memoryStore.close());
    }
    widget.client.close();
    super.dispose();
  }

  Future<MenteDbMemoryStore> _ensureMemoryStore() async {
    final current = _memoryStore;
    if (current != null) {
      return current;
    }
    final store = await (_memoryStoreFuture ??= widget.memoryStoreFactory());
    _memoryStore = store;
    _databasePath = store.databasePath;
    return store;
  }

  Future<BridgeGraphProjection> _loadGraphProjection(
    MenteDbMemoryStore memoryStore,
  ) {
    return memoryStore.graphProjection(
      depth: 3,
      limit: 320,
      labelChars: 72,
      previewChars: 280,
      includeInvalidated: false,
      includeEdges: true,
    );
  }

  String? _selectedNodeAfterRefresh(
    BridgeGraphProjection projection, {
    String? preferredNodeId,
  }) {
    final preferred = preferredNodeId ?? _selectedGraphNodeId;
    if (preferred != null &&
        projection.nodes.any((node) => node.id == preferred)) {
      return preferred;
    }
    if (projection.nodes.isEmpty) {
      return null;
    }
    return projection.nodes.first.id;
  }

  Future<void> _runManualSleepMaintenance() async {
    setState(() {
      _isMaintaining = true;
      _error = null;
    });

    try {
      final memoryStore = await _ensureMemoryStore();
      final sleepResult = await memoryStore.runSleepMaintenance();
      final count = await memoryStore.memoryCount();
      final graph = await _loadGraphProjection(memoryStore);
      if (!mounted) {
        return;
      }
      setState(() {
        _sleepResult = sleepResult;
        _memoryCount = count;
        _graphProjection = graph;
        _selectedGraphNodeId = _selectedNodeAfterRefresh(graph);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isMaintaining = false;
        });
      }
    }
  }

  Future<void> _refreshGraph() async {
    setState(() {
      _isLoadingGraph = true;
      _error = null;
    });

    try {
      final memoryStore = await _ensureMemoryStore();
      final graph = await _loadGraphProjection(memoryStore);
      final count = await memoryStore.memoryCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _graphProjection = graph;
        _memoryCount = count;
        _selectedGraphNodeId = _selectedNodeAfterRefresh(graph);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGraph = false;
        });
      }
    }
  }

  Future<void> _runComparison() async {
    final endpoint = _endpointController.text.trim();
    final model = _modelController.text.trim();
    final userPrompt = _promptController.text.trim();
    final memoryBank = _memoryController.text.trim();

    if (endpoint.isEmpty || model.isEmpty || userPrompt.isEmpty) {
      setState(() {
        _error = 'Endpoint, model, and prompt are required.';
      });
      return;
    }
    setState(() {
      _isRunning = true;
      _error = null;
      _ingestResult = null;
      _recallResult = null;
      _sleepResult = null;
      _conversationTurnResult = null;
      _processTurnResult = null;
      _withoutMemory = null;
      _withMemory = null;
    });

    try {
      final memoryStore = await _ensureMemoryStore();
      final ingestResult = memoryBank.isEmpty
          ? null
          : await memoryStore.replaceMemoryBank(memoryBank);
      final nextTurnIndex = _turnIndex + 1;
      final preTurnResult = await memoryStore.processTurn(
        userPrompt,
        turnId: nextTurnIndex,
        projectContext: _projectContext,
      );

      final uri = resolveChatCompletionsUri(endpoint);
      final apiKey = _apiKeyController.text.trim();
      final providerHeaders = buildOpenRouterAttributionHeaders(
        endpoint: uri,
        referer: _refererController.text,
        title: _appTitleController.text,
      );
      final systemPrompt = _systemController.text.trim();
      final withoutMemoryMessages = buildChatMessages(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        memoryContext: null,
      );
      final withMemoryMessages = buildChatMessages(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        memoryContext: preTurnResult.contextText,
      );

      final responses = await Future.wait([
        widget.client.complete(
          endpoint: uri,
          apiKey: apiKey.isEmpty ? null : apiKey,
          model: model,
          temperature: _temperature,
          messages: withoutMemoryMessages,
          headers: providerHeaders,
        ),
        widget.client.complete(
          endpoint: uri,
          apiKey: apiKey.isEmpty ? null : apiKey,
          model: model,
          temperature: _temperature,
          messages: withMemoryMessages,
          headers: providerHeaders,
        ),
      ]);

      final processTurnResult = await memoryStore.processTurn(
        userPrompt,
        assistantResponse: responses[1].content,
        turnId: nextTurnIndex,
        projectContext: _projectContext,
      );
      final sleepResult =
          _runSleepMaintenance ? await memoryStore.runSleepMaintenance() : null;
      final count = await memoryStore.memoryCount();
      final graph = await _loadGraphProjection(memoryStore);

      if (!mounted) {
        return;
      }
      setState(() {
        _turnIndex = nextTurnIndex;
        _databasePath = memoryStore.databasePath;
        _memoryCount = count;
        _ingestResult = ingestResult;
        _recallResult = null;
        _sleepResult = sleepResult;
        _conversationTurnResult = null;
        _processTurnResult = processTurnResult;
        _graphProjection = graph;
        _selectedGraphNodeId = _selectedNodeAfterRefresh(
          graph,
          preferredNodeId: processTurnResult.episodicId,
        );
        _withoutMemory = responses[0];
        _withMemory = responses[1];
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  void _loadSample() {
    setState(() {
      _selectedPersonaId = 'dinner_planner';
      _scenarioStepIndex = 0;
      _conversationId = _newConversationId();
      _turnIndex = 0;
      _systemController.text = defaultSystemPrompt;
      _promptController.text = sampleUserPrompt;
      _memoryController.text = sampleMemoryBank;
      _ingestResult = null;
      _recallResult = null;
      _sleepResult = null;
      _conversationTurnResult = null;
      _processTurnResult = null;
      _withoutMemory = null;
      _withMemory = null;
      _error = null;
    });
  }

  void _useOpenRouterDefaults() {
    setState(() {
      _endpointController.text = defaultOpenRouterEndpoint;
      _modelController.text = defaultOpenRouterModel;
      _refererController.text = defaultOpenRouterReferer;
      _appTitleController.text = defaultOpenRouterTitle;
      _ingestResult = null;
      _recallResult = null;
      _sleepResult = null;
      _conversationTurnResult = null;
      _processTurnResult = null;
      _withoutMemory = null;
      _withMemory = null;
      _error = null;
    });
  }

  void _clearOutputs() {
    setState(() {
      _withoutMemory = null;
      _withMemory = null;
      _ingestResult = null;
      _recallResult = null;
      _sleepResult = null;
      _conversationTurnResult = null;
      _processTurnResult = null;
      _error = null;
    });
  }

  void _selectPersona(String personaId) {
    final persona = demoPersonaById(personaId);
    final firstPrompt = persona.scenario.steps.isEmpty
        ? ''
        : persona.scenario.steps.first.userPrompt;
    setState(() {
      _selectedPersonaId = persona.id;
      _scenarioStepIndex = 0;
      _conversationId = _newConversationId();
      _turnIndex = 0;
      _memoryController.text = persona.memoryBank;
      _promptController.text = firstPrompt;
      _withoutMemory = null;
      _withMemory = null;
      _ingestResult = null;
      _recallResult = null;
      _sleepResult = null;
      _conversationTurnResult = null;
      _processTurnResult = null;
      _graphProjection = null;
      _selectedGraphNodeId = null;
      _error = null;
    });
  }

  Future<void> _sendScenarioStep() async {
    if (_isRunning) {
      return;
    }
    final persona = _selectedPersona;
    if (persona.scenario.steps.isEmpty) {
      return;
    }
    final stepIndex = _scenarioStepIndex.clamp(
      0,
      persona.scenario.steps.length - 1,
    );
    final step = persona.scenario.steps[stepIndex];
    setState(() {
      if (step.startsNewSession) {
        _conversationId = _newConversationId();
        _turnIndex = 0;
        _withoutMemory = null;
        _withMemory = null;
      }
      _promptController.text = step.userPrompt;
    });

    await _runComparison();
    if (!mounted || _error != null) {
      return;
    }
    setState(() {
      _scenarioStepIndex =
          (_scenarioStepIndex + 1) % persona.scenario.steps.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 980;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MenteDB Memory Demo'),
        actions: [
          IconButton(
            tooltip: 'Use OpenRouter',
            onPressed: _useOpenRouterDefaults,
            icon: const Icon(Icons.route),
          ),
          IconButton(
            tooltip: 'Load sample',
            onPressed: _loadSample,
            icon: const Icon(Icons.auto_fix_high),
          ),
          IconButton(
            tooltip: 'Clear outputs',
            onPressed: _clearOutputs,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsSection(
                    endpointController: _endpointController,
                    apiKeyController: _apiKeyController,
                    modelController: _modelController,
                    refererController: _refererController,
                    appTitleController: _appTitleController,
                    hideApiKey: _hideApiKey,
                    temperature: _temperature,
                    onToggleApiKey: () {
                      setState(() {
                        _hideApiKey = !_hideApiKey;
                      });
                    },
                    onTemperatureChanged: (value) {
                      setState(() {
                        _temperature = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _ScenarioSection(
                    persona: _selectedPersona,
                    stepIndex: _scenarioStepIndex,
                    isRunning: _isRunning,
                    onPersonaChanged: _selectPersona,
                    onSendStep: _sendScenarioStep,
                  ),
                  const SizedBox(height: 16),
                  _PromptSection(
                    systemController: _systemController,
                    promptController: _promptController,
                    memoryController: _memoryController,
                    runSleepMaintenance: _runSleepMaintenance,
                    onRunSleepMaintenanceChanged: (value) {
                      setState(() {
                        _runSleepMaintenance = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isRunning ? null : _runComparison,
                    icon: _isRunning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.compare_arrows),
                    label: Text(_isRunning ? 'Running' : 'Run comparison'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 16),
                  _NativeStatusPanel(
                    databasePath: _databasePath,
                    memoryCount: _memoryCount,
                    ingestResult: _ingestResult,
                    recallResult: _recallResult,
                    sleepResult: _sleepResult,
                    conversationTurnResult: _conversationTurnResult,
                    processTurnResult: _processTurnResult,
                    graphProjection: _graphProjection,
                    selectedGraphNodeId: _selectedGraphNodeId,
                    isMaintaining: _isMaintaining,
                    isLoadingGraph: _isLoadingGraph,
                    onRunSleepMaintenance: _isRunning || _isMaintaining
                        ? null
                        : _runManualSleepMaintenance,
                    onRefreshGraph:
                        _isRunning || _isLoadingGraph ? null : _refreshGraph,
                    onGraphNodeSelected: (nodeId) {
                      setState(() {
                        _selectedGraphNodeId = nodeId;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _ResultGrid(
                    isWide: isWide,
                    withoutMemory: _withoutMemory,
                    withMemory: _withMemory,
                  ),
                  const SizedBox(height: 12),
                  _SdkContractFooter(config: const GraphProjectionConfig()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.endpointController,
    required this.apiKeyController,
    required this.modelController,
    required this.refererController,
    required this.appTitleController,
    required this.hideApiKey,
    required this.temperature,
    required this.onToggleApiKey,
    required this.onTemperatureChanged,
  });

  final TextEditingController endpointController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final TextEditingController refererController;
  final TextEditingController appTitleController;
  final bool hideApiKey;
  final double temperature;
  final VoidCallback onToggleApiKey;
  final ValueChanged<double> onTemperatureChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final endpointField = TextField(
          controller: endpointController,
          decoration: const InputDecoration(
            labelText: 'Endpoint',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
        );
        final modelField = TextField(
          controller: modelController,
          decoration: const InputDecoration(
            labelText: 'Model',
            prefixIcon: Icon(Icons.memory),
          ),
        );
        final apiKeyField = TextField(
          controller: apiKeyController,
          obscureText: hideApiKey,
          decoration: InputDecoration(
            labelText: 'API key',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              tooltip: hideApiKey ? 'Show API key' : 'Hide API key',
              onPressed: onToggleApiKey,
              icon: Icon(hideApiKey ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        );
        final refererField = TextField(
          controller: refererController,
          decoration: const InputDecoration(
            labelText: 'OpenRouter referer',
            prefixIcon: Icon(Icons.public),
          ),
          keyboardType: TextInputType.url,
        );
        final titleField = TextField(
          controller: appTitleController,
          decoration: const InputDecoration(
            labelText: 'OpenRouter app title',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        );

        return _Panel(
          title: 'Connection',
          icon: Icons.hub,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: endpointField),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: modelField),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: apiKeyField),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: refererField),
                        const SizedBox(width: 12),
                        Expanded(child: titleField),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    endpointField,
                    const SizedBox(height: 12),
                    modelField,
                    const SizedBox(height: 12),
                    apiKeyField,
                    const SizedBox(height: 12),
                    refererField,
                    const SizedBox(height: 12),
                    titleField,
                  ],
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.thermostat, size: 20),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: Text(
                      'Temperature ${temperature.toStringAsFixed(1)}',
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: temperature,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      label: temperature.toStringAsFixed(1),
                      onChanged: onTemperatureChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScenarioSection extends StatelessWidget {
  const _ScenarioSection({
    required this.persona,
    required this.stepIndex,
    required this.isRunning,
    required this.onPersonaChanged,
    required this.onSendStep,
  });

  final DemoPersona persona;
  final int stepIndex;
  final bool isRunning;
  final ValueChanged<String> onPersonaChanged;
  final VoidCallback onSendStep;

  @override
  Widget build(BuildContext context) {
    final steps = persona.scenario.steps;
    final currentStep =
        steps.isEmpty ? null : steps[stepIndex.clamp(0, steps.length - 1)];
    return _Panel(
      title: 'Guided scenarios',
      icon: Icons.playlist_play,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 820;
          final personaPicker = DropdownButtonFormField<String>(
            initialValue: persona.id,
            decoration: const InputDecoration(
              labelText: 'Persona',
              prefixIcon: Icon(Icons.person_search_outlined),
            ),
            items: [
              for (final item in demoPersonas)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: isRunning
                ? null
                : (value) {
                    if (value != null) {
                      onPersonaChanged(value);
                    }
                  },
          );
          final role = InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Role',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            child: Text(persona.role),
          );
          final scenario = InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Scenario',
              prefixIcon: Icon(Icons.route_outlined),
            ),
            child: Text(persona.scenario.name),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: personaPicker),
                    const SizedBox(width: 12),
                    Expanded(child: role),
                    const SizedBox(width: 12),
                    Expanded(child: scenario),
                  ],
                )
              else ...[
                personaPicker,
                const SizedBox(height: 12),
                role,
                const SizedBox(height: 12),
                scenario,
              ],
              if (currentStep != null) ...[
                const SizedBox(height: 12),
                _ScenarioStepPreview(
                  step: currentStep,
                  index: stepIndex + 1,
                  count: steps.length,
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed:
                      isRunning || currentStep == null ? null : onSendStep,
                  icon: isRunning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(isRunning ? 'Running step' : 'Send guided step'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScenarioStepPreview extends StatelessWidget {
  const _ScenarioStepPreview({
    required this.step,
    required this.index,
    required this.count,
  });

  final DemoScenarioStep step;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MetricChip(
                  icon: Icons.format_list_numbered,
                  label: 'Step $index of $count',
                ),
                if (step.startsNewSession)
                  const _MetricChip(
                    icon: Icons.fiber_new_outlined,
                    label: 'New session',
                  ),
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(step.userPrompt),
            const SizedBox(height: 8),
            Text(
              step.expectedMemorySignal,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptSection extends StatelessWidget {
  const _PromptSection({
    required this.systemController,
    required this.promptController,
    required this.memoryController,
    required this.runSleepMaintenance,
    required this.onRunSleepMaintenanceChanged,
  });

  final TextEditingController systemController;
  final TextEditingController promptController;
  final TextEditingController memoryController;
  final bool runSleepMaintenance;
  final ValueChanged<bool> onRunSleepMaintenanceChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final systemField = TextField(
          controller: systemController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'System prompt',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.tune),
          ),
        );
        final promptField = TextField(
          controller: promptController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'User prompt',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.chat_bubble_outline),
          ),
        );

        final promptChild = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: systemField),
                  const SizedBox(width: 12),
                  Expanded(child: promptField),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  systemField,
                  const SizedBox(height: 12),
                  promptField,
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Panel(title: 'Prompt', icon: Icons.edit_note, child: promptChild),
            const SizedBox(height: 16),
            _Panel(
              title: 'Memory bank',
              icon: Icons.account_tree_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: memoryController,
                    minLines: 8,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: 'Memory text',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: runSleepMaintenance,
                    onChanged: onRunSleepMaintenanceChanged,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Run sleep maintenance'),
                    secondary: const Icon(Icons.bedtime_outlined),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NativeStatusPanel extends StatelessWidget {
  const _NativeStatusPanel({
    required this.databasePath,
    required this.memoryCount,
    required this.ingestResult,
    required this.recallResult,
    required this.sleepResult,
    required this.conversationTurnResult,
    required this.processTurnResult,
    required this.graphProjection,
    required this.selectedGraphNodeId,
    required this.isMaintaining,
    required this.isLoadingGraph,
    required this.onRunSleepMaintenance,
    required this.onRefreshGraph,
    required this.onGraphNodeSelected,
  });

  final String? databasePath;
  final int? memoryCount;
  final IngestMemoryBankResult? ingestResult;
  final RecallMemoryContextResult? recallResult;
  final BridgeSleepMaintenanceResult? sleepResult;
  final StoreConversationTurnResult? conversationTurnResult;
  final ProcessTurnResult? processTurnResult;
  final BridgeGraphProjection? graphProjection;
  final String? selectedGraphNodeId;
  final bool isMaintaining;
  final bool isLoadingGraph;
  final VoidCallback? onRunSleepMaintenance;
  final VoidCallback? onRefreshGraph;
  final ValueChanged<String?> onGraphNodeSelected;

  @override
  Widget build(BuildContext context) {
    final recalled = recallResult;
    final ingested = ingestResult;
    final sleep = sleepResult;
    final storedTurn = conversationTurnResult;
    final processed = processTurnResult;
    final graph = graphProjection;
    final path = databasePath;

    return _Panel(
      title: 'MenteDB',
      icon: Icons.storage_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                icon: Icons.dataset_outlined,
                label: 'Memories ${memoryCount ?? 0}',
              ),
              if (ingested != null)
                _MetricChip(
                  icon: Icons.upload_file,
                  label: 'Stored ${ingested.stored}',
                ),
              if (ingested != null && ingested.replaced > 0)
                _MetricChip(
                  icon: Icons.swap_horiz,
                  label: 'Replaced ${ingested.replaced}',
                ),
              if (recalled != null)
                _MetricChip(
                  icon: Icons.manage_search,
                  label: 'Recalled ${recalled.memories.length}',
                ),
              if (recalled != null && recalled.truncated)
                const _MetricChip(
                  icon: Icons.content_cut,
                  label: 'Context capped',
                ),
              if (sleep != null)
                _MetricChip(
                  icon: Icons.bedtime_outlined,
                  label: sleep.leaseAcquired
                      ? 'Sleep processed ${sleep.processedMemories}'
                      : 'Sleep busy',
                ),
              if (sleep != null && sleep.enrichmentPending)
                _MetricChip(
                  icon: Icons.auto_awesome_motion,
                  label: 'Enrich ${sleep.enrichmentCandidates}',
                ),
              if (storedTurn != null)
                _MetricChip(
                  icon: Icons.history,
                  label: 'Recent chat ${storedTurn.stored}',
                ),
              if (processed != null)
                _MetricChip(
                  icon: Icons.psychology_alt_outlined,
                  label: 'Process stored ${processed.stored}',
                ),
              if (processed != null && processed.context.isNotEmpty)
                _MetricChip(
                  icon: Icons.manage_search,
                  label: 'Process context ${processed.context.length}',
                ),
              if (graph != null)
                _MetricChip(
                  icon: Icons.account_tree_outlined,
                  label: 'Graph ${graph.nodes.length}/${graph.edges.length}',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onRunSleepMaintenance,
                icon: isMaintaining
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bedtime_outlined),
                label: Text(isMaintaining ? 'Maintaining' : 'Run sleep'),
              ),
              OutlinedButton.icon(
                onPressed: onRefreshGraph,
                icon: isLoadingGraph
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(isLoadingGraph ? 'Refreshing' : 'Refresh graph'),
              ),
            ],
          ),
          if (path != null) ...[
            const SizedBox(height: 10),
            SelectableText(path),
          ],
          const SizedBox(height: 12),
          MemoryActivityView(result: processed),
          if (processed == null &&
              recalled != null &&
              recalled.context.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(recalled.context),
          ],
          const SizedBox(height: 12),
          MemoryGraphView(
            projection: graph,
            selectedNodeId: selectedGraphNodeId,
            onNodeSelected: onGraphNodeSelected,
            isLoading: isLoadingGraph,
          ),
        ],
      ),
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({
    required this.isWide,
    required this.withoutMemory,
    required this.withMemory,
  });

  final bool isWide;
  final ChatCompletionResult? withoutMemory;
  final ChatCompletionResult? withMemory;

  @override
  Widget build(BuildContext context) {
    final withoutMemoryPanel = _ResultPanel(
      title: 'No memory',
      icon: Icons.remove_circle_outline,
      result: withoutMemory,
    );
    final withMemoryPanel = _ResultPanel(
      title: 'With memory',
      icon: Icons.add_circle_outline,
      result: withMemory,
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: withoutMemoryPanel),
          const SizedBox(width: 12),
          Expanded(child: withMemoryPanel),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        withoutMemoryPanel,
        const SizedBox(height: 12),
        withMemoryPanel,
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.title,
    required this.icon,
    required this.result,
  });

  final String title;
  final IconData icon;
  final ChatCompletionResult? result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final completed = result;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 12),
            if (completed == null)
              const SizedBox(height: 180, child: Center(child: Text('Waiting')))
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    icon: Icons.timer_outlined,
                    label: '${completed.latency.inMilliseconds} ms',
                  ),
                  if (completed.totalTokens != null)
                    _MetricChip(
                      icon: Icons.functions,
                      label: '${completed.totalTokens} tokens',
                    ),
                  if (completed.finishReason != null)
                    _MetricChip(
                      icon: Icons.flag_outlined,
                      label: completed.finishReason!,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 180),
                child: SelectableText(completed.content),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _SdkContractFooter extends StatelessWidget {
  const _SdkContractFooter({required this.config});

  final GraphProjectionConfig config;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetricChip(
          icon: Icons.account_tree_outlined,
          label: 'Graph limit ${config.limit}',
        ),
        _MetricChip(
          icon: Icons.travel_explore,
          label: 'Graph depth ${config.depth}',
        ),
        const _MetricChip(
          icon: Icons.psychology_alt_outlined,
          label: 'API processTurn',
        ),
      ],
    );
  }
}
