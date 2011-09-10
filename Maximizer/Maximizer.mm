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

static void hook_class(Class cls, SEL selector, IMP replacement, IMP *original) {
#if defined(SUBSTRATE)
    MSHookMessageEx(cls, selector, replacement, original);
#elif defined(SIMBL)
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
#else
#error "Must use either CydiaSubstrate or SIMBL."
#endif
}

static void add_to_class(Class cls, SEL selector, IMP implementation, const char *encoding) {
    BOOL success = class_addMethod(cls, selector, implementation, encoding);   
    
    if (!success) {
        NSLog(@"ERROR: Unable to add [%@ %@].", cls, NSStringFromSelector(selector));
        return;
    }
}

#if defined(SUBSTRATE)
__attribute__((constructor)) static void maximizer_init()
#elif defined(SIMBL)
@interface Maximizer : NSObject { }
@end

@implementation Maximizer
+ (void)load
#else
#error "Must use either CydiaSubstrate or SIMBL."
#endif

{
#ifdef DEBUG
        NSLog(@"Loading Maximizer into bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
#endif
        
    hook_class([NSWindow class], @selector(initWithContentRect:styleMask:backing:defer:), (IMP) window_initwithcontentrect_stylemask_backing_defer, (IMP *) &original_window_initwithcontentrect_stylemask_backing_defer);
    hook_class([NSWindow class], @selector(setCollectionBehavior:), (IMP) window_setcollectionbehavior, (IMP *) &original_window_setcollectionbehavior);
    
#ifdef SIMBL
    for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
        if (is_supported_window(window)) {
            // the hook for this adds the zoom button
            [window setCollectionBehavior:[window collectionBehavior]];
        }
    }
#endif
}

#ifdef SIMBL
@end
#endif


