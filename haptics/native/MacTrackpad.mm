#import <AppKit/AppKit.h>

#include "MacTrackpad.hpp"

void MacTrackpad::perform(Pattern pattern) {
    const NSHapticFeedbackPattern feedback = pattern == Pattern::Alignment ? NSHapticFeedbackPatternAlignment : NSHapticFeedbackPatternGeneric;
    [NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:feedback performanceTime:NSHapticFeedbackPerformanceTimeNow];
}
