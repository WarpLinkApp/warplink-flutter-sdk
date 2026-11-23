import 'package:warplink_flutter/src/deferred_coordinator.dart';
import 'package:warplink_flutter/src/tether/tether_read_result.dart';

DeferredCoordinator? _live;

/// Points Tether routing at the deferred check of the live runtime. Each new
/// runtime calls this, so a reset for tests rebinds it.
void bindTetherRoute(DeferredCoordinator deferred) => _live = deferred;

/// Gives `onLink` the exact link of a matched Tether read when it replaces a
/// different link `onLink` already received. `WarpLink.readTether` and the paste
/// button call this. Not exported from the package.
void routeTetherResult(TetherReadResult result) {
  if (result is TetherMatched) {
    _live?.routeTetherMatch(result.link);
  }
}
