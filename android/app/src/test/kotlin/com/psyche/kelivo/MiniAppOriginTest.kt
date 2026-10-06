package com.psyche.kelivo

import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Message
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.webkit.HttpAuthHandler
import android.webkit.ClientCertRequest
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, shadows = [MiniAppOriginTest.RecordingCookies::class])
@Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
class MiniAppOriginTest {
    private val origin = "https://moru-miniapp-clock.invalid"
    private val prefix = "/0123456789abcdefghijklmno/app/clock/"
    private val legacyUrl = "file:///data/user/0/com.mishaqp.moru/files/mini_apps/clock/app/index.html"
    private val blank = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>"
    private lateinit var webView: WebView
    private lateinit var server: PrivateHttpServer
    private lateinit var origins: MiniAppOrigin
    private lateinit var delegate: RecordingClient
    private val requests = ConcurrentLinkedQueue<Pair<String, Map<String, List<String>>>>()
    private var respond: (PrivateExchange) -> Unit = { exchange ->
        exchange.responseHeaders.add("Content-Type", "application/javascript; charset=utf-8")
        exchange.responseHeaders.add("ETag", "\"test\"")
        exchange.responseHeaders.add("Cache-Control", "no-cache")
        reply(exchange, 200, "export const ready = true;")
    }

    @Before fun setUp() {
        RecordingCookies.reset()
        webView = WebView(RuntimeEnvironment.getApplication())
        delegate = RecordingClient()
        webView.webViewClient = delegate
        webView.settings.domStorageEnabled = true
        origins = MiniAppOrigin()
        server = PrivateHttpServer { exchange ->
            requests.add(exchange.requestURI.toASCIIString() to exchange.requestHeaders.toMap())
            try { respond(exchange) } finally { exchange.close() }
        }
        server.start()
    }

    @After fun tearDown() {
        origins.detach(1)
        server.stop()
        (server.executor as java.util.concurrent.ExecutorService).shutdownNow()
        webView.destroy()
    }

    private fun attach(legacy: String? = null, newOrigin: String = origin, backend: String = backend()) =
        origins.attach(1, webView, newOrigin, backend, legacy)

    private fun backend() = "http://127.0.0.1:${server.address.port}$prefix"
    private fun client() = webView.webViewClient
    private fun request(path: String, method: String = "GET", headers: Map<String, String> = emptyMap(), main: Boolean = false) =
        Request(Uri.parse(path), method, headers, main)
    private fun get(path: String, headers: Map<String, String> = emptyMap(), main: Boolean = false): WebResourceResponse =
        checkNotNull(client().shouldInterceptRequest(webView, request(path, headers = headers, main = main)))
    private fun body(response: WebResourceResponse) = response.data.use { String(it.readBytes(), Charsets.UTF_8) }

    @Test fun stableOriginHidesBackendCapabilityWhileServingResources() {
        attach()
        val response = get("$origin/scripts/module.mjs?revision=2")
        assertEquals(200, response.statusCode)
        assertEquals("application/javascript", response.mimeType)
        assertEquals("utf-8", response.encoding)
        assertEquals("\"test\"", response.responseHeaders.entries.first { it.key.equals("ETag", true) }.value)
        assertEquals("export const ready = true;", body(response))
        assertEquals("${prefix}scripts/module.mjs?revision=2", requests.single().first)
    }

    @Test fun privateCookiesUseOnlyTheStableAppHostAndNeverAnInvalidParentDomain() {
        respond = { exchange ->
            exchange.responseHeaders.add("Set-Cookie", "appOnly=yes; Path=/; Secure")
            exchange.responseHeaders.add("Set-Cookie", "shared=no; Domain=.invalid; Path=/; Secure")
            exchange.responseHeaders.add("Set-Cookie", "other=no; Domain=moru-miniapp-other.invalid; Path=/; Secure")
            reply(exchange, 200, "cookies")
        }
        attach()
        val response = get("$origin/cookies.js")
        body(response)
        val values = response.responseHeaders.entries.filter { it.key.equals("Set-Cookie", true) }.map { it.value }.joinToString()
        assertTrue(values.contains("appOnly=yes"))
        assertFalse(values.contains("shared=no"))
        assertFalse(values.contains("other=no"))
        assertEquals("appOnly=yes", CookieManager.getInstance().getCookie(origin))
        respond = { exchange -> reply(exchange, 200, "again") }
        body(get("$origin/again.js"))
        assertEquals(listOf("appOnly=yes"), requests.last().second.entries.first { it.key.equals("Cookie", true) }.value)
    }

