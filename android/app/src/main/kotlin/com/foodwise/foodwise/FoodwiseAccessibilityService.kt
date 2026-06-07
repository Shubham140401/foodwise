package com.foodwise.foodwise

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

class FoodwiseAccessibilityService : AccessibilityService() {

    companion object {
        private val FOOD_APPS = mapOf(
            "in.swiggy.android" to "Swiggy",
            "com.application.zomato" to "Zomato"
            // Blinkit disabled until scraping is stable on Swiggy + Zomato
        )

        const val ACTION_FOOD_DATA = "com.foodwise.FOOD_DATA"
        const val ACTION_ORDER_CONFIRMED = "com.foodwise.ORDER_CONFIRMED"
        const val ACTION_SCRAPE_DONE = "com.foodwise.SCRAPE_DONE"
        const val EXTRA_JSON = "json"
        const val EXTRA_APP = "app"
        const val EXTRA_TIMESTAMP = "timestamp"

        // 10 s per app for home-page scrape; 35 s for search (click → load → 3-pass scroll)
        private const val SCRAPE_DWELL_MS = 10_000L
        private const val SEARCH_DWELL_MS = 90_000L

        val latestData = mutableMapOf<String, AppScreenData>()
        var instance: FoodwiseAccessibilityService? = null

        private val ORDER_CONFIRMATION_STRINGS = mapOf(
            "Swiggy" to listOf(
                "order placed", "your order has been placed",
                "order is confirmed", "your order is confirmed",
                "arriving in", "out for delivery", "order accepted"
            ),
            "Zomato" to listOf(
                "order placed", "order confirmed", "your order is confirmed",
                "restaurant is preparing", "out for delivery",
                "order is on its way", "rider is on the way"
            ),
            "Blinkit" to listOf(
                "order placed", "order confirmed", "your order is confirmed",
                "store is picking", "out for delivery"
            )
        )

        private val lastConfirmedAt = mutableMapOf<String, Long>()
        private const val CONFIRM_DEBOUNCE_MS = 5 * 60 * 1000L
    }

    data class FoodItemData(
        val name: String,
        val restaurant: String,
        val price: Int,          // effective (discounted) menu price
        val originalPrice: Int,  // struck-out price if the item is discounted, else == price
        val rating: String,
        val deliveryTime: String,
        val deliveryFee: Int,
        val discount: String
    )

    data class AppScreenData(
        val app: String,
        val restaurants: List<RestaurantItem>,
        val foodItems: List<FoodItemData>,   // populated during search scrape
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

    // ── Scrape sequence state ────────────────────────────────────────────────

    private val scrapeHandler = Handler(Looper.getMainLooper())
    private val scrapeQueue = ArrayDeque<String>()
    private var scraping = false
    private var callerPackageName: String? = null

    // Keeps the screen on (and unlocked-as-it-already-is) for the whole scrape.
    // Without this the display timeout fires mid-scrape — injected dispatchGesture
    // taps do NOT count as user activity, so ~30 s in the screen locks and every
    // subsequent tap/paste hits the keyguard. Acquired in _startSequence, released
    // when the queue drains (and in onDestroy as a safety net).
    private var scrapeWakeLock: PowerManager.WakeLock? = null

    // When non-empty the service navigates to search results for this query
    // instead of reading the home page.
    private var searchQuery: String = ""

    // Package name of the app currently being scraped (e.g. "in.swiggy.android").
    // Only events from this package should trigger search-fill logic, so that
    // background food apps (Blinkit still open) don't interfere.
    private var currentScrapePackage: String? = null

    // Tracks whether we've already filled the search box for the current app
    private var searchFilled = false
    // True after we've clicked the fake-search container and are waiting for the
    // real search screen to appear. Prevents rapid re-clicking before the window
    // state change fires.
    private var containerClicked = false
    // True after text has been injected into the search field, so we don't spam
    // clipboard/paste on every subsequent event.
    private var textInjected = false

    // Items accumulated across scroll passes for the current search app
    private val collectedFoodItems = mutableListOf<FoodItemData>()
    // Offers/coupons seen across all scroll passes (order-preserving union).
    private val collectedCoupons = linkedSetOf<String>()
    private val collectedBanners = linkedSetOf<String>()
    private var scrollPass = 0
    private var noGrowthPasses = 0
    // Offers carousel sweep state (the strip auto-rotates and loops circularly).
    private var carouselSwipes = 0
    private val seenPagerIndices = mutableSetOf<Int>()
    // The strip auto-rotates ~every 4s; this many polls covers a full 5-card loop.
    private val MAX_CAROUSEL_SWIPES = 24
    // Safety cap; normally we stop earlier — when the menu reaches its end.
    private val MAX_SCROLL_PASSES = 25
    // Name of the restaurant we drilled into (Swiggy). On a single-restaurant menu
    // page the restaurant is known, so we tag every scraped dish with it instead of
    // guessing from look-ahead text (which produced wrong values like a dish name).
    private var currentRestaurantName: String = ""

    fun startScrapeSequence(appNames: List<String>, callerPkg: String? = null) {
        if (scraping) return
        searchQuery = ""
        _startSequence(appNames, callerPkg)
    }

    fun startSearchScrape(query: String, appNames: List<String>, callerPkg: String? = null) {
        if (scraping) return
        searchQuery = query.trim()
        _startSequence(appNames, callerPkg)
    }

    // Acquires a screen-bright wake lock so the display can't time out during the
    // scrape. SCREEN_BRIGHT_WAKE_LOCK is deprecated but is the only reliable way for
    // a background service to keep the screen on; fine for a personal app.
    @Suppress("DEPRECATION")
    private fun acquireScrapeWakeLock() {
        if (scrapeWakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "foodwise:scrape"
            )
            wl.setReferenceCounted(false)
            // Safety timeout so a crashed scrape can never pin the screen on forever.
            wl.acquire(3 * 60 * 1000L)
            scrapeWakeLock = wl
            Log.d("FoodwiseScrape", "wakeLock: acquired (screen kept on for scrape)")
        } catch (e: Exception) {
            Log.d("FoodwiseScrape", "wakeLock: acquire failed ${e.message}")
        }
    }

    private fun releaseScrapeWakeLock() {
        try {
            if (scrapeWakeLock?.isHeld == true) {
                scrapeWakeLock?.release()
                Log.d("FoodwiseScrape", "wakeLock: released")
            }
        } catch (_: Exception) {}
        scrapeWakeLock = null
    }

    private fun _startSequence(appNames: List<String>, callerPkg: String?) {
        callerPackageName = callerPkg
        scraping = true
        acquireScrapeWakeLock()
        scrapeQueue.clear()
        scrapeQueue.addAll(
            appNames.mapNotNull { name ->
                FOOD_APPS.entries.firstOrNull { it.value == name }?.key
            }
        )
        launchNextScrapeApp()
    }

    private fun launchNextScrapeApp() {
        if (scrapeQueue.isEmpty()) {
            scraping = false
            searchQuery = ""
            releaseScrapeWakeLock()
            val returnPkg = callerPackageName ?: packageName
            val relaunch = packageManager.getLaunchIntentForPackage(returnPkg)
            if (relaunch != null) {
                relaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                startActivity(relaunch)
            } else {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
            callerPackageName = null
            sendBroadcast(Intent(ACTION_SCRAPE_DONE).apply { setPackage(packageName) })
            return
        }

        val pkg = scrapeQueue.removeFirst()
        currentScrapePackage = pkg
        searchFilled = false
        containerClicked = false
        textInjected = false
        currentRestaurantName = ""
        carouselSwipes = 0
        seenPagerIndices.clear()
        collectedFoodItems.clear()
        scrollPass = 0

        val launchIntent = packageManager.getLaunchIntentForPackage(pkg) ?: run {
            launchNextScrapeApp()
            return
        }
        // FLAG_ACTIVITY_CLEAR_TOP brings the app to the front and clears any
        // deep-navigation back-stack, so we always land on the home screen — not a
        // previous order detail or restaurant page that may have been left open.
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        )
        startActivity(launchIntent)

        val dwell = if (searchQuery.isNotEmpty()) SEARCH_DWELL_MS else SCRAPE_DWELL_MS
        scrapeHandler.postDelayed({ launchNextScrapeApp() }, dwell)
    }

