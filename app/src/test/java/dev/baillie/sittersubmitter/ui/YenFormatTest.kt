package dev.baillie.sittersubmitter.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class YenFormatTest {

    @Test
    fun formatYen_groupsThousandsTheJapaneseWay() {
        assertEquals("¥0", formatYen(0))
        assertEquals("¥980", formatYen(980))
        assertEquals("¥7,800", formatYen(7800))
        assertEquals("¥104,650", formatYen(104650))
        assertEquals("¥1,234,567", formatYen(1234567))
    }

    @Test
    fun formatYen_ignoresThePhonesRegion() {
        val default = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY) // Groups thousands with dots
            assertEquals("¥104,650", formatYen(104650))
        } finally {
            Locale.setDefault(default)
        }
    }
}