    @Test fun sameOriginCanReconnectToANewBackendWithoutChangingWebViewStorageProfile() {
        attach()
        val previous = client()
        body(get("$origin/first.js"))
        val secondPrefix = "/another-capability-0123456789/app/clock/"
        attach(backend = "http://127.0.0.1:${server.address.port}$secondPrefix")
        assertEquals(404, previous.shouldInterceptRequest(webView, request("$origin/late.js"))!!.statusCode)
        body(get("$origin/next.js"))
        assertEquals("${secondPrefix}next.js", requests.last().first)
        assertTrue(webView.settings.domStorageEnabled)
    }

    @Test fun reservedNamespaceDeniesOtherAppsPortsSchemesAndTrailingDotsWithoutNetworkOrDelegate() {
        attach()
        listOf(
            "https://moru-miniapp-other.invalid/index.html",
            "https://moru-miniapp-check-other.invalid/index.html",
            "http://moru-miniapp-clock.invalid/index.html",
            "$origin:444/index.html",
            "https://moru-miniapp-clock.invalid./index.html",
            "https://user@moru-miniapp-clock.invalid/index.html",
            "https://%6doru-miniapp-clock.invalid/index.html",
            "https://sub.moru-miniapp-clock.invalid/index.html",
        ).forEach { url -> assertEquals(url, 404, get(url).statusCode) }
        assertTrue(requests.isEmpty())
        assertEquals(0, delegate.intercepted)
    }

    @Test fun rejectsFileContentAndEncodedTraversalBeforeOpeningTheBackend() {
        attach()
        listOf("file:///etc/passwd", "content://settings/system", "$origin/../secret", "$origin/%2e%2e/secret", "$origin/a%2fb", "$origin/a%5cb", "$origin/a%00b", "$origin/%252e%252e/secret", "$origin/a%252fb").forEach {
            assertEquals(it, 404, get(it).statusCode)
        }
        assertTrue(requests.isEmpty())
    }

    @Test fun exactMissingLegacyEntryAndTransferPathAreTrustedBlankDocuments() {
        val attached = attach(legacyUrl)
        assertEquals("", attached["cookies"])
        assertEquals(blank, body(get(legacyUrl)))
        assertEquals(blank, body(get("$origin/.moru-storage-transfer")))
        listOf("$legacyUrl?x=1", "$legacyUrl/child", "file:///data/user/0/com.mishaqp.moru/files/mini_apps/clock/app/other.html").forEach {
            assertEquals(404, get(it).statusCode)
        }
        assertTrue(requests.isEmpty())
    }

    @Test fun finishingMigrationRevokesLegacyEntryAndDisablesFileAndContentAccess() {
        attach(legacyUrl)
        assertFalse(webView.settings.allowFileAccess)
        origins.finishMigration(1)
        assertEquals(404, get(legacyUrl).statusCode)
        assertFalse(webView.settings.allowFileAccess)
        assertFalse(webView.settings.allowContentAccess)
        assertFalse(webView.settings.allowFileAccessFromFileURLs)
        assertFalse(webView.settings.allowUniversalAccessFromFileURLs)
        assertTrue(webView.settings.domStorageEnabled)
        assertEquals(blank, body(get("$origin/.moru-storage-transfer")))
    }

