package com.miniandroid.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VersionFormatterTest {

    @Test
    fun acceptsThreePartNumericVersion() {
        assertTrue(VersionFormatter.isValid("1.0.2"))
        assertTrue(VersionFormatter.isValid("10.20.30"))
    }

    @Test
    fun rejectsMalformedVersions() {
        assertFalse(VersionFormatter.isValid("1.0"))
        assertFalse(VersionFormatter.isValid("1.0.2.3"))
        assertFalse(VersionFormatter.isValid("1.0.x"))
        assertFalse(VersionFormatter.isValid("1..2"))
        assertFalse(VersionFormatter.isValid(""))
    }

    @Test
    fun prefixesValidVersionWithV() {
        assertEquals("v1.0.2", VersionFormatter.format("1.0.2"))
    }

    @Test
    fun fallsBackToUnknownForMalformedVersion() {
        assertEquals(VersionFormatter.UNKNOWN, VersionFormatter.format("nope"))
    }

    @Test
    fun computesVersionCodeMatchingBuildScript() {
        assertEquals(10_002, VersionFormatter.versionCodeOf("1.0.2"))
        assertEquals(10_000, VersionFormatter.versionCodeOf("1.0.0"))
        assertEquals(102_030, VersionFormatter.versionCodeOf("10.20.30"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun versionCodeRejectsMalformedVersion() {
        VersionFormatter.versionCodeOf("1.0")
    }
}