    // ── AccessibilityService lifecycle ───────────────────────────────────────

    override fun onServiceConnected() {
        instance = this
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

    override fun onDestroy() {
        instance = null
        scrapeHandler.removeCallbacksAndMessages(null)
        releaseScrapeWakeLock()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        val appName = FOOD_APPS[pkg] ?: return

        // Once text injection is underway, skip ALL tree traversal so the main
        // thread stays free and the postDelayed paste/scroll callbacks fire on time.
        // Without this, constant accessibility events flood the handler and delay
        // a 300ms postDelayed callback by 20+ seconds.
        if (scraping && searchQuery.isNotEmpty() && textInjected &&
            pkg == currentScrapePackage) return

        val root = rootInActiveWindow ?: return
        val allText = mutableListOf<String>()
        collectAllText(root, allText)

        if (isOrderConfirmation(appName, allText)) broadcastOrderConfirmed(appName)

        if (scraping && searchQuery.isNotEmpty() && !searchFilled &&
            pkg == currentScrapePackage) {
            if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                // New window just appeared — wait 500 ms for it to fully render
                // before trying to fill the search field.
                scrapeHandler.postDelayed({
                    val r = rootInActiveWindow ?: return@postDelayed
                    val filled = tryFillSearchField(r, searchQuery)
                    r.recycle()
                    if (filled) {
                        searchFilled = true
                        scheduleScrollAndCollect(appName)
                    }
                }, 500)
            } else {
                val filled = tryFillSearchField(root, searchQuery)
                if (filled) {
                    searchFilled = true
                    scheduleScrollAndCollect(appName)
                }
            }
        }

        val data = scrapeScreen(appName, root, allText)
        root.recycle()

        // Broadcast home-page data (restaurants / coupons) only when not in search mode
        if (searchQuery.isEmpty() &&
            (data.restaurants.isNotEmpty() || data.coupons.isNotEmpty())) {
            latestData[appName] = data
            broadcastData(data)
        }
    }

    // ── Search field navigation ──────────────────────────────────────────────

    // Two-stage search:
    // Stage 1 — no EditText visible yet (home screen): click the search container,
    //            return false so we retry on the next window-state-changed event.
    // Stage 2 — EditText is visible (search screen opened): fill it and submit.
    // Zomato / Swiggy search placeholder phrases that mean "we're on the search screen".
    private val SEARCH_SCREEN_HINTS = listOf(
        "type to search", "type here to search", "search for restaurants",
        "search restaurants or dishes", "search dishes", "search for dishes"
    )

    private fun tryFillSearchField(root: AccessibilityNodeInfo, query: String): Boolean {
        // ── Stage 2a: a visible editable field is already present ─────────────
        // Route through the robust injection chain (SET_TEXT → focus-then-paste →
        // IME typing) rather than SET_TEXT alone: Swiggy & Zomato are React Native
        // and reject ACTION_SET_TEXT, so SET_TEXT-only silently typed nothing.
        // injectTextIntoAppWindow drives focus + paste and triggers scroll-collect
        // itself once the text lands, so we set textInjected and return false here.
        val editText = findSearchEditText(root)
        if (editText != null) {
            editText.recycle()
            if (!textInjected) {
                Log.d("FoodwiseScrape", "tryFillSearchField: visible EditText present, injecting via robust chain")
                injectTextIntoAppWindow(query)
                textInjected = true
            }
            return false
        }

        // ── Stage 2b: search screen is open but EditText needs a tap to focus ─
        // Detected when a "type to search…" placeholder is visible as regular text.
        val allText = mutableListOf<String>()
        collectAllText(root, allText)
        val allLower = allText.joinToString(" ").lowercase()
        val onSearchScreen = SEARCH_SCREEN_HINTS.any { allLower.contains(it) }
        Log.d("FoodwiseScrape", "tryFillSearchField: onSearchScreen=$onSearchScreen text=${allText.take(6)}")

        if (onSearchScreen) {
            if (!textInjected) {
                // Short-cut: if the exact query appears as a recent-search chip,
                // tap it — results load immediately and we can scroll.
                // Note: the text leaf node is often NOT isClickable; the clickable
                // wrapper is a parent. So we don't filter by isClickable — we just
                // find any node matching the text and tap its screen coordinates.
                val suggestions = root.findAccessibilityNodeInfosByText(query) ?: emptyList()
                val suggestion = suggestions.firstOrNull { n ->
                    val t = (n.text?.toString()?.trim()
                        ?: n.contentDescription?.toString()?.trim() ?: "").lowercase()
                    t == query.lowercase()
                }
                if (suggestion != null) {
                    val b = Rect()
                    suggestion.getBoundsInScreen(b)
                    if (b.width() > 0 && b.height() > 0) {
                        Log.d("FoodwiseScrape", "tapping recent suggestion '$query' at (${b.centerX()},${b.centerY()})")
                        tapAt(b.centerX().toFloat(), b.centerY().toFloat())
                        suggestions.forEach { it.recycle() }
                        textInjected = true
                        return true
                    }
                }
                suggestions.forEach { it.recycle() }
                injectTextIntoAppWindow(query)
                textInjected = true
            }
            return false
        }

        // ── Stage 1: home screen — tap the fake search bar to open search screen ─
        if (!containerClicked) {
            val container = findSearchContainer(root)
            if (container != null) {
                val bounds = Rect()
                container.getBoundsInScreen(bounds)
                Log.d("FoodwiseScrape", "tryFillSearchField: tapping container " +
                    "class=${container.className} text='${container.text}' " +
                    "desc='${container.contentDescription}' top=${bounds.top} h=${bounds.height()}")
                // Use dispatchGesture (physical tap) so canvas-drawn search bars
                // (e.g. Swiggy's React Native UI) also receive the touch event.
                tapAt(bounds.centerX().toFloat(), bounds.centerY().toFloat())
                container.recycle()
                containerClicked = true
                // Safety net: if the search screen doesn't appear within 6 s, reset
                // the flag so the next event can attempt another tap. Swiggy sometimes
                // needs a second tap if the first gesture landed on the wrong layer.
                scrapeHandler.postDelayed({
                    // Only retry the container tap if we're still on the home screen
                    // (text not yet injected). If we're already on the search screen,
                    // resetting containerClicked would cause a spurious second tap that
                    // could dismiss the keyboard.
                    if (!searchFilled && containerClicked && !textInjected) {
                        Log.d("FoodwiseScrape", "tryFillSearchField: retry — resetting containerClicked after 6 s with no result")
                        containerClicked = false
                    }
                }, 6_000)
            } else {
                Log.d("FoodwiseScrape", "tryFillSearchField: no container found on this screen")
            }
        }
        return false
    }