    @Test fun migrationHistoryIsClearedOnceOnTheFirstRealEntryPageBeforeDelegateCallback() {
        var observedClear = false
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) { observedClear = shadowOf(view).wasClearHistoryCalled() }
        }
        attach(legacyUrl)
        origins.finishMigration(1)
        client().onPageFinished(webView, "$origin/.moru-storage-transfer")
        assertFalse(observedClear)
        client().onPageFinished(webView, "$origin/index.html")
        assertTrue(observedClear)
    }

    @Test fun forwardsRangesAndPreservesPartialStatusHeadersAndBinaryStream() {
        respond = { exchange ->
            exchange.responseHeaders.add("Content-Type", "application/wasm")
            exchange.responseHeaders.add("Content-Range", "bytes 2-4/10")
            exchange.responseHeaders.add("Accept-Ranges", "bytes")
            exchange.sendResponseHeaders(206, 3)
            exchange.responseBody.write(byteArrayOf(2, 3, 4))
        }
        attach()
        val response = get("$origin/module.wasm", mapOf("Range" to "bytes=2-4"))
        assertEquals(206, response.statusCode)
        assertEquals("application/wasm", response.mimeType)
        assertEquals("bytes 2-4/10", response.responseHeaders.entries.first { it.key.equals("Content-Range", true) }.value)
        assertArrayEquals(byteArrayOf(2, 3, 4), response.data.use { it.readBytes() })
        assertEquals(listOf("bytes=2-4"), requests.single().second.entries.first { it.key.equals("Range", true) }.value)
    }

    @Test fun backendErrorsKeepTheirStatusAndBody() {
        respond = { exchange ->
            exchange.responseHeaders.add("Content-Type", "text/plain; charset=iso-8859-1")
            reply(exchange, 404, "missing")
        }
        attach()
        val response = get("$origin/missing.txt")
        assertEquals(404, response.statusCode)
        assertEquals("iso-8859-1", response.encoding)
        assertEquals("missing", body(response))
    }

    @Test fun privateCacheRevalidationReturnsAUsableBodyInsteadOfUnsupported304() {
        respond = { exchange ->
            if (exchange.requestHeaders.getFirst("If-None-Match") != null) {
                exchange.sendResponseHeaders(304, -1)
            } else reply(exchange, 200, "revalidated")
        }
        attach()
        val response = get("$origin/cached.js", mapOf("If-None-Match" to "\"test\""))
        assertEquals(200, response.statusCode)
        assertEquals("revalidated", body(response))
        assertEquals(2, requests.size)
    }

    @Test fun cannotReplayMethodsWithUnavailableRequestBodies() {
        attach()
        val response = client().shouldInterceptRequest(webView, request("$origin/__moru", method = "POST"))!!
        assertEquals(405, response.statusCode)
        assertTrue(requests.isEmpty())
    }

    @Test fun subresourceRedirectsStayInsideThePrivateCapability() {
        respond = { exchange ->
            if (exchange.requestURI.path.endsWith("old.js")) {
                exchange.responseHeaders.add("Location", "${prefix}new.js")
                exchange.sendResponseHeaders(307, -1)
            } else reply(exchange, 200, "redirected")
        }
        attach()
        assertEquals("redirected", body(get("$origin/old.js")))
        assertEquals(listOf("${prefix}old.js", "${prefix}new.js"), requests.map { it.first })
    }

    @Test fun mainFrameRedirectNavigatesToStableUrlWithoutShowingCapability() {
        respond = { exchange ->
            exchange.responseHeaders.add("Location", "${prefix}nested/index.html")
            exchange.sendResponseHeaders(301, -1)
        }
        attach()
        assertEquals(blank, body(get("$origin/", main = true)))
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("$origin/nested/index.html", shadowOf(webView).lastLoadedUrl)
        assertEquals(1, requests.size)
    }

    @Test fun privateRedirectCannotEscapeToAnotherAppOrExternalServer() {
        attach()
        listOf("/0123456789abcdefghijklmno/app/other/secret", "/other-token/app/clock/secret", "https://example.com/secret", "${prefix}%2e%2e/secret").forEach { location ->
            respond = { exchange ->
                exchange.responseHeaders.add("Location", location)
                exchange.sendResponseHeaders(302, -1)
            }
            assertEquals(location, 404, get("$origin/old.js").statusCode)
        }
        assertEquals(4, requests.size)
    }

    @Test fun detachedClientDeniesLateRequestsAndRevokesResponseStreams() {
        attach()
        val installed = client()
        val response = get("$origin/stream.js")
        origins.detach(1)
        assertEquals(404, installed.shouldInterceptRequest(webView, request("$origin/late.js"))!!.statusCode)
        try {
            response.data.read()
            fail("Detached response stream must be closed")
        } catch (_: java.io.IOException) { }
        assertEquals(1, requests.size)
    }

    @Test fun finishingMigrationClosesExistingStreamsButKeepsTheBackendAvailable() {
        attach(legacyUrl)
        val response = get("$origin/stream.js")
        origins.finishMigration(1)
        try {
            response.data.read()
            fail("A response opened during migration must be closed when migration finishes")
        } catch (_: java.io.IOException) { }
        assertEquals("export const ready = true;", body(get("$origin/entry.js")))
        assertEquals(2, requests.size)
    }

    @Test fun closingFlushesAppCookiesWithoutRemovingThem() {
        attach()
        val cookies = CookieManager.getInstance() as PersistentCookies
        cookies.setCookie(origin, "saved=yes; Path=/; Secure")
        assertNull(cookies.savedCookie)
        origins.detach(1)
        assertEquals("saved=yes", cookies.savedCookie)
        assertEquals("saved=yes", cookies.getCookie(origin))
    }

    @Test fun closingResponseStreamPreventsSubsequentReads() {
        attach()
        val stream = get("$origin/module.js").data
        stream.close()
        try {
            stream.read()
            fail("Closed response stream must not retain its private connection")
        } catch (_: java.io.IOException) { }
    }

    @Test fun preservesDelegateCallbacksAndNormalExternalNavigation() {
        attach()
        val client = client()
        client.onPageStarted(webView, "$origin/index.html", null)
        client.onPageFinished(webView, "$origin/index.html")
        client.onLoadResource(webView, "$origin/a.js")
        client.onPageCommitVisible(webView, "$origin/index.html")
        client.doUpdateVisitedHistory(webView, "$origin/index.html", true)
        client.onScaleChanged(webView, 1f, 2f)
        client.onReceivedLoginRequest(webView, "realm", "account", "args")
        client.onUnhandledKeyEvent(webView, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_A))
        assertEquals(listOf("started", "finished", "resource", "visible", "history", "scale", "login", "key"), delegate.events)
        assertTrue(client.shouldOverrideUrlLoading(webView, request("https://example.com/")))
        assertTrue(client.shouldOverrideUrlLoading(webView, "https://example.com/"))
        assertTrue(client.shouldOverrideKeyEvent(webView, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_B)))
        assertSame(delegate.externalResponse, client.shouldInterceptRequest(webView, request("https://example.com/a.js")))
        assertSame(delegate.externalResponse, client.shouldInterceptRequest(webView, "https://example.com/a.js"))
        assertEquals(2, delegate.intercepted)
        assertTrue(client.shouldOverrideUrlLoading(webView, request("file:///etc/passwd")))
    }

    @Test fun deniedNavigationsNeverReachTheSideEffectingDelegate() {
        val notified = mutableListOf<String>()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean { notified.add(request.url.toString()); return false }
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean { notified.add(url); return false }
        }
        attach()
        listOf(
            "file:///etc/passwd", "content://settings/system",
            "https://moru-miniapp-other.invalid/index.html", "$origin:444/index.html",
            "$origin/../secret", "$origin/%2e%2e/secret", "$origin/a%2fb", "$origin/%252e%252e/secret",
        ).forEach { url ->
            assertTrue(url, client().shouldOverrideUrlLoading(webView, request(url)))
            assertTrue(url, client().shouldOverrideUrlLoading(webView, url))
        }
        assertTrue("A denied URL must not trigger Dart's external launcher", notified.isEmpty())
        listOf("$origin/index.html", "https://example.com/").forEach { url ->
            assertFalse(client().shouldOverrideUrlLoading(webView, request(url)))
            assertFalse(client().shouldOverrideUrlLoading(webView, url))
        }
        assertEquals(listOf("$origin/index.html", "$origin/index.html", "https://example.com/", "https://example.com/"), notified)
    }

    @Test fun validatesBackendAndOriginBeforeReplacingTheExistingClient() {
        listOf(
            "http://example.com:1234$prefix",
            "http://localhost:1234$prefix",
            "http://127.0.0.1:1234/app/clock/",
            "http://127.0.0.1:1234/short/app/clock/",
            "http://127.0.0.1:1234$prefix?secret=yes",
            "http://127.0.0.1:1234$prefix#secret",
            "http://user@127.0.0.1:1234$prefix",
            "http://127.0.0.1:1234/0123456789abcdefghijklmno/app/%2e%2e/",
        ).forEach { url ->
            try { attach(backend = url); fail(url) } catch (_: IllegalArgumentException) { }
            assertSame(delegate, client())
        }
        listOf("https://example.com", "http://moru-miniapp-clock.invalid", "https://moru-miniapp-other.invalid", "$origin/", "$origin:444").forEach { url ->
            try { attach(newOrigin = url); fail(url) } catch (_: IllegalArgumentException) { }
            assertSame(delegate, client())
        }
    }

    @Test fun checkerOriginCanUseTheSamePrivateBackend() {
        val checker = "https://moru-miniapp-check-abc123.invalid"
        attach(newOrigin = checker)
        assertEquals("export const ready = true;", body(get("$checker/check.js")))
        assertEquals(404, get("$origin/check.js").statusCode)
    }

    @Test fun installationIdentityHostCanServeAnAppWithADifferentDisplayId() {
        val installedOrigin = "https://moru-miniapp-${"0".repeat(32)}.invalid"
        attach(newOrigin = installedOrigin)
        assertEquals("export const ready = true;", body(get("$installedOrigin/module.js")))
        assertEquals(404, get("$origin/module.js").statusCode)
    }

    @Test fun privilegedPrivateReaderServesOnlyTrustedBlankAndLeavesTargetRestricted() {
        attach(legacyUrl)
        val reader = origins.loadLegacy(1)
        assertEquals(legacyUrl, shadowOf(reader).lastLoadedUrl)
        assertTrue(reader.settings.javaScriptEnabled)
        assertTrue(reader.settings.domStorageEnabled)
        assertTrue(reader.settings.allowFileAccess)
        assertFalse(reader.settings.allowContentAccess)
        assertFalse(reader.settings.allowFileAccessFromFileURLs)
        assertTrue(reader.settings.allowUniversalAccessFromFileURLs)
        assertFalse(webView.settings.allowFileAccess)
        assertFalse(webView.settings.allowUniversalAccessFromFileURLs)
        assertFalse(webView.settings.allowFileAccessFromFileURLs)
        assertTrue(reader.settings.supportMultipleWindows())
        assertTrue(reader.settings.javaScriptCanOpenWindowsAutomatically)
        assertFalse(webView.settings.supportMultipleWindows())
        assertEquals(blank, body(reader.webViewClient.shouldInterceptRequest(reader, request(legacyUrl))!!))
        listOf("file:///etc/passwd", "content://settings/system", "$origin/.moru-storage-transfer", "https://example.com/").forEach { url ->
            assertEquals(404, reader.webViewClient.shouldInterceptRequest(reader, request(url))!!.statusCode)
            assertTrue(reader.webViewClient.shouldOverrideUrlLoading(reader, request(url)))
        }
        assertFalse(reader.webViewClient.shouldOverrideUrlLoading(reader, request(legacyUrl)))
        assertTrue(requests.isEmpty())
    }

    @Test fun migrationPopupUsesTheUntouchedTargetAndKeepsItsExistingClientAndInterfaces() {
        attach(legacyUrl)
        val targetClient = client()
        val targetBridge = Any()
        webView.addJavascriptInterface(targetBridge, "MoruBridge")
        val reader = origins.loadLegacy(1)
        assertTrue(reader.settings.allowUniversalAccessFromFileURLs)
        assertFalse(webView.settings.allowUniversalAccessFromFileURLs)
        assertFalse(reader.webChromeClient!!.onCreateWindow(webView, false, false, Message.obtain(Handler(Looper.getMainLooper())).apply { obj = reader.WebViewTransport() }))
        val transport = reader.WebViewTransport()
        var delivered = false
        val message = Message.obtain(Handler(Looper.getMainLooper()) { delivered = true; true }).apply { obj = transport }
        assertTrue(reader.webChromeClient!!.onCreateWindow(reader, false, false, message))
        shadowOf(Looper.getMainLooper()).idle()
        assertSame(webView, transport.webView)
        assertTrue(delivered)
        assertSame(targetClient, client())
        assertSame(targetBridge, shadowOf(webView).getJavascriptInterface("MoruBridge"))
        assertFalse(webView.settings.allowUniversalAccessFromFileURLs)
        assertFalse(reader.webChromeClient!!.onCreateWindow(reader, false, false, Message.obtain(Handler(Looper.getMainLooper())).apply { obj = reader.WebViewTransport() }))
    }

    @Test fun migrationPopupRejectsTargetsThatHaveAlreadyNavigated() {
        attach(legacyUrl)
        webView.loadUrl("$origin/index.html")
        val reader = origins.loadLegacy(1)
        assertFalse(reader.webChromeClient!!.onCreateWindow(reader, false, false, Message.obtain(Handler(Looper.getMainLooper())).apply { obj = reader.WebViewTransport() }))
    }

    @Test fun finishAndDetachRevokeReaderPrivilegeAndBlockLateReaderRequestsAndPopups() {
        listOf<() -> Unit>({ origins.finishMigration(1) }, { origins.detach(1) }).forEach { close ->
            attach(legacyUrl)
            val reader = origins.loadLegacy(1)
            // Exercise cleanup independently of the reader's initial grant.
            reader.settings.allowUniversalAccessFromFileURLs = true
            close()
            assertFalse(reader.settings.allowUniversalAccessFromFileURLs)
            assertTrue(shadowOf(reader).wasDestroyCalled())
            assertFalse(webView.settings.allowUniversalAccessFromFileURLs)
            assertEquals(404, reader.webViewClient.shouldInterceptRequest(reader, request(legacyUrl))!!.statusCode)
            assertTrue(reader.webViewClient.shouldOverrideUrlLoading(reader, request(legacyUrl)))
            val transport = reader.WebViewTransport()
            val message = Message.obtain(Handler(Looper.getMainLooper())).apply { obj = transport }
            assertFalse(reader.webChromeClient!!.onCreateWindow(reader, false, false, message))
            assertNull(transport.webView)
        }
        assertTrue(requests.isEmpty())
    }

    @Test fun legacyMessagesAndPageEventsUseTheChannelAndStopAfterFinishingMigration() {
        val messenger = RecordingMessenger()
        val channel = MethodChannel(messenger, "app.miniAppOrigin")
        MiniAppOrigin::class.java.getDeclaredField("channel").apply { isAccessible = true }.set(origins, channel)
        attach(legacyUrl)
        val reader = origins.loadLegacy(1)
        reader.webViewClient.onPageFinished(reader, legacyUrl)
        val bridge = shadowOf(reader).getJavascriptInterface("MoruStorageMigration")!!
        bridge.javaClass.getDeclaredMethod("postMessage", String::class.java).apply { isAccessible = true }.invoke(bridge, "ready")
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("legacyPageFinished", "legacyMessage"), messenger.calls.map { it.first })
        assertEquals(mapOf("id" to 1L, "url" to legacyUrl), messenger.calls[0].second)
        assertEquals(mapOf("id" to 1L, "message" to "ready"), messenger.calls[1].second)
        origins.finishMigration(1)
        assertTrue(shadowOf(reader).wasDestroyCalled())
        assertNull(shadowOf(reader).getJavascriptInterface("MoruStorageMigration"))
        bridge.javaClass.getDeclaredMethod("postMessage", String::class.java).apply { isAccessible = true }.invoke(bridge, "late")
        reader.webViewClient.onPageFinished(reader, legacyUrl)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(2, messenger.calls.size)
        assertEquals(404, reader.webViewClient.shouldInterceptRequest(reader, request(legacyUrl))!!.statusCode)
    }

    @Test fun evaluateLegacyCompletesOnlyWhenItsJavascriptCallbackRuns() {
        attach(legacyUrl)
        val reader = origins.loadLegacy(1)
        var completed = false
        origins.evaluateLegacy(1, "window.rawSnapshot = true;") { completed = true }
        assertEquals("window.rawSnapshot = true;", shadowOf(reader).lastEvaluatedJavascript)
        assertFalse(completed)
        shadowOf(reader).lastEvaluatedJavascriptCallback.onReceiveValue("null")
        assertTrue(completed)
        origins.detach(1)
        assertTrue(shadowOf(reader).wasDestroyCalled())
    }

    @Test fun closingMigrationFailsPendingJavascriptEvaluationExactlyOnce() {
        attach(legacyUrl)
        val reader = origins.loadLegacy(1)
        val completions = mutableListOf<Boolean>()
        origins.evaluateLegacy(1, "window.ready = true;") { completions.add(it) }
        val callback = shadowOf(reader).lastEvaluatedJavascriptCallback
        origins.detach(1)
        assertEquals(listOf(false), completions)
        callback.onReceiveValue("null")
        assertEquals(listOf(false), completions)
    }

    @Test fun legacyReaderCannotBeOpenedWithoutAnActiveMigration() {
        attach()
        try { origins.loadLegacy(1); fail("No migration reader for a fresh app") } catch (_: IllegalArgumentException) { }
        attach(legacyUrl)
        origins.finishMigration(1)
        try { origins.loadLegacy(1); fail("No migration reader after migration finishes") } catch (_: IllegalArgumentException) { }
    }

    @Test fun forwardsEveryErrorAuthenticationAndDecisionCallbackWithItsOriginalArguments() {
        val calls = mutableListOf<Pair<String, List<Any?>>>()
        val original = object : WebViewClient() {
            override fun onReceivedError(view: WebView, code: Int, description: String?, failingUrl: String?) { calls.add("oldError" to listOf(view, code, description, failingUrl)) }
            override fun onReceivedError(view: WebView, request: WebResourceRequest?, error: WebResourceError?) { calls.add("error" to listOf(view, request, error)) }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest?, error: WebResourceResponse?) { calls.add("http" to listOf(view, request, error)) }
            override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler?, host: String?, realm: String?) { calls.add("auth" to listOf(view, handler, host, realm)) }
            override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest?) { calls.add("cert" to listOf(view, request)) }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler?, error: SslError?) { calls.add("ssl" to listOf(view, handler, error)) }
            override fun onFormResubmission(view: WebView, dontResend: Message?, resend: Message?) { calls.add("form" to listOf(view, dontResend, resend)) }
            override fun onTooManyRedirects(view: WebView, cancel: Message?, continueMessage: Message?) { calls.add("redirects" to listOf(view, cancel, continueMessage)) }
            override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest?, threatType: Int, response: SafeBrowsingResponse?) { calls.add("safe" to listOf(view, request, threatType, response)) }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail?): Boolean { calls.add("gone" to listOf(view, detail)); return true }
        }
        webView.webViewClient = original
        attach()
        val installed = client()
        val request = request("$origin/a.js")
        val response = WebResourceResponse("text/plain", "utf-8", "error".byteInputStream())
        val cancel = Message.obtain()
        val resend = Message.obtain()
        installed.onReceivedError(webView, 7, "description", "$origin/a.js")
        installed.onReceivedError(webView, request, null)
        installed.onReceivedHttpError(webView, request, response)
        installed.onReceivedHttpAuthRequest(webView, null, "host", "realm")
        installed.onReceivedClientCertRequest(webView, null)
        installed.onReceivedSslError(webView, null, null)
        installed.onFormResubmission(webView, cancel, resend)
        installed.onTooManyRedirects(webView, cancel, resend)
        installed.onSafeBrowsingHit(webView, request, 5, null)
        assertTrue(installed.onRenderProcessGone(webView, null))
        assertEquals(listOf("oldError", "error", "http", "auth", "cert", "ssl", "form", "redirects", "safe", "gone"), calls.map { it.first })
        assertEquals(listOf(webView, request, response), calls[2].second)
        assertEquals(listOf(webView, cancel, resend), calls[6].second)
    }

    @Test fun detachingRestoresDelegateOnlyAfterLeavingTheReservedOrigin() {
        attach()
        webView.loadUrl("$origin/index.html")
        val installed = client()
        origins.detach(1)
        assertSame(installed, client())
        assertEquals(404, get("$origin/late.js").statusCode)
        attach()
        webView.loadUrl("https://example.com/")
        origins.detach(1)
        assertSame(delegate, client())
    }

    private fun reply(exchange: PrivateExchange, status: Int, body: String) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        exchange.sendResponseHeaders(status, bytes.size.toLong())
        exchange.responseBody.write(bytes)
    }

    private class Request(private val address: Uri, private val verb: String, private val headers: Map<String, String>, private val main: Boolean) : WebResourceRequest {
        override fun getUrl() = address
        override fun isForMainFrame() = main
        override fun isRedirect() = false
        override fun hasGesture() = false
        override fun getMethod() = verb
        override fun getRequestHeaders() = headers
    }

    private class RecordingClient : WebViewClient() {
        val events = mutableListOf<String>()
        var intercepted = 0
        val externalResponse = WebResourceResponse("text/plain", "utf-8", "external".byteInputStream())
        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) { events.add("started") }
        override fun onPageFinished(view: WebView, url: String) { events.add("finished") }
        override fun onLoadResource(view: WebView, url: String) { events.add("resource") }
        override fun onPageCommitVisible(view: WebView, url: String) { events.add("visible") }
        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) { events.add("history") }
        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) { events.add("scale") }
        override fun onReceivedLoginRequest(view: WebView, realm: String, account: String?, args: String) { events.add("login") }
        override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) { events.add("key") }
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = true
        override fun shouldOverrideUrlLoading(view: WebView, url: String) = true
        override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent) = true
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse { intercepted++; return externalResponse }
        override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse { intercepted++; return externalResponse }
    }

    private class RecordingMessenger : BinaryMessenger {
        val calls = mutableListOf<Pair<String, Any?>>()
        override fun send(channel: String, message: ByteBuffer?) { send(channel, message, null) }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            val buffer = checkNotNull(message).duplicate().apply { flip() }
            val call = StandardMethodCodec.INSTANCE.decodeMethodCall(buffer)
            calls.add(call.method to call.arguments)
            callback?.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null).apply { flip() })
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) { }
    }

    @Implements(CookieManager::class)
    class RecordingCookies {
        companion object {
            private var instance: PersistentCookies? = null
            @JvmStatic @Implementation fun getInstance(): CookieManager = instance ?: PersistentCookies().also { instance = it }
            @JvmStatic fun reset() { instance = null }
        }
    }

    class PersistentCookies : android.webkit.RoboCookieManager() {
        var savedCookie: String? = null
        override fun flush() { savedCookie = getCookie("https://moru-miniapp-clock.invalid"); super.flush() }
    }

    /** Real loopback HTTP, without a test dependency on JDK-only HTTP classes. */
    private class PrivateHttpServer(private val handle: (PrivateExchange) -> Unit) {
        private val listener = ServerSocket().apply { bind(InetSocketAddress("127.0.0.1", 0)) }
        val address: InetSocketAddress get() = listener.localSocketAddress as InetSocketAddress
        val executor = Executors.newCachedThreadPool { runnable -> Thread(runnable).apply { isDaemon = true } }
        fun start() {
            executor.execute {
                while (!listener.isClosed) {
                    val socket = try { listener.accept() } catch (_: java.net.SocketException) { break }
                    executor.execute { socket.use { handle(PrivateExchange(it)) } }
                }
            }
        }
        fun stop() { listener.close() }
    }

    private class Headers : LinkedHashMap<String, List<String>>() {
        fun add(name: String, value: String) { this[name] = get(name).orEmpty() + value }
        fun getFirst(name: String) = entries.firstOrNull { it.key.equals(name, true) }?.value?.firstOrNull()
    }

    private class PrivateExchange(private val socket: Socket) {
        val requestURI: URI
        val requestHeaders = Headers()
        val responseHeaders = Headers()
        val responseBody: OutputStream get() = socket.getOutputStream()
        init {
            val reader = socket.getInputStream().bufferedReader(Charsets.US_ASCII)
            requestURI = URI(checkNotNull(reader.readLine()).split(' ')[1])
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                val colon = line.indexOf(':')
                requestHeaders.add(line.substring(0, colon), line.substring(colon + 1).trim())
            }
        }
        fun sendResponseHeaders(status: Int, length: Long) {
            val reason = when (status) { 200 -> "OK"; 206 -> "Partial Content"; 301 -> "Moved Permanently"; 302 -> "Found"; 304 -> "Not Modified"; 307 -> "Temporary Redirect"; 404 -> "Not Found"; else -> "Response" }
            val headers = StringBuilder("HTTP/1.1 $status $reason\r\nConnection: close\r\nContent-Length: ${length.coerceAtLeast(0)}\r\n")
            responseHeaders.forEach { (name, values) -> values.forEach { headers.append("$name: $it\r\n") } }
            responseBody.write(headers.append("\r\n").toString().toByteArray(Charsets.US_ASCII))
            responseBody.flush()
        }
        fun close() { socket.close() }
    }
}
