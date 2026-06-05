package com.foodwise.foodwise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
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
                else -> result.notImplemented()
            }
        }
    }

    fun startListening() {
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val json = intent?.getStringExtra(FoodwiseAccessibilityService.EXTRA_JSON) ?: return
                channel.invokeMethod("onFoodData", json)
            }
        }
        val filter = IntentFilter(FoodwiseAccessibilityService.ACTION_FOOD_DATA)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }

        orderReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val app = intent?.getStringExtra(FoodwiseAccessibilityService.EXTRA_APP) ?: return
                val ts = intent.getLongExtra(FoodwiseAccessibilityService.EXTRA_TIMESTAMP, System.currentTimeMillis())
                channel.invokeMethod("onOrderConfirmed", mapOf("app" to app, "timestamp" to ts))
            }
        }
        val orderFilter = IntentFilter(FoodwiseAccessibilityService.ACTION_ORDER_CONFIRMED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(orderReceiver, orderFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(orderReceiver, orderFilter)
        }
    }

    fun stopListening() {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
        orderReceiver?.let { context.unregisterReceiver(it) }
        orderReceiver = null
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains("${context.packageName}/${FoodwiseAccessibilityService::class.java.name}")
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
            "coupons" to data.coupons,
            "banners" to data.banners
        )
}