    // Injects [query] into the search field of the food app currently being scraped.
    // Uses ACTION_SET_TEXT on the app's window root — intentionally avoids the
    // keyboard window so we never accidentally type into the IME's own input field.
    private fun injectTextIntoAppWindow(query: String) {
        scrapeHandler.postDelayed({
            // Find the food app's window (not the keyboard).
            val appRoot: AccessibilityNodeInfo? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    windows
                        ?.filter { w -> w.root?.packageName?.toString() == currentScrapePackage }
                        ?.mapNotNull { w -> w.root }
                        ?.firstOrNull()
                } else {
                    rootInActiveWindow
                }
            if (appRoot == null) {
                Log.d("FoodwiseScrape", "injectText: no app window found for $currentScrapePackage")
                return@postDelayed
            }
            Log.d("FoodwiseScrape", "injectText: searching in window pkg=${appRoot.packageName}")

            // Try ACTION_SET_TEXT on the first editable node.
            val editText = findSearchEditText(appRoot)
            if (editText != null) {
                val args = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, query)
                }
                val ok = editText.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                Log.d("FoodwiseScrape", "injectText: SET_TEXT on ${editText.className} result=$ok")
                editText.recycle()
                if (ok) {
                    val appName = FOOD_APPS[currentScrapePackage]
                    if (appName != null) onSearchTextEntered(appName)
                    appRoot.recycle()
                    return@postDelayed
                }
            }
            // No editable node via isEditable — try the input-focused node which may
            // be a custom EditText that doesn't report isEditable=true.
            val allText2 = mutableListOf<String>()
            collectAllText(appRoot, allText2)
            Log.d("FoodwiseScrape", "injectText: no editable EditText, screen=${allText2.take(6)}")

