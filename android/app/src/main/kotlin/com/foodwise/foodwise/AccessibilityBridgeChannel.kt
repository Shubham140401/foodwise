package com.foodwise.foodwise

import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class AccessibilityBridgeChannel(
    private val context: Context,
    flutterEngine: FlutterEngine
) {
    companion object {
        const val CHANNEL = "com.foodwise/accessibility"
    }

    private var receiver: BroadcastReceiver? = null
    private var orderReceiver: BroadcastReceiver? = null
    private var scrapeReceiver: BroadcastReceiver? = null
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(isAccessibilityEnabled())
                "openSettings" -> {
                    openAccessibilitySettings()
                    result.success(null)
                }
                "getLatestData" -> {
                    val app = call.argument<String>("app")
                    val data = if (app != null)
                        FoodwiseAccessibilityService.latestData[app]
                    else null
                    result.success(data?.let { serializeData(it) })
                }
                "getAllLatestData" -> {
                    val all = FoodwiseAccessibilityService.latestData.values.map { serializeData(it) }
                    result.success(all)
                }
                "scrapeApps" -> {
                    val apps = call.argument<List<String>>("apps") ?: listOf("Swiggy", "Zomato")
                    val svc = FoodwiseAccessibilityService.instance
                    if (svc != null) {
                        svc.startScrapeSequence(apps, context.packageName)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isUsageStatsGranted" -> {
                    try {
                        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            appOps.unsafeCheckOpNoThrow(
                                AppOpsManager.OPSTR_GET_USAGE_STATS,
                                Process.myUid(),
                                context.packageName
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            appOps.checkOpNoThrow(
                                AppOpsManager.OPSTR_GET_USAGE_STATS,
                                Process.myUid(),
                                context.packageName
                            )
                        }
                        result.success(mode == AppOpsManager.MODE_ALLOWED)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openUsageStatsSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        // On Android 10+ we can deep-link directly to our app's entry.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            data = Uri.parse("package:${context.packageName}")
                        }
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(null)
                }
                "searchAndScrape" -> {
                    // Opens each app, navigates to search for the given query,
                    // reads food item results, then returns to foodwise.
                    val query = call.argument<String>("query") ?: ""
                    val apps = call.argument<List<String>>("apps") ?: listOf("Swiggy", "Zomato")
                    val svc = FoodwiseAccessibilityService.instance
                    if (svc != null && query.isNotEmpty()) {
                        svc.startSearchScrape(query, apps, context.packageName)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "clearCache" -> {
                    FoodwiseAccessibilityService.latestData.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun startListening() {
        // Live screen data from Swiggy/Zomato
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val json = intent?.getStringExtra(FoodwiseAccessibilityService.EXTRA_JSON) ?: return
                channel.invokeMethod("onFoodData", json)
            }
        }
        registerReceiver(receiver, IntentFilter(FoodwiseAccessibilityService.ACTION_FOOD_DATA))

        // Order placed confirmation
        orderReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val app = intent?.getStringExtra(FoodwiseAccessibilityService.EXTRA_APP) ?: return
                val ts = intent.getLongExtra(
                    FoodwiseAccessibilityService.EXTRA_TIMESTAMP,
                    System.currentTimeMillis()
                )
                channel.invokeMethod("onOrderConfirmed", mapOf("app" to app, "timestamp" to ts))
            }
        }
        registerReceiver(orderReceiver, IntentFilter(FoodwiseAccessibilityService.ACTION_ORDER_CONFIRMED))

        // Auto-scrape sequence completed
        scrapeReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                channel.invokeMethod("onScrapeDone", null)
            }
        }
        registerReceiver(scrapeReceiver, IntentFilter(FoodwiseAccessibilityService.ACTION_SCRAPE_DONE))
    }

    fun stopListening() {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
        orderReceiver?.let { context.unregisterReceiver(it) }
        orderReceiver = null
        scrapeReceiver?.let { context.unregisterReceiver(it) }
        scrapeReceiver = null
    }

    private fun registerReceiver(receiver: BroadcastReceiver?, filter: IntentFilter) {
        receiver ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(
            "${context.packageName}/${FoodwiseAccessibilityService::class.java.name}"
        )
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(intent)
    }

    private fun serializeData(data: FoodwiseAccessibilityService.AppScreenData): Map<String, Any> =
        mapOf(
            "app" to data.app,
            "scrapedAt" to data.scrapedAt,
            "restaurants" to data.restaurants.map {
                mapOf(
                    "name" to it.name,
                    "deliveryFee" to it.deliveryFee,
                    "deliveryTime" to it.deliveryTime,
                    "rating" to it.rating,
                    "discount" to it.discount
                )
            },
            "foodItems" to data.foodItems.map {
                mapOf(
                    "name" to it.name,
                    "restaurant" to it.restaurant,
                    "price" to it.price,
                    "rating" to it.rating,
                    "deliveryTime" to it.deliveryTime,
                    "deliveryFee" to it.deliveryFee,
                    "discount" to it.discount
                )
            },
            "coupons" to data.coupons,
            "banners" to data.banners
        )
}
