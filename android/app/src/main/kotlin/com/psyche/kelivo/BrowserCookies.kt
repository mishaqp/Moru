package com.psyche.kelivo

import android.net.Uri
import android.webkit.CookieManager

/** Signing a site out of the browser: its cookies only, not other sites'. */
internal object BrowserCookies {
    /** Names of the cookies in a `Cookie` header (`a=1; b=2`). */
    fun names(header: String?): List<String> =
        header.orEmpty().split(';')
            .map { it.substringBefore('=').trim() }
            .filter { it.isNotEmpty() }

    /**
     * The `Set-Cookie` values that expire [name] for [host]: a cookie was
     * set for the host itself or for a parent domain, so each one is
     * expired, on the root path.
     */
    fun expiring(name: String, host: String): List<String> {
        val parts = host.split('.')
        val domains = (0 until maxOf(parts.size - 1, 1)).map {
            parts.drop(it).joinToString(".")
        }
        return listOf("$name=; Max-Age=0; Path=/") +
            domains.map { "$name=; Max-Age=0; Path=/; Domain=.$it" }
    }

    /** Expires every cookie the browser sends to [url]; returns how many. */
    fun clear(url: String): Int {
        val host = Uri.parse(url).host ?: return 0
        val manager = CookieManager.getInstance()
        val names = names(manager.getCookie(url))
        for (name in names) {
            for (value in expiring(name, host)) manager.setCookie(url, value)
        }
        manager.flush()
        return names.size
    }
}
