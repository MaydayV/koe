#import "SPStatusBarManager.h"
#import "SPPermissionManager.h"
#import "SPAudioDeviceManager.h"
#import "SPHistoryManager.h"
#import "SPLocalization.h"
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <UserNotifications/UserNotifications.h>
#define L(KEY) [SPLocalization tr:(KEY)]

// Icon size for menu bar (points)
static const CGFloat kIconSize = 18.0;

@interface SPStatusBarManager ()

@property (nonatomic, weak) id<SPStatusBarDelegate> delegate;
@property (nonatomic, strong) SPPermissionManager *permissionManager;
@property (nonatomic, strong) SPAudioDeviceManager *audioDeviceManager;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *statusMenuItem;
@property (nonatomic, strong) NSMenuItem *micPermissionItem;
@property (nonatomic, strong) NSMenuItem *accessibilityPermissionItem;
@property (nonatomic, strong) NSMenuItem *inputMonitoringPermissionItem;
@property (nonatomic, strong) NSMenuItem *notificationPermissionItem;
@property (nonatomic, strong) NSMenuItem *hotkeyDisplayItem;
@property (nonatomic, strong) NSMenuItem *statsCountItem;
@property (nonatomic, strong) NSMenuItem *statsTimeItem;
@property (nonatomic, strong) NSMenuItem *statsSpeedItem;
@property (nonatomic, strong) NSMenuItem *statsHeaderItem;
@property (nonatomic, strong) NSMenuItem *permissionsHeaderItem;
@property (nonatomic, strong) NSMenuItem *microphoneMenuItem;
@property (nonatomic, strong) NSMenuItem *setupWizardMenuItem;
@property (nonatomic, strong) NSMenuItem *openConfigMenuItem;
@property (nonatomic, strong) NSMenuItem *launchAtLoginMenuItem;
@property (nonatomic, strong) NSMenuItem *quitMenuItem;
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic, assign) NSInteger animationFrame;
@property (nonatomic, copy) NSString *currentState;

@end

@implementation SPStatusBarManager

- (instancetype)initWithDelegate:(id<SPStatusBarDelegate>)delegate
               permissionManager:(SPPermissionManager *)permissionManager
              audioDeviceManager:(SPAudioDeviceManager *)audioDeviceManager {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _permissionManager = permissionManager;
        _audioDeviceManager = audioDeviceManager;
        _currentState = @"idle";
        _animationFrame = 0;
        [self setupStatusBar];
    }
    return self;
}

