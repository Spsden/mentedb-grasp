# Flutter Integration Plan

MenteDB should be embedded in the Flutter app as a native Rust engine. Do not
use the server path for the primary mobile or desktop app runtime unless you
need a separate developer or sync process.

## Bridge Choice

Use Flutter Rust Bridge as the default native bridge for Android, iOS, macOS,
Windows, and Linux. Keep the checked-in Dart surface stable by implementing the
`MenteDbNativeBridge` contract in `sdks/flutter/mentedb_flutter`.

A custom Dart FFI SDK can also implement the same contract later. The app code
should depend on the facade, not on generated bridge details.

## Runtime Shape

```text
Flutter UI
  -> mentedb_flutter facade
  -> generated FRB bindings or Dart FFI adapter
  -> MenteDb Rust handle
  -> storage, indexes, graph, context, cognitive subsystems
```

The database path should live under the app support directory on desktop and
the platform application documents or support directory on Android and iOS.

## Background Work

Desktop can run maintenance from a timer, tray process, or app lifecycle hook.
Android should call the same bridge from WorkManager. iOS should call it from a
BGProcessingTask or BGAppRefreshTask, with smaller budgets and expiration
handling.

Use `MenteDb::try_run_sleep_maintenance` for local work. It holds a file lease
and returns `None` when another process already owns the job.

Use `try_run_enrichment_with_lease` for LLM enrichment when the `enrichment`
feature is enabled. This uses the same lease, so local maintenance and network
enrichment do not overlap.

Recommended mobile maintenance budget:

```dart
const SleepMaintenanceConfig(
  maxMemories: 250,
  runConsolidation: false,
  applyArchivalDeletes: false,
);
```

Recommended desktop maintenance budget:

```dart
const SleepMaintenanceConfig(
  maxMemories: 2000,
  runConsolidation: true,
  applyArchivalDeletes: false,
);
```

## Graph UI

Use `MenteDb::graph_projection` for an Obsidian-like 2D or 3D graph. The Rust
API returns a bounded DTO with nodes, edges, salience, confidence, tags, and
preview text. The Flutter layer owns layout, camera, selection, filtering, and
progressive rendering.

Start with:

```dart
final graph = await menteDb.graphProjection(
  config: const GraphProjectionConfig(limit: 500, depth: 2),
);
```

Large graphs should request a centered projection when the user selects a node:

```dart
final focused = await menteDb.graphProjection(
  config: GraphProjectionConfig(center: selectedId, depth: 3, limit: 750),
);
```

## Long-Term Memory Boundary

This integration does not implement the later long-term storage plan. Raw
conversation retention, packed transcript pages, archive tier movement, and
multi-year storage compaction remain separate future work.
