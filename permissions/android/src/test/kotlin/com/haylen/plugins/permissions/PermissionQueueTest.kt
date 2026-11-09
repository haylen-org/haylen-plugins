package com.haylen.plugins.permissions

import org.junit.Assert.assertEquals
import org.junit.Test

class PermissionQueueTest {
    // Prompts that show every request and write down what happened to each one.
    private open class RecordedPrompts : PermissionQueue.Prompts<String> {
        val log = mutableListOf<String>()

        override fun show(request: String): Boolean {
            log.add("show $request")
            return true
        }

        override fun answerPrompted(request: String) {
            log.add("prompted $request")
        }

        override fun answerWithoutPrompt(request: String) {
            log.add("held $request")
        }
    }

    @Test
    fun showsOnePromptAtATimeInOrder() {
        val prompts = RecordedPrompts()
        val queue = PermissionQueue(prompts)

        queue.add("camera")
        queue.add("location")
        queue.answered()
        queue.answered()

        assertEquals(listOf("show camera", "prompted camera", "show location", "prompted location"), prompts.log)
    }

    // An activity that finished for good while its prompt showed never hears the answer, so the next activity answers the waiting requests, and later requests show their prompts again.
    @Test
    fun answersTheRequestsOfAnActivityThatFinishedDuringItsPrompt() {
        val prompts = RecordedPrompts()
        val queue = PermissionQueue(prompts)

        queue.add("camera")
        queue.add("location")
        queue.answerWithoutPrompts()
        queue.answered()
        queue.add("microphone")

        assertEquals(listOf("show camera", "held camera", "held location", "show microphone"), prompts.log)
    }

    @Test
    fun movesOnFromARequestThatCouldNotShowItsPrompt() {
        val prompts = object : RecordedPrompts() {
            override fun show(request: String): Boolean {
                super.show(request)
                return request != "camera"
            }
        }
        val queue = PermissionQueue(prompts)

        queue.add("camera")
        queue.add("location")
        queue.add("microphone")

        assertEquals(listOf("show camera", "show location"), prompts.log)
    }
}
