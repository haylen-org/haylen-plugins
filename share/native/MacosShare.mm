#import <AppKit/AppKit.h>

#include "MacosShare.hpp"

#include "ShareAnswer.hpp"

// The delegate of the picker that shows, which ends the share once the person picks a service or closes the picker.
@interface MacosSharePicker : NSObject <NSSharingServicePickerDelegate>

@property(nonatomic, copy) NSString* subject;

@end

struct MacosShare::Showing {
    std::uint64_t call = 0;
    MacosSharePicker* delegate = nil;
    NSSharingServicePicker* picker = nil;
};

@implementation MacosSharePicker

- (void)sharingServicePicker:(NSSharingServicePicker*)sharingServicePicker didChooseSharingService:(NSSharingService*)service {
    if (service != nil && self.subject != nil) {
        service.subject = self.subject;
    }
    NSString* title = service.title != nil ? service.title : @"";
    MacosShare::end(service != nil, title.UTF8String);
}

@end

const HaylenNativeApi* MacosShare::api = nullptr;

void MacosShare::use(const HaylenNativeApi& value) noexcept {
    api = &value;
}

void MacosShare::show(std::uint64_t call, const HaylenNativeWindow& window, ShareRequest request) {
    Showing& showing = getShowing();
    if (showing.picker != nil) {
        ShareAnswer::fail(call, "busy", "The share sheet already shows.");
        return;
    }

    NSMutableArray* items = [NSMutableArray array];
    if (request.text) {
        [items addObject:@(request.text->c_str())];
    }

    NSFileManager* files = NSFileManager.defaultManager;
    NSURL* folder = [files.temporaryDirectory URLByAppendingPathComponent:@"share" isDirectory:YES];
    [files removeItemAtURL:folder error:nil];
    for (const ShareRequest::File& file : request.files) {
        NSString* name = @(file.name.c_str());
        NSURL* destination = [folder URLByAppendingPathComponent:name];
        NSData* bytes = [NSData dataWithBytes:file.bytes.data() length:file.bytes.size()];
        NSError* error = nil;
        const BOOL created = [files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error];
        if (!created || ![bytes writeToURL:destination options:NSDataWritingAtomic error:&error]) {
            ShareAnswer::fail(call, "failed", "The file \"" + file.name + "\" of the share could not be written: " + error.localizedDescription.UTF8String);
            return;
        }
        [items addObject:destination];
    }

    if (request.url) {
        NSURL* url = [NSURL URLWithString:@(request.url->c_str())];
        if (url == nil) {
            ShareAnswer::fail(call, "invalidUrl", "The url \"" + *request.url + "\" of the share is not valid.");
            return;
        }
        [items addObject:url];
    }

    // The anchor counts from the top left corner of the window, and AppKit from the bottom left corner of the view.
    NSView* view = ((__bridge NSWindow*)window.handle).contentView;
    const NSRect bounds = view.bounds;
    NSRect rect = NSMakeRect(NSMidX(bounds), NSMidY(bounds), 0, 0);
    if (request.anchor) {
        const ShareRequest::Anchor& anchor = *request.anchor;
        const CGFloat x = bounds.origin.x + anchor.x * bounds.size.width;
        const CGFloat y = NSMaxY(bounds) - (anchor.y + anchor.height) * bounds.size.height;
        rect = NSMakeRect(x, y, anchor.width * bounds.size.width, anchor.height * bounds.size.height);
    }

    showing.call = call;
    showing.delegate = [[MacosSharePicker alloc] init];
    showing.delegate.subject = request.title ? @(request.title->c_str()) : nil;
    showing.picker = [[NSSharingServicePicker alloc] initWithItems:items];
    showing.picker.delegate = showing.delegate;
    api->coverApp();
    [showing.picker showRelativeToRect:rect ofView:view preferredEdge:NSRectEdgeMinY];
}

// The record of the share holds the only references to the picker and its delegate, so it lets them go last, once the call has its answer.
void MacosShare::end(bool shared, const std::string& target) {
    Showing& showing = getShowing();
    api->uncoverApp();
    ShareAnswer::finish(showing.call, shared, target);
    showing = {};
}

MacosShare::Showing& MacosShare::getShowing() {
    static Showing* showing = new Showing();
    return *showing;
}