            val focused = appRoot.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focused != null) {
                Log.d("FoodwiseScrape", "injectText: focused class=${focused.className} editable=${focused.isEditable}")
                // Try SET_TEXT first — works on React Native TextInput and custom views.
                val args = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, query)
                }
                val setOk = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                Log.d("FoodwiseScrape", "injectText: SET_TEXT on focused result=$setOk")
                focused.recycle()
                if (setOk) {
                    val appName = FOOD_APPS[currentScrapePackage]
                    if (appName != null) onSearchTextEntered(appName)
                    appRoot.recycle()
                    return@postDelayed
                }
                // SET_TEXT failed (React Native blocks it). Fall back to a
                // focus-then-paste: tap the visible search field to force input
                // focus, fire system PASTE, then verify the text actually landed
                // (retrying once) before resorting to coordinate key typing. This
                // fixes Zomato pasting into the wrong focused node ("above the keyboard").
                Log.d("FoodwiseScrape", "injectText: SET_TEXT blocked, using focus-then-paste")
                appRoot.recycle()
                pasteWithFocus(query, 0)
                return@postDelayed
            } else {
                Log.d("FoodwiseScrape", "injectText: no focused node — tapping search area to focus")
                val sh = screenHeight
                tapAt(540f, sh * 0.17f)
                textInjected = false        // allow one more attempt
            }
            appRoot.recycle()
        }, 500)
    }

    // Returns the food app's window root (not the keyboard window), or the active
    // window root on pre-Lollipop. Caller owns the returned node and must recycle it.
    private fun appWindowRoot(): AccessibilityNodeInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            windows
                ?.filter { w -> w.root?.packageName?.toString() == currentScrapePackage }
                ?.mapNotNull { w -> w.root }
                ?.firstOrNull()
        } else {
            rootInActiveWindow
        }

    // True if the app's visible search field (or the input-focused node) currently
    // contains [query]. Used to confirm a paste actually landed in the right place.
    private fun searchFieldContains(query: String): Boolean {
        val root = appWindowRoot() ?: return false
        var found = false
        val field = findSearchEditText(root)
        if (field != null) {
            val t = field.text?.toString()?.trim() ?: ""
            if (t.isNotEmpty() && t.contains(query, ignoreCase = true)) found = true
            field.recycle()
        }
        if (!found) {
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focused != null) {
                val t = focused.text?.toString()?.trim() ?: ""
                if (t.isNotEmpty() && t.contains(query, ignoreCase = true)) found = true
                focused.recycle()
            }
        }
        root.recycle()
        return found
    }

    // Focus-then-paste: tap the visible search field to force input focus, set the
    // clipboard, fire system-level PASTE, then verify the text landed. Retries once
    // with a fresh focus tap before falling back to coordinate key typing. This is
    // the reliable path for React Native fields (Zomato) where ACTION_SET_TEXT fails.
    private fun pasteWithFocus(query: String, attempt: Int) {
        if (searchFilled) return

        // 1. Locate the visible search field and tap it to force input focus.
        val appRoot = appWindowRoot()
        val focusBounds = Rect()
        var haveBounds = false
        val field = appRoot?.let { findSearchEditText(it) }
        if (field != null) {
            field.getBoundsInScreen(focusBounds)
            if (focusBounds.width() > 0 && focusBounds.height() > 0) haveBounds = true
            field.recycle()
        }
        if (!haveBounds) {
            val focused = appRoot?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focused != null) {
                focused.getBoundsInScreen(focusBounds)
                if (focusBounds.width() > 0 && focusBounds.height() > 0) haveBounds = true
                focused.recycle()
            }
        }
        appRoot?.recycle()

        if (haveBounds) {
            Log.d("FoodwiseScrape", "pasteWithFocus[$attempt]: tapping search field at (${focusBounds.centerX()},${focusBounds.centerY()})")
            tapAt(focusBounds.centerX().toFloat(), focusBounds.centerY().toFloat())
        } else {
            Log.d("FoodwiseScrape", "pasteWithFocus[$attempt]: no field bounds, tapping default top area")
            tapAt(screenWidth * 0.5f, screenHeight * 0.12f)
        }

        // 2. After focus settles, set the clipboard and fire system PASTE.
        scrapeHandler.postDelayed({
            if (searchFilled) return@postDelayed
            try {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("q", query))
            } catch (_: Exception) {}
            // GLOBAL_ACTION_PASTE = 8, available since API 31 (Android 12).
            val pasteOk = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                performGlobalAction(8)
            } else false
            Log.d("FoodwiseScrape", "pasteWithFocus[$attempt]: global PASTE result=$pasteOk")

            // 3. Verify the text actually landed before declaring success.
            scrapeHandler.postDelayed({
                if (searchFilled) return@postDelayed
                val landed = searchFieldContains(query)
                Log.d("FoodwiseScrape", "pasteWithFocus[$attempt]: verify landed=$landed")
                if (landed) {
                    val appName = FOOD_APPS[currentScrapePackage]
                    if (appName != null) {
                        searchFilled = true
                        scheduleScrollAndCollect(appName)
                    }
                    submitSearch()
                } else if (attempt < 1) {
                    pasteWithFocus(query, attempt + 1)
                } else {
                    Log.d("FoodwiseScrape", "pasteWithFocus: paste failed twice, falling back to IME key typing")
                    typeViaImeKeys(query)
                }
            }, 450)
        }, 350)
    }

    // Called the moment query text is confirmed in the field. Kicks off scroll
    // collection and submits the query. We submit quickly (200 ms) so the app loads
    // results before a React Native re-render can wipe programmatically-set text
    // (the "pizza vanished" symptom on Swiggy). Idempotent via searchFilled.
    private fun onSearchTextEntered(appName: String) {
        if (searchFilled) return
        searchFilled = true
        // Commit the search (press Enter) so the dropdown / results render.
        scrapeHandler.postDelayed({
            if (!submitViaImeEnter()) submitSearch()
        }, 200)
        // Swiggy drill-in: tap top dropdown suggestion → 1st restaurant → scrape its
        // menu. Other apps just scroll-collect the results page.
        if (appName == "Swiggy") {
            startSwiggyDrillIn(appName, searchQuery)
        } else {
            scheduleScrollAndCollect(appName)
        }
    }

    // Presses the IME "enter/search" action on the editable field — the reliable
    // way to commit a search (equivalent to tapping the keyboard's enter key).
    // ACTION_IME_ENTER is API 30+. Returns true if it was dispatched.
    private fun submitViaImeEnter(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val root = appWindowRoot() ?: return false
        val field = findSearchEditText(root)
            ?: root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        var ok = false
        if (field != null) {
            ok = field.performAction(
                AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id
            )
            Log.d("FoodwiseScrape", "submit: IME_ENTER result=$ok")
            field.recycle()
        }
        root.recycle()
        return ok
    }

    // Submits the current search: clicks the app's submit button if present,
    // otherwise taps the keyboard's Search/Enter key.
    private fun submitSearch() {
        scrapeHandler.postDelayed({
            val r = rootInActiveWindow ?: return@postDelayed
            val btn = findSearchSubmitButton(r)
            if (btn != null) {
                btn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                btn.recycle()
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val imeWin = windows?.firstOrNull { w ->
                    w.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD
                }?.root
                if (imeWin != null) {
                    val enter = imeWin.findAccessibilityNodeInfosByText("Search")
                        ?.firstOrNull { n -> n.isClickable }
                        ?: imeWin.findAccessibilityNodeInfosByText("search")
                            ?.firstOrNull { n -> n.isClickable }
                    enter?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    enter?.recycle()
                    imeWin.recycle()
                }
            }
            r.recycle()
        }, 500)
    }

    // Types [query] by tapping each character key on the on-screen IME keyboard.
    // Works regardless of the app's text-injection security because it produces
    // real touch events at the keyboard key positions.
    private fun typeViaImeKeys(query: String, charIndex: Int = 0) {
        if (charIndex >= query.length) {
            // All chars typed — trigger scroll collection then submit.
            val kbAppName = FOOD_APPS[currentScrapePackage]
            if (kbAppName != null && !searchFilled) {
                searchFilled = true
                scheduleScrollAndCollect(kbAppName)
            }
            scrapeHandler.postDelayed({
                val r = rootInActiveWindow ?: return@postDelayed
                val btn = findSearchSubmitButton(r)
                if (btn != null) {
                    btn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    btn.recycle()
                } else {
                    val imeWin = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        windows?.firstOrNull { w ->
                            w.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD
                        }?.root
                    } else null
                    if (imeWin != null) {
                        val enter = imeWin.findAccessibilityNodeInfosByText("Search")
                            ?.firstOrNull { n -> n.isClickable }
                            ?: imeWin.findAccessibilityNodeInfosByText("search")
                                ?.firstOrNull { n -> n.isClickable }
                        enter?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        enter?.recycle()
                        imeWin.recycle()
                    }
                }
                r.recycle()
            }, 400)
            return
        }
        val ch = query[charIndex].lowercaseChar().toString()
        val chUp = ch.uppercase()
        // Find the keyboard window.
        val imeRoot = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            windows?.firstOrNull { w ->
                w.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD
            }?.root
        } else null

        var tapped = false
        if (imeRoot != null) {
            // Samsung keyboard labels keys with uppercase letters in the accessibility tree.
            // Try lowercase first, then uppercase, then contentDescription.
            val key = (imeRoot.findAccessibilityNodeInfosByText(ch) ?: emptyList())
                .plus(imeRoot.findAccessibilityNodeInfosByText(chUp) ?: emptyList())
                .firstOrNull { n ->
                    n.isClickable &&
                    (n.text?.toString()?.trim()?.let { it.equals(ch, ignoreCase = true) } == true ||
                     n.contentDescription?.toString()?.trim()?.let { it.equals(ch, ignoreCase = true) } == true)
                }
            if (key != null) {
                val b = Rect()
                key.getBoundsInScreen(b)
                Log.d("FoodwiseScrape", "typeViaIme: typing '$ch' via node at (${b.centerX()},${b.centerY()})")
                tapAt(b.centerX().toFloat(), b.centerY().toFloat())
                key.recycle()
                tapped = true
            }
            imeRoot.recycle()
        }

        if (!tapped) {
            // Coordinate fallback: Samsung keyboard key positions based on screen size.
            val coords = qwertyKeyCoords(ch)
            if (coords != null) {
                Log.d("FoodwiseScrape", "typeViaIme: typing '$ch' via coords (${coords.first.toInt()},${coords.second.toInt()})")
                tapAt(coords.first, coords.second)
            } else {
                Log.d("FoodwiseScrape", "typeViaIme: key '$ch' not in layout — skipping")
            }
        }
        // Schedule next character 200ms later (give more time per tap with coord method).
        scrapeHandler.postDelayed({ typeViaImeKeys(query, charIndex + 1) }, 200)
    }

    // Simulates a physical tap at (x, y) using GestureDescription (API 24+).
    // Falls back to nothing on older APIs (accessibility action click is the only option there).
    //
    // GestureDescription throws IllegalArgumentException ("Path bounds must not be
    // negative" / "must be within display bounds") for any off-screen coordinate, and
    // an uncaught throw here CRASHES the whole accessibility-service process — aborting
    // the scrape mid-run. Off-screen/zero bounds happen routinely: React Native apps
    // keep hidden measuring inputs with negative bounds. So we clamp to the display and
    // reject clearly-invalid taps, and wrap the dispatch defensively.
    private fun tapAt(x: Float, y: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val sw = screenWidth
        val sh = screenHeight
        if (sw <= 0 || sh <= 0) return
        // A center at (<=0, <=0) means the source node had empty/off-screen bounds —
        // not a real on-screen target. Skip rather than tap a meaningless point.
        if (x <= 0f && y <= 0f) {
            Log.d("FoodwiseScrape", "tapAt: skipping invalid coords ($x, $y)")
            return
        }
        val cx = x.coerceIn(1f, (sw - 1).toFloat())
        val cy = y.coerceIn(1f, (sh - 1).toFloat())
        try {
            val path = Path().apply { moveTo(cx, cy) }
            val stroke = GestureDescription.StrokeDescription(path, 0, 50)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            dispatchGesture(gesture, null, null)
            Log.d("FoodwiseScrape", "tapAt: gesture dispatched at ($cx, $cy)")
        } catch (e: Exception) {
            Log.d("FoodwiseScrape", "tapAt: gesture failed for ($cx, $cy): ${e.message}")
        }
    }

    private val screenWidth: Int by lazy {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            wm.currentWindowMetrics.bounds.width()
        } else {
            @Suppress("DEPRECATION")
            val dm = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getMetrics(dm)
            dm.widthPixels
        }
    }

    // Screen height used for position-based search bar detection.
    private val screenHeight: Int by lazy {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            wm.currentWindowMetrics.bounds.height()
        } else {
            @Suppress("DEPRECATION")
            val dm = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getMetrics(dm)
            dm.heightPixels
        }
    }

    // Uses isEditable — works for EditText, AutoCompleteTextView, and custom inputs.
    // Skips off-screen / zero-size phantom inputs: React Native apps (Swiggy, Zomato)
    // keep hidden measuring EditTexts with negative or empty bounds, which are not the
    // real search field and crash tapAt if we try to focus them. We only return a node
    // whose bounds are visible and on-screen.
    private fun findSearchEditText(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable) {
            val b = Rect()
            node.getBoundsInScreen(b)
            val sw = screenWidth
            val sh = screenHeight
            val onScreen = b.width() > 0 && b.height() > 0 &&
                b.left >= 0 && b.top >= 0 &&
                (sw <= 0 || b.right <= sw) && (sh <= 0 || b.top < sh)
            if (onScreen) {
                Log.d("FoodwiseScrape", "findSearchEditText HIT: class=${node.className} text='${node.text}' hint='${node.hintText}' bounds=$b")
                return node
            }
            Log.d("FoodwiseScrape", "findSearchEditText SKIP off-screen editable: class=${node.className} bounds=$b")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findSearchEditText(child)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    // Returns screen (x, y) for a QWERTY key, calibrated for Samsung keyboard on
    // Galaxy S20 (1080×2400 px). Used when accessibility tree doesn't expose key nodes.
    private fun qwertyKeyCoords(char: String): Pair<Float, Float>? {
        val sw = screenWidth.toFloat()
        val sh = screenHeight.toFloat()
        val r1 = sh * 0.643f   // row 1: Q-W-E-R-T-Y-U-I-O-P
        val r2 = sh * 0.728f   // row 2: A-S-D-F-G-H-J-K-L
        val r3 = sh * 0.813f   // row 3: Z-X-C-V-B-N-M
        return when (char.lowercase()) {
            "q" -> Pair(sw * 0.050f, r1); "w" -> Pair(sw * 0.150f, r1)
            "e" -> Pair(sw * 0.250f, r1); "r" -> Pair(sw * 0.350f, r1)
            "t" -> Pair(sw * 0.450f, r1); "y" -> Pair(sw * 0.550f, r1)
            "u" -> Pair(sw * 0.650f, r1); "i" -> Pair(sw * 0.750f, r1)
            "o" -> Pair(sw * 0.850f, r1); "p" -> Pair(sw * 0.950f, r1)
            "a" -> Pair(sw * 0.100f, r2); "s" -> Pair(sw * 0.200f, r2)
            "d" -> Pair(sw * 0.300f, r2); "f" -> Pair(sw * 0.400f, r2)
            "g" -> Pair(sw * 0.500f, r2); "h" -> Pair(sw * 0.600f, r2)
            "j" -> Pair(sw * 0.700f, r2); "k" -> Pair(sw * 0.800f, r2)
            "l" -> Pair(sw * 0.900f, r2)
            "z" -> Pair(sw * 0.200f, r3); "x" -> Pair(sw * 0.310f, r3)
            "c" -> Pair(sw * 0.420f, r3); "v" -> Pair(sw * 0.520f, r3)
            "b" -> Pair(sw * 0.630f, r3); "n" -> Pair(sw * 0.740f, r3)
            "m" -> Pair(sw * 0.840f, r3)
            else -> null
        }
    }

    // Finds the search bar on the home screen of Swiggy or Zomato.
    //
    // Strategy:
    //   Pass 1 — OS text search for "search" (case-insensitive). Swiggy shows
    //            "Search for cakes", "Search for biryani" etc.; Zomato shows
    //            "Search burger", "Search pasta" etc. Both contain the word "search"
    //            in their placeholder text. findAccessibilityNodeInfosByText does a
    //            full subtree scan and returns the LEAF node (the TextView), NOT the
    //            outer FrameLayout wrapper — so clicking it actually navigates.
    //   Pass 2 — Position-based fallback: any narrow, non-address, clickable bar in
    //            the top 22 % of the screen.
    private fun findSearchContainer(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // ── Pass 1: text-based ──────────────────────────────────────────────
        // We do NOT require isClickable: Swiggy/Zomato render the fake "Search for
        // '…'" bar as a React Native element whose clickable wrapper is an ancestor,
        // so the text node itself reports isClickable=false. We match the placeholder
        // text and tap its screen coordinates (the gesture still lands the touch).
        val candidates = root.findAccessibilityNodeInfosByText("search") ?: emptyList()
        val valid = candidates.filter { n ->
            val cls  = n.className?.toString() ?: ""
            val desc = n.contentDescription?.toString()?.lowercase() ?: ""
            val text = n.text?.toString()?.lowercase() ?: ""
            val combined = "$text $desc"
            val b = Rect().also { n.getBoundsInScreen(it) }
            val sh = screenHeight
            // Must mention "search", sit near the top, have real bounds, and not be
            // a voice/mic/address element. Exclude Instamart/grocery ("Search for
            // products") — typing "pizza" there returns groceries, not restaurant food.
            combined.contains("search") &&
                !cls.contains("ImageButton") && !cls.contains("ImageView") &&
                !desc.contains("voice") && !desc.contains("mic") &&
                !desc.contains("microphone") && !desc.contains("address") &&
                !desc.contains("delivering") && !desc.contains("location") &&
                !desc.contains("product") && !desc.contains("grocery") &&
                !desc.contains("instamart") && !desc.contains("genie") &&
                !text.contains("address") && !text.contains("deliver") &&
                !text.contains("product") && !text.contains("grocery") &&
                b.width() > 0 && b.height() > 0 &&
                (sh <= 0 || b.top < sh * 0.30)
        }
        // Prefer the topmost match — the primary food search bar sits at the very top,
        // above secondary bars (e.g. an Instamart card lower on the page).
        val byText = valid.minByOrNull { n ->
            Rect().also { n.getBoundsInScreen(it) }.top
        }
        if (byText != null) {
            val bounds = Rect()
            byText.getBoundsInScreen(bounds)
            Log.d("FoodwiseScrape", "findSearchContainer TEXT-MATCH: class=${byText.className} " +
                "text='${byText.text}' desc='${byText.contentDescription}' " +
                "top=${bounds.top} h=${bounds.height()}")
            // Recycle unselected candidates.
            candidates.forEach { if (it != byText) it.recycle() }
            return byText
        }
        candidates.forEach { it.recycle() }

        // ── Pass 2: position-based fallback ────────────────────────────────
        return findSearchContainerByPosition(root)
    }

    private fun findSearchContainerByPosition(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val className = node.className?.toString() ?: ""
        if (className.contains("ImageButton") || className.contains("ImageView")) return null

        val desc = node.contentDescription?.toString()?.lowercase() ?: ""
        if (desc.contains("voice") || desc.contains("mic") || desc.contains("microphone") ||
            desc.contains("address") || desc.contains("delivering") ||
            desc.contains("deliver to") || desc.contains("selected address") ||
            desc.contains("location") || desc.contains("pincode")) return null

        if (node.isClickable) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val sh = screenHeight
            val sw = screenWidth
            val isNearTop = sh > 0 && bounds.top < sh * 0.22
            val isNarrow  = sh > 0 && bounds.height() < sh * 0.09
            // A real search bar spans most of the width. Require >55% screen width so
            // we don't lock onto small near-top boxes (e.g. a 270px banner/toggle).
            val isWide    = sw > 0 && bounds.width() > sw * 0.55
            val text = node.text?.toString()?.lowercase() ?: ""
            val hint = node.hintText?.toString()?.lowercase() ?: ""
            if (text.contains("address") || text.contains("deliver") ||
                hint.contains("address") || hint.contains("deliver") ||
                text.contains("location") || hint.contains("location")) return null
            if (isNearTop && isNarrow && isWide) {
                Log.d("FoodwiseScrape", "findSearchContainer POS-MATCH: class=$className " +
                    "text='$text' desc='$desc' top=${bounds.top} h=${bounds.height()} w=${bounds.width()}")
                return node
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findSearchContainerByPosition(child)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    // Finds the submit / search button on the search screen (magnifier icon, "Search" label).
    private fun findSearchSubmitButton(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isClickable) {
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            val text = node.text?.toString()?.lowercase() ?: ""
            if (desc == "search" || text == "search" ||
                desc.contains("submit") || desc.contains("go") && desc.length < 10) return node
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findSearchSubmitButton(child)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    // ── Scroll-and-collect: reads items across multiple scroll passes ─────────

    // Called once after the search query is filled. Waits for results, then
    // reads items on 3 successive scroll passes to collect up to ~15 items.
    private fun scheduleScrollAndCollect(appName: String) {
        collectedFoodItems.clear()
        collectedCoupons.clear()
        collectedBanners.clear()
        scrollPass = 0
        noGrowthPasses = 0
        scrapeHandler.postDelayed({ doScrollAndCollect(appName) }, 2000)
    }

    private fun doScrollAndCollect(appName: String) {
        val root = rootInActiveWindow
        if (root == null) {
            Log.d("FoodwiseScrape", "collect[$appName] pass=$scrollPass: rootInActiveWindow=null, aborting")
            return
        }
        val allText = mutableListOf<String>()
        collectAllText(root, allText)
        Log.d("FoodwiseScrape", "collect[$appName] pass=$scrollPass: ${allText.size} text nodes")

        // Merge new items — avoid duplicates by name.
        val existing = collectedFoodItems.map { it.name }.toSet()
        val newItems = parseFoodItems(allText).filter { it.name !in existing }
        collectedFoodItems.addAll(newItems)
        if (newItems.isEmpty()) noGrowthPasses++ else noGrowthPasses = 0

        // Coupons come from the top offers carousel only (collected in
        // collectOfferCarousel, with their min-cart thresholds attached). The menu
        // body's per-item offer tags are noisy and threshold-less, so we don't add
        // them here — that's what caused offers to apply below their min-cart.
        Log.d("FoodwiseScrape", "collect[$appName] pass=$scrollPass: parsed items=${collectedFoodItems.size} banners=${collectedBanners.size}")

        if (collectedFoodItems.isNotEmpty()) {
            val updated = AppScreenData(
                app = appName,
                restaurants = latestData[appName]?.restaurants ?: emptyList(),
                // Send the whole menu (safety-capped); Dart ranks and keeps the top 30.
                foodItems = collectedFoodItems.take(80),
                coupons = collectedCoupons.toList(),
                banners = collectedBanners.toList()
            )
            latestData[appName] = updated
            broadcastData(updated)
        }

        // Scroll the ENTIRE menu to the end (RecyclerView/RN only exposes on-screen
        // nodes to accessibility, so off-screen dishes must be scrolled into view —
        // there is no way to read the full list without scrolling). Stop only at the
        // end (two passes with nothing new) or the safety cap. Ranking + the top-30
        // cut happen in Dart afterwards, so we collect everything here.
        val atEnd = noGrowthPasses >= 2
        if (!atEnd && scrollPass < MAX_SCROLL_PASSES) {
            scrollPass++
            val scrollable = findScrollable(root)
            scrollable?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            root.recycle()
            scrapeHandler.postDelayed({ doScrollAndCollect(appName) }, 1200)
        } else {
            Log.d("FoodwiseScrape", "collect[$appName]: done (items=${collectedFoodItems.size} atEnd=$atEnd pass=$scrollPass)")
            root.recycle()
        }
    }

    private fun findScrollable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findScrollable(child)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    // ── Swiggy drill-in navigation ────────────────────────────────────────────
    // After "pizza" + Enter, Swiggy shows an autocomplete dropdown. Flow:
    //   S1: tap the top dropdown suggestion (the dish) → opens a restaurant list
    //   S2: tap the 1st restaurant → opens its menu
    //   S3: scrape the menu items + coupons
    // Each stage logs the clickable elements it sees so we can calibrate selection.
    private fun startSwiggyDrillIn(appName: String, query: String) {
        // S1 — wait for the dropdown to render, then tap the top suggestion.
        scrapeHandler.postDelayed({
            val root = rootInActiveWindow
            if (root == null) { scheduleScrollAndCollect(appName); return@postDelayed }
            Log.d("FoodwiseScrape", "drillIn S1: dropdown clickables ↓")
            logClickables(root, "dropdown")
            val ok1 = tapTopSuggestion(root, query)
            Log.d("FoodwiseScrape", "drillIn S1: tapTopSuggestion=$ok1")
            root.recycle()

            // S2 — wait for the restaurant list, then tap the 1st restaurant.
            scrapeHandler.postDelayed({
                val r2 = rootInActiveWindow
                if (r2 == null) { scheduleScrollAndCollect(appName); return@postDelayed }
                Log.d("FoodwiseScrape", "drillIn S2: restaurant-list clickables ↓")
                logClickables(r2, "restaurants")
                val ok2 = tapFirstRestaurant(r2)
                Log.d("FoodwiseScrape", "drillIn S2: tapFirstRestaurant=$ok2")
                r2.recycle()

                // S3 — wait for the menu to render. First sweep the top offers
                // carousel for all price-based coupons, then scrape the menu items.
                scrapeHandler.postDelayed({
                    Log.d("FoodwiseScrape", "drillIn S3: collecting offer carousel")
                    collectOfferCarousel(appName)
                }, 2800)
            }, 3000)
        }, 1800)
    }

    // Sweeps the offers carousel at the top of a restaurant page. Swiggy shows
    // offer cards there with a "1/5 … 5/5" pager. We read the visible offer text,
    // swipe left to the next card, and repeat until the pager reaches its end (or
    // a safety cap). All offer text is unioned into collectedBanners; the Dart
    // rule engine parses out the price-based (non card/wallet) coupons.
    private fun collectOfferCarousel(appName: String) {
        val root = rootInActiveWindow
        if (root == null) { scheduleScrollAndCollect(appName); return }

        val texts = mutableListOf<String>()
        collectAllText(root, texts)
        // Combine the visible card's offer fragments into ONE string so the offer
        // and its "ABOVE ₹X" min-cart stay together (otherwise a bare "60% OFF"
        // becomes a no-threshold offer that wrongly applies to every item).
        val offerStr = carouselOfferString(root)
        if (offerStr.isNotBlank()) collectedBanners.add(offerStr)

        // Pager like "2/5" → current=2, total=5. The carousel auto-rotates and
        // loops (5→1), so we track which distinct cards we've seen rather than
        // chasing "current < total" (which never ends on a circular pager).
        val pager = texts.firstOrNull { it.matches(Regex("\\d+\\s*/\\s*\\d+")) }
        val current = pager?.substringBefore('/')?.trim()?.toIntOrNull() ?: 0
        val total = pager?.substringAfter('/')?.trim()?.toIntOrNull() ?: 0
        if (current > 0) seenPagerIndices.add(current)
        val foundY = findOfferRowY(root)
        val offerY = if (foundY > 0) foundY else screenHeight * 0.26f
        Log.d("FoodwiseScrape", "carousel poll=$carouselSwipes pager=$pager seen=$seenPagerIndices offer='${offerStr.take(60)}'")
        root.recycle()

        // Done once we've seen every card, or there's no pager (≤1 offer), or cap.
        val sawAll = total > 0 && seenPagerIndices.size >= total
        if (!sawAll && total > 0 && carouselSwipes < MAX_CAROUSEL_SWIPES) {
            carouselSwipes++
            swipeLeft(offerY)               // nudge forward; auto-rotate also helps
            scrapeHandler.postDelayed({ collectOfferCarousel(appName) }, 900)
        } else {
            Log.d("FoodwiseScrape", "carousel: done (polls=$carouselSwipes seen=$seenPagerIndices total=$total)")
            scheduleScrollAndCollect(appName)
        }
    }

    // Joins the offer fragments of the currently-visible carousel card (top half of
    // the screen) into a single string, e.g. "60% OFF UPTO ₹120 | ABOVE ₹159".
    // Only one card is on screen per poll, so all top-region offer text is one offer.
    private fun carouselOfferString(root: AccessibilityNodeInfo): String {
        val sh = screenHeight
        val parts = mutableListOf<String>()
        fun walk(n: AccessibilityNodeInfo) {
            val t = (n.text ?: n.contentDescription)?.toString()?.trim()
            if (!t.isNullOrBlank()) {
                val low = t.lowercase()
                if (low.contains("% off") || low.contains("flat ₹") ||
                    low.contains("upto ₹") || low.contains("above ₹") ||
                    low.contains("free del")) {
                    val b = Rect().also { n.getBoundsInScreen(it) }
                    if (b.top in 1 until (sh * 0.5).toInt() && t !in parts) parts.add(t)
                }
            }
            for (i in 0 until n.childCount) { val c = n.getChild(i) ?: continue; walk(c); c.recycle() }
        }
        walk(root)
        return parts.joinToString(" ")
    }

    // Y of the offers strip — the row holding an offer like "…% OFF" / "FLAT ₹…"
    // in the upper part of the screen. Returns -1 if no offer row is visible.
    private fun findOfferRowY(root: AccessibilityNodeInfo): Float {
        val sh = screenHeight
        var y = -1f
        fun walk(n: AccessibilityNodeInfo) {
            val t = n.text?.toString() ?: n.contentDescription?.toString()
            if (t != null && (t.contains("% off", true) || t.contains("flat ₹", true) ||
                    t.contains("upto ₹", true))) {
                val b = Rect().also { n.getBoundsInScreen(it) }
                if (b.top in 1 until (sh * 0.5).toInt() && b.width() > 0) {
                    if (y < 0 || b.centerY() < y) y = b.centerY().toFloat()
                }
            }
            for (i in 0 until n.childCount) { val c = n.getChild(i) ?: continue; walk(c); c.recycle() }
        }
        walk(root)
        return y
    }

    // Horizontal swipe (finger right→left) to advance a carousel by one card.
    // A slower, wider drag is recognised as a page swipe rather than a fling.
    private fun swipeLeft(y: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val sw = screenWidth
        if (sw <= 0 || y <= 0f) return
        try {
            val path = Path().apply { moveTo(sw * 0.92f, y); lineTo(sw * 0.08f, y) }
            val stroke = GestureDescription.StrokeDescription(path, 0, 450)
            dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
            Log.d("FoodwiseScrape", "swipeLeft at y=$y")
        } catch (e: Exception) { Log.d("FoodwiseScrape", "swipeLeft failed: ${e.message}") }
    }

    // Taps the topmost autocomplete suggestion matching [query], sitting below the
    // search field. Returns true if a suggestion was tapped.
    private fun tapTopSuggestion(root: AccessibilityNodeInfo, query: String): Boolean {
        val sh = screenHeight
        val matches = root.findAccessibilityNodeInfosByText(query) ?: emptyList()
        val pick = matches.mapNotNull { n ->
            val b = Rect().also { n.getBoundsInScreen(it) }
            if (b.width() > 0 && b.height() > 0 && b.top > sh * 0.10 && b.bottom < sh * 0.92) b else null
        }.minByOrNull { it.top }
        matches.forEach { it.recycle() }
        if (pick != null) {
            Log.d("FoodwiseScrape", "tapTopSuggestion: tapping at (${pick.centerX()},${pick.centerY()})")
            tapAt(pick.centerX().toFloat(), pick.centerY().toFloat())
            return true
        }
        return false
    }

    // Taps the topmost restaurant card. A card is a clickable node whose subtree
    // shows a rating (e.g. "4.3") plus a delivery-time / price / offer cue, below
    // the filter row. We tap by bounds so we never need to retain the node.
    private fun tapFirstRestaurant(root: AccessibilityNodeInfo): Boolean {
        val sh = screenHeight
        val b = findFirstRestaurantBounds(root, sh) ?: return false
        val ty = b.top + b.height() * 0.30f   // upper part = name/image, not a sub-button
        Log.d("FoodwiseScrape", "tapFirstRestaurant: '$currentRestaurantName' card at (${b.centerX()},${ty.toInt()}) bounds=$b")
        tapAt(b.centerX().toFloat(), ty)
        return true
    }

    private fun findFirstRestaurantBounds(root: AccessibilityNodeInfo, sh: Int): Rect? {
        val sw = screenWidth
        var best: Rect? = null
        fun walk(n: AccessibilityNodeInfo) {
            if (n.isClickable) {
                val b = Rect().also { n.getBoundsInScreen(it) }
                // Restaurant cards on the results page are wide (≈full width), reasonably
                // tall, and sit below the search/filter header. They do NOT reliably show a
                // numeric rating here — they show the restaurant name plus an offer / delivery
                // cue. The "Featured" tiles above are empty-text image tiles, so requiring real
                // text with a restaurant cue filters those out.
                // Width ≈ full screen. Height range is broad so it matches both the tall
                // results-page CardViews (~580px) and the shorter autocomplete restaurant rows
                // (~170px). Top must clear the search/filter header.
                val isWide = b.width() > sw * 0.7
                if (isWide && b.height() > sh * 0.05 && b.height() < sh * 0.5 && b.top > sh * 0.15) {
                    val sub = mutableListOf<String>()
                    collectAllText(n, sub)
                    val joined = sub.joinToString(" ")
                    // Restaurant rows show a rating like "4.3 (2.4K+)" or carry "Restaurant"/offer
                    // cues; dish suggestions are tagged "Dish". Skip dishes — the user wants the
                    // first actual restaurant.
                    val hasRating = Regex("[1-5]\\.\\d\\s*\\(").containsMatchIn(joined)
                    val hasName = joined.contains("Restaurant", true) ||
                        joined.contains("Favourite", true)
                    val hasOffer = joined.contains("delivery", true) || joined.contains("off", true) ||
                        joined.contains("for two", true)
                    val isDish = joined.contains("Dish", true) && !hasRating
                    if (!isDish && (hasRating || hasName || hasOffer) &&
                        (best == null || b.top < best!!.top)) {
                        best = b
                        // Capture the restaurant name (first real text line of the card),
                        // dropping a trailing "Restaurant" suffix Swiggy adds for a11y.
                        val nm = sub.firstOrNull {
                            it.length > 2 && it.any { c -> c.isLetter() } &&
                                !it.matches(Regex("[1-5]\\.\\d.*")) &&
                                !it.equals("Favourite", true)
                        } ?: ""
                        currentRestaurantName = nm.replace(Regex("\\s+Restaurant$"), "").trim()
                    }
                }
            }
            for (i in 0 until n.childCount) {
                val c = n.getChild(i) ?: continue
                walk(c)
                c.recycle()
            }
        }
        walk(root)
        return best
    }

    // Debug: logs up to ~45 clickable nodes with their subtree text and bounds so we
    // can see the actual tree and calibrate suggestion / restaurant selection.
    private fun logClickables(root: AccessibilityNodeInfo, tag: String) {
        var count = 0
        fun walk(n: AccessibilityNodeInfo) {
            if (count > 45) return
            if (n.isClickable) {
                val b = Rect().also { n.getBoundsInScreen(it) }
                val sub = mutableListOf<String>()
                collectAllText(n, sub)
                val cls = n.className?.toString()?.substringAfterLast('.') ?: ""
                Log.d("FoodwiseScrape", "CLICK[$tag] $cls b=[${b.left},${b.top},${b.right},${b.bottom}] txt=${sub.take(4)}")
                count++
            }
            for (i in 0 until n.childCount) {
                val c = n.getChild(i) ?: continue
                walk(c)
                c.recycle()
            }
        }
        walk(root)
    }

    // ── Screen scraping ──────────────────────────────────────────────────────

    private fun scrapeScreen(
        app: String,
        root: AccessibilityNodeInfo,
        allText: List<String>
    ): AppScreenData {
        val restaurants = if (searchQuery.isEmpty()) parseRestaurants(app, allText) else emptyList()
        val foodItems   = if (searchQuery.isNotEmpty()) parseFoodItems(allText) else emptyList()
        val coupons     = parseCoupons(allText)
        val banners     = parseBanners(allText)
        return AppScreenData(app, restaurants, foodItems, coupons, banners)
    }

    // UI / chrome tokens that are NOT dish names. Swiggy renders "ADD",
    // "CUSTOMISABLE", "Bestseller" etc. near prices; without this filter they get
    // mistaken for the item name.
    private val nonDishLabels = setOf(
        "add", "added", "customisable", "customise", "bestseller", "must try",
        "repeat", "veg", "non-veg", "nonveg", "ratings", "rating", "off",
        "free delivery", "more", "item", "items", "in stock", "sold out"
    )

    private fun isLikelyDishName(t: String): Boolean {
        val s = t.trim()
        if (s.length < 3 || s.contains("₹")) return false
        if (!s.any { it.isLetter() }) return false
        if (s.lowercase() in nonDishLabels) return false
        if (s.matches(Regex("[1-5]\\.\\d.*"))) return false          // rating
        if (s.matches(Regex("\\d+[-–]\\d+\\s*min.*", RegexOption.IGNORE_CASE))) return false
        if (s.contains("% off", true) || s.contains("flat ₹", true)) return false
        // All-caps short tokens are almost always buttons/badges (ADD, MRP, GST).
        if (s.length <= 4 && s == s.uppercase()) return false
        return true
    }

    private fun parseFoodItems(texts: List<String>): List<FoodItemData> {
        val items = mutableListOf<FoodItemData>()
        var i = 0
        while (i < texts.size) {
            val text = texts[i]

            // Price node: a standalone "₹XXX". Swiggy's menu exposes only ONE price
            // per item to accessibility (e.g. the dish row is [name][name][₹X][ADD]);
            // the struck/discounted pair is not both in the tree, so we take this one.
            val priceMatch = Regex("^₹(\\d{2,4})$").find(text.trim())
            if (priceMatch != null) {
                val price = priceMatch.groupValues[1].toIntOrNull() ?: 0
                if (price in 49..1999) {
                    // Nearest real dish name before the price, skipping UI labels.
                    val name = texts.subList(maxOf(0, i - 6), i)
                        .lastOrNull { isLikelyDishName(it) } ?: ""
                    val ahead = texts.subList(i + 1, minOf(i + 9, texts.size))
                    val rating = ahead.firstOrNull { it.matches(Regex("\\d\\.\\d.*")) } ?: ""
                    val deliveryTime = ahead.firstOrNull {
                        it.matches(Regex("\\d+[-–]\\d+\\s*min.*", RegexOption.IGNORE_CASE))
                    } ?: ""
                    // On a single-restaurant menu the restaurant is the one we drilled into.
                    val restaurant = currentRestaurantName
                    val feeText = ahead.firstOrNull { it.contains("delivery", ignoreCase = true) } ?: ""
                    val deliveryFee = Regex("₹(\\d+)").find(feeText)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                    val discount = ahead.firstOrNull {
                        it.contains("% off", ignoreCase = true) || it.contains("flat ₹", ignoreCase = true)
                    } ?: ""

                    if (name.isNotEmpty()) {
                        items.add(FoodItemData(name, restaurant, price, price, rating, deliveryTime, deliveryFee, discount))
                    }
                }
            }
            i++
        }
        return items.distinctBy { it.name }.take(30)
    }

    private fun parseRestaurants(app: String, texts: List<String>): List<RestaurantItem> {
        val items = mutableListOf<RestaurantItem>()
        var i = 0
        while (i < texts.size) {
            val text = texts[i]
            val isRating = text.matches(Regex("\\d\\.\\d.*"))
            val isDiscount = text.contains("% off", ignoreCase = true) ||
                    text.contains("flat ₹", ignoreCase = true) ||
                    text.contains("free delivery", ignoreCase = true)
            val isDeliveryTime = text.matches(Regex("\\d+[-–]\\d+\\s*min.*", RegexOption.IGNORE_CASE))
            val isProbablyName = text.length > 3 &&
                    !text.matches(Regex("[₹\\d.,% ]+")) &&
                    !isRating && !isDeliveryTime && !isDiscount &&
                    !text.contains("delivery", ignoreCase = true) &&
                    !text.contains("min", ignoreCase = true) &&
                    text[0].isUpperCase()

            if (isProbablyName && i + 3 < texts.size) {
                val lookahead = texts.subList(i + 1, minOf(i + 6, texts.size))
                val rating = lookahead.firstOrNull { it.matches(Regex("\\d\\.\\d.*")) } ?: ""
                val deliveryTime = lookahead.firstOrNull {
                    it.matches(Regex("\\d+[-–]\\d+\\s*min.*", RegexOption.IGNORE_CASE))
                } ?: ""
                val feeText = lookahead.firstOrNull { it.contains("delivery", ignoreCase = true) } ?: ""
                val fee = Regex("₹(\\d+)").find(feeText)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                val discount = lookahead.firstOrNull {
                    it.contains("% off", ignoreCase = true) || it.contains("flat ₹", ignoreCase = true)
                } ?: ""
                if (rating.isNotEmpty() || deliveryTime.isNotEmpty()) {
                    items.add(RestaurantItem(text, fee, deliveryTime, rating, discount))
                }
            }
            i++
        }
        return items.take(10)
    }

    private fun parseCoupons(texts: List<String>): List<String> {
        val coupons = mutableListOf<String>()
        val patterns = listOf(
            Regex("[A-Z]{4,12}\\d*"),
            Regex("USE\\s+[A-Z0-9]+"),
            Regex("APPLY\\s+[A-Z0-9]+")
        )
        for (text in texts) {
            for (pattern in patterns) {
                val match = pattern.find(text) ?: continue
                if (match.value.length >= 4) {
                    val code = match.value.replace("USE ", "").replace("APPLY ", "").trim()
                    if (!coupons.contains(code)) coupons.add(code)
                }
            }
        }
        return coupons.take(8)
    }

    private fun parseBanners(texts: List<String>): List<String> {
        return texts.filter { text ->
            (text.contains("% off", ignoreCase = true) ||
                    text.contains("flat ₹", ignoreCase = true) ||
                    text.contains("free del", ignoreCase = true) ||
                    text.contains("save ₹", ignoreCase = true) ||
                    text.contains("upto ₹", ignoreCase = true) ||
                    // Threshold fragments ("ABOVE ₹179") arrive as separate nodes; keep
                    // them so the app can compute the coupon's min-cart requirement.
                    text.contains("above ₹", ignoreCase = true)) && text.length < 70
        }.distinct().take(8)
    }

    private fun isOrderConfirmation(app: String, texts: List<String>): Boolean {
        val now = System.currentTimeMillis()
        val last = lastConfirmedAt[app] ?: 0L
        if (now - last < CONFIRM_DEBOUNCE_MS) return false
        val patterns = ORDER_CONFIRMATION_STRINGS[app] ?: return false
        val joined = texts.joinToString(" ").lowercase()
        val matched = patterns.any { joined.contains(it) }
        if (matched) lastConfirmedAt[app] = now
        return matched
    }

    private fun broadcastOrderConfirmed(app: String) {
        sendBroadcast(Intent(ACTION_ORDER_CONFIRMED).apply {
            putExtra(EXTRA_APP, app)
            putExtra(EXTRA_TIMESTAMP, System.currentTimeMillis())
            setPackage(packageName)
        })
    }

    private fun collectAllText(node: AccessibilityNodeInfo, result: MutableList<String>) {
        val ownText = node.text?.toString()?.trim()?.takeIf { it.isNotBlank() }
        if (ownText != null) result.add(ownText)
        // Add the contentDescription unless it just duplicates THIS node's own text.
        // (Previously we skipped any value already anywhere in the list, which dropped
        // legitimately-repeated values like a second item priced the same — e.g. a
        // discounted "₹129" that another dish also costs.)
        node.contentDescription?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let {
            if (it != ownText) result.add(it)
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                collectAllText(child, result)
                child.recycle()
            }
        }
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
            put("foodItems", JSONArray().apply {
                data.foodItems.forEach { f ->
                    put(JSONObject().apply {
                        put("name", f.name)
                        put("restaurant", f.restaurant)
                        put("price", f.price)
                        put("originalPrice", f.originalPrice)
                        put("rating", f.rating)
                        put("deliveryTime", f.deliveryTime)
                        put("deliveryFee", f.deliveryFee)
                        put("discount", f.discount)
                    })
                }
            })
            put("coupons", JSONArray(data.coupons))
            put("banners", JSONArray(data.banners))
        }
        sendBroadcast(Intent(ACTION_FOOD_DATA).apply {
            putExtra(EXTRA_JSON, json.toString())
            setPackage(packageName)
        })
    }

    override fun onInterrupt() {}
}
