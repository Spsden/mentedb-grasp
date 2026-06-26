import 'package:flutter/material.dart';
import 'package:mentedb_flutter/mentedb_flutter.dart';

import 'src/memory_prompt.dart';
import 'src/openai_compatible_client.dart';

void main() {
  runApp(const MemoryDemoApp());
}

class MemoryDemoApp extends StatelessWidget {
  const MemoryDemoApp({super.key, OpenAiCompatibleChatClient? client})
      : _client = client;

  final OpenAiCompatibleChatClient? _client;

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
      home: MemoryDemoScreen(client: _client ?? OpenAiCompatibleChatClient()),
    );
  }
}

class MemoryDemoScreen extends StatefulWidget {
  const MemoryDemoScreen({super.key, required this.client});

  final OpenAiCompatibleChatClient client;

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
  final _promptController = TextEditingController(text: sampleUserPrompt);
  final _memoryController = TextEditingController(text: sampleMemoryBank);

  double _temperature = 0.2;
  bool _hideApiKey = true;
  bool _isRunning = false;
  String? _error;
  ChatCompletionResult? _withoutMemory;
  ChatCompletionResult? _withMemory;

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
    widget.client.close();
    super.dispose();
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
    if (memoryBank.isEmpty) {
      setState(() {
        _error = 'Add memory text before running the comparison.';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _error = null;
      _withoutMemory = null;
      _withMemory = null;
    });

    try {
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
        memoryBank: null,
      );
      final withMemoryMessages = buildChatMessages(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        memoryBank: memoryBank,
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

      if (!mounted) {
        return;
      }
      setState(() {
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
      _systemController.text = defaultSystemPrompt;
      _promptController.text = sampleUserPrompt;
      _memoryController.text = sampleMemoryBank;
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
      _withoutMemory = null;
      _withMemory = null;
      _error = null;
    });
  }

  void _clearOutputs() {
    setState(() {
      _withoutMemory = null;
      _withMemory = null;
      _error = null;
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
                  _PromptSection(
                    systemController: _systemController,
                    promptController: _promptController,
                    memoryController: _memoryController,
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

class _PromptSection extends StatelessWidget {
  const _PromptSection({
    required this.systemController,
    required this.promptController,
    required this.memoryController,
  });

  final TextEditingController systemController;
  final TextEditingController promptController;
  final TextEditingController memoryController;

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
              child: TextField(
                controller: memoryController,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Memory text',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        );
      },
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
      ],
    );
  }
}
