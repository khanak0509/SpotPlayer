package com.spotplayer.spotplayer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SpotPlayerWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.spot_player_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("title", "SpotPlayer"))
                setTextViewText(R.id.widget_artist, widgetData.getString("artist", "Tap to open"))
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
