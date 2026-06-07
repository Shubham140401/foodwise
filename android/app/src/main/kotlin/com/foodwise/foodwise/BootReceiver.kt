package com.foodwise.foodwise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // WorkManager 2.1+ automatically reschedules all enqueued periodic
        // work after a device reboot via its own internal boot receiver.
        // This class just needs to exist in the manifest so Android wakes
        // the app process — no manual rescheduling required here.
    }
}
