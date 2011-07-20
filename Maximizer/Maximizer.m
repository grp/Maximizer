//
//  Maximizer.m
//  Maximizer
//
//  Created by Grant Paul on 07/16/11.
//  Copyright 2011 Xuzz Productions, LLC. All rights reserved.
//

#import <objc/runtime.h>
#import "Maximizer.h"

static BOOL is_chromium() {
    BOOL chrome = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.google.Chrome"];
    BOOL chromium = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"org.chromium.Chromium"];
    
    return (chrome || chromium);
}

static BOOL window_is_fullscreen(NSWindow *window) {
    return !!([window styleMask] & NSFullScreenWindowMask);
}

static BOOL is_supported_window(NSWindow *window) {
    Class class = [window class];
    NSString *className = NSStringFromClass(class);
    
    // ignore private windows, probably a good idea?
    if ([className hasPrefix:@"_"]) return NO;
    
    // panels are supposedly "auxiliary" windows
    if ([window isKindOfClass:NSClassFromString(@"NSPanel")]) return NO;
    
    // ignore spellcheck/autocorrect
    if ([className hasPrefix:@"NSCorrection"]) return NO;
    
    // combo boxes
    if ([window isKindOfClass:NSClassFromString(@"NSComboBoxWindow")]) return NO;
    
    // full screen toolbars
    if ([window isKindOfClass:NSClassFromString(@"NSToolbarFullScreenWindow")]) return NO;
    
    // open panels
    if ([window isKindOfClass:NSClassFromString(@"NSOpenPanel")]) return NO;
    
    // twitter for mac tooltips
    if ([window isKindOfClass:NSClassFromString(@"ABUITooltipWindow")]) return NO;
    
    // firefox stuff; still has issues as most things are ToolbarWindow/BaseWindow instances
    if ([window isKindOfClass:NSClassFromString(@"PopupWindow")] || [window isKindOfClass:NSClassFromString(@"FI_TFloatingInputWindow")] || [window isKindOfClass:NSClassFromString(@"ComplexTextInputPanel")]) return NO;
    
    // safari completion window
    if ([window isKindOfClass:NSClassFromString(@"CompletionWindow")]) return NO;
    
    // mail
    if ([window isKindOfClass:NSClassFromString(@"TypeAheadWindow")]) return NO;
    
    if (is_chromium()) {
        // chrome bookmark dropdowns
        if ([window isKindOfClass:NSClassFromString(@"BookmarkBarFolderWindow")]) return NO;
        
        // chrome download animations
        if ([window isKindOfClass:NSClassFromString(@"AnimatableImage")]) return NO;
        
        // chrome sign-in prompts
        if ([window isKindOfClass:NSClassFromString(@"GTMWSCOverlayWindow")]) return NO;
        
        // chrome flashblock popover
        if ([window isKindOfClass:NSClassFromString(@"InfoBubbleWindow")]) return NO;
        
        // chrome omnibox suggestion window
        if ([[window contentView] isKindOfClass:NSClassFromString(@"OmniboxPopupView")]) return NO;
    }
    
    // XXX: there are lots more non-content NSWindow subclasses that should be special cased here.
    //      actually, we probably shouldn't special case anything, we should somehow intelligently
    //      figure out which windows are "main content" windows and which are "auxiliary" windows.
    //      but that's quite a lot of work, especially for someone who doesn't know cocoa like me.
    
    return YES;
}

static id (*original_window_initwithcontentrect_stylemask_backing_defer)(NSWindow *self, SEL _cmd, NSRect contentRect, NSUInteger windowStyle, NSBackingStoreType bufferingType, BOOL deferCreation);
static id window_initwithcontentrect_stylemask_backing_defer(NSWindow *self, SEL _cmd, NSRect contentRect, NSUInteger windowStyle, NSBackingStoreType bufferingType, BOOL deferCreation) {
    self = original_window_initwithcontentrect_stylemask_backing_defer(self, _cmd, contentRect, windowStyle, bufferingType, deferCreation);
    
    // run this on the next runloop iteration because we might want
    // to check is_supported_window() after the window has been setup
    dispatch_async(dispatch_get_main_queue(), ^{
        if (is_supported_window(self)) {
#ifdef DEBUG
            // This is useful to determinte the class of malfunctioning NSWindow instances.
            NSLog(@"Window created with content rect of class: %@", [self class]);
#endif
            
            // this adds the full-screen behaviors, keeping the old ones
            [self setCollectionBehavior:[self collectionBehavior]];
        }
    });
    
    return self;
}

