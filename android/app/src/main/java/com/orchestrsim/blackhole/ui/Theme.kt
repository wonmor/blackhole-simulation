package com.orchestrsim.blackhole.ui

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFF8CF2FF)

/**
 * The app always draws on a black, space-dark canvas, so it uses one dark
 * scheme regardless of the system light/dark setting. Every "on" colour is
 * white (or near-white) so text stays readable on any panel.
 */
private val DarkScheme = darkColorScheme(
    primary = Accent,
    onPrimary = Color.Black,
    primaryContainer = Color(0xFF12343A),
    onPrimaryContainer = Color.White,
    secondary = Accent,
    onSecondary = Color.Black,
    secondaryContainer = Color(0xFF1C3C42),
    onSecondaryContainer = Color.White,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color(0xFF101216),
    onSurface = Color.White,
    surfaceVariant = Color(0xFF1E2228),
    onSurfaceVariant = Color(0xFFE6E9EE),
    surfaceContainerLowest = Color(0xFF0B0D11),
    surfaceContainerLow = Color(0xFF12151A),
    surfaceContainer = Color(0xFF161A20),
    surfaceContainerHigh = Color(0xFF1B2027),
    surfaceContainerHighest = Color(0xFF222831),
    inverseSurface = Color.White,
    inverseOnSurface = Color.Black,
    outline = Color(0xFF6B7380),
    outlineVariant = Color(0xFF3A414B)
)

@Composable
fun BlackHoleTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = DarkScheme) {
        // Most of the UI is drawn on plain Boxes rather than Surfaces, and
        // Material3's LocalContentColor defaults to Color.Black outside a
        // Surface. Provide the scheme's onBackground at the root so every Text
        // and Icon without an explicit colour is white.
        CompositionLocalProvider(
            LocalContentColor provides MaterialTheme.colorScheme.onBackground,
            content = content
        )
    }
}
