package com.haylen.plugins.mediasession

import android.graphics.Bitmap
import android.graphics.BitmapFactory

// The picture of the artwork that the now-playing controls show, from the bytes of a PNG or JPEG image that the app gives. It decodes at the smallest scale of two that fits `MAX_SIDE`, so a large image never holds a full bitmap on the main thread, and it keeps the picture of the bytes it decoded last, so an update that only moves the position decodes nothing.
internal class MediaSessionArtwork {
    companion object {
        // The longest side of the picture, which Android shows at a few hundred pixels at most.
        const val MAX_SIDE = 1024
    }

    private var bytes: ByteArray? = null
    private var picture: Bitmap? = null

    // The picture of the bytes, or `null` for no bytes or bytes that are no image.
    fun decode(artwork: ByteArray?): Bitmap? {
        if (artwork == null || artwork.isEmpty()) {
            return null
        }

        if (artwork.contentEquals(bytes)) {
            return picture
        }

        val bounds = BitmapFactory.Options()
        bounds.inJustDecodeBounds = true
        BitmapFactory.decodeByteArray(artwork, 0, artwork.size, bounds)

        val scaled = BitmapFactory.Options()
        scaled.inSampleSize = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / scaled.inSampleSize > MAX_SIDE) {
            scaled.inSampleSize *= 2
        }

        bytes = artwork
        picture = BitmapFactory.decodeByteArray(artwork, 0, artwork.size, scaled)
        return picture
    }
}
