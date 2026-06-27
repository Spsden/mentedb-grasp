import 'package:flutter/material.dart';
import 'package:mentedb_flutter/mentedb_flutter.dart';

class MemoryActivityView extends StatelessWidget {
  const MemoryActivityView({
    super.key,
    required this.result,
  });

  final ProcessTurnResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: Text('Waiting for memory activity')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActivityChip(
              icon: Icons.manage_search,
              label: 'Context ${result.context.length}',
            ),
            _ActivityChip(
              icon: Icons.save_outlined,
              label: 'Stored ${result.stored}',
            ),
            _ActivityChip(
              icon: Icons.account_tree_outlined,
              label: 'Edges ${result.edgesCreated}',
            ),
            _ActivityChip(
              icon: Icons.flag_outlined,
              label: 'Actions ${result.detectedActions.length}',
            ),
            if (result.painWarnings.isNotEmpty)
              _ActivityChip(
                icon: Icons.warning_amber_outlined,
                label: 'Pain ${result.painWarnings.length}',
              ),
            if (result.enrichmentPending)
              const _ActivityChip(
                icon: Icons.auto_awesome_motion,
                label: 'Enrichment pending',
              ),
            if (result.cacheHit)
              const _ActivityChip(
                icon: Icons.bolt_outlined,
                label: 'Cache hit',
              ),
          ],
        ),
        const SizedBox(height: 12),
        _ActivitySection(
          title: 'Retrieved context',
          icon: Icons.manage_search,
          isEmpty: result.context.isEmpty,
          emptyText: 'No context returned for this turn',
          children: [
            for (final item in result.context.take(6)) _ContextTile(item: item),
          ],
        ),
        const SizedBox(height: 10),
        _ActivitySection(
          title: 'Stored memories',
          icon: Icons.save_outlined,
          isEmpty: result.storedMemories.isEmpty,
          emptyText: 'No memories stored',
          children: [
            for (final memory in result.storedMemories)
              _StoredMemoryTile(memory: memory),
          ],
        ),
        const SizedBox(height: 10),
        _ActivitySection(
          title: 'Cognitive signals',
          icon: Icons.psychology_alt_outlined,
          isEmpty: _signalCount(result) == 0,
          emptyText: 'No extra cognitive signals',
          children: [
            if (result.detectedActions.isNotEmpty)
              _SignalList(
                title: 'Actions',
                values: result.detectedActions
                    .map((action) => '${action.actionType}: ${action.detail}')
                    .toList(growable: false),
              ),
            if (result.proactiveRecalls.isNotEmpty)
              _SignalList(
                title: 'Proactive recall',
                values: result.proactiveRecalls
                    .map(
                      (recall) =>
                          '${recall.actionType}: ${_compact(recall.content, 140)}',
                    )
                    .toList(growable: false),
              ),
            if (result.painWarnings.isNotEmpty)
              _SignalList(
                title: 'Pain warnings',
                values: result.painWarnings
                    .map(
                      (warning) =>
                          '${warning.intensity.toStringAsFixed(2)}: ${warning.description}',
                    )
                    .toList(growable: false),
              ),
            if (result.predictedTopics.isNotEmpty)
              _SignalList(
                title: 'Predicted topics',
                values: result.predictedTopics,
              ),
            _SignalList(
              title: 'Counters',
              values: [
                'Sentiment ${result.sentiment.toStringAsFixed(2)}',
                'Facts ${result.factsExtracted}',
                'Inference ${result.inferenceActions}',
                'Phantoms ${result.phantomCount}',
                'Contradictions ${result.contradictionCount}',
                'Delta +${result.deltaAdded.length} -${result.deltaRemoved.length}',
              ],
            ),
          ],
        ),
      ],
    );
  }

  int _signalCount(ProcessTurnResult result) {
    return result.detectedActions.length +
        result.proactiveRecalls.length +
        result.painWarnings.length +
        result.predictedTopics.length +
        result.factsExtracted +
        result.inferenceActions +
        result.phantomCount +
        result.contradictionCount +
        result.deltaAdded.length +
        result.deltaRemoved.length;
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.title,
    required this.icon,
    required this.isEmpty,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final IconData icon;
  final bool isEmpty;
  final String emptyText;
  final List<Widget> children;

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
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isEmpty)
              Text(
                emptyText,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _ContextTile extends StatelessWidget {
  const _ContextTile({required this.item});

  final ProcessTurnContextItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ActivityChip(
                icon: Icons.score_outlined,
                label: item.score.toStringAsFixed(3),
              ),
              _ActivityChip(
                icon: Icons.category_outlined,
                label: item.memoryType.name,
              ),
              _ActivityChip(
                icon: Icons.public,
                label: item.scope,
              ),
              if (item.isNew)
                const _ActivityChip(
                  icon: Icons.fiber_new_outlined,
                  label: 'New',
                ),
              if (item.fromCache)
                const _ActivityChip(
                  icon: Icons.bolt_outlined,
                  label: 'Cached',
                ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(_compact(item.content, 360)),
        ],
      ),
    );
  }
}

class _StoredMemoryTile extends StatelessWidget {
  const _StoredMemoryTile({required this.memory});

  final ProcessTurnStoredMemory memory;

  @override
  Widget build(BuildContext context) {
    final tags = memory.tags.take(4).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ActivityChip(
                icon: Icons.category_outlined,
                label: memory.memoryType.name,
              ),
              _ActivityChip(
                icon: Icons.bubble_chart_outlined,
                label: 'Salience ${memory.salience.toStringAsFixed(2)}',
              ),
              for (final tag in tags)
                _ActivityChip(
                  icon: Icons.label_outline,
                  label: _compact(tag, 28),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(_compact(memory.content, 360)),
        ],
      ),
    );
  }
}

class _SignalList extends StatelessWidget {
  const _SignalList({
    required this.title,
    required this.values,
  });

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final value in values.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: SelectableText(value),
            ),
        ],
      ),
    );
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({
    required this.icon,
    required this.label,
  });

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

String _compact(String value, int maxChars) {
  final cleaned = value.replaceAll('\n', ' ').trim();
  if (cleaned.length <= maxChars) {
    return cleaned;
  }
  return '${cleaned.substring(0, maxChars).trimRight()}...';
}
