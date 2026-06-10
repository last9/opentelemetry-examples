package io.last9.rumexample.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Shared design system translated from the Last9 RUM React Native reference app.
 * Centralises the colour palette and reusable composables so each screen stays
 * focused on the RUM features it demonstrates.
 */
object L9Theme {
    val Accent = Color(0xFF6C63FF)
    val ScreenBg = Color(0xFFF8F9FA)
    val CardBg = Color.White
    val CardBorder = Color(0xFFEEEEEE)
    val FeatureBg = Color(0xFFF0EFFF)
    val TitleText = Color(0xFF111111)
    val HintText = Color(0xFF888888)
    val BodyText = Color(0xFF555555)
    val DividerLight = Color(0xFFF5F5F5)

    val Ok = Color(0xFF00B894)
    val Error = Color(0xFFFF6B6B)
    val Neutral = Color(0xFF636E72)

    // Varied accent colours used by the error buttons.
    val ErrorAccents = listOf(
        Color(0xFFFF6B6B),
        Color(0xFFFF9F43),
        Color(0xFF6C5CE7),
        Color(0xFFA29BFE),
    )
}

private val CardBorderStroke = BorderStroke(1.dp, L9Theme.CardBorder)

/** White screen header with an 18sp/bold title and an optional back affordance. */
@Composable
fun ScreenHeader(
    title: String,
    onBack: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(L9Theme.CardBg)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            Text(
                "‹ Back",
                color = L9Theme.Accent,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .clickable(onClick = onBack)
                    .padding(end = 12.dp),
            )
        }
        Text(
            title,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = L9Theme.TitleText,
            modifier = Modifier.weight(1f),
        )
        if (trailing != null) trailing()
    }
    HorizontalDivider(color = L9Theme.CardBorder, thickness = 1.dp)
}

/**
 * Light-purple card listing the RUM features demonstrated on the current screen.
 */
@Composable
fun FeatureBadge(features: List<String>, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = L9Theme.FeatureBg),
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(
                "RUM FEATURES ON THIS SCREEN",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = L9Theme.Accent,
                letterSpacing = 0.5.sp,
            )
            Spacer(Modifier.size(6.dp))
            features.forEach { feature ->
                Text(
                    "✓ $feature",
                    fontSize = 12.sp,
                    color = Color(0xFF444444),
                    lineHeight = 20.sp,
                )
            }
        }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        fontSize = 15.sp,
        fontWeight = FontWeight.Bold,
        color = L9Theme.TitleText,
        modifier = modifier,
    )
}

@Composable
fun Hint(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        fontSize = 12.sp,
        color = L9Theme.HintText,
        lineHeight = 18.sp,
        modifier = modifier,
    )
}

/** White card wrapper with a subtle border and rounded corners. */
@Composable
fun L9Card(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(12.dp)
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = shape,
        colors = CardDefaults.cardColors(containerColor = L9Theme.CardBg),
        border = CardBorderStroke,
    ) {
        if (onClick != null) {
            Box(modifier = Modifier.clickable(onClick = onClick)) { content() }
        } else {
            content()
        }
    }
}

/** Purple filled primary button with white bold text and radius 10. */
@Composable
fun PrimaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val container = if (enabled) L9Theme.Accent else L9Theme.Accent.copy(alpha = 0.5f)
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(container)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 12.dp, horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    }
}

/** Pill-shaped outlined button used for the Sign Out toggle. */
@Composable
fun OutlineButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color.White)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = L9Theme.BodyText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** White action-grid card: emoji icon stacked over a small label. */
@Composable
fun ActionButton(
    icon: String,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    L9Card(modifier = modifier, onClick = onClick) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(icon, fontSize = 22.sp)
            Spacer(Modifier.size(4.dp))
            Text(label, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = L9Theme.BodyText)
        }
    }
}

/**
 * API result card: white card with a 3dp coloured left border showing the
 * request label and `status · durationMs`.
 */
@Composable
fun ApiResultCard(
    label: String,
    status: Int,
    ok: Boolean,
    durationMs: Long,
    error: String? = null,
    modifier: Modifier = Modifier,
) {
    val color = when {
        ok -> L9Theme.Ok
        status == 0 -> L9Theme.Neutral
        else -> L9Theme.Error
    }
    LeftBorderCard(color = color, borderWidth = 3.dp, modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    label,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = L9Theme.TitleText,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    "${if (status != 0) status else "ERR"} · ${durationMs}ms",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = color,
                )
            }
            if (!error.isNullOrEmpty()) {
                Spacer(Modifier.size(4.dp))
                Text(error, fontSize = 11.sp, color = L9Theme.Error)
            }
        }
    }
}

/**
 * Error button: white card with a 4dp coloured left border, bold title and a
 * small subtitle describing the underlying SDK call.
 */
@Composable
fun ErrorButton(
    title: String,
    subtitle: String,
    accent: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LeftBorderCard(color = accent, borderWidth = 4.dp, modifier = modifier, onClick = onClick) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = L9Theme.TitleText)
            Spacer(Modifier.size(4.dp))
            Text(subtitle, fontSize = 11.sp, color = L9Theme.HintText)
        }
    }
}

