package com.failas.expnd

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Renders the EXPND home-screen widget from the snapshot the Flutter side
 * writes via `home_widget` (see WidgetBridge). Read-only: it never computes
 * balances, it just paints the pre-formatted strings it's handed.
 */
class ExpndWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.expnd_widget).apply {
                bind(context, this, widgetData)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bind(context: Context, views: RemoteViews, data: SharedPreferences) {
        // Headline: what's left of the monthly budget, or the month's spend
        // when no budget is set. Net worth is deliberately not shown on the
        // Home Screen. (The view id predates this and is kept for the layout.)
        val left = data.getString("left_to_spend", "") ?: ""
        val over = data.getBoolean("over_budget", false)
        val month = data.getString("month_label", "") ?: ""
        views.setTextViewText(
            R.id.widget_net_label,
            when {
                left.isEmpty() -> if (month.isEmpty()) "SPENT" else "$month SPENT"
                over -> "OVER BUDGET"
                else -> "LEFT TO SPEND"
            }
        )
        views.setTextViewText(
            R.id.widget_net_worth,
            if (left.isEmpty()) data.getString("month_spent", "—") else left
        )
        views.setTextColor(
            R.id.widget_net_worth,
            ContextCompat.getColor(
                context,
                if (over) R.color.widget_expense else R.color.widget_gold
            )
        )
        views.setTextViewText(
            R.id.widget_month_label,
            (data.getString("month_label", "") ?: "") + " SPENT"
        )
        views.setTextViewText(R.id.widget_month_spent, data.getString("month_spent", "—"))
        views.setTextViewText(R.id.widget_budget, data.getString("budget_text", "") ?: "")
        views.setViewVisibility(
            R.id.widget_show,
            if (data.getBoolean("amounts_hidden", false)) View.VISIBLE else View.GONE
        )

        // Recent transactions.
        val count = data.readInt("tx_count", 0)
        val rows = intArrayOf(R.id.tx_row_0, R.id.tx_row_1, R.id.tx_row_2)
        val notes = intArrayOf(R.id.tx_note_0, R.id.tx_note_1, R.id.tx_note_2)
        val amounts = intArrayOf(R.id.tx_amount_0, R.id.tx_amount_1, R.id.tx_amount_2)

        for (i in rows.indices) {
            if (i < count) {
                views.setViewVisibility(rows[i], View.VISIBLE)
                views.setTextViewText(notes[i], data.getString("tx${i}_note", "") ?: "")
                val amount = data.getString("tx${i}_amount", "") ?: ""
                views.setTextViewText(amounts[i], amount)
                views.setTextColor(amounts[i], amountColor(context, amount))
            } else {
                views.setViewVisibility(rows[i], View.GONE)
            }
        }
        views.setViewVisibility(
            R.id.widget_empty,
            if (count == 0) View.VISIBLE else View.GONE
        )

        // Tapping the card opens the app; the ADD pill deep-links to add-entry.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        )
        views.setOnClickPendingIntent(
            R.id.widget_add,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("expnd://add")
            )
        )
        views.setOnClickPendingIntent(
            R.id.widget_show,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("expnd://show")
            )
        )
    }

    /** Green for income (+), red for expense (−), neutral for transfers. */
    private fun amountColor(context: Context, amount: String): Int {
        val res = when {
            amount.startsWith("+") -> R.color.widget_income
            amount.startsWith("-") || amount.startsWith("−") -> R.color.widget_expense
            else -> R.color.widget_text
        }
        return ContextCompat.getColor(context, res)
    }

    /** `home_widget` may persist a Dart int as either Int or Long; read both. */
    private fun SharedPreferences.readInt(key: String, fallback: Int): Int = try {
        getInt(key, fallback)
    } catch (e: ClassCastException) {
        getLong(key, fallback.toLong()).toInt()
    }
}
