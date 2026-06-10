package io.last9.rumexample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import io.last9.rum.L9Rum
import io.last9.rumexample.screens.ErrorsScreen
import io.last9.rumexample.screens.HomeScreen
import io.last9.rumexample.screens.NetworkScreen
import io.last9.rumexample.screens.ProfileScreen
import io.last9.rumexample.screens.WebViewScreen
import io.last9.rumexample.ui.L9Theme

/**
 * Bottom-navigation destinations mirroring the reference app's five tabs.
 * Navigating between them via Navigation Compose drives the SDK's view tracking.
 */
private enum class Tab(val route: String, val label: String, val icon: String) {
    HOME("home", "Home", "🏠"),
    NETWORK("network", "Network", "🌐"),
    WEBVIEW("webview", "WebView", "🔗"),
    ERRORS("errors", "Errors", "⚠️"),
    PROFILE("profile", "Profile", "👤"),
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = L9Theme.ScreenBg) {
                    RumExampleApp()
                }
            }
        }
    }
}

@Composable
fun RumExampleApp() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination
    val currentRoute = currentDestination?.route

    // Log tab/route changes to the global event log, mirroring the reference's
    // NavigationContainer.onStateChange route logging.
    LaunchedEffect(currentRoute) {
        currentRoute?.let { EventLog.add("route → $it") }
    }

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = Color.White) {
                Tab.entries.forEach { tab ->
                    val selected = currentDestination?.hierarchy?.any { it.route == tab.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Text(tab.icon) },
                        label = { Text(tab.label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedTextColor = L9Theme.Accent,
                            unselectedTextColor = Color(0xFF999999),
                            indicatorColor = L9Theme.FeatureBg,
                        ),
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Tab.HOME.route,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(Tab.HOME.route) { HomeScreen() }
            composable(Tab.NETWORK.route) { NetworkScreen() }
            composable(Tab.WEBVIEW.route) { WebViewScreen() }
            composable(Tab.ERRORS.route) { ErrorsScreen() }
            composable(Tab.PROFILE.route) { ProfileScreen() }
        }
    }
}
