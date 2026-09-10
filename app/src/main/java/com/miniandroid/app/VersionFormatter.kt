package com.miniandroid.app

/**
 * Formats and validates the semantic version string produced from
 * version.properties by the build.
 */
object VersionFormatter {

    const val UNKNOWN = "unknown"

    fun isValid(versionName: String): Boolean {
        val parts = versionName.split(".")
        return parts.size == 3 && parts.all { part ->
            part.isNotEmpty() && part.all(Char::isDigit)
        }
    }

    fun format(versionName: String): String =
        if (isValid(versionName)) "v$versionName" else UNKNOWN

    /**
     * Mirrors the versionCode arithmetic in app/build.gradle so the value
     * shipped in the APK can be asserted against in tests.
     */
    fun versionCodeOf(versionName: String): Int {
        require(isValid(versionName)) { "Malformed version name: $versionName" }
        val (major, minor, patch) = versionName.split(".").map(String::toInt)
        return major * 10_000 + minor * 100 + patch
    }
}
