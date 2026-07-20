package br.com.azulzin.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination

// The "push" bridge component (.plans/mobile/04 §3): the web's Avisos row sends
// "register" (may prompt POST_NOTIFICATIONS); the native layout sends
// "registerIfGranted" on launch (silent). Replies carry the FCM token; the WEB posts it
// to /push_devices through its own session — no native HTTP, no cookie extraction.
//
// ponytail: Firebase initializes only once the founder ships google-services.json
// (AzulzinApplication guards init). Until then no token reply is ever sent.
class PushComponent(name: String, private val delegate: BridgeDelegate<HotwireDestination>) :
    BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        when (message.event) {
            "register" -> register(message, interactive = true)
            "registerIfGranted" -> register(message, interactive = false)
        }
    }

    private fun register(message: Message, interactive: Boolean) {
        val activity = delegate.destination.fragment.activity as? MainActivity ?: return
        if (FirebaseApp.getApps(activity).isEmpty()) return
        val needsPermission = Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            if (interactive) activity.requestNotificationsPermission { granted ->
                if (granted) replyWithToken(message)
            }
        } else {
            replyWithToken(message)
        }
    }

    private fun replyWithToken(message: Message) {
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            replyTo(message.event,
                """{"token":"$token","platform":"android","appVersion":"${BuildConfig.VERSION_NAME}"}""")
        }
    }
}
