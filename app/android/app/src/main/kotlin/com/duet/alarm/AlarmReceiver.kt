package com.duet.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * The alarm fires here. We have a few seconds at most, so this does exactly one
 * thing: start the foreground service. Anything else risks the process being
 * killed before the sound starts.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ALARM_ID) ?: return
        Log.i(TAG, "FIRED $id at ${System.currentTimeMillis()}")

        val svc = Intent(context, AlarmService::class.java).apply {
            putExtra(EXTRA_ALARM_ID, id)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc)
        } else {
            context.startService(svc)
        }
    }

    companion object {
        private const val TAG = "DuetReceiver"
        const val ACTION_FIRE = "com.duet.alarm.FIRE"
        const val EXTRA_ALARM_ID = "alarm_id"
    }
}
