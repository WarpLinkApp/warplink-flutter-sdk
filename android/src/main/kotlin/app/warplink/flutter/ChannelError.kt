package app.warplink.flutter

import app.warplink.WarpLinkError

/** A channel-level error: the `code`, `message`, and `details` of a `result.error` call. */
data class ChannelError(
    val code: String,
    val message: String?,
    val details: Map<String, Any?>? = null
) {
    /** The status code carried in [details], present only for `E_SERVER_ERROR`. */
    val statusCode: Int?
        get() = details?.get(STATUS_CODE_KEY) as? Int

    companion object {
        const val NOT_CONFIGURED = "E_NOT_CONFIGURED"
        const val INVALID_API_KEY_FORMAT = "E_INVALID_API_KEY_FORMAT"
        const val INVALID_API_KEY = "E_INVALID_API_KEY"
        const val NETWORK_ERROR = "E_NETWORK_ERROR"
        const val SERVER_ERROR = "E_SERVER_ERROR"
        const val INVALID_URL = "E_INVALID_URL"
        const val LINK_NOT_FOUND = "E_LINK_NOT_FOUND"
        const val PASSWORD_REQUIRED = "E_PASSWORD_REQUIRED"
        const val DECODING_ERROR = "E_DECODING_ERROR"
        const val STATUS_CODE_KEY = "statusCode"
    }
}

/**
 * Maps a native failure to its channel error.
 *
 * The message is the native text, unchanged. A failure that is not a
 * [WarpLinkError] maps to `E_SERVER_ERROR`.
 */
fun Throwable.toChannelError(): ChannelError =
    when (this) {
        is WarpLinkError.NotConfigured -> ChannelError(ChannelError.NOT_CONFIGURED, message)
        is WarpLinkError.InvalidApiKeyFormat ->
            ChannelError(ChannelError.INVALID_API_KEY_FORMAT, message)
        is WarpLinkError.InvalidApiKey -> ChannelError(ChannelError.INVALID_API_KEY, message)
        is WarpLinkError.NetworkError -> ChannelError(ChannelError.NETWORK_ERROR, message)
        is WarpLinkError.ServerError ->
            ChannelError(
                ChannelError.SERVER_ERROR,
                message,
                mapOf(ChannelError.STATUS_CODE_KEY to statusCode)
            )
        is WarpLinkError.InvalidUrl -> ChannelError(ChannelError.INVALID_URL, message)
        is WarpLinkError.LinkNotFound -> ChannelError(ChannelError.LINK_NOT_FOUND, message)
        is WarpLinkError.PasswordRequired -> ChannelError(ChannelError.PASSWORD_REQUIRED, message)
        is WarpLinkError.DecodingError -> ChannelError(ChannelError.DECODING_ERROR, message)
        else -> ChannelError(ChannelError.SERVER_ERROR, message ?: toString())
    }
