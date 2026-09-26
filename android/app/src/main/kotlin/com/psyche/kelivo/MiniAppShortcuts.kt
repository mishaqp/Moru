package com.psyche.kelivo

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/** Home screen shortcuts that open one mini app in Moru. */
internal object MiniAppShortcuts {
    const val ACTION_OPEN = "com.mishaqp.moru.OPEN_MINI_APP"
    const val EXTRA_ID = "mini_app_id"

    /** Asks the launcher to pin a shortcut; false when it cannot. */
    fun requestPin(context: Context, id: String, name: String, icon: ByteArray): Boolean {
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(context)) return false
        val bitmap = BitmapFactory.decodeByteArray(icon, 0, icon.size) ?: return false
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN)
            .putExtra(EXTRA_ID, id)
        val shortcut = ShortcutInfoCompat.Builder(context, "mini_app_$id")
            .setShortLabel(name)
            .setIcon(IconCompat.createWithBitmap(bitmap))
            .setIntent(intent)
            .build()
        return ShortcutManagerCompat.requestPinShortcut(context, shortcut, null)
    }
}

/** The mini app a shortcut Intent opens, consumed so it is delivered once. */
internal fun takeMiniAppId(intent: Intent?): String? {
    if (intent?.action != MiniAppShortcuts.ACTION_OPEN) return null
    val id = intent.getStringExtra(MiniAppShortcuts.EXTRA_ID)?.trim()
    intent.removeExtra(MiniAppShortcuts.EXTRA_ID)
    return id?.takeIf { it.isNotEmpty() }
}
