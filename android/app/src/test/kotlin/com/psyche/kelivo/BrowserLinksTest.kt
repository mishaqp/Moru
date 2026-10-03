package com.psyche.kelivo

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class BrowserLinksTest {
    private val own = "com.mishaqp.moru"

    @Test fun webLinksStayInTheBrowser() {
        assertNull(BrowserLinks.intentFor("https://example.com", own))
        assertNull(BrowserLinks.intentFor("about:blank", own))
        assertNull(BrowserLinks.intentFor("javascript:alert(1)", own))
        assertNull(BrowserLinks.intentFor("file:///sdcard/x", own))
    }

    @Test fun appLinksBecomeBrowsableViewIntents() {
        val tel = BrowserLinks.intentFor("tel:+123", own)!!
        assertEquals(Intent.ACTION_VIEW, tel.action)
        assertEquals("tel:+123", tel.dataString)
        assertTrue(tel.hasCategory(Intent.CATEGORY_BROWSABLE))
    }

    @Test fun intentLinksLoseComponentAndSelector() {
        val url = "intent://scan/#Intent;scheme=zxing;package=com.example.scanner;" +
            "component=com.example.scanner/.Private;" +
            "S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fscanner;end"
        val intent = BrowserLinks.intentFor(url, own)!!
        assertNull(intent.component)
        assertNull(intent.selector)
        assertEquals("com.example.scanner", intent.`package`)
        assertTrue(intent.hasCategory(Intent.CATEGORY_BROWSABLE))
        assertEquals("https://example.com/scanner", BrowserLinks.fallbackUrl(url))
    }

    @Test fun pagesCannotOpenThisApp() {
        assertNull(
            BrowserLinks.intentFor("intent://x#Intent;scheme=moru;package=$own;end", own),
        )
    }

    @Test fun onlyWebFallbacksAreUsed() {
        assertNull(
            BrowserLinks.fallbackUrl(
                "intent://x#Intent;scheme=a;S.browser_fallback_url=javascript%3Aalert(1);end",
            ),
        )
        assertNull(BrowserLinks.fallbackUrl("tel:+1"))
    }

    @Test fun downloadNamesComeFromTheHeaderOrUrl() {
        assertEquals(
            "report.pdf",
            BrowserDownloads.fileName(
                "https://example.com/get?id=1",
                "attachment; filename=\"report.pdf\"",
                "application/pdf",
            ),
        )
        assertEquals(
            "photo.jpg",
            BrowserDownloads.fileName("https://example.com/a/photo.jpg", null, "image/jpeg"),
        )
    }

    @Test fun finishedDownloadsReportTheRealPath() {
        val done = BrowserDownloads.finishedEvent(
            7,
            "report.pdf",
            android.app.DownloadManager.STATUS_SUCCESSFUL,
            "file:///storage/emulated/0/Download/report-1.pdf",
            0,
        )
        assertEquals("done", done["status"])
        assertEquals("report-1.pdf", done["file"])
        assertEquals("/storage/emulated/0/Download/report-1.pdf", done["path"])

        val failed = BrowserDownloads.finishedEvent(
            8,
            "report.pdf",
            android.app.DownloadManager.STATUS_FAILED,
            null,
            android.app.DownloadManager.ERROR_HTTP_DATA_ERROR,
        )
        assertEquals("failed", failed["status"])
        assertEquals("report.pdf", failed["file"])
        assertNull(failed["path"])
    }

    @Test fun signingOutExpiresTheSiteCookiesOnEveryDomainLevel() {
        assertEquals(listOf("sid", "theme"), BrowserCookies.names("sid=a=1; theme=dark; "))
        assertEquals(
            listOf(
                "sid=; Max-Age=0; Path=/",
                "sid=; Max-Age=0; Path=/; Domain=.www.shop.example",
                "sid=; Max-Age=0; Path=/; Domain=.shop.example",
            ),
            BrowserCookies.expiring("sid", "www.shop.example"),
        )
    }

    @Test fun realInputMapsPointsAndKeys() {
        assertEquals(0f to 0f, BrowserInput.point(0.0, 0.0, 1080, 1800))
        assertEquals(539.5f to 1799f, BrowserInput.point(0.5, 1.0, 1080, 1800))
        // Outside the page is kept on its edge.
        assertEquals(1079f to 0f, BrowserInput.point(1.5, -0.2, 1080, 1800))
        assertEquals(android.view.KeyEvent.KEYCODE_ENTER, BrowserInput.keyCode("Enter"))
        assertEquals(android.view.KeyEvent.KEYCODE_DEL, BrowserInput.keyCode("Backspace"))
        assertNull(BrowserInput.keyCode("a"))
    }
}
