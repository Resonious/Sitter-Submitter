package dev.baillie.sittersubmitter.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.unit.sp

// Set of Material typography styles to start with
val Typography = Typography(
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp
    )
    /* Other default text styles to override
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 22.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.sp
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp
    )
    */
).withLocale(LocaleList("ja"))

// The UI is Japanese, so draw kanji with their Japanese shapes even on phones set to another language
// (Android otherwise uses the Chinese shapes of characters such as 内).
private fun Typography.withLocale(localeList: LocaleList) = copy(
    displayLarge = displayLarge.copy(localeList = localeList),
    displayMedium = displayMedium.copy(localeList = localeList),
    displaySmall = displaySmall.copy(localeList = localeList),
    headlineLarge = headlineLarge.copy(localeList = localeList),
    headlineMedium = headlineMedium.copy(localeList = localeList),
    headlineSmall = headlineSmall.copy(localeList = localeList),
    titleLarge = titleLarge.copy(localeList = localeList),
    titleMedium = titleMedium.copy(localeList = localeList),
    titleSmall = titleSmall.copy(localeList = localeList),
    bodyLarge = bodyLarge.copy(localeList = localeList),
    bodyMedium = bodyMedium.copy(localeList = localeList),
    bodySmall = bodySmall.copy(localeList = localeList),
    labelLarge = labelLarge.copy(localeList = localeList),
    labelMedium = labelMedium.copy(localeList = localeList),
    labelSmall = labelSmall.copy(localeList = localeList)
)