/** White card with a coloured left accent border (a full-height stripe). */
@Composable
fun LeftBorderCard(
    color: Color,
    borderWidth: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    L9Card(modifier = modifier, onClick = onClick) {
        // IntrinsicSize.Min sizes the Row to its content height so the stripe
        // (fillMaxHeight) stretches the full height of the card.
        Row(modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Box(
                modifier = Modifier
                    .width(borderWidth)
                    .fillMaxHeight()
                    .background(color),
            )
            Box(modifier = Modifier.weight(1f)) { content() }
        }
    }
}

/** Key/value row for the SDK config card. */
@Composable
fun ConfigRow(key: String, value: String, showDivider: Boolean = true) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 5.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(key, fontSize = 12.sp, color = L9Theme.HintText)
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF333333))
    }
    if (showDivider) HorizontalDivider(color = L9Theme.DividerLight, thickness = 1.dp)
}

/** Monospace session-id value used in the Session card. */
@Composable
fun MonoText(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        fontSize = 11.sp,
        fontFamily = FontFamily.Monospace,
        color = Color(0xFF333333),
        modifier = modifier,
    )
}

/** Circular purple avatar showing user initials. */
@Composable
fun Avatar(initials: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(64.dp)
            .clip(RoundedCornerShape(32.dp))
            .background(L9Theme.Accent),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            initials,
            color = Color.White,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
    }
}

/** White card with a centered spinner and an optional hint, used while loading. */
@Composable
fun LoadingCard(hint: String? = null, modifier: Modifier = Modifier) {
    L9Card(modifier = modifier) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            androidx.compose.material3.CircularProgressIndicator(color = L9Theme.Accent)
            if (!hint.isNullOrEmpty()) {
                Spacer(Modifier.size(12.dp))
                Hint(hint)
            }
        }
    }
}

/** White summary card: bold title over a list of plain text lines. */
@Composable
fun SummaryCard(title: String, lines: List<String>, modifier: Modifier = Modifier) {
    L9Card(modifier = modifier) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = L9Theme.TitleText)
            Spacer(Modifier.size(6.dp))
            lines.forEach { line ->
                Text(line, fontSize = 12.sp, color = L9Theme.BodyText, lineHeight = 20.sp)
            }
        }
    }
}

/** White card with a bold label over a small body — used for users/comments. */
@Composable
fun AccentEntryCard(
    accent: Color,
    label: String,
    sub: String? = null,
    body: String? = null,
    modifier: Modifier = Modifier,
) {
    LeftBorderCard(color = accent, borderWidth = 3.dp, modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = L9Theme.TitleText)
            if (!sub.isNullOrEmpty()) {
                Text(sub, fontSize = 11.sp, color = L9Theme.HintText)
            }
            if (!body.isNullOrEmpty()) {
                Spacer(Modifier.size(4.dp))
                Text(body, fontSize = 12.sp, color = L9Theme.BodyText, lineHeight = 18.sp)
            }
        }
    }
}

/** Tappable post list row: title + body preview with a chevron. */
@Composable
fun PostListItem(
    title: String,
    body: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    L9Card(modifier = modifier, onClick = onClick) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = L9Theme.TitleText,
                    maxLines = 1,
                )
                Spacer(Modifier.size(2.dp))
                Text(body, fontSize = 11.sp, color = L9Theme.HintText, maxLines = 1)
            }
            Text("›", fontSize = 20.sp, color = Color(0xFFCCCCCC))
        }
    }
}

/** White card showing a monospace context dump (e.g. WebView native context JSON). */
@Composable
fun ContextCard(text: String, modifier: Modifier = Modifier) {
    L9Card(modifier = modifier) {
        Box(modifier = Modifier.padding(12.dp)) {
            Text(
                text,
                fontSize = 11.sp,
                color = Color(0xFF333333),
                fontFamily = FontFamily.Monospace,
                lineHeight = 16.sp,
            )
        }
    }
}

/** Bottom-sheet style modal that renders the global [io.last9.rumexample.EventLog]. */
@Composable
fun DebugLogModal(
    entries: List<io.last9.rumexample.EventLog.Entry>,
    onDismiss: () -> Unit,
) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White),
        ) {
            Column(modifier = Modifier.padding(20.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Event Log", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Text(
                        "✕",
                        fontSize = 20.sp,
                        color = L9Theme.HintText,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .clickable(onClick = onDismiss)
                            .padding(4.dp),
                    )
                }
                Spacer(Modifier.size(12.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(360.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(L9Theme.DividerLight)
                        .padding(8.dp),
                ) {
                    if (entries.isEmpty()) {
                        Hint("No events yet")
                    } else {
                        androidx.compose.foundation.lazy.LazyColumn {
                            items(entries.size) { i ->
                                val e = entries[i]
                                Row(modifier = Modifier.padding(vertical = 1.dp)) {
                                    Text(
                                        "${e.ts} ",
                                        fontSize = 11.sp,
                                        color = L9Theme.HintText,
                                        fontFamily = FontFamily.Monospace,
                                    )
                                    Text(
                                        e.msg,
                                        fontSize = 11.sp,
                                        color = Color(0xFF333333),
                                        fontFamily = FontFamily.Monospace,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
