package com.haylen.plugins.permissions

import java.util.ArrayDeque

// The requests of permissions that wait for the prompt of the system, which shows one at a time, in the order they came. Only the main thread reaches it.
internal class PermissionQueue<R : Any>(private val prompts: Prompts<R>) {
    // What the queue asks of the permissions it holds.
    interface Prompts<R> {
        // Shows the prompt of the request and returns `true`, or answers the request at once and returns `false` when no prompt can show.
        fun show(request: R): Boolean

        // Answers the request whose prompt the person closed.
        fun answerPrompted(request: R)

        // Answers the request with the state the app holds, without a prompt.
        fun answerWithoutPrompt(request: R)
    }

    private val waiting = ArrayDeque<R>()
    private var showing = false

    fun add(request: R) {
        waiting.add(request)
        if (waiting.size == 1) {
            showNext()
        }
    }

    // The prompt that shows was answered. A result that Android delivers while no prompt shows, such as one that reached a new process, answers nothing.
    fun answered() {
        val head = waiting.peek()
        if (!showing || head == null) {
            return
        }

        showing = false
        prompts.answerPrompted(head)
        waiting.poll()
        showNext()
    }

    // Android never answers the prompt of an activity that finished for good, so its requests and the ones behind them answer what the app holds, and the next request shows its own prompt.
    fun answerWithoutPrompts() {
        showing = false
        while (true) {
            val request = waiting.peek() ?: return
            prompts.answerWithoutPrompt(request)
            waiting.poll()
        }
    }

    // A request stays at the head while it answers, so a request that its answer adds waits behind it.
    private fun showNext() {
        while (true) {
            val request = waiting.peek() ?: return
            if (prompts.show(request)) {
                showing = true
                return
            }

            waiting.poll()
        }
    }
}
