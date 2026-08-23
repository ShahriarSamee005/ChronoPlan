import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'carve_proposals_provider.dart';
import 'usage_suggestions_provider.dart';

/// How many reconciliation items are still waiting on the user today:
///
///   • one per empty hour with detected screen time ([usageSuggestionsProvider])
///   • one per LOGGED hour that still has carve proposals
///     ([carveProposalsProvider], counted by distinct logged entry — an hour
///     with three app proposals is still one thing to reconcile)
///
/// The dashboard badge and the suggestions-card header both read this, so the
/// two can never disagree. Reactive: it recomputes whenever either source does,
/// and both degrade to an empty list while loading or on error.
final pendingReconciliationCountProvider = Provider<int>((ref) {
  final suggestions =
      ref.watch(usageSuggestionsProvider).valueOrNull ?? const [];
  final proposals = ref.watch(carveProposalsProvider).valueOrNull ?? const [];

  final loggedHours = proposals.map((p) => p.loggedEntry.id).toSet();

  return suggestions.length + loggedHours.length;
});
