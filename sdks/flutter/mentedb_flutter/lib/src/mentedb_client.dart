import 'enrichment.dart';
import 'graph_projection.dart';
import 'sleep_maintenance.dart';

/// Native bridge implemented by generated FRB bindings or a Dart FFI adapter.
abstract interface class MenteDbNativeBridge {
  Future<GraphProjection> graphProjection(GraphProjectionConfig config);

  Future<SleepMaintenanceResult?> tryRunSleepMaintenance(
    SleepMaintenanceConfig config,
  );

  Future<EnrichmentState> enrichmentState();

  Future<void> requestEnrichment();
}

/// App-facing MenteDB facade for Flutter code.
final class MenteDbClient {
  const MenteDbClient(this._bridge);

  final MenteDbNativeBridge _bridge;

  Future<GraphProjection> graphProjection({
    GraphProjectionConfig config = const GraphProjectionConfig(),
  }) {
    return _bridge.graphProjection(config);
  }

  Future<SleepMaintenanceResult?> runBackgroundMaintenance({
    SleepMaintenanceConfig config = const SleepMaintenanceConfig(),
  }) {
    return _bridge.tryRunSleepMaintenance(config);
  }

  Future<EnrichmentState> enrichmentState() {
    return _bridge.enrichmentState();
  }

  Future<void> requestEnrichment() {
    return _bridge.requestEnrichment();
  }
}
