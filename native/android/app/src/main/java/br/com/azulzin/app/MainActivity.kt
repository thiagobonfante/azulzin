package br.com.azulzin.app

import android.os.Bundle
import androidx.fragment.app.FragmentContainerView
import com.google.android.material.bottomnavigation.BottomNavigationView
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration

// Bottom nav + one NavigatorHost per tab (the 1.2 multi-navigator pattern,
// .plans/mobile/03 §1). Switching tabs toggles host visibility so each tab keeps
// its own back stack; system back pops the visible tab's stack first.
class MainActivity : HotwireActivity() {
    private val hosts by lazy {
        mapOf(
            R.id.tab_inicio to R.id.inicio_nav_host,
            R.id.tab_chat to R.id.chat_nav_host,
            R.id.tab_movimentos to R.id.movimentos_nav_host,
            R.id.tab_metas to R.id.metas_nav_host,
            R.id.tab_mais to R.id.mais_nav_host
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val bottomNav = findViewById<BottomNavigationView>(R.id.bottom_nav)
        bottomNav.inflateMenu(R.menu.bottom_nav)   // in code — see the layout comment
        bottomNav.setOnItemSelectedListener { item ->
            hosts.forEach { (tabId, hostId) ->
                findViewById<FragmentContainerView>(hostId).isVisible(tabId == item.itemId)
            }
            true
        }
    }

    private fun FragmentContainerView.isVisible(visible: Boolean) {
        visibility = if (visible) android.view.View.VISIBLE else android.view.View.GONE
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration("inicio", "${BuildConfig.BASE_URL}/dashboard", R.id.inicio_nav_host),
        NavigatorConfiguration("chat", "${BuildConfig.BASE_URL}/chat", R.id.chat_nav_host),
        NavigatorConfiguration("movimentos", "${BuildConfig.BASE_URL}/transactions", R.id.movimentos_nav_host),
        NavigatorConfiguration("metas", "${BuildConfig.BASE_URL}/goals", R.id.metas_nav_host),
        NavigatorConfiguration("mais", "${BuildConfig.BASE_URL}/menu", R.id.mais_nav_host)
    )
}
