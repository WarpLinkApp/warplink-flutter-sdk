package app.warplink.flutter

import app.warplink.WarpLinkError

/**
 * The values `configure` passes to the native SDK.
 *
 * The automatic deep link path and the automatic deferred check are never part
 * of a request: the native SDK is always configured with both off.
 */
data class ConfigureRequest(
    val apiKey: String,
    val apiEndpoint: String,
    val debugLogging: Boolean,
    val linkDomains: List<String>
)

/** Parses the arguments of the `configure` method (contract section 2.1). */
object ConfigureArguments {
    const val DEFAULT_ENDPOINT = "https://api.warplink.app/v1"
    private val KEY_FORMAT = Regex("^wl_(live|test)_[a-zA-Z0-9]{32}$")

    /** Returns the request, or the error to reply with when the key is malformed. */
    fun parse(arguments: Map<*, *>?): Result<ConfigureRequest> {
        val apiKey = arguments?.get("apiKey") as? String ?: ""
        if (!KEY_FORMAT.matches(apiKey)) {
            return Result.failure(WarpLinkError.InvalidApiKeyFormat)
        }
        val endpoint = (arguments?.get("apiEndpoint") as? String)?.takeIf { it.isNotBlank() }
        return Result.success(
            ConfigureRequest(
                apiKey = apiKey,
                apiEndpoint = endpoint ?: DEFAULT_ENDPOINT,
                debugLogging = arguments?.get("debugLogging") == true,
                linkDomains = (arguments?.get("linkDomains") as? List<*>)
                    ?.filterIsInstance<String>()
                    .orEmpty()
            )
        )
    }
}
