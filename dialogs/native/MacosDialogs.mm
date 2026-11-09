#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "MacosDialogs.hpp"

#include <string>
#include <vector>

#include "DialogsAnswer.hpp"

struct MacosDialogs::State {
    // The alerts and panels that show or wait, by the call that asked for them, so a cancel closes them and a call answers once.
    NSMutableDictionary<NSNumber*, id>* shown = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary*>* queued = [NSMutableArray array];
    BOOL showing = NO;
};

// The sheets of the dialogs, which `MacosDialogs` hands each request to on the main thread of AppKit.
@interface MacosDialogSheets : NSObject

+ (void)showMessage:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner;
+ (void)showOpenFiles:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner;
+ (void)showSaveFile:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner;
+ (void)showOpenFolder:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner;
+ (void)showOpenPhotos:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner;
+ (void)cancel:(uint64_t)call;

@end

@implementation MacosDialogSheets

// A closed sheet answers through its completion, which finds the call gone, so nothing answers it twice.
+ (void)cancel:(uint64_t)call {
    MacosDialogs::State& state = MacosDialogs::getState();
    id shown = state.shown[@(call)];
    if (shown == nil) {
        return;
    }
    [state.shown removeObjectForKey:@(call)];
    if ([shown isKindOfClass:NSAlert.class]) {
        NSWindow* sheet = ((NSAlert*)shown).window;
        [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
        return;
    }
    NSSavePanel* panel = shown;
    if (panel.sheetParent != nil) {
        [panel cancel:nil];
    }
}

// A sheet that the app gave up while it waited never begins.
+ (void)queue:(uint64_t)call sheet:(id)sheet over:(NSWindow*)owner handler:(void (^)(NSModalResponse))handler {
    MacosDialogs::State& state = MacosDialogs::getState();
    state.shown[@(call)] = sheet;
    [state.queued addObject:@{@"call" : @(call), @"sheet" : sheet, @"owner" : owner, @"handler" : [handler copy]}];
    [self showNext];
}

+ (void)showNext {
    MacosDialogs::State& state = MacosDialogs::getState();
    while (!state.showing && state.queued.count > 0) {
        NSDictionary* next = state.queued.firstObject;
        [state.queued removeObjectAtIndex:0];
        if (state.shown[next[@"call"]] == nil) {
            continue;
        }

        state.showing = YES;
        void (^handler)(NSModalResponse) = next[@"handler"];
        // clang-format off
        void (^completion)(NSModalResponse) = ^(NSModalResponse response) {
            [self ended];
            handler(response);
        };
        // clang-format on
        if ([next[@"sheet"] isKindOfClass:NSAlert.class]) {
            [(NSAlert*)next[@"sheet"] beginSheetModalForWindow:next[@"owner"] completionHandler:completion];
        } else {
            [(NSSavePanel*)next[@"sheet"] beginSheetModalForWindow:next[@"owner"] completionHandler:completion];
        }
    }
}

// The completion of a sheet runs while AppKit still ends it, so the next sheet begins on a later turn of the main queue.
+ (void)ended {
    MacosDialogs::getState().showing = NO;
    // clang-format off
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showNext];
    });
    // clang-format on
}

// The first button answers Return, and a button named Cancel answers Escape, as in every alert of the Mac.
+ (void)showMessage:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner {
    NSString* title = [self text:request.title];
    NSString* text = [self text:request.text];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.alertStyle = [self styleOf:request.kind];
    alert.messageText = title.length == 0 ? text : title;
    alert.informativeText = title.length == 0 ? @"" : text;
    for (const std::string& label : request.buttons) {
        [alert addButtonWithTitle:[self text:label]];
    }

    const auto count = static_cast<NSInteger>(request.buttons.size());
    // clang-format off
    [self queue:call sheet:alert over:owner handler:^(NSModalResponse response) {
        if (![self take:call]) {
            return;
        }
        const NSInteger index = response - NSAlertFirstButtonReturn;
        if (index < 0 || index >= count) {
            DialogsAnswer::dismissed(call);
            return;
        }
        DialogsAnswer::button(call, static_cast<std::size_t>(index) + 1);
    }];
    // clang-format on
}

+ (void)showOpenFiles:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = request.multiple;
    panel.message = [self text:request.title];
    NSArray<UTType*>* types = [self contentTypes:request.filters];
    if (types.count > 0) {
        panel.allowedContentTypes = types;
    }
    [self open:panel call:call over:owner];
}

// The file is written on a queue of its own, so a large file never holds the frames back.
+ (void)showSaveFile:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner {
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.message = [self text:request.title];
    panel.nameFieldStringValue = [self text:request.name];
    panel.canCreateDirectories = YES;
    NSArray<UTType*>* types = [self contentTypes:request.filters];
    if (types.count > 0) {
        panel.allowedContentTypes = types;
    }

    NSData* data = [NSData dataWithBytes:request.bytes.data() length:request.bytes.size()];
    // clang-format off
    [self queue:call sheet:panel over:owner handler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            [self write:data to:panel.URL call:call];
            return;
        }
        if ([self take:call]) {
            DialogsAnswer::dismissed(call);
        }
    }];
    // clang-format on
}