- (void)setupStatusBar {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];

    [self applyIdleIcon];

    // Build menu
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    menu.autoenablesItems = NO;

    // Status display
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"status.ready")
                                                    action:nil
                                             keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [menu addItem:self.statusMenuItem];

    self.hotkeyDisplayItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:L(@"status.hotkey_prefix_format"), [SPLocalization displayNameForTriggerKey:@"fn"]]
                                                        action:nil
                                                 keyEquivalent:@""];
    self.hotkeyDisplayItem.enabled = NO;
    [menu addItem:self.hotkeyDisplayItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Statistics section
    self.statsHeaderItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    self.statsHeaderItem.view = [self headerViewWithTitle:L(@"status.header.statistics")];
    [menu addItem:self.statsHeaderItem];

    self.statsCountItem = [[NSMenuItem alloc] initWithTitle:@"  ..."
                                                    action:nil
                                             keyEquivalent:@""];
    self.statsCountItem.enabled = NO;
    [menu addItem:self.statsCountItem];

    self.statsTimeItem = [[NSMenuItem alloc] initWithTitle:@"  ..."
                                                   action:nil
                                            keyEquivalent:@""];
    self.statsTimeItem.enabled = NO;
    [menu addItem:self.statsTimeItem];

    self.statsSpeedItem = [[NSMenuItem alloc] initWithTitle:@"  ..."
                                                    action:nil
                                             keyEquivalent:@""];
    self.statsSpeedItem.enabled = NO;
    [menu addItem:self.statsSpeedItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Permissions section
    self.permissionsHeaderItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    self.permissionsHeaderItem.view = [self headerViewWithTitle:L(@"status.header.permissions")];
    [menu addItem:self.permissionsHeaderItem];

    self.micPermissionItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:L(@"status.permissions.microphone_format"), L(@"status.permissions.checking")]
                                                       action:nil
                                                keyEquivalent:@""];
    self.micPermissionItem.enabled = NO;
    [menu addItem:self.micPermissionItem];

    self.accessibilityPermissionItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:L(@"status.permissions.accessibility_format"), L(@"status.permissions.checking")]
                                                                 action:nil
                                                          keyEquivalent:@""];
    self.accessibilityPermissionItem.enabled = NO;
    [menu addItem:self.accessibilityPermissionItem];

    self.inputMonitoringPermissionItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:L(@"status.permissions.input_monitoring_format"), L(@"status.permissions.checking")]
                                                                   action:nil
                                                            keyEquivalent:@""];
    self.inputMonitoringPermissionItem.enabled = NO;
    [menu addItem:self.inputMonitoringPermissionItem];

    self.notificationPermissionItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:L(@"status.permissions.notifications_format"), L(@"status.permissions.checking")]
                                                                action:nil
                                                         keyEquivalent:@""];
    self.notificationPermissionItem.enabled = NO;
    [menu addItem:self.notificationPermissionItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Microphone selection submenu
    self.microphoneMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"status.menu.microphone")
                                                           action:nil
                                                    keyEquivalent:@""];
    NSMenu *micSubmenu = [[NSMenu alloc] initWithTitle:L(@"status.menu.microphone")];
    self.microphoneMenuItem.submenu = micSubmenu;
    [menu addItem:self.microphoneMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.setupWizardMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"status.menu.setup_wizard")
                                                        action:@selector(openSetupWizard:)
                                                 keyEquivalent:@","];
    self.setupWizardMenuItem.target = self;
    [menu addItem:self.setupWizardMenuItem];

    self.openConfigMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"status.menu.open_config")
                                                       action:@selector(openConfigFolder:)
                                                keyEquivalent:@""];
    self.openConfigMenuItem.target = self;
    [menu addItem:self.openConfigMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.launchAtLoginMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"status.menu.launch_at_login")
                                                      action:@selector(toggleLaunchAtLogin:)
                                               keyEquivalent:@""];
    self.launchAtLoginMenuItem.target = self;
    if (@available(macOS 13.0, *)) {
        self.launchAtLoginMenuItem.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled)
                          ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:self.launchAtLoginMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.quitMenuItem = [[NSMenuItem alloc] initWithTitle:L(@"status.menu.quit")
                                                 action:@selector(quitApp:)
                                          keyEquivalent:@"q"];
    self.quitMenuItem.target = self;
    [menu addItem:self.quitMenuItem];

    self.statusItem.menu = menu;
}

#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu *)menu {
    [self refreshLocalizedStaticText];
    [self refreshHotkeyDisplay];
    [self refreshPermissionStatus];
    [self refreshStats];
    [self refreshMicrophoneSubmenu:menu];
    if ([self.delegate respondsToSelector:@selector(statusBarMenuDidOpen)]) {
        [self.delegate statusBarMenuDidOpen];
    }
}

- (void)menuDidClose:(NSMenu *)menu {
    if ([self.delegate respondsToSelector:@selector(statusBarMenuDidClose)]) {
        [self.delegate statusBarMenuDidClose];
    }
}

- (void)refreshPermissionStatus {
    BOOL mic = [self.permissionManager isMicrophoneGranted];
    BOOL accessibility = [self.permissionManager isAccessibilityGranted];
    BOOL inputMonitoring = [self.permissionManager isInputMonitoringGranted];

    NSString *micState = mic ? L(@"status.permissions.granted") : L(@"status.permissions.not_granted");
    NSString *accState = accessibility ? L(@"status.permissions.granted") : L(@"status.permissions.not_granted");
    NSString *inputState = inputMonitoring ? L(@"status.permissions.granted") : L(@"status.permissions.not_granted");

    self.micPermissionItem.title = [NSString stringWithFormat:L(@"status.permissions.microphone_format"), micState];
    self.accessibilityPermissionItem.title = [NSString stringWithFormat:L(@"status.permissions.accessibility_format"), accState];
    self.inputMonitoringPermissionItem.title = [NSString stringWithFormat:L(@"status.permissions.input_monitoring_format"), inputState];

    [self.permissionManager checkNotificationPermissionWithCompletion:^(BOOL granted) {
        NSString *notificationState = granted ? L(@"status.permissions.granted") : L(@"status.permissions.not_granted");
        self.notificationPermissionItem.title = [NSString stringWithFormat:L(@"status.permissions.notifications_format"), notificationState];
    }];
}

