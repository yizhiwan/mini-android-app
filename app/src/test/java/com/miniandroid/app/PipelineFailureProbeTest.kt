package com.miniandroid.app

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * TEMPORARY. Deliberately failing test used to verify that a red PR build
 * posts its log to the pull request and blocks the merge. Delete this file
 * once the failure path has been confirmed — it is not a real test.
 */
class PipelineFailureProbeTest {

    @Test
    fun deliberatelyFailsToExerciseTheFailureNotificationPath() {
        assertEquals("1.0.2", VersionFormatter.format("1.0.2"))
    }
}
