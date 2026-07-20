package br.com.azulzin.app

import android.os.Bundle
import dev.hotwire.core.turbo.visit.VisitAction
import dev.hotwire.core.turbo.visit.VisitOptions
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.tabs.HotwireBottomNavigationController
import dev.hotwire.navigation.tabs.HotwireBottomTab
import dev.hotwire.navigation.tabs.navigatorConfigurations

// The framework's bottom-tabs pattern (hotwire-native-android 1.2): the controller builds
// the BottomNavigationView menu from the tabs and owns NavigatorHost switching — no
// hand-rolled visibility toggling (that kept every tab pinned to the first host).
class MainActivity : HotwireActivity() {
    private lateinit var bottomNavigationController: HotwireBottomNavigationController

    private val tabs by lazy {
        listOf(
            tab(R.string.tab_inicio, android.R.drawable.ic_menu_view, "inicio", "dashboard"),
            tab(R.string.tab_chat, android.R.drawable.ic_menu_send, "chat", "chat"),
            tab(R.string.tab_movimentos, android.R.drawable.ic_menu_agenda, "movimentos", "transactions"),
            tab(R.string.tab_recentes, android.R.drawable.ic_menu_recent_history, "recentes", "transactions/recent"),
            tab(R.string.tab_mais, android.R.drawable.ic_menu_more, "mais", "menu")
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        bottomNavigationController = HotwireBottomNavigationController(this, findViewById(R.id.bottom_nav))
        bottomNavigationController.load(tabs)

        // Tabs that loaded while signed out are parked on the sign-in redirect; after the
        // user authenticates in another tab, selecting them re-routes to the real start
        // location. Signed out this costs one redundant reload per tap — acceptable.
        // ponytail: sign-OUT staleness (other tabs keep authenticated snapshots until
        // tapped… and a tap keeps the stale page since location looks legit) is NOT
        // handled here — revisit with the biometric-lock phase (delegate.resetSessions()).
        bottomNavigationController.setOnTabSelectedListener { _, tab ->
            val navigator = delegate.findNavigatorHost(tab.configuration.navigatorHostId)?.navigator
            if (navigator?.isReady() == true && navigator.location?.endsWith("/session/new") == true) {
                // REPLACE, not push: the stale sign-in page must leave the stack — a push
                // would put a back arrow on the tab root pointing at it.
                navigator.route(tab.configuration.startLocation, VisitOptions(action = VisitAction.REPLACE))
            }
        }
    }

    override fun navigatorConfigurations() = tabs.navigatorConfigurations

    // ponytail: system placeholder icons until brand assets exist (.plans/mobile/07 #6).
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
        "metas" to R.id.metas_nav_host,
        "mais" to R.id.mais_nav_host
    )
}
