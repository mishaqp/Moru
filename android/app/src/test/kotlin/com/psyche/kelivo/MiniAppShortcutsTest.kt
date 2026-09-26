package com.psyche.kelivo

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class MiniAppShortcutsTest {
    private fun shortcut(id: String?) = Intent(MiniAppShortcuts.ACTION_OPEN)
        .putExtra(MiniAppShortcuts.EXTRA_ID, id)

    @Test fun shortcutIntentOpensItsAppOnce() {
        val intent = shortcut("  water-tracker ")
        assertEquals("water-tracker", takeMiniAppId(intent))
        assertNull(takeMiniAppId(intent))
    }

    @Test fun otherIntentsAndBlankIdsOpenNothing() {
        assertNull(takeMiniAppId(null))
        assertNull(takeMiniAppId(Intent(Intent.ACTION_MAIN).putExtra(MiniAppShortcuts.EXTRA_ID, "x")))
        assertNull(takeMiniAppId(shortcut("   ")))
        assertNull(takeMiniAppId(shortcut(null)))
    }
}
