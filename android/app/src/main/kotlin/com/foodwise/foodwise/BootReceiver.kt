package com.foodwise.foodwise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.WorkmanagerPlugin
import java.util.concurrent.TimeUnit

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON") return

        // Re-register the WorkManager periodic task after reboot.
        // The Flutter Dart isolate handles the actual task logic via
        // callbackDispatcher; we just need to ensure the work is enqueued.
        WorkmanagerPlugin.rescheduleTask(context)
    }
}
