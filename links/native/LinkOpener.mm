#import <AppKit/AppKit.h>

#include "LinkOpener.hpp"

// The workspace of AppKit opens the url with the app that its scheme is associated with, on the thread of the call.
void LinkOpener::open(std::string url, std::function<void(Answer)> reply) {
    NSString* text = [NSString stringWithUTF8String:url.c_str()];
    NSURL* address = text != nil ? [NSURL URLWithString:text] : nil;
    if (address == nil) {
        reply(Answer::NotAUrl);
        return;
    }

    const bool opened = [NSWorkspace.sharedWorkspace openURL:address];
    reply(opened ? Answer::Opened : Answer::NoApp);
}
