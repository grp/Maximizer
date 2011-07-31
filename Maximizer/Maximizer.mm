//
//  Maximizer.m
//  Maximizer
//
//  Created by Grant Paul on 07/16/11.
//  Copyright 2011 Xuzz Productions, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#ifdef SUBSTRATE
#import <CydiaSubstrate/CydiaSubstrate.h>
#endif

/* Chromium Prototypes {{{ */

@interface BrowserWindowController : NSWindowController <NSWindowDelegate> { }
- (void)layoutSubviews;
- (BOOL)hasTabStrip;
@end

static BOOL is_chromium() {
    BOOL chrome = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.google.Chrome"];
    BOOL chromium = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"org.chromium.Chromium"];
    
    return (chrome || chromium);
}

/* }}} */

static BOOL window_is_fullscreen(NSWindow *window) {
    return !!([window styleMask] & NSFullScreenWindowMask);
}

// can this window go fullscreen?
static BOOL is_supported_window(NSWindow *window) {
    // a good test is to see if a window has the (+) button in the titlebar
    if (!([window styleMask] & NSResizableWindowMask)) return NO;
    
    NSString *className = NSStringFromClass([window class]);
    
    // ignore private windows, probably a good idea?
    if ([className hasPrefix:@"_"]) return NO;
    
    // fix Mail compose windows
    if ([className isEqualToString:@"ModalDimmingWindow"]) return NO;
    if ([className isEqualToString:@"TypeAheadWindow"]) return NO;
    if ([className isEqualToString:@"MouseTrackingWindow"]) return NO;
    
    // panels are supposedly "auxiliary" windows
    if ([window isKindOfClass:NSClassFromString(@"NSPanel")]) return NO;
    
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
            NSLog(@"Maximizer: Supported window created of class: %@", [self class]);
#endif
            
            // this adds the full-screen behaviors, keeping the old ones
            [self setCollectionBehavior:[self collectionBehavior]];
            
            // chromium popup windows shouldn't go fullscreen without a tabstrip
            // this has to be done here because they are automatically set full-
            // screen before we know that they shouldn't be able to, so we need to
            // undo the damage that was caused before. XXX: this does not work :(
            if (is_chromium()) {
                NSWindowController *controller = [self windowController];
                
                if ([controller isKindOfClass:NSClassFromString(@"BrowserWindowController")]) {
                    BrowserWindowController *browserController = (BrowserWindowController *) controller;
                    
                    [self setCollectionBehavior:([self collectionBehavior] & ~NSWindowCollectionBehaviorFullScreenPrimary)];
                    
                    if (![browserController hasTabStrip] && window_is_fullscreen(self)) {
                        [self toggleFullScreen:nil];
                    }
                }
            }
        } else {
#ifdef DEBUG
            // This is useful to determinte the class of unsupported-but-should-be NSWindow instances.
            NSLog(@"Maximizer: Unsupported window created of class: %@", [self class]);
#endif
        }
    });
    
    return self;
}

static void (*original_window_setcollectionbehavior)(NSWindow *self, SEL _cmd, NSWindowCollectionBehavior behavior);
static void window_setcollectionbehavior(NSWindow *self, SEL _cmd, NSWindowCollectionBehavior behavior) {
    if (is_supported_window(self)) {
        behavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    }
    
    original_window_setcollectionbehavior(self, _cmd, behavior);
}

/* Chromium Hacks {{{ */

static NSSize browserwindowcontroller_window_willusefullscreencontentsize(BrowserWindowController *self, SEL _cmd, NSWindow *window, NSSize proposedSize) {
    [window setFrame:NSMakeRect(0, 0, proposedSize.width, proposedSize.height) display:YES animate:NO];
    [self layoutSubviews];
    return proposedSize;
}

static void browserwindowcontroller_windowwillenterfullscreen(BrowserWindowController *self, SEL _cmd, NSNotification *notification) {
    // it's useful to consider a window in its final state while animating, so we
    // know how to update it before it has finsihed animating to the new state
    [[self window] setStyleMask:([[self window] styleMask] | NSFullScreenWindowMask)];
    [self layoutSubviews];
}

