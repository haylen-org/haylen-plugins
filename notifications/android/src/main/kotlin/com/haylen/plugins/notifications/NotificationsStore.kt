package com.haylen.plugins.notifications

import android.content.Context
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

// The notifications that wait for their alarm, which Android does not list, kept in the shared preferences of the plugin so they outlive the process and a restart of the device. An entry leaves when its notification posts or is cancelled.
object NotificationsStore {
    private const val PREFERENCES = "com.haylen.plugins.notifications"

    // A notification of the app, with its date as a Unix time in seconds and its data as any JSON value.
    class Entry(val id: String, val title: String, val body: String, val date: Double, val sound: Boolean, val badge: Int?, val data: Any?) {
        fun toJson(): JSONObject {
            val json = describe()
            json.put("sound", sound)
            badge?.let { json.put("badge", it) }
            return json
        }

        fun describe(): JSONObject {
            val json = JSONObject()
            json.put("id", id)
            json.put("title", title)
            json.put("body", body)
            json.put("date", date)
            json.put("data", data ?: JSONObject.NULL)
            return json
        }

        // The data as JSON text, which the extras of an intent carry.
        fun dataText(): String {
            return JSONArray().put(data ?: JSONObject.NULL).toString()
        }

        companion object {
            // Seconds count from now, and a date is a Unix time in seconds.
            fun fromParams(params: JSONObject): Entry {
                val date = if (params.has("date")) params.getDouble("date") else System.currentTimeMillis() / 1000.0 + params.getDouble("seconds")
                return Entry(params.getString("id"), params.getString("title"), params.getString("body"), date, params.getBoolean("sound"), if (params.has("badge")) params.getInt("badge") else null, params.opt("data"))
            }

            fun fromJson(json: JSONObject): Entry {
                return Entry(json.getString("id"), json.getString("title"), json.getString("body"), json.getDouble("date"), json.getBoolean("sound"), if (json.has("badge")) json.getInt("badge") else null, json.opt("data"))
            }

            fun readData(text: String?): Any? {
                return if (text == null) JSONObject.NULL else JSONArray(text).opt(0)
            }
        }
    }

    @Synchronized
    fun put(context: Context, entry: Entry) {
        preferences(context).edit { putString(entry.id, entry.toJson().toString()) }
    }

    @Synchronized
    fun get(context: Context, id: String): Entry? {
        val text = preferences(context).getString(id, null) ?: return null
        return Entry.fromJson(JSONObject(text))
    }

    @Synchronized
    fun remove(context: Context, id: String) {
        preferences(context).edit { remove(id) }
    }

    // The entries in the order of their dates.
    @Synchronized
    fun all(context: Context): List<Entry> {
        val entries = preferences(context).all.values.filterIsInstance<String>().map { Entry.fromJson(JSONObject(it)) }
        return entries.sortedBy { it.date }
    }

    private fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
