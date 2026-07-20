package br.com.azulzin.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.widget.Button
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import java.io.DataOutputStream
import java.net.HttpURLConnection
import java.net.URL
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import dev.hotwire.core.turbo.visit.VisitAction
import dev.hotwire.core.turbo.visit.VisitOptions
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.tabs.HotwireBottomNavigationController
import dev.hotwire.navigation.tabs.HotwireBottomTab
import dev.hotwire.navigation.tabs.navigatorConfigurations

// The framework's bottom-tabs pattern (hotwire-native-android 1.2): the controller builds
// the BottomNavigationView menu from the tabs and owns NavigatorHost switching — no
// hand-rolled visibility toggling (that kept every tab pinned to the first host).
class MainActivity : HotwireActivity() {
    private lateinit var bottomNavigationController: HotwireBottomNavigationController
    private lateinit var lockOverlay: View

    // Biometric lock (.plans/mobile/03 §4): gate on cold start and on foreground after
    // > 2 min stopped; the overlay stays up until auth succeeds.
    private var unlocked = false
    private var authenticating = false
    private var stoppedAt: Long? = null
    private val relockAfterMs = 120_000L
    private val authenticators = BIOMETRIC_STRONG or DEVICE_CREDENTIAL

    private var selectedTabName = "inicio"

