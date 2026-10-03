package com.psyche.kelivo

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.URLUtil

/** Files a page in the browser downloads, saved to Downloads like Chrome. */
internal object BrowserDownloads {
    private val started = mutableMapOf<Long, String>()
    private var receiver: BroadcastReceiver? = null

    /** Told when a download this browser started ends; set by the activity. */
    @Volatile
    var onFinished: ((Map<String, Any?>) -> Unit)? = null

    /**
     * What the page and the model learn when download [id] of [file] ends:
     * the real path (the download manager renames a taken name to
     * `name-1.pdf`), or why it failed.
     */
    fun finishedEvent(id: Long, file: String, status: Int, localUri: String?, reason: Int): Map<String, Any?> {
        val done = status == DownloadManager.STATUS_SUCCESSFUL
        val path = localUri?.let { Uri.parse(it).path }
        return mapOf(
            "id" to id,
            "file" to (path?.substringAfterLast('/') ?: file),
            "status" to if (done) "done" else "failed",
            "path" to if (done) path else null,
            "reason" to if (done) null else reason,
        )
    }

    private fun listen(context: Context) {
        if (receiver != null) return
        val listener = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
                val file = synchronized(started) { started.remove(id) } ?: return
                val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                val event = manager.query(DownloadManager.Query().setFilterById(id)).use { row ->
                    if (!row.moveToFirst()) {
                        finishedEvent(id, file, DownloadManager.STATUS_FAILED, null, 0)
                    } else {
                        finishedEvent(
                            id,
                            file,
                            row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)),
                            row.getString(row.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)),
                            row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)),
                        )
                    }
                }
                onFinished?.invoke(event)
            }
        }
        // The system's download manager sends it, so it must be exported.
        ContextCompat.registerReceiver(
            context.applicationContext,
            listener,
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
            ContextCompat.RECEIVER_EXPORTED,
        )
        receiver = listener
    }

    /** The name the file gets, from the URL, Content-Disposition and type. */
    fun fileName(url: String, contentDisposition: String?, mimeType: String?): String =
        URLUtil.guessFileName(url, contentDisposition, mimeType)
            .replace('/', '_')
            .ifBlank { "download" }

    /**
     * Starts [url] in the system download manager with the page's cookies
     * and user agent, so files behind a login download too. Only http(s):
     * `blob:` and `data:` files exist inside the page alone.
     */
    fun enqueue(
        context: Context,
        url: String,
        userAgent: String?,
        contentDisposition: String?,
        mimeType: String?,
    ): Map<String, Any?> {
        val uri = Uri.parse(url)
        val scheme = uri.scheme?.lowercase()
        require(scheme == "http" || scheme == "https") { "unsupported_scheme" }
        val name = fileName(url, contentDisposition, mimeType)
        val request = DownloadManager.Request(uri)
            .setTitle(name)
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
        if (!mimeType.isNullOrBlank()) request.setMimeType(mimeType)
        if (!userAgent.isNullOrBlank()) request.addRequestHeader("User-Agent", userAgent)
        CookieManager.getInstance().getCookie(url)?.let {
            request.addRequestHeader("Cookie", it)
        }
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        listen(context)
        val id = manager.enqueue(request)
        synchronized(started) { started[id] = name }
        // The path is known once it ends: a taken name gets a suffix.
        return mapOf(
            "id" to id,
            "file" to name,
            "url" to url,
            "mime" to mimeType,
        )
    }
}
