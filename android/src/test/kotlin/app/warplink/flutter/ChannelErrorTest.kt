package app.warplink.flutter

import app.warplink.WarpLinkError
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ChannelErrorTest {
    @Test
    fun mapsEveryNativeErrorToItsCode() {
        val cases =
            listOf(
                WarpLinkError.NotConfigured to "E_NOT_CONFIGURED",
                WarpLinkError.InvalidApiKeyFormat to "E_INVALID_API_KEY_FORMAT",
                WarpLinkError.InvalidApiKey to "E_INVALID_API_KEY",
                WarpLinkError.NetworkError(IOException("offline")) to "E_NETWORK_ERROR",
                WarpLinkError.ServerError(500, "boom") to "E_SERVER_ERROR",
                WarpLinkError.InvalidUrl to "E_INVALID_URL",
                WarpLinkError.LinkNotFound to "E_LINK_NOT_FOUND",
                WarpLinkError.PasswordRequired to "E_PASSWORD_REQUIRED",
                WarpLinkError.DecodingError(IllegalStateException("bad")) to "E_DECODING_ERROR"
            )
        cases.forEach { (error, code) -> assertEquals(code, error.toChannelError().code) }
    }

    @Test
    fun passesTheNativeMessageThroughUnchanged() {
        assertEquals(
            WarpLinkError.LinkNotFound.message,
            WarpLinkError.LinkNotFound.toChannelError().message
        )
        val network = WarpLinkError.NetworkError(IOException("offline"))
        assertEquals(network.message, network.toChannelError().message)
    }

    @Test
    fun serverErrorCarriesTheStatusCodeInDetails() {
        val mapped = WarpLinkError.ServerError(503, "unavailable").toChannelError()
        assertEquals(mapOf("statusCode" to 503), mapped.details)
        assertEquals(503, mapped.statusCode)
    }

    @Test
    fun otherCodesHaveNullDetails() {
        assertNull(WarpLinkError.InvalidApiKey.toChannelError().details)
        assertNull(WarpLinkError.NotConfigured.toChannelError().statusCode)
    }

    @Test
    fun aForeignFailureMapsToServerErrorWithoutDetails() {
        val mapped = IllegalStateException("unexpected").toChannelError()
        assertEquals("E_SERVER_ERROR", mapped.code)
        assertEquals("unexpected", mapped.message)
        assertNull(mapped.details)
    }
}