static void browserwindowcontroller_windowwillexitfullscreen(BrowserWindowController *self, SEL _cmd, NSNotification *notification) {
    // it's useful to consider a window in its final state while animating, so we
    // know how to update it before it has finsihed animating to the new state
    [[self window] setStyleMask:([[self window] styleMask] & ~NSFullScreenWindowMask)];
    [self layoutSubviews];
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
    
#ifdef SIMBL
    // This is a hack. The window apparently caches what its delegate responds to,
    // so we need to set the delegate to nil and back so it re-generates that cache
    // and then calls the appropriate delegate methods. Doing it here is an even
    // bigger hack than normal, but this method does get called at one point, so
    // it's probably better than nothing.
    [[self window] setDelegate:nil];
    [[self window] setDelegate:self];
#endif
    
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

static void hook_class(Class cls, SEL selector, IMP replacement, IMP *original) {
#ifdef SUBSTRATE
    MSHookMessageEx(cls, selector, replacement, original);
#endif
    
#ifdef SIMBL
    if (cls == nil || selector == NULL || replacement == NULL) {
        NSLog(@"ERROR: Couldn't hook because a required argument was nil or NULL.");
        return;
    }
    
    Method method = class_getInstanceMethod(cls, selector);
    
    if (method == NULL) {
        NSLog(@"ERROR: Unable to find method [%@ %@].", cls, NSStringFromSelector(selector));
        return;
    }
    
    IMP result = method_setImplementation(method, replacement);
    
    if (original != NULL) {
        *original = result;
    }
#endif
}

static void add_to_class(Class cls, SEL selector, IMP implementation, const char *encoding) {
    BOOL success = class_addMethod(cls, selector, implementation, encoding);   
    
    if (!success) {
        NSLog(@"ERROR: Unable to add [%@ %@].", cls, NSStringFromSelector(selector));
        return;
    }
}

#ifdef SUBSTRATE
__attribute__((constructor)) static void maximizer_init()
#endif
    
#ifdef SIMBL
@interface Maximizer : NSObject { }
@end

@implementation Maximizer
+ (void)load
#endif

{
#ifdef DEBUG
        NSLog(@"Loading Maximizer into bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
#endif
        
    hook_class([NSWindow class], @selector(initWithContentRect:styleMask:backing:defer:), (IMP) window_initwithcontentrect_stylemask_backing_defer, (IMP *) &original_window_initwithcontentrect_stylemask_backing_defer);
    hook_class([NSWindow class], @selector(setCollectionBehavior:), (IMP) window_setcollectionbehavior, (IMP *) &original_window_setcollectionbehavior);
        
    if (is_chromium()) {
        hook_class(NSClassFromString(@"BrowserWindowController"), @selector(setUpOSFullScreenButton), (IMP) browserwindowcontroller_setuposfullscreenbutton, (IMP *) &original_browserwindowcontroller_setuposfullscreenbutton);
        hook_class(NSClassFromString(@"BrowserWindowController"), @selector(layoutTabStripAtMaxY:width:fullscreen:), (IMP) browserwindowcontroller_layouttabstripatmaxy_width_fullscreen, (IMP *) &original_browserwindowcontroller_layouttabstripatmaxy_width_fullscreen);
        hook_class(NSClassFromString(@"BrowserWindowController"), @selector(tabTearingAllowed), (IMP) browserwindowcontroller_tabtearingallowed, (IMP *) &original_browserwindowcontroller_tabtearingallowed);
        hook_class(NSClassFromString(@"BrowserWindowController"), @selector(windowMovementAllowed), (IMP) browserwindowcontroller_windowmovementallowed, (IMP *) &original_browserwindowcontroller_windowmovementallowed);
        
        add_to_class(NSClassFromString(@"BrowserWindowController"), @selector(windowDidEnterFullScreen:), (IMP) browserwindowcontroller_windowdidenterfullscreen, "v@:@");
        add_to_class(NSClassFromString(@"BrowserWindowController"), @selector(windowDidExitFullScreen:), (IMP) browserwindowcontroller_windowdidexitfullscreen, "v@:@");
        add_to_class(NSClassFromString(@"BrowserWindowController"), @selector(windowWillEnterFullScreen:), (IMP) browserwindowcontroller_windowwillenterfullscreen, "v@:@");
        add_to_class(NSClassFromString(@"BrowserWindowController"), @selector(windowWillExitFullScreen:), (IMP) browserwindowcontroller_windowwillexitfullscreen, "v@:@");
        add_to_class(NSClassFromString(@"BrowserWindowController"), @selector(window:willUseFullScreenContentSize:), (IMP) browserwindowcontroller_window_willusefullscreencontentsize, "{nssize=ff}@:@{nssize=ff}");
    }
    
#ifdef SIMBL
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
#endif
}

#ifdef SIMBL
@end
#endif


