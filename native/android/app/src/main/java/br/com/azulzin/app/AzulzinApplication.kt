package br.com.azulzin.app

import android.app.Application
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration

class AzulzinApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Server can gate features per app version later (.plans/mobile/01 §1).
        Hotwire.config.applicationUserAgentPrefix = "Azulzin/${BuildConfig.VERSION_NAME}"

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
