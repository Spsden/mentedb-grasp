# MenteDB Flutter

This package embeds MenteDB in native Flutter apps through Flutter Rust Bridge.
It does not target Flutter web.

The native bridge lives in `rust/` and is bundled with Cargokit for Android,
iOS, macOS, Linux, and Windows. The docs-style Dart entrypoint is `MenteDB`,
which mirrors the official TypeScript quick start around `processTurn`:

```dart
final db = await MenteDB.open('./my-agent-memory');
final result = await db.processTurn(
  'I prefer Flutter and Supabase for Synapse.',
  assistantResponse: 'Noted, I will keep that stack in mind.',
  turnId: 0,
  projectContext: 'synapse',
);

print(result.contextText);
print(result.stored);
await db.close();
```

For lower-level app integration, `RustMenteDbMemoryStore` opens a local
MenteDB directory and exposes:

1. Unified `processTurn` with context, stored IDs, activity signals, and deltas.
2. Text memory bank ingest as real `MemoryNode` records.
3. Hybrid recall for advanced custom prompt assembly.
4. Recent chat turn storage for compatibility with older flows.
5. Leased sleep maintenance for background jobs or manual user action.
6. Graph projection for Flutter memory graph renderers.
7. Explicit close and flush behavior through the Rust facade.

The bridge uses MenteDB's deterministic hash embedder for local demo recall so
the example can run without an embedding API key. Production apps should swap
that Rust provider for the app's selected local or remote embedding provider.

Regenerate bindings after changing Rust bridge types:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

The runnable example under `example/` compares an OpenAI-compatible chat
completion with no memory against one that receives context from
`processTurn`. The example also includes a Memory Activity sidebar, guided
personas and scenarios, a manual sleep maintenance button, and an
Obsidian-style 3D graph panel for inspecting the memory graph.
