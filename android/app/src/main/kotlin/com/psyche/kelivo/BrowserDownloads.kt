package com.psyche.kelivo

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.URLUtil

/** Files a page in the browser downloads, saved to Downloads like Chrome. */
internal object BrowserDownloads {
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
        val id = manager.enqueue(request)
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return mapOf(
            "id" to id,
            "file" to name,
            "path" to "${dir.absolutePath}/$name",
            "url" to url,
            "mime" to mimeType,
        )
    }
}
