package br.com.azulzin.app

import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import androidx.lifecycle.lifecycleScope
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import kotlinx.coroutines.launch
import org.json.JSONObject

// The "sign-in" bridge component (.plans/mobile/10): the auth screens' hidden SSO
// buttons reveal when this registers; a tap sends "signIn" {provider} and the reply
// carries the Google ID token — the WEB posts it to /auth/:provider/token, so the
// session cookie lands in the webview. Credential Manager is configured with the WEB
// client id (the token's aud, matching Auth::IdToken server-side). Android has no
// Apple provider (the web only renders that button for the iOS UA).
//
// ponytail: GOOGLE_WEB_CLIENT_ID is an empty BuildConfig field until the founder adds
// the Android OAuth client (package + SHA-1) in the Google Cloud console; empty = the
// tap replies nothing and the page stays put.
class SignInComponent(name: String, private val delegate: BridgeDelegate<HotwireDestination>) :
    BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        if (message.event != "signIn") return
        if (JSONObject(message.jsonData).optString("provider") != "google_oauth2") return
        signInWithGoogle(message)
    }

    private fun signInWithGoogle(message: Message) {
        val activity = delegate.destination.fragment.activity ?: return
        if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isEmpty()) return

        val option = GetGoogleIdOption.Builder()
            .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)   // first-time users must see the picker too
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()

        activity.lifecycleScope.launch {
            try {
                val credential = CredentialManager.create(activity)
                    .getCredential(activity, request).credential
                if (credential is CustomCredential &&
                    credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                    val idToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
                    replyTo(message.event, """{"idToken":"$idToken"}""")
                }
            } catch (_: GetCredentialException) {
                // cancelled / no Google account — no reply, the sign-in form stays put
            }
        }
    }
}
