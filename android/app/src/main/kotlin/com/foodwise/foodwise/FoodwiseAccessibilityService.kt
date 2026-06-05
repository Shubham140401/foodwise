package com.foodwise.foodwise

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

class FoodwiseAccessibilityService : AccessibilityService() {

    companion object {
        // Packages we care about
        private val FOOD_APPS = mapOf(
            "in.swiggy.android" to "Swiggy",
            "com.application.zomato" to "Zomato",
            "com.blinkit.consumer" to "Blinkit"
        )

        // Broadcast action Flutter listens to via a background isolate
        const val ACTION_FOOD_DATA = "com.foodwise.FOOD_DATA"
        const val EXTRA_JSON = "json"

        // Shared state — last scraped data per app
        val latestData = mutableMapOf<String, AppScreenData>()
    }

    data class AppScreenData(
        val app: String,
        val restaurants: List<RestaurantItem>,
        val coupons: List<String>,
        val banners: List<String>,
        val scrapedAt: Long = System.currentTimeMillis()
    )

    data class RestaurantItem(
        val name: String,
        val deliveryFee: Int,
        val deliveryTime: String,
        val rating: String,
        val discount: String
    )

    override fun onServiceConnected() {
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            packageNames = FOOD_APPS.keys.toTypedArray()
            notificationTimeout = 500
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        val appName = FOOD_APPS[pkg] ?: return

        val root = rootInActiveWindow ?: return
        val data = scrapeScreen(appName, root)
        root.recycle()

        if (data.restaurants.isNotEmpty() || data.coupons.isNotEmpty()) {
            latestData[appName] = data
            broadcastData(data)
        }
    }

    private fun scrapeScreen(app: String, root: AccessibilityNodeInfo): AppScreenData {
        val allText = mutableListOf<String>()
        collectAllText(root, allText)

        val restaurants = parseRestaurants(app, allText)
        val coupons = parseCoupons(allText)
        val banners = parseBanners(allText)

        return AppScreenData(app, restaurants, coupons, banners)
    }

    private fun collectAllText(node: AccessibilityNodeInfo, result: MutableList<String>) {
        node.text?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let { result.add(it) }
        node.contentDescription?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let {
            if (!result.contains(it)) result.add(it)
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                collectAllText(child, result)
                child.recycle()
            }
        }
    }

    private fun parseRestaurants(app: String, texts: List<String>): List<RestaurantItem> {
        val items = mutableListOf<RestaurantItem>()

        // Heuristic: look for delivery fee patterns like "₹30 delivery" or "Free delivery"
        // and associate with nearby restaurant names
        var i = 0
        while (i < texts.size) {
            val text = texts[i]

            // Rating pattern: "4.2" or "4.2 (500+)"
            val isRating = text.matches(Regex("\\d\\.\\d.*"))

            // Delivery fee pattern
            val deliveryFeeMatch = Regex("₹(\\d+)\\s*delivery|Free delivery", RegexOption.IGNORE_CASE)
                .find(text)

            // Discount pattern: "30% OFF", "FLAT ₹100"
            val isDiscount = text.contains("% off", ignoreCase = true) ||
                    text.contains("flat ₹", ignoreCase = true) ||
                    text.contains("free delivery", ignoreCase = true)

            // Delivery time: "30-40 min"
            val isDeliveryTime = text.matches(Regex("\\d+[-–]\\d+\\s*min.*", RegexOption.IGNORE_CASE))

            // Restaurant name heuristic: not a number, not a price, length > 3
            val isProbablyName = text.length > 3 &&
                    !text.matches(Regex("[₹\\d.,% ]+")) &&
                    !isRating && !isDeliveryTime && !isDiscount &&
                    !text.contains("delivery", ignoreCase = true) &&
                    !text.contains("min", ignoreCase = true) &&
                    text[0].isUpperCase()

            if (isProbablyName && i + 3 < texts.size) {
                // Look ahead for rating, delivery time, fee in next few nodes
                val lookahead = texts.subList(i + 1, minOf(i + 6, texts.size))
                val rating = lookahead.firstOrNull { it.matches(Regex("\\d\\.\\d.*")) } ?: ""
                val deliveryTime = lookahead.firstOrNull {
                    it.matches(Regex("\\d+[-–]\\d+\\s*min.*", RegexOption.IGNORE_CASE))
                } ?: ""
                val feeText = lookahead.firstOrNull {
                    it.contains("delivery", ignoreCase = true)
                } ?: ""
                val fee = Regex("₹(\\d+)").find(feeText)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                val discount = lookahead.firstOrNull {
                    it.contains("% off", ignoreCase = true) ||
                            it.contains("flat ₹", ignoreCase = true)
                } ?: ""

                if (rating.isNotEmpty() || deliveryTime.isNotEmpty()) {
                    items.add(RestaurantItem(text, fee, deliveryTime, rating, discount))
                }
            }
            i++
        }

        return items.take(10) // cap at 10 results
    }

    private fun parseCoupons(texts: List<String>): List<String> {
        val coupons = mutableListOf<String>()
        val couponPatterns = listOf(
            Regex("[A-Z]{4,12}\\d*"),          // e.g. SWIGGY50, FLAT200
            Regex("USE\\s+[A-Z0-9]+"),          // e.g. USE FIRSTORDER
            Regex("APPLY\\s+[A-Z0-9]+")         // e.g. APPLY SAVE100
        )
        for (text in texts) {
            for (pattern in couponPatterns) {
                val match = pattern.find(text)
                if (match != null && match.value.length >= 4) {
                    val code = match.value.replace("USE ", "").replace("APPLY ", "").trim()
                    if (!coupons.contains(code)) coupons.add(code)
                }
            }
        }
        return coupons.take(5)
    }

    private fun parseBanners(texts: List<String>): List<String> {
        return texts.filter { text ->
            (text.contains("% off", ignoreCase = true) ||
                    text.contains("flat ₹", ignoreCase = true) ||
                    text.contains("free delivery", ignoreCase = true) ||
                    text.contains("save ₹", ignoreCase = true)) &&
                    text.length < 60
        }.take(5)
    }

    private fun broadcastData(data: AppScreenData) {
        val json = JSONObject().apply {
            put("app", data.app)
            put("scrapedAt", data.scrapedAt)
            put("restaurants", JSONArray().apply {
                data.restaurants.forEach { r ->
                    put(JSONObject().apply {
                        put("name", r.name)
                        put("deliveryFee", r.deliveryFee)
                        put("deliveryTime", r.deliveryTime)
                        put("rating", r.rating)
                        put("discount", r.discount)
                    })
                }
            })
            put("coupons", JSONArray(data.coupons))
            put("banners", JSONArray(data.banners))
        }

        val intent = Intent(ACTION_FOOD_DATA).apply {
            putExtra(EXTRA_JSON, json.toString())
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    override fun onInterrupt() {}
}