static void (*original_window_setcollectionbehavior)(NSWindow *self, SEL _cmd, NSWindowCollectionBehavior behavior);
static void window_setcollectionbehavior(NSWindow *self, SEL _cmd, NSWindowCollectionBehavior behavior) {
    if (is_supported_window(self)) {
        behavior |= NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorFullScreenAuxiliary;
    }
    
    original_window_setcollectionbehavior(self, _cmd, behavior);
}

/* Chromium Hacks {{{ */
@interface BrowserWindowController : NSWindowController <NSWindowDelegate> { }
- (void)layoutSubviews;
@end

static NSSize browserwindowcontroller_window_willusefullscreencontentsize(BrowserWindowController *self, SEL _cmd, NSWindow *window, NSSize proposedSize) {
    [window setFrame:NSMakeRect(0, 0, proposedSize.width, proposedSize.height) display:YES animate:NO];
    [self layoutSubviews];
    return proposedSize;
}

static void browserwindowcontroller_windowdidenterfullscreen(BrowserWindowController *self, SEL _cmd, NSNotification *notification) {
    [self layoutSubviews];
}

static void browserwindowcontroller_windowdidexitfullscreen(BrowserWindowController *self, SEL _cmd, NSNotification *notification) {
    [self layoutSubviews];
}

static CGFloat (*original_browserwindowcontroller_layouttabstripatmaxy_width_fullscreen)(BrowserWindowController *self, SEL _cmd, CGFloat maxY, CGFloat width, BOOL fullscreen);
static CGFloat browserwindowcontroller_layouttabstripatmaxy_width_fullscreen(BrowserWindowController *self, SEL _cmd, CGFloat maxY, CGFloat width, BOOL fullscreen) {
    fullscreen = fullscreen || window_is_fullscreen([self window]);
    
    // This is a hack. The window apparently caches what its delegate responds to,
    // so we need to set the delegate to nil and back so it re-generates that cache
    // and then calls the appropriate delegate methods. Doing it here is an even
    // bigger hack than normal, but this method does get called at one point, so
    // it's probably better than nothing. This isn't needed with CydiaSubstrate. :(
    [[self window] setDelegate:nil];
    [[self window] setDelegate:self];
    
    return original_browserwindowcontroller_layouttabstripatmaxy_width_fullscreen(self, _cmd, maxY, width, fullscreen);
}

static void (*original_browserwindowcontroller_setuposfullscreenbutton)(BrowserWindowController *self, SEL _cmd);
static void browserwindowcontroller_setuposfullscreenbutton(BrowserWindowController *self, SEL _cmd) {
    return;
}

static BOOL (*original_browserwindowcontroller_tabtearingallowed)(BrowserWindowController *self, SEL _cmd);
static BOOL browserwindowcontroller_tabtearingallowed(BrowserWindowController *self, SEL _cmd) {
    // disable tab tearing in fullscreen mode as right now it messes things up pretty badly
    if (window_is_fullscreen([self window])) {
        return NO;
    } else {
        return original_browserwindowcontroller_tabtearingallowed(self, _cmd);
    }
}

static BOOL (*original_browserwindowcontroller_windowmovementallowed)(BrowserWindowController *self, SEL _cmd);
static BOOL browserwindowcontroller_windowmovementallowed(BrowserWindowController *self, SEL _cmd) {
    // this should probably also be disabled
    if (window_is_fullscreen([self window])) {
        return NO;
    } else {
        return original_browserwindowcontroller_windowmovementallowed(self, _cmd);
    }
}
/* }}} */

@implementation Maximizer

