package app.warplink.flutter

/**
 * The drop order of a full ledger (contract section 11.10).
 *
 * The first rule that applies picks the entry to drop. An undelivered launch
 * entry is never a victim.
 */
class LedgerBound(private val isWarpLinkUrl: (String) -> Boolean) {
    /** The entry to drop from [entries], oldest first, or `null` when none may go. */
    fun victim(entries: List<ArrivalEntry>): ArrivalEntry? =
        entries.firstOrNull { it.isDelivered }
            ?: entries.firstOrNull { !it.isLaunch && !isWarpLinkUrl(it.url) }
            ?: entries.firstOrNull { !it.isLaunch }
}