    private val tabs by lazy {
        listOf(
            tab(R.string.tab_inicio, R.drawable.ic_tab_home, "inicio", "dashboard"),
            tab(R.string.tab_chat, R.drawable.ic_tab_chat, "chat", "chat"),
            tab(R.string.tab_movimentos, R.drawable.ic_tab_transactions, "movimentos", "transactions"),
            tab(R.string.tab_recentes, R.drawable.ic_tab_recent, "recentes", "transactions/recent"),
            tab(R.string.tab_mais, R.drawable.ic_tab_more, "mais", "menu")
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Finance-app baseline: blank recents thumbnail + no screenshots. Release only —
        // dev verification drives the emulator via adb screencap.
        if (!BuildConfig.DEBUG) {
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        }
        lockOverlay = findViewById(R.id.lock_overlay)
        findViewById<Button>(R.id.lock_retry).setOnClickListener { authenticate() }

        bottomNavigationController = HotwireBottomNavigationController(this, findViewById(R.id.bottom_nav))
        bottomNavigationController.load(tabs)

        // Tabs that loaded while signed out park on the sign-in redirect; the tab the
        // user signed IN on shows the root landing. Both re-route to the tab's start
        // location on selection. Signed out this costs one redundant reload per tap —
        // acceptable. (Sign-OUT staleness is handled eagerly in authScreenShown.)
        bottomNavigationController.setOnTabSelectedListener { _, tab ->
            selectedTabName = tab.configuration.name
            val navigator = delegate.findNavigatorHost(tab.configuration.navigatorHostId)?.navigator
            val parked = navigator?.takeIf { it.isReady() }?.location ?: return@setOnTabSelectedListener
            val inicioStart = tabs.first().configuration.startLocation
            val stale = parked.endsWith("/session/new") ||
                (parked == inicioStart && tab.configuration.startLocation != inicioStart)
            if (stale) {
                // REPLACE, not push: the stale page must leave the stack — a push would
                // put a back arrow on the tab root pointing at it.
                navigator.route(tab.configuration.startLocation, VisitOptions(action = VisitAction.REPLACE))
            }
        }

        routePushUrl(intent)   // cold-start notification tap carries the deep link here
        handleShare(intent)    // cold-start share intent carries the stream here
    }

    // MARK: biometric gate

    override fun onStart() {
        super.onStart()
        stoppedAt?.let { if (SystemClock.elapsedRealtime() - it > relockAfterMs) unlocked = false }
        stoppedAt = null
        if (unlocked) lockOverlay.visibility = View.GONE else authenticate()
    }

    override fun onStop() {
        super.onStop()
        stoppedAt = SystemClock.elapsedRealtime()
    }

    private fun authenticate() {
        if (authenticating) return
        // No credential at all → never lock the user out of their own finances.
        if (BiometricManager.from(this).canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            unlocked = true
            lockOverlay.visibility = View.GONE
            return
        }
        lockOverlay.visibility = View.VISIBLE
        findViewById<Button>(R.id.lock_retry).visibility = View.GONE
        authenticating = true
        BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                authenticating = false
                unlocked = true
                lockOverlay.visibility = View.GONE
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                authenticating = false
                findViewById<Button>(R.id.lock_retry).visibility = View.VISIBLE
            }
            // onAuthenticationFailed (wrong finger) is transient — the prompt stays up.
        }).authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(getString(R.string.lock_title))
                .setAllowedAuthenticators(authenticators)
                .build()
        )
    }

    // MARK: push (registration permission + tap-through deep link)

    private var notificationsPermissionCallback: ((Boolean) -> Unit)? = null
    private val notificationsPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            notificationsPermissionCallback?.invoke(granted)
            notificationsPermissionCallback = null
        }

    // PushComponent's seam for the POST_NOTIFICATIONS runtime prompt (API 33+).
    fun requestNotificationsPermission(callback: (Boolean) -> Unit) {
        notificationsPermissionCallback = callback
        notificationsPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        routePushUrl(intent)
        handleShare(intent)
    }

    // MARK: share-to-app receipts (.plans/mobile/05 §2)

    // A shared image/PDF uploads straight to POST /captures with the webview's session
    // cookie + the custom capture header (the CSRF stance the controller enforces).
    // Signed out → the app just opens on sign-in; the share is dropped with a toast (v1).
    private fun handleShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        intent.action = null   // consume — don't re-upload on config change
        @Suppress("DEPRECATION")
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
        val caption = intent.getStringExtra(Intent.EXTRA_TEXT)
        val cookie = CookieManager.getInstance().getCookie(BuildConfig.BASE_URL)
        if (cookie.isNullOrBlank() || !cookie.contains("session_id=")) {
            Toast.makeText(this, R.string.share_sign_in_first, Toast.LENGTH_LONG).show()
            return
        }
        Thread { uploadCapture(uri, caption, cookie) }.start()
    }

    private fun uploadCapture(uri: Uri, caption: String?, cookie: String) {
        val ok = try {
            val mime = contentResolver.getType(uri) ?: "image/jpeg"
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null) false else postCapture(bytes, mime, caption, cookie)
        } catch (e: Exception) {
            false
        }
        runOnUiThread {
            Toast.makeText(this, if (ok) R.string.share_received else R.string.share_failed,
                Toast.LENGTH_LONG).show()
        }
    }

    private fun postCapture(bytes: ByteArray, mime: String, caption: String?, cookie: String): Boolean {
        val boundary = "azulzin-${SystemClock.elapsedRealtimeNanos()}"
        val ext = if (mime == "application/pdf") "pdf" else "jpg"
        val conn = URL("${BuildConfig.BASE_URL}/captures").openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.instanceFollowRedirects = false   // the success redirect is the 3xx we want to SEE
        conn.setRequestProperty("Cookie", cookie)
        conn.setRequestProperty("X-Azulzin-Capture", "1")
        conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        DataOutputStream(conn.outputStream).use { out ->
            out.writeBytes("--$boundary\r\n")
            out.writeBytes("Content-Disposition: form-data; name=\"file\"; filename=\"share.$ext\"\r\n")
            out.writeBytes("Content-Type: $mime\r\n\r\n")
            out.write(bytes)
            out.writeBytes("\r\n")
            if (!caption.isNullOrBlank()) {
                out.writeBytes("--$boundary\r\n")
                out.writeBytes("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
                out.write(caption.toByteArray(Charsets.UTF_8))
                out.writeBytes("\r\n")
            }
            out.writeBytes("--$boundary--\r\n")
        }
        return conn.responseCode in 200..399
    }

    // FCM notification taps re-launch with data extras; route the deep link on the
    // Início navigator. ponytail: on a cold start the navigator isn't ready yet —
    // bounded 500ms retries instead of a lifecycle observer.
    private fun routePushUrl(intent: Intent?, attempt: Int = 0) {
        val path = intent?.getStringExtra("url") ?: return
        val navigator = delegate.findNavigatorHost(R.id.inicio_nav_host)?.navigator
        if (navigator?.isReady() == true) {
            intent.removeExtra("url")
            navigator.route(BuildConfig.BASE_URL + path)
        } else if (attempt < 10) {
            window.decorView.postDelayed({ routePushUrl(intent, attempt + 1) }, 500)
        }
    }

    // MARK: sign-out staleness

    // The VISIBLE tab arriving at the sign-in page (Sair, or a server-side expiry) means
    // every OTHER ready tab still shows an authenticated snapshot — reset() them so the
    // next selection does a fresh visit from the start location. Tabs already on the
    // sign-in page are left alone (the user may be typing into one).
    fun authScreenShown(from: Navigator) {
        val selected = tabs.find { it.configuration.name == selectedTabName } ?: return
        if (delegate.findNavigatorHost(selected.configuration.navigatorHostId)?.navigator !== from) return
        tabs.forEach { tab ->
            val navigator = delegate.findNavigatorHost(tab.configuration.navigatorHostId)?.navigator ?: return@forEach
            if (navigator !== from && navigator.isReady() &&
                navigator.location?.endsWith("/session/new") != true) {
                navigator.reset()
            }
        }
    }

    override fun navigatorConfigurations() = tabs.navigatorConfigurations

    private fun tab(titleRes: Int, iconRes: Int, name: String, path: String) = HotwireBottomTab(
        title = getString(titleRes),
        iconResId = iconRes,
        configuration = NavigatorConfiguration(
            name = name,
            startLocation = "${BuildConfig.BASE_URL}/$path",
            navigatorHostId = hostIds.getValue(name)
        )
    )

    private val hostIds = mapOf(
        "inicio" to R.id.inicio_nav_host,
        "chat" to R.id.chat_nav_host,
        "movimentos" to R.id.movimentos_nav_host,
        "recentes" to R.id.recentes_nav_host,
        "mais" to R.id.mais_nav_host
    )
}
