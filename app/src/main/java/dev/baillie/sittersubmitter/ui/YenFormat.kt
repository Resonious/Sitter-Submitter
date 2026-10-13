package dev.baillie.sittersubmitter.ui

import java.util.Locale

/** An amount of yen as the app shows it, like ¥104,650: grouped the Japanese way, whatever the phone's region. */
fun formatYen(amount: Int): String = String.format(Locale.JAPAN, "¥%,d", amount)