- (void)refreshStats {
    SPHistoryStats *stats = [[SPHistoryManager sharedManager] aggregateStats];

    // Count display
    NSMutableArray *parts = [NSMutableArray array];
    if (stats.totalCharCount > 0) {
        [parts addObject:[NSString stringWithFormat:L(@"status.stats.chars_format"), (long)stats.totalCharCount]];
    }
    if (stats.totalWordCount > 0) {
        [parts addObject:[NSString stringWithFormat:L(@"status.stats.words_format"), (long)stats.totalWordCount]];
    }
    if (parts.count > 0) {
        self.statsCountItem.title = [NSString stringWithFormat:L(@"status.stats.total_format"),
                                     [parts componentsJoinedByString:@" / "]];
    } else {
        self.statsCountItem.title = [NSString stringWithFormat:L(@"status.stats.total_format"), L(@"status.stats.total_no_data")];
    }

    // Time + session count
    NSInteger totalSec = stats.totalDurationMs / 1000;
    NSInteger min = totalSec / 60;
    NSInteger sec = totalSec % 60;
    if (stats.sessionCount > 0) {
        self.statsTimeItem.title = [NSString stringWithFormat:L(@"status.stats.time_format"),
                                    (long)min, (long)sec, (long)stats.sessionCount];
    } else {
        self.statsTimeItem.title = L(@"status.stats.time_empty");
    }

    // Typing speed
    if (stats.totalDurationMs > 0 && (stats.totalCharCount + stats.totalWordCount) > 0) {
        double minutes = (double)stats.totalDurationMs / 60000.0;
        if (stats.totalCharCount > stats.totalWordCount) {
            // Primarily Chinese
            double speed = (double)stats.totalCharCount / minutes;
            self.statsSpeedItem.title = [NSString stringWithFormat:L(@"status.stats.speed_chars"), speed];
        } else {
            // Primarily English
            double speed = (double)stats.totalWordCount / minutes;
            self.statsSpeedItem.title = [NSString stringWithFormat:L(@"status.stats.speed_words"), speed];
        }
    } else {
        self.statsSpeedItem.title = L(@"status.stats.speed_empty");
    }
}

- (void)refreshHotkeyDisplay {
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:@".koe/config.yaml"];
    NSString *yaml = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];

    // Simple extraction of trigger_key value from config
    NSString *triggerKey = @"fn";
    if (yaml) {
        NSArray<NSString *> *lines = [yaml componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed hasPrefix:@"trigger_key:"]) {
                NSString *value = [trimmed substringFromIndex:@"trigger_key:".length];
                value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                // Strip quotes
                if (value.length >= 2 && [value hasPrefix:@"\""] && [value hasSuffix:@"\""]) {
                    value = [value substringWithRange:NSMakeRange(1, value.length - 2)];
                }
                // Strip inline comment for unquoted values
                NSRange commentRange = [value rangeOfString:@" #"];
                if (commentRange.location != NSNotFound) {
                    value = [[value substringToIndex:commentRange.location]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
                if (value.length > 0) triggerKey = value;
                break;
            }
        }
    }

    // Map config value to display name
    NSString *displayName = [SPLocalization displayNameForTriggerKey:triggerKey];
    self.hotkeyDisplayItem.title = [NSString stringWithFormat:L(@"status.hotkey_prefix_format"), displayName];
}

#pragma mark - Microphone Selection

