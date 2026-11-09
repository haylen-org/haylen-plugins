package com.haylen.uitests

import android.Manifest.permission.POST_NOTIFICATIONS
import android.os.Build
import androidx.test.uiautomator.By
import java.util.regex.Pattern
import org.junit.Assume.assumeTrue
import org.junit.Test

// The sample checks, asks for and uses a permission of every state of its local plugin "permission-states" through the Permissions plugin, and logs each answer. The permission "asked" is `POST_NOTIFICATIONS`, whose dialog Android shows from Android 13 on, again after one refusal. The test takes it back before it starts, so the dialog shows.
class PermissionsTests : HaylenUiTestCase() {
    companion object {
        val ALLOW = arrayOf("permission_allow_button")
        val DENY = arrayOf("permission_deny_button", "permission_deny_and_dont_ask_again_button")
    }

    override val revokedPermissions = listOf(POST_NOTIFICATIONS)

    @Test
    fun everyFixedStateAnswersTheSameToACheckARequestAndAUse() {
        for ((name, state) in listOf("held" to "granted", "refused" to "denied", "untold" to "unknown")) {
            tap("Check $name")
            expectLine("The call \"states.permission('$name')\" answered \"$state\".")
            tap("Ask for $name")
            expectLine("The call \"states.requestPermission('$name')\" answered \"$state\".")
        }

        // A permission that the system tells nothing of until the app tries counts as allowed, so only the refused one fails its use.
        tap("Use held")
        expectLine("The call \"states.use('held')\" answered: The plugin used the permission \"held\".")
        tap("Use untold")
        expectLine("The call \"states.use('untold')\" answered: The plugin used the permission \"untold\".")
        tap("Use refused")
        waitForStart("The call \"states.use('refused')\" failed with \"denied\": The person has not allowed the permission \"refused\" of the sample.")

        val absent = "failed with \"unsupported\": The sample has the permission \"absent\" on no device."
        tap("Check absent")
        expectLine("The call \"states.permission('absent')\" $absent")
        tap("Ask for absent")
        expectLine("The call \"states.requestPermission('absent')\" $absent")
        tap("Use absent")
        expectLine("The call \"states.use('absent')\" $absent")

        tap("Check permissions.state('nobody')")
        waitFor(Pattern.compile("The call \"permissions\\.state\\('nobody'\\)\" raised: .*The permission \"nobody\" belongs to no plugin that the app loaded\\..*", Pattern.DOTALL))
        saveScreenshot("fixed-states")
    }

    @Test
    fun askedIsRefusedOnceAndThenAllowedOnASecondRequest() {
        assumeTrue("Android asks for notifications from Android 13 on.", Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
        tap("Check permissions.state('asked')")
        expectLine("The call \"permissions.state('asked')\" answered \"prompt\".")

        tap("Ask for asked")
        answerPermission(*DENY)
        expectLine("The call \"states.requestPermission('asked')\" answered \"denied\".")

        // Android shows its dialog again after one refusal, so the permission is still a prompt.
        val prompt = "The call \"states.permission('asked')\" answered \"prompt\"."
        tap("Check asked")
        expectLine(prompt)

        tap("Ask for asked")
        answerPermission(*ALLOW)
        expectLine("The call \"states.requestPermission('asked')\" answered \"granted\".")
        tap("Check asked")
        expectLine("The call \"states.permission('asked')\" answered \"granted\".")
        tap("Use asked")
        expectLine("The call \"states.use('asked')\" answered: The plugin used the permission \"asked\".")
        saveScreenshot("asked-allowed")
    }

    // Waits until the log holds the line, whose node names it in its content description.
    private fun expectLine(line: String) {
        waitFor(By.desc(line), "the line \"$line\" in the log")
    }
}
