package com.psyche.kelivo

import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.KeyEvent
import android.webkit.ClientCertRequest
import android.webkit.CookieManager
import android.webkit.HttpAuthHandler
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import androidx.webkit.WebViewCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.lang.ref.WeakReference
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URI
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/** Stable browser origins; the random loopback capability stays behind request interception. */
@Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
internal class MiniAppOrigin {
    private data class Registration(val view: WeakReference<WebView>, val client: WeakReference<OriginClient>)
    private val registrations = mutableMapOf<Long, Registration>()
    private var channel: MethodChannel? = null

    fun configure(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.miniAppOrigin")
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                if (call.method !in setOf("attach", "loadLegacy", "evaluateLegacy", "finishMigration", "detach")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                val id = (args["id"] as? Number)?.toLong() ?: throw IllegalArgumentException()
                require(id >= 0)
                when (call.method) {
                    "attach" -> {
                        val view = WebViewFlutterAndroidExternalApi.getWebView(engine, id)
                        if (view == null) {
                            result.error("webview_unavailable", "The mini app WebView is unavailable.", null)
                        } else {
                            val origin = args["origin"] as? String ?: throw IllegalArgumentException()
                            val backend = args["backend"] as? String ?: throw IllegalArgumentException()
                            val legacy = args["legacyUrl"]?.let { it as? String ?: throw IllegalArgumentException() }
                            val transfer = args["transferPath"]?.let { it as? String ?: throw IllegalArgumentException() } ?: TRANSFER_PATH
                            result.success(attach(id, view, origin, backend, legacy, transfer))
                        }
                    }
                    "loadLegacy" -> { loadLegacy(id); result.success(null) }
                    "evaluateLegacy" -> {
                        val script = args["script"] as? String ?: throw IllegalArgumentException()
                        evaluateLegacy(id, script) { success ->
                            if (success) result.success(null) else result.error("migration_closed", "The mini app storage migration was closed.", null)
                        }
                    }
                    "finishMigration" -> { finishMigration(id); result.success(null) }
                    "detach" -> { detach(id); result.success(null) }
                }
            } catch (_: IllegalArgumentException) {
                result.error("invalid_arguments", "Invalid mini app origin arguments.", null)
            } catch (_: UnsupportedOperationException) {
                result.error("unsupported_webview", "This Android WebView cannot preserve its navigation client.", null)
            }
        }
    }

    fun attach(id: Long, view: WebView, origin: String, backend: String, legacyUrl: String? = null, transferPath: String = TRANSFER_PATH): Map<String, String> {
        val route = Route(origin, backend, legacyUrl, transferPath)
        val previous = WebViewCompat.getWebViewClient(view)
        val delegate = if (previous is OriginClient) {
            previous.deactivate()
            previous.delegate
        } else previous
        registrations.remove(id)?.client?.get()?.deactivate()
        registrations.entries.removeAll { (_, registration) ->
            if (registration.view.get() == null) { registration.client.get()?.deactivate(); true } else false
        }
        val cookies = legacyUrl?.let { CookieManager.getInstance().getCookie(it) }.orEmpty()
        val client = OriginClient(view, delegate, route) { method, args -> channel?.invokeMethod(method, args + ("id" to id)) }
        view.settings.apply {
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
        }
        view.webViewClient = client
        registrations[id] = Registration(WeakReference(view), WeakReference(client))
        return mapOf("cookies" to cookies)
    }

    fun loadLegacy(id: Long): WebView = (registrations[id]?.client?.get() ?: throw IllegalArgumentException()).loadLegacy()

    fun evaluateLegacy(id: Long, script: String, completed: (Boolean) -> Unit) {
        (registrations[id]?.client?.get() ?: throw IllegalArgumentException()).evaluateLegacy(script, completed)
    }

    fun finishMigration(id: Long) {
        registrations[id]?.client?.get()?.finishMigration()
        registrations[id]?.view?.get()?.settings?.apply { allowFileAccess = false; allowContentAccess = false }
        CookieManager.getInstance().flush()
    }

    fun detach(id: Long) {
        val registration = registrations.remove(id) ?: return
        registration.client.get()?.let { client ->
            client.deactivate()
            registration.view.get()?.let { view ->
                view.stopLoading()
                view.settings.apply { allowFileAccess = false; allowContentAccess = false }
                // Keep an inert interceptor while a reserved document is still displayed:
                // restoring the ordinary client there could turn late requests into DNS traffic.
                val address = view.url?.let(Uri::parse)
                if (WebViewCompat.getWebViewClient(view) === client && (address == null || (!reserved(address) && !localFile(address)))) {
                    view.webViewClient = client.delegate
                }
            }
        }
        CookieManager.getInstance().flush()
    }

    private class Route(origin: String, backend: String, val legacyUrl: String?, val transferPath: String) {
        val origin: URI = parse(origin) ?: throw IllegalArgumentException()
        val backend: URI = parse(backend) ?: throw IllegalArgumentException()
        val host: String = this.origin.host.orEmpty()
        init {
            require(this.backend.scheme == "http" && this.backend.host == "127.0.0.1" && this.backend.port in 1..65535)
            require(this.backend.rawAuthority == "127.0.0.1:${this.backend.port}" && this.backend.rawQuery == null && this.backend.rawFragment == null)
            require(safePath(this.backend.rawPath))
            val parts = this.backend.rawPath.split('/')
            require(parts.size == 5 && parts[0].isEmpty() && parts[2] == "app" && parts[4].isEmpty())
            require(Regex("[A-Za-z0-9_-]{16,128}").matches(parts[1]) && Regex("[a-z0-9][a-z0-9-]{0,39}").matches(parts[3]))
            require(this.origin.scheme == "https" && this.origin.rawAuthority == host && this.origin.rawPath.isEmpty() && this.origin.rawQuery == null && this.origin.rawFragment == null)
            require(host == "moru-miniapp-${parts[3]}.invalid" || Regex("moru-miniapp-[a-f0-9]{32}\\.invalid").matches(host) || Regex("moru-miniapp-check-[a-z0-9][a-z0-9-]{0,38}\\.invalid").matches(host))
            require(transferPath.startsWith('/') && !transferPath.startsWith("//") && safePath(transferPath) && parse(transferPath)?.rawPath == transferPath)
            legacyUrl?.let {
                val legacy = parse(it) ?: throw IllegalArgumentException()
                require(legacy.scheme == "file" && legacy.rawAuthority.isNullOrEmpty() && legacy.rawQuery == null && legacy.rawFragment == null && legacy.rawPath.startsWith('/') && safePath(legacy.rawPath))
            }
        }
        fun owns(uri: URI) = uri.scheme.equals("https", true) && uri.host.equals(host, true) && uri.port in setOf(-1, 443) && uri.rawUserInfo == null
        fun privateUrl(uri: URI): URI? {
            if (!owns(uri) || !safePath(uri.rawPath)) return null
            val path = uri.rawPath.ifEmpty { "/" }
            return parse(backend.toASCIIString() + path.removePrefix("/") + (uri.rawQuery?.let { "?$it" } ?: ""))
        }
        fun privateRedirect(from: URI, location: String): URI? {
            val resolved = try { from.resolve(location) } catch (_: IllegalArgumentException) { return null }
            if (owns(resolved)) return privateUrl(resolved)
            return resolved.takeIf { it.scheme == backend.scheme && it.rawAuthority == backend.rawAuthority && it.rawPath.startsWith(backend.rawPath) && safePath(it.rawPath) }
        }
        fun publicUrl(uri: URI): String = origin.toASCIIString() + "/" + uri.rawPath.removePrefix(backend.rawPath) + (uri.rawQuery?.let { "?$it" } ?: "") + (uri.rawFragment?.let { "#$it" } ?: "")
    }

    private class OriginClient(view: WebView, val delegate: WebViewClient, private val route: Route, private val emitLegacy: (String, Map<String, String>) -> Unit) : WebViewClient() {
        private val view = WeakReference(view)
        private val lock = Any()
        private val connections = mutableSetOf<ConnectionLease>()
        @Volatile private var active = true
        @Volatile private var legacyUrl = route.legacyUrl
        private var clearMigrationHistory = false
        @Volatile private var legacyReader: WebView? = null
        private var popupCreated = false
        private val evaluations = mutableSetOf<(Boolean) -> Unit>()

        fun loadLegacy(): WebView {
            val address = legacyUrl
            val target = view.get()
            require(active && address != null && target != null)
            legacyReader?.let { it.loadUrl(address); return it }
            val reader = WebView(target.context)
            legacyReader = reader
            reader.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = true
                allowContentAccess = false
                allowFileAccessFromFileURLs = false
                // The trusted blank can copy opaque cache responses into its HTTPS popup.
                allowUniversalAccessFromFileURLs = true
                cacheMode = WebSettings.LOAD_NO_CACHE
                setSupportMultipleWindows(true)
                javaScriptCanOpenWindowsAutomatically = true
            }
            val readerReference = WeakReference(reader)
            fun isCurrent() = active && legacyUrl != null && legacyReader != null && legacyReader === readerReference.get()
            reader.addJavascriptInterface(LegacyMessages { message ->
                Handler(Looper.getMainLooper()).post { if (isCurrent()) emitLegacy("legacyMessage", mapOf("message" to message)) }
            }, "MoruStorageMigration")
            reader.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse = if (isCurrent() && request.url.toString() == address) blank() else error(404)
                override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse = if (isCurrent() && url == address) blank() else error(404)
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = !isCurrent() || request.url.toString() != address
                override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = !isCurrent() || url != address
                override fun onPageFinished(view: WebView, url: String) {
                    Handler(Looper.getMainLooper()).post { if (isCurrent() && url == address) emitLegacy("legacyPageFinished", mapOf("url" to url)) }
                }
            }
            reader.webChromeClient = object : WebChromeClient() {
                override fun onCreateWindow(source: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                    val currentTarget = this@OriginClient.view.get() ?: return false
                    val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
                    if (!isCurrent() || source !== legacyReader || popupCreated || resultMsg.target == null || WebViewCompat.getWebViewClient(currentTarget) !== this@OriginClient) return false
                    if (currentTarget.url != null && (currentTarget.url != "about:blank" || currentTarget.copyBackForwardList().size != 0)) return false
                    popupCreated = true
                    transport.webView = currentTarget
                    resultMsg.sendToTarget()
                    return true
                }
            }
            reader.loadUrl(address)
            return reader
        }
        fun evaluateLegacy(script: String, completed: (Boolean) -> Unit) {
            val reader = legacyReader
            require(active && legacyUrl != null && reader != null)
            evaluations.add(completed)
            reader.evaluateJavascript(script) {
                if (evaluations.remove(completed)) completed(active && legacyUrl != null && legacyReader === reader)
            }
        }
        private fun closeLegacyReader() {
            val reader = legacyReader
            legacyReader = null
            reader?.settings?.allowUniversalAccessFromFileURLs = false
            reader?.removeJavascriptInterface("MoruStorageMigration")
            reader?.stopLoading()
            reader?.destroy()
            val pending = evaluations.toList()
            evaluations.clear()
            pending.forEach { it(false) }
        }

        fun finishMigration() {
            clearMigrationHistory = clearMigrationHistory || legacyUrl != null
            val open = synchronized(lock) { legacyUrl = null; connections.toList().also { connections.clear() } }
            open.forEach { it.close() }
            closeLegacyReader()
        }
        fun deactivate() {
            val open = synchronized(lock) { active = false; legacyUrl = null; connections.toList().also { connections.clear() } }
            open.forEach { it.close() }
            closeLegacyReader()
        }
        private fun intercept(address: Uri, method: String, headers: Map<String, String>, mainFrame: Boolean): WebResourceResponse? {
            if (localFile(address)) return if (active && address.toString() == legacyUrl) blank() else error(404)
            if (!reserved(address)) return null
            val uri = parse(address.toString()) ?: return error(404)
            if (!active || !route.owns(uri)) return error(404)
            if (method !in setOf("GET", "HEAD")) return error(405)
            if (!safePath(uri.rawPath)) return error(404)
            if (uri.rawPath == route.transferPath) return blank()
            val target = route.privateUrl(uri) ?: return error(404)
            return proxy(uri, target, method, headers, mainFrame)
        }
        private fun proxy(publicRequest: URI, target: URI, method: String, headers: Map<String, String>, mainFrame: Boolean): WebResourceResponse {
            var next = target
            var conditional = true
            repeat(8) {
                val connection = next.toURL().openConnection(Proxy.NO_PROXY) as HttpURLConnection
                connection.apply {
                    instanceFollowRedirects = false
                    useCaches = false
                    connectTimeout = 5000
                    readTimeout = 15000
                    requestMethod = method
                    headers.forEach { (name, value) ->
                        if (name.lowercase(Locale.ROOT) !in REQUEST_HOP_HEADERS && (conditional || !name.equals("If-None-Match", true) && !name.equals("If-Modified-Since", true))) setRequestProperty(name, value)
                    }
                    setRequestProperty("Accept-Encoding", "identity")
                    setRequestProperty("Connection", "close")
                    if (headers.keys.none { it.equals("Cookie", true) }) CookieManager.getInstance().getCookie(publicRequest.toASCIIString())?.let { setRequestProperty("Cookie", it) }
                }
                lateinit var lease: ConnectionLease
                lease = ConnectionLease(connection) { synchronized(lock) { connections.remove(lease) } }
                if (!synchronized(lock) { if (active) { connections.add(lease); true } else false }) { lease.close(); return error(404) }
                try {
                    val status = connection.responseCode
                    if (!active) { lease.close(); return error(404) }
                    if (status == 304 && conditional) { conditional = false; lease.close(); return@repeat }
                    if (status in setOf(301, 302, 303, 307, 308)) {
                        val redirect = connection.getHeaderField("Location")?.let { route.privateRedirect(next, it) }
                        lease.close()
                        if (redirect == null) return error(404)
                        if (mainFrame && route.publicUrl(redirect) != publicRequest.toASCIIString()) {
                            val stable = route.publicUrl(redirect)
                            Handler(Looper.getMainLooper()).post {
                                view.get()?.let { current ->
                                    if (active && WebViewCompat.getWebViewClient(current) === this) current.loadUrl(stable)
                                }
                            }
                            return blank()
                        }
                        next = redirect
                        return@repeat
                    }
                    if (status !in 100..599 || status in 300..399) { lease.close(); return error(502) }
                    val responseHeaders = linkedMapOf<String, String>()
                    connection.headerFields.forEach { (name, values) ->
                        if (name != null && name.lowercase(Locale.ROOT) !in RESPONSE_HOP_HEADERS) {
                            val valid = if (name.equals("Set-Cookie", true)) values.filter { cookieForHost(it, route.host) } else values
                            if (valid.isNotEmpty()) responseHeaders[name] = valid.joinToString(", ")
                            if (name.equals("Set-Cookie", true)) valid.forEach { CookieManager.getInstance().setCookie(publicRequest.toASCIIString(), it) }
                        }
                    }
                    val contentType = connection.contentType.orEmpty().split(';')
                    val mime = contentType.first().trim().ifEmpty { "application/octet-stream" }
                    val charset = contentType.drop(1).firstOrNull { it.trim().startsWith("charset=", true) }?.substringAfter('=')?.trim()?.trim('"', '\'')
                    val reason = connection.responseMessage?.takeIf { it.isNotBlank() && it.all { char -> char.code in 32..126 } } ?: "Response"
                    val input = if (status >= 400) connection.errorStream else connection.inputStream
                    val stream = lease.stream(input ?: ByteArray(0).inputStream())
                    return WebResourceResponse(mime, charset, status, reason, responseHeaders, stream)
                } catch (_: IOException) {
                    lease.close()
                    return error(if (active) 502 else 404)
                } catch (_: IllegalArgumentException) {
                    lease.close()
                    return error(502)
                }
            }
            return error(502)
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? = intercept(request.url, request.method, request.requestHeaders, request.isForMainFrame) ?: delegate.shouldInterceptRequest(view, request)
        override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? = intercept(Uri.parse(url), "GET", emptyMap(), false) ?: delegate.shouldInterceptRequest(view, url)
        private fun blocked(uri: Uri): Boolean {
            if (localFile(uri)) return !active || uri.toString() != legacyUrl
            if (!reserved(uri)) return false
            val address = parse(uri.toString()) ?: return true
            return !active || !route.owns(address) || !safePath(address.rawPath)
        }
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = if (blocked(request.url)) true else delegate.shouldOverrideUrlLoading(view, request)
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = if (blocked(Uri.parse(url))) true else delegate.shouldOverrideUrlLoading(view, url)
        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) = delegate.onPageStarted(view, url, favicon)
        override fun onPageFinished(view: WebView, url: String) {
            val uri = parse(url)
            if (clearMigrationHistory && active && uri != null && route.owns(uri) && uri.rawPath != route.transferPath) { clearMigrationHistory = false; view.clearHistory() }
            delegate.onPageFinished(view, url)
        }
        override fun onLoadResource(view: WebView, url: String) = delegate.onLoadResource(view, url)
        override fun onPageCommitVisible(view: WebView, url: String) = delegate.onPageCommitVisible(view, url)
        override fun onReceivedError(view: WebView, code: Int, description: String?, failingUrl: String?) = delegate.onReceivedError(view, code, description, failingUrl)
        override fun onReceivedError(view: WebView, request: WebResourceRequest?, error: WebResourceError?) = delegate.onReceivedError(view, request, error)
        override fun onReceivedHttpError(view: WebView, request: WebResourceRequest?, response: WebResourceResponse?) = delegate.onReceivedHttpError(view, request, response)
        override fun onTooManyRedirects(view: WebView, cancel: Message?, continueMessage: Message?) = delegate.onTooManyRedirects(view, cancel, continueMessage)
        override fun onFormResubmission(view: WebView, dontResend: Message?, resend: Message?) = delegate.onFormResubmission(view, dontResend, resend)
        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) = delegate.doUpdateVisitedHistory(view, url, isReload)
        override fun onReceivedSslError(view: WebView, handler: SslErrorHandler?, error: SslError?) = delegate.onReceivedSslError(view, handler, error)
        override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest?) = delegate.onReceivedClientCertRequest(view, request)
        override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler?, host: String?, realm: String?) = delegate.onReceivedHttpAuthRequest(view, handler, host, realm)
        override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent): Boolean = delegate.shouldOverrideKeyEvent(view, event)
        override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) = delegate.onUnhandledKeyEvent(view, event)
        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) = delegate.onScaleChanged(view, oldScale, newScale)
        override fun onReceivedLoginRequest(view: WebView, realm: String, account: String?, args: String) = delegate.onReceivedLoginRequest(view, realm, account, args)
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail?): Boolean = delegate.onRenderProcessGone(view, detail)
        override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest?, threatType: Int, response: SafeBrowsingResponse?) = delegate.onSafeBrowsingHit(view, request, threatType, response)
    }

    private class LegacyMessages(private val received: (String) -> Unit) {
        @JavascriptInterface fun postMessage(message: String) = received(message)
    }

    /** A response owns its private connection until EOF/close or session revocation. */
    private class ConnectionLease(private val connection: HttpURLConnection, private val released: () -> Unit) {
        private val closed = AtomicBoolean()
        private var input: InputStream? = null
        fun stream(stream: InputStream): InputStream = synchronized(this) {
            if (closed.get()) { stream.close(); throw IOException("Mini app session closed") }
            input = stream
            object : FilterInputStream(stream) {
                private fun checkOpen() { if (closed.get()) throw IOException("Mini app response closed") }
                override fun read(): Int { checkOpen(); return `in`.read().also { if (it == -1) close() } }
                override fun read(bytes: ByteArray, offset: Int, length: Int): Int { checkOpen(); return `in`.read(bytes, offset, length).also { if (it == -1) close() } }
                override fun skip(count: Long): Long { checkOpen(); return `in`.skip(count) }
                override fun available(): Int { checkOpen(); return `in`.available() }
                override fun close() = this@ConnectionLease.close()
            }
        }
        fun close() {
            if (!closed.compareAndSet(false, true)) return
            try { synchronized(this) { input?.close(); input = null } } catch (_: IOException) { }
            finally { connection.disconnect(); released() }
        }
    }

    companion object {
        private const val TRANSFER_PATH = "/.moru-storage-transfer"
        private const val BLANK = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>"
        private val REQUEST_HOP_HEADERS = setOf("host", "connection", "content-length", "transfer-encoding", "accept-encoding", "proxy-authorization", "proxy-connection", "keep-alive", "te", "trailer", "upgrade")
        private val RESPONSE_HOP_HEADERS = setOf("connection", "transfer-encoding", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "upgrade")
        private fun parse(value: String): URI? = try { URI(value) } catch (_: java.net.URISyntaxException) { null }
        private fun reserved(uri: Uri): Boolean = uri.host?.lowercase(Locale.ROOT)?.trimEnd('.')?.let {
            it.endsWith(".invalid") && (it.startsWith("moru-miniapp-") || it.removeSuffix(".invalid").substringAfterLast('.').startsWith("moru-miniapp-"))
        } == true
        private fun localFile(uri: Uri) = uri.scheme.equals("file", true) || uri.scheme.equals("content", true)
        private fun safePath(path: String?): Boolean = path != null && path.split('/').all { part ->
            val decoded = Uri.decode(part)
            decoded != "." && decoded != ".." && !decoded.contains('/') && !decoded.contains('\\') && !decoded.contains('\u0000') && !Regex("%(?:2e|2f|5c|00)", RegexOption.IGNORE_CASE).containsMatchIn(decoded)
        }
        private fun cookieForHost(cookie: String, host: String): Boolean {
            val domains = cookie.split(';').drop(1).filter { it.trim().substringBefore('=').equals("domain", true) }
            return domains.all { it.substringAfter('=', "").trim().trimStart('.').equals(host, true) }
        }
        private fun blank() = WebResourceResponse("text/html", "utf-8", 200, "OK", mapOf("Cache-Control" to "no-store", "Content-Security-Policy" to "default-src 'none'; base-uri 'none'; frame-ancestors 'none'", "X-Content-Type-Options" to "nosniff"), BLANK.byteInputStream(Charsets.UTF_8))
        private fun error(status: Int) = WebResourceResponse("text/plain", "utf-8", status, when (status) { 404 -> "Not Found"; 405 -> "Method Not Allowed"; else -> "Bad Gateway" }, mapOf("Cache-Control" to "no-store", "X-Content-Type-Options" to "nosniff"), ByteArray(0).inputStream())
    }
}
