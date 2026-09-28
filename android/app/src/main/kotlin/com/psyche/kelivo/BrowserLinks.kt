package com.psyche.kelivo

import android.content.Intent
import android.net.Uri
import java.net.URISyntaxException

/**
 * Links in the browser that belong to other apps: `intent:` (Chrome's
 * format), `tel:`, `mailto:`, `market:`, `tg:` and the like.
 */
internal object BrowserLinks {
    private val browserSchemes = setOf(
        "http", "https", "about", "data", "blob", "javascript", "file", "content",
    )

    /**
     * The intent that opens [url] in another app, made safe like Chrome
     * makes it: only BROWSABLE activities, no explicit component or selector
     * (a page must not reach an app's private screens) and never this app.
     * Null for web URLs and for what cannot be parsed.
     */
    fun intentFor(url: String, ownPackage: String): Intent? {
        val scheme = Uri.parse(url).scheme?.lowercase() ?: return null
        if (scheme in browserSchemes) return null
        val intent = if (scheme == "intent") {
            try {
                Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
            } catch (e: URISyntaxException) {
                return null
            }
        } else {
            Intent(Intent.ACTION_VIEW, Uri.parse(url))
        }
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        if (intent.`package` == ownPackage) return null
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return intent
    }

    /** The web page an `intent:` link names for when no app takes it. */
    fun fallbackUrl(url: String): String? {
        if (!url.startsWith("intent:", ignoreCase = true)) return null
        val intent = try {
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
        } catch (e: URISyntaxException) {
            return null
        }
        val fallback = intent.getStringExtra("browser_fallback_url") ?: return null
        val scheme = Uri.parse(fallback).scheme?.lowercase()
        return if (scheme == "http" || scheme == "https") fallback else null
    }
}
