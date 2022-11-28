#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSRect frame = NSMakeRect(0, 0, 480, 270);
    self.window  = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"QLJava QuickLook Plugin Manager";
    [self.window center];
    
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 440, 60)];
    label.stringValue = @"QLJava QuickLook Extension is now installed.\n\nYou can enable or disable the extension in System Settings -> Login Items & Extensions -> Extensions -> Quick Look.";
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.bezeled = NO;
    label.alignment = NSTextAlignmentCenter;
    label.font = [NSFont systemFontOfSize:13];
    
    [self.window.contentView addSubview:label];
    [self.window makeKeyAndOrderFront:nil];
    
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end
