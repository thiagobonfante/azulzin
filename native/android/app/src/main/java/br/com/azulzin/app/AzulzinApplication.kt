package br.com.azulzin.app

import android.app.Application
import com.google.firebase.FirebaseApp
import dev.hotwire.core.bridge.BridgeComponentFactory
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerBridgeComponents
import dev.hotwire.navigation.config.registerFragmentDestinations
import dev.hotwire.navigation.fragments.HotwireWebBottomSheetFragment

class AzulzinApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Server can gate features per app version later (.plans/mobile/01 §1).
        Hotwire.config.applicationUserAgentPrefix = "Azulzin/${BuildConfig.VERSION_NAME}"

        // Swap the stock web fragment for ours (mic grant for chat audio capture).
        Hotwire.defaultFragmentDestination = AzulzinWebFragment::class
        Hotwire.registerFragmentDestinations(
            AzulzinWebFragment::class,
            HotwireWebBottomSheetFragment::class
        )

        // Push registration bridge (.plans/mobile/04 §3). Without the google-services
        // Gradle plugin, initializeApp only succeeds once the founder-provisioned
        // google-services.json ships — until then FirebaseApp.getApps stays empty and
        // PushComponent never replies a token.
        Hotwire.registerBridgeComponents(
            BridgeComponentFactory("push", ::PushComponent)
        )
        FirebaseApp.initializeApp(this)

        // Asset copy = first-launch/offline fallback; remote wins when reachable.
        // Keep the asset in sync with PathConfigurationsController at release time.
        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                assetFilePath = "json/configuration.json",
                remoteFileUrl = "${BuildConfig.BASE_URL}/configurations/android_v1.json"
            )
        )
    }
}
