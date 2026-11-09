package com.haylen.plugins.share

import androidx.core.content.FileProvider

// The provider of the files that the plugin shares, a class of its own so it never clashes with another provider of the app in the merged manifest.
class ShareFileProvider : FileProvider()