+ (void)hookClass:(Class)class selector:(SEL)selector replacement:(IMP)replacement original:(IMP *)original {
    if (class == nil || selector == NULL || replacement == NULL) {
        NSLog(@"ERROR: Couldn't hook because a required argument was nil or NULL.");
        return;
    }
    
    Method method = class_getInstanceMethod(class, selector);
    
    if (method == NULL) {
        NSLog(@"ERROR: Unable to find method [%@ %@].", class, NSStringFromSelector(selector));
        return;
    }
    
    IMP result = method_setImplementation(method, replacement);
    
    if (original != NULL) {
        *original = result;
    }
}

+ (void)addToClass:(Class)class selector:(SEL)selector implementation:(IMP)implementation encoding:(const char *)types {
    BOOL success = class_addMethod(class, selector, implementation, types);
    
    if (!success) {
        NSLog(@"ERROR: Unable to add [%@ %@].", class, NSStringFromSelector(selector));
        return;
    }
}

+ (void)load {
    static Maximizer *maximizer = nil;
    
    if (maximizer == nil) {
        maximizer = [[self alloc] init];
        
#ifdef DEBUG
        NSLog(@"Loading Maximizer into bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
#endif
        
        [[self class] hookClass:[NSWindow class] selector:@selector(initWithContentRect:styleMask:backing:defer:) replacement:(IMP) window_initwithcontentrect_stylemask_backing_defer original:(IMP *) &original_window_initwithcontentrect_stylemask_backing_defer];
        [[self class] hookClass:[NSWindow class] selector:@selector(setCollectionBehavior:) replacement:(IMP) window_setcollectionbehavior original:(IMP *) &original_window_setcollectionbehavior];
        
        if (is_chromium()) {
            [[self class] hookClass:NSClassFromString(@"BrowserWindowController") selector:@selector(setUpOSFullScreenButton) replacement:(IMP) browserwindowcontroller_setuposfullscreenbutton original:(IMP *) &original_browserwindowcontroller_setuposfullscreenbutton];
            [[self class] hookClass:NSClassFromString(@"BrowserWindowController") selector:@selector(layoutTabStripAtMaxY:width:fullscreen:) replacement:(IMP) browserwindowcontroller_layouttabstripatmaxy_width_fullscreen original:(IMP *) &original_browserwindowcontroller_layouttabstripatmaxy_width_fullscreen];
            [[self class] hookClass:NSClassFromString(@"BrowserWindowController") selector:@selector(tabTearingAllowed) replacement:(IMP) browserwindowcontroller_tabtearingallowed original:(IMP *) &original_browserwindowcontroller_tabtearingallowed];
            [[self class] hookClass:NSClassFromString(@"BrowserWindowController") selector:@selector(windowMovementAllowed) replacement:(IMP) browserwindowcontroller_windowmovementallowed original:(IMP *) &original_browserwindowcontroller_windowmovementallowed];
            
            [[self class] addToClass:NSClassFromString(@"BrowserWindowController") selector:@selector(windowDidEnterFullScreen:) implementation:(IMP) browserwindowcontroller_windowdidenterfullscreen encoding:"v@:@"];
            [[self class] addToClass:NSClassFromString(@"BrowserWindowController") selector:@selector(windowDidExitFullScreen:) implementation:(IMP) browserwindowcontroller_windowdidexitfullscreen encoding:"v@:@"];
            [[self class] addToClass:NSClassFromString(@"BrowserWindowController") selector:@selector(window:willUseFullScreenContentSize:) implementation:(IMP) browserwindowcontroller_window_willusefullscreencontentsize encoding:"{nssize=ff}@:@{nssize=ff}"];
        }
        
        for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
            if (is_supported_window(window)) {
                // the hook for this adds the zoom button
                [window setCollectionBehavior:[window collectionBehavior]];
                
                // chrome sets the fullscreen button to enter their fullscreen mode, but we don't want
                // that, so we need to set it back to entering lion's fullscreen mode ourselves. :(
                // this is prevented in the future by nop-ing out the setupOSFullScreenButton method
                if (is_chromium()) {
                    NSButton *fullscreenButton = [window standardWindowButton:NSWindowFullScreenButton];	
                    [fullscreenButton setAction:@selector(toggleFullScreen:)];	
                    [fullscreenButton setTarget:window];	
                }
            }
        }
    }
}

@end
