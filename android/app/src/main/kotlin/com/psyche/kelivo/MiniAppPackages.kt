package com.psyche.kelivo

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telecom.TelecomManager
import android.view.accessibility.AccessibilityManager
import android.view.inputmethod.InputMethodManager

object MiniAppPackagePolicy {
    fun isEligible(info: ApplicationInfo, ownPackage: String, protectedPackages: Set<String>): Boolean {
        val packageName = info.packageName ?: return false
        return MiniAppDeviceCatalog.validPackageName(packageName) &&
            packageName != ownPackage && packageName !in protectedPackages &&
            packageName != "android" && !packageName.startsWith("com.android.") &&
            packageName !in setOf("com.google.android.gms", "com.google.android.gsf", "com.android.vending", "com.topjohnwu.magisk", "me.weishu.kernelsu", "me.bmax.apatch", "com.rifsxd.ksunext") &&
            info.uid % 100000 >= 10000 &&
            info.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP or ApplicationInfo.FLAG_PERSISTENT) == 0 &&
            info.enabled
    }
}

/** Android's visible launcher packages, not unrestricted package enumeration. */
class MiniAppPackages(private val context: Context) {
    private val pm get() = context.packageManager

    private fun protectedPackages(): Set<String> = buildSet {
        add(context.packageName)
        runCatching {
            pm.resolveActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName?.let { add(it) }
        }
        runCatching {
            (context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)?.enabledInputMethodList?.forEach { add(it.packageName) }
        }
        runCatching {
            (context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager)?.activeAdmins?.forEach { add(it.packageName) }
        }
        runCatching {
            (context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)
                ?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                ?.forEach { it.resolveInfo?.serviceInfo?.packageName?.let { name -> add(name) } }
        }
        runCatching {
            pm.queryIntentServices(Intent("android.net.VpnService"), 0).take(MAX_DISCOVERED).forEach { it.serviceInfo?.packageName?.let { name -> add(name) } }
        }
        runCatching { Telephony.Sms.getDefaultSmsPackage(context)?.let { add(it) } }
        runCatching { (context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage?.let { add(it) } }
    }

    fun list(): List<Map<String, String>> {
        val protected = protectedPackages()
        return pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .take(MAX_DISCOVERED)
            .mapNotNull { it.activityInfo?.applicationInfo }
            .distinctBy { it.packageName }
            .filter { MiniAppPackagePolicy.isEligible(it, context.packageName, protected) }
            .map { mapOf("packageName" to it.packageName, "label" to runCatching { pm.getApplicationLabel(it).toString().take(120) }.getOrDefault(it.packageName)) }
            .sortedWith(compareBy({ it["label"]?.lowercase() }, { it["packageName"] }))
            .take(MAX_SELECTED)
    }

    fun selected(packageName: String): ApplicationInfo? {
        if (!MiniAppDeviceCatalog.validPackageName(packageName)) return null
        // Selection is constrained to the same bounded list shown in the UI.
        if (list().none { it["packageName"] == packageName }) return null
        val info = runCatching { pm.getApplicationInfo(packageName, 0) }.getOrNull() ?: return null
        return info.takeIf { MiniAppPackagePolicy.isEligible(it, context.packageName, protectedPackages()) }
    }

    fun isStopped(packageName: String): Boolean? = runCatching {
        pm.getApplicationInfo(packageName, 0).flags and ApplicationInfo.FLAG_STOPPED != 0
    }.getOrNull()

    companion object {
        const val MAX_DISCOVERED = 512
        const val MAX_SELECTED = 128
    }
}
