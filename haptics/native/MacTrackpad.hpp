#pragma once

// The Force Touch trackpad of a Mac, which plays a feedback pattern at once and which a person feels only while a finger rests on it.
class MacTrackpad final {
  public:
    enum class Pattern { Generic, Alignment };

    static void perform(Pattern pattern);
};