- (void)refreshMicrophoneSubmenu:(NSMenu *)menu {
    (void)menu;
    NSMenu *submenu = self.microphoneMenuItem.submenu;
    if (!submenu) return;
    [submenu removeAllItems];

    NSString *selectedUID = self.audioDeviceManager.selectedDeviceUID;
    NSArray<SPAudioInputDevice *> *devices = [self.audioDeviceManager availableInputDevices];

    // Check if selected device is currently available
    BOOL selectedFound = NO;
    if (selectedUID) {
        for (SPAudioInputDevice *device in devices) {
            if ([device.uid isEqualToString:selectedUID]) {
                selectedFound = YES;
                break;
            }
        }
    }

    // "System Default" option
    NSMenuItem *defaultItem = [[NSMenuItem alloc] initWithTitle:L(@"status.menu.system_default")
                                                        action:@selector(selectAudioDevice:)
                                                 keyEquivalent:@""];
    defaultItem.target = self;
    defaultItem.representedObject = nil;
    defaultItem.state = (selectedUID == nil) ? NSControlStateValueOn : NSControlStateValueOff;
    [submenu addItem:defaultItem];

    if (devices.count > 0) {
        [submenu addItem:[NSMenuItem separatorItem]];
    }

    // Available input devices
    // NOTE: Only device.name is shown. If the user has multiple devices with identical
    // names (e.g. two identical USB mics), they cannot be distinguished visually.
    // A future improvement could append a disambiguator (manufacturer, UID suffix, etc.).
    for (SPAudioInputDevice *device in devices) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:device.name
                                                      action:@selector(selectAudioDevice:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = device.uid;
        item.state = [device.uid isEqualToString:selectedUID] ? NSControlStateValueOn : NSControlStateValueOff;
        [submenu addItem:item];
    }

    // Show disconnected but still-selected device as a greyed-out item
    if (selectedUID && !selectedFound) {
        NSString *deviceName = self.audioDeviceManager.selectedDeviceName ?: selectedUID;
        [submenu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *unavailableItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:L(@"status.menu.unavailable_format"), deviceName]
                                                                action:nil
                                                         keyEquivalent:@""];
        unavailableItem.state = NSControlStateValueOn;
        unavailableItem.enabled = NO;
        [submenu addItem:unavailableItem];
    }
}

- (void)selectAudioDevice:(NSMenuItem *)sender {
    NSString *uid = sender.representedObject;
    NSString *name = uid ? sender.title : nil;
    [self.audioDeviceManager selectDevice:uid name:name];
    NSLog(@"[Koe] Audio device selected: %@", uid ?: @"System Default");

    if ([self.delegate respondsToSelector:@selector(statusBarDidSelectAudioDeviceWithUID:)]) {
        [self.delegate statusBarDidSelectAudioDeviceWithUID:uid];
    }
}

#pragma mark - Helpers

- (NSView *)headerViewWithTitle:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    label.textColor = [NSColor labelColor];
    [label sizeToFit];

    // Match standard menu item padding
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, label.frame.size.height + 4)];
    label.frame = NSMakeRect(20, 2, label.frame.size.width, label.frame.size.height);
    [container addSubview:label];
    return container;
}

#pragma mark - Custom Icon Drawing

/// Create a template image drawn with the given block. Template images auto-adapt to dark/light mode.
- (NSImage *)templateImageWithDrawing:(void (^)(NSSize size))drawBlock {
    NSSize size = NSMakeSize(kIconSize, kIconSize);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        drawBlock(size);
        return YES;
    }];
    image.template = YES;
    return image;
}

/// Idle: five static waveform bars — a calm, resting audio visualizer matching recording style
- (void)applyIdleIcon {
    NSImage *icon = [self templateImageWithDrawing:^(NSSize size) {
        CGFloat barWidth = 2.0;
        CGFloat spacing = 2.5;
        CGFloat centerX = size.width / 2.0;
        CGFloat centerY = size.height / 2.0;

        // Heights for 5 bars — symmetric resting state (short, medium, tall, medium, short)
        CGFloat heights[] = {4.0, 7.0, 11.0, 7.0, 4.0};
        NSInteger barCount = 5;
        CGFloat totalWidth = barCount * barWidth + (barCount - 1) * spacing;
        CGFloat startX = centerX - totalWidth / 2.0;

        [[NSColor blackColor] setFill];
        for (NSInteger i = 0; i < barCount; i++) {
            CGFloat x = startX + i * (barWidth + spacing);
            CGFloat h = heights[i];
            CGFloat y = centerY - h / 2.0;
            NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, barWidth, h)
                                                               xRadius:barWidth / 2.0
                                                               yRadius:barWidth / 2.0];
            [bar fill];
        }
    }];
    self.statusItem.button.image = icon;
}

