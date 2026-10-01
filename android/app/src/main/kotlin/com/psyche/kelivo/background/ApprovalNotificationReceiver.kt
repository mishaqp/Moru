package com.psyche.kelivo.background

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.psyche.kelivo.KelivoApplication

/** Explicit immutable notification actions only. Never initializes a FlutterEngine. */
class ApprovalNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val (target, action) = BackgroundNotifications.readAction(intent) ?: return
        val app = context.applicationContext as? KelivoApplication ?: return
        val pending = goAsync()
        app.backgroundRuntime.handleApprovalAction(target, action) { pending.finish() }
    }
}
