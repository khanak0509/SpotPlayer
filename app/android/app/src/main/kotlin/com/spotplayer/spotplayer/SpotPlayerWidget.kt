package com.spotplayer.spotplayer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class SpotPlayerWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val playing = widgetData.getBoolean("is_playing", false)
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.spot_player_widget).apply {
                setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("title", "SpotPlayer") ?: "SpotPlayer",
                )
                setTextViewText(
                    R.id.widget_artist,
                    widgetData.getString("artist", "Tap to open") ?: "Tap to open",
                )
                setImageViewResource(
                    R.id.widget_play_pause,
                    if (playing) {
                        android.R.drawable.ic_media_pause
                    } else {
                        android.R.drawable.ic_media_play
                    },
                )

                val openApp = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                )
                setOnClickPendingIntent(R.id.widget_meta, openApp)
                setOnClickPendingIntent(R.id.widget_title, openApp)
                setOnClickPendingIntent(R.id.widget_artist, openApp)

                setOnClickPendingIntent(
                    R.id.widget_prev,
                    mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 11),
                )
                setOnClickPendingIntent(
                    R.id.widget_play_pause,
                    mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 12),
                )
                setOnClickPendingIntent(
                    R.id.widget_next,
                    mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 13),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun mediaButtonPendingIntent(
        context: Context,
        keyCode: Int,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setClass(context, MediaButtonReceiver::class.java)
            putExtra(
                Intent.EXTRA_KEY_EVENT,
                KeyEvent(KeyEvent.ACTION_DOWN, keyCode),
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }
}