+ (void)showOpenFolder:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = [self text:request.title];
    // clang-format off
    [self queue:call sheet:panel over:owner handler:^(NSModalResponse response) {
        if (![self take:call]) {
            return;
        }
        if (response != NSModalResponseOK) {
            DialogsAnswer::dismissed(call);
            return;
        }
        DialogsAnswer::folder(call, panel.URL.path.UTF8String);
    }];
    // clang-format on
}

// The Mac keeps photos as image files, so the panel of images opens in the Pictures folder.
+ (void)showOpenPhotos:(const DialogsRequest&)request call:(uint64_t)call over:(NSWindow*)owner {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = request.multiple;
    panel.message = [self text:request.title];
    panel.allowedContentTypes = @[ UTTypeImage ];
    panel.directoryURL = [NSFileManager.defaultManager URLsForDirectory:NSPicturesDirectory inDomains:NSUserDomainMask].firstObject;
    [self open:panel call:call over:owner];
}

+ (void)open:(NSOpenPanel*)panel call:(uint64_t)call over:(NSWindow*)owner {
    // clang-format off
    [self queue:call sheet:panel over:owner handler:^(NSModalResponse response) {
        if (![self take:call]) {
            return;
        }
        if (response != NSModalResponseOK) {
            DialogsAnswer::dismissed(call);
            return;
        }
        std::vector<DialogsAnswer::File> files;
        for (NSURL* url in panel.URLs) {
            files.push_back({.name = url.lastPathComponent.UTF8String, .path = url.path.UTF8String});
        }
        DialogsAnswer::files(call, files);
    }];
    // clang-format on
}

+ (void)write:(NSData*)data to:(NSURL*)url call:(uint64_t)call {
    // clang-format off
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* error = nil;
        const BOOL written = [data writeToURL:url options:NSDataWritingAtomic error:&error];
        [self wrote:url call:call error:written ? nil : error];
    });
    // clang-format on
}

// The answer of a save goes back to the main thread, where the dialogs live.
+ (void)wrote:(NSURL*)url call:(uint64_t)call error:(NSError*)error {
    // clang-format off
    dispatch_async(dispatch_get_main_queue(), ^{
        [self saved:url call:call error:error];
    });
    // clang-format on
}

+ (void)saved:(NSURL*)url call:(uint64_t)call error:(NSError*)error {
    const BOOL waiting = [self take:call];
    if (error != nil) {
        DialogsAnswer::fail(call, "failed", std::string("The file could not be written. ") + error.localizedDescription.UTF8String);
        return;
    }
    if (waiting) {
        DialogsAnswer::saved(call, {.name = url.lastPathComponent.UTF8String, .path = url.path.UTF8String});
    }
}

// Forgets the call and tells whether it still waited for its answer, which a cancel of the app takes away.
+ (BOOL)take:(uint64_t)call {
    MacosDialogs::State& state = MacosDialogs::getState();
    if (state.shown[@(call)] == nil) {
        return NO;
    }
    [state.shown removeObjectForKey:@(call)];
    return YES;
}

+ (NSAlertStyle)styleOf:(DialogsRequest::Kind)kind {
    switch (kind) {
    case DialogsRequest::Kind::Info:
        return NSAlertStyleInformational;
    case DialogsRequest::Kind::Warning:
        return NSAlertStyleWarning;
    case DialogsRequest::Kind::Error:
        return NSAlertStyleCritical;
    }
    return NSAlertStyleInformational;
}

+ (NSString*)text:(const std::string&)value {
    return @(value.c_str());
}

// The content types of the extensions of the filters, none when there are no filters.
+ (NSArray<UTType*>*)contentTypes:(const std::vector<DialogsRequest::Filter>&)filters {
    NSMutableArray<UTType*>* types = [NSMutableArray array];
    for (const DialogsRequest::Filter& filter : filters) {
        for (const std::string& extension : filter.extensions) {
            UTType* type = [UTType typeWithFilenameExtension:[self text:extension]];
            if (type != nil && ![types containsObject:type]) {
                [types addObject:type];
            }
        }
    }
    return types;
}

@end

const HaylenNativeApi* MacosDialogs::api = nullptr;

void MacosDialogs::use(const HaylenNativeApi& value) noexcept {
    api = &value;
}

void MacosDialogs::show(std::uint64_t call, DialogsRequest request) {
    HaylenNativeWindow window{};
    if (api->getWindow(&window) == 0) {
        DialogsAnswer::fail(call, "failed", "The app has no window to show the dialog on.");
        return;
    }

    NSWindow* owner = (__bridge NSWindow*)window.handle;
    switch (request.method) {
    case DialogsRequest::Method::Message:
        [MacosDialogSheets showMessage:request call:call over:owner];
        return;
    case DialogsRequest::Method::OpenFiles:
        [MacosDialogSheets showOpenFiles:request call:call over:owner];
        return;
    case DialogsRequest::Method::SaveFile:
        [MacosDialogSheets showSaveFile:request call:call over:owner];
        return;
    case DialogsRequest::Method::OpenFolder:
        [MacosDialogSheets showOpenFolder:request call:call over:owner];
        return;
    case DialogsRequest::Method::OpenPhotos:
        [MacosDialogSheets showOpenPhotos:request call:call over:owner];
        return;
    }
}

void MacosDialogs::cancel(std::uint64_t call) {
    [MacosDialogSheets cancel:call];
}

MacosDialogs::State& MacosDialogs::getState() {
    static State* state = new State();
    return *state;
}
