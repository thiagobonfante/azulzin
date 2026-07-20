package br.com.azulzin.app

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.webkit.PermissionRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import dev.hotwire.core.turbo.webview.HotwireWebChromeClient
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment

// Chat audio capture (.plans/mobile/08 §4): the composer's getUserMedia surfaces here as
// a WebView PermissionRequest. Granting it requires the app itself to hold RECORD_AUDIO,
// so relay to the runtime permission prompt when the user hasn't granted it yet.
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class AzulzinWebFragment : HotwireWebFragment() {
    private var pendingMicRequest: PermissionRequest? = null

    private val micPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            pendingMicRequest?.let {
                if (granted) it.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) else it.deny()
            }
            pendingMicRequest = null
        }

    override fun createWebChromeClient() = object : HotwireWebChromeClient(navigator.session) {
        override fun onPermissionRequest(request: PermissionRequest) {
            // Mic only, and only for our own pages — deny anything else.
            val mic = PermissionRequest.RESOURCE_AUDIO_CAPTURE in request.resources
            val ours = request.origin?.host == Uri.parse(BuildConfig.BASE_URL).host
            if (!mic || !ours) return request.deny()

            val held = ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.RECORD_AUDIO)
            if (held == PackageManager.PERMISSION_GRANTED) {
                request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
            } else {
                pendingMicRequest = request
                micPermission.launch(Manifest.permission.RECORD_AUDIO)
            }
        }
    }
}
