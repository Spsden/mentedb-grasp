/// Lightweight enrichment state for app schedulers.
final class EnrichmentState {
  const EnrichmentState({
    required this.pending,
    required this.lastCompletedTurn,
    required this.candidateCount,
  });

  /// True when the Rust engine has marked enrichment as pending.
  final bool pending;

  /// Last turn ID completed by enrichment.
  final int lastCompletedTurn;

  /// Candidate memories available for the next enrichment run.
  final int candidateCount;
}
