package com.haylen.plugins.mediasession

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream

@RunWith(AndroidJUnit4::class)
class MediaSessionArtworkTest {
    private fun png(width: Int, height: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
        bitmap.recycle()
        return bytes.toByteArray()
    }

    // A large image decodes at a scale that fits the controls, so its full bitmap never takes the memory of the main thread.
    @Test
    fun decodesALargeImageWithinItsLongestSide() {
        val picture = checkNotNull(MediaSessionArtwork().decode(png(4000, 2000)))

        assertTrue(maxOf(picture.width, picture.height) <= MediaSessionArtwork.MAX_SIDE)
        assertEquals(2, picture.width / picture.height)
    }

    // An update that only moves the position hands the same bytes again, which decode nothing.
    @Test
    fun keepsThePictureOfTheBytesItDecodedLast() {
        val artwork = MediaSessionArtwork()
        val first = artwork.decode(png(64, 64))

        assertSame(first, artwork.decode(png(64, 64)))
        assertNull(artwork.decode(byteArrayOf(1, 2, 3)))
        assertNull(artwork.decode(null))
    }
}