/// Recording: animated waveform bars with varying heights — voice activity
- (void)applyRecordingIconWithFrame:(NSInteger)frame {
    // 5 bars, heights shift each frame to create a wave animation
    NSImage *icon = [self templateImageWithDrawing:^(NSSize size) {
        CGFloat barWidth = 2.0;
        CGFloat spacing = 2.5;
        CGFloat centerX = size.width / 2.0;
        CGFloat centerY = size.height / 2.0;
        NSInteger barCount = 5;

        CGFloat totalWidth = barCount * barWidth + (barCount - 1) * spacing;
        CGFloat startX = centerX - totalWidth / 2.0;

        [[NSColor blackColor] setFill];
        for (NSInteger i = 0; i < barCount; i++) {
            // Sine wave pattern that shifts with frame
            double phase = (double)(i + frame) * 0.8;
            CGFloat h = 4.0 + 9.0 * fabs(sin(phase));
            CGFloat x = startX + i * (barWidth + spacing);
            CGFloat y = centerY - h / 2.0;
            NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, barWidth, h)
                                                               xRadius:barWidth / 2.0
                                                               yRadius:barWidth / 2.0];
            [bar fill];
        }
    }];
    self.statusItem.button.image = icon;
}

/// Processing: pulsing dot pattern (thinking/working)
- (void)applyProcessingIconWithFrame:(NSInteger)frame {
    NSImage *icon = [self templateImageWithDrawing:^(NSSize size) {
        CGFloat centerY = size.height / 2.0;
        CGFloat centerX = size.width / 2.0;
        CGFloat dotSpacing = 5.0;
        NSInteger dotCount = 3;
        CGFloat totalWidth = (dotCount - 1) * dotSpacing;
        CGFloat startX = centerX - totalWidth / 2.0;

        for (NSInteger i = 0; i < dotCount; i++) {
            // Cascade: each dot pulses in sequence
            double phase = (double)(frame - i) * 0.7;
            CGFloat radius = 1.5 + 1.5 * fmax(0, sin(phase));
            CGFloat alpha = 0.4 + 0.6 * fmax(0, sin(phase));
            CGFloat x = startX + i * dotSpacing;

            [[NSColor colorWithWhite:0 alpha:alpha] setFill];
            NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:
                NSMakeRect(x - radius, centerY - radius, radius * 2, radius * 2)];
            [dot fill];
        }
    }];
    self.statusItem.button.image = icon;
}

/// Error: X mark
- (void)applyErrorIcon {
    NSImage *icon = [self templateImageWithDrawing:^(NSSize size) {
        CGFloat centerX = size.width / 2.0;
        CGFloat centerY = size.height / 2.0;
        CGFloat arm = 4.0;

        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 2.0;
        path.lineCapStyle = NSLineCapStyleRound;

        [path moveToPoint:NSMakePoint(centerX - arm, centerY - arm)];
        [path lineToPoint:NSMakePoint(centerX + arm, centerY + arm)];
        [path moveToPoint:NSMakePoint(centerX + arm, centerY - arm)];
        [path lineToPoint:NSMakePoint(centerX - arm, centerY + arm)];

        [[NSColor blackColor] setStroke];
        [path stroke];
    }];
    self.statusItem.button.image = icon;
}

/// Pasting: checkmark
- (void)applyPasteIcon {
    NSImage *icon = [self templateImageWithDrawing:^(NSSize size) {
        CGFloat centerX = size.width / 2.0;
        CGFloat centerY = size.height / 2.0;

        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 2.0;
        path.lineCapStyle = NSLineCapStyleRound;
        path.lineJoinStyle = NSLineJoinStyleRound;

        // Checkmark
        [path moveToPoint:NSMakePoint(centerX - 4, centerY)];
        [path lineToPoint:NSMakePoint(centerX - 1, centerY - 3.5)];
        [path lineToPoint:NSMakePoint(centerX + 5, centerY + 4)];

        [[NSColor blackColor] setStroke];
        [path stroke];
    }];
    self.statusItem.button.image = icon;
}

