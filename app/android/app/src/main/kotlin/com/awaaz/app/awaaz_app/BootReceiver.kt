package com.awaaz.app.awaaz_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts standby after a reboot or an app update, if it was on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                AwaazService.resumeStandby(context)
        }
    }
}