#pragma mark - State Updates

- (void)updateState:(NSString *)state {
    self.currentState = state;
    [self stopAnimation];

    if ([state isEqualToString:@"idle"] || [state isEqualToString:@"completed"]) {
        self.statusMenuItem.title = L(@"status.ready");
        [self applyIdleIcon];

    } else if ([state hasPrefix:@"recording"]) {
        self.statusMenuItem.title = L(@"status.listening");
        [self startRecordingAnimation];

    } else if ([state isEqualToString:@"connecting_asr"]) {
        self.statusMenuItem.title = L(@"status.connecting");
        [self startProcessingAnimation];

    } else if ([state isEqualToString:@"finalizing_asr"]) {
        self.statusMenuItem.title = L(@"status.recognizing");
        [self startProcessingAnimation];

    } else if ([state isEqualToString:@"correcting"]) {
        self.statusMenuItem.title = L(@"status.thinking");
        [self startProcessingAnimation];

    } else if ([state hasPrefix:@"preparing_paste"] || [state isEqualToString:@"pasting"]) {
        self.statusMenuItem.title = L(@"status.pasting");
        [self applyPasteIcon];

    } else if ([state isEqualToString:@"error"] || [state isEqualToString:@"failed"]) {
        self.statusMenuItem.title = L(@"status.error");
        [self applyErrorIcon];

    } else {
        self.statusMenuItem.title = L(@"status.working");
        [self startProcessingAnimation];
    }
}

- (void)refreshLocalizedStaticText {
    self.statsHeaderItem.view = [self headerViewWithTitle:L(@"status.header.statistics")];
    self.permissionsHeaderItem.view = [self headerViewWithTitle:L(@"status.header.permissions")];
    self.microphoneMenuItem.title = L(@"status.menu.microphone");
    self.microphoneMenuItem.submenu.title = L(@"status.menu.microphone");
    self.setupWizardMenuItem.title = L(@"status.menu.setup_wizard");
    self.openConfigMenuItem.title = L(@"status.menu.open_config");
    self.launchAtLoginMenuItem.title = L(@"status.menu.launch_at_login");
    self.quitMenuItem.title = L(@"status.menu.quit");
    [self updateState:self.currentState];
}

#pragma mark - Animations

- (void)startRecordingAnimation {
    self.animationFrame = 0;
    [self applyRecordingIconWithFrame:0];
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.15
                                                         repeats:YES
                                                           block:^(NSTimer *timer) {
        self.animationFrame++;
        [self applyRecordingIconWithFrame:self.animationFrame];
    }];
}

- (void)startProcessingAnimation {
    self.animationFrame = 0;
    [self applyProcessingIconWithFrame:0];
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                         repeats:YES
                                                           block:^(NSTimer *timer) {
        self.animationFrame++;
        [self applyProcessingIconWithFrame:self.animationFrame];
    }];
}

- (void)stopAnimation {
    [self.animationTimer invalidate];
    self.animationTimer = nil;
    self.animationFrame = 0;
}

#pragma mark - Actions

- (void)openSetupWizard:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidSelectSetupWizard)]) {
        [self.delegate statusBarDidSelectSetupWizard];
    }
}

- (void)openConfigFolder:(id)sender {
    NSString *path = [NSString stringWithFormat:@"%@/.koe", NSHomeDirectory()];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)reloadConfig:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidSelectReloadConfig)]) {
        [self.delegate statusBarDidSelectReloadConfig];
    }
}

- (void)toggleLaunchAtLogin:(NSMenuItem *)sender {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = SMAppService.mainAppService;
        NSError *error = nil;
        if (service.status == SMAppServiceStatusEnabled) {
            [service unregisterAndReturnError:&error];
            sender.state = NSControlStateValueOff;
        } else {
            [service registerAndReturnError:&error];
            sender.state = NSControlStateValueOn;
        }
        if (error) {
            NSLog(@"[Koe] Launch at login toggle failed: %@", error.localizedDescription);
        }
    }
}

- (void)quitApp:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidSelectQuit)]) {
        [self.delegate statusBarDidSelectQuit];
    } else {
        [NSApp terminate:nil];
    }
}

- (void)dealloc {
    [self stopAnimation];
}

@end
