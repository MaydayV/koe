#import "SPSetupWizardWindowController.h"
#import "SPLocalization.h"
#import <Cocoa/Cocoa.h>

static NSString *const kConfigDir = @".koe";
static NSString *const kConfigFile = @"config.yaml";
static NSString *const kDictionaryFile = @"dictionary.txt";
static NSString *const kSystemPromptFile = @"system_prompt.txt";
#define L(KEY) [SPLocalization tr:(KEY)]

// ─── YAML helpers (minimal, line-based) ─────────────────────────────
// We parse/write the config.yaml with simple line-based logic to avoid
// pulling in a YAML library.  The config file is flat enough for this.

static NSString *configDirPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:kConfigDir];
}

static NSString *configFilePath(void) {
    return [configDirPath() stringByAppendingPathComponent:kConfigFile];
}

/// Read a top-level or nested YAML value.  `keyPath` e.g. @"asr.app_key".
/// Handles `key: "value"` and `key: value`.  Returns @"" if not found.
static NSString *yamlRead(NSString *yaml, NSString *keyPath) {
    NSArray<NSString *> *parts = [keyPath componentsSeparatedByString:@"."];
    if (parts.count == 0) return @"";

    NSArray<NSString *> *lines = [yaml componentsSeparatedByString:@"\n"];
    BOOL inSection = (parts.count == 1);  // top-level key needs no section
    NSString *section = parts.count > 1 ? parts[0] : nil;
    NSString *key = parts.lastObject;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;

        // Check section header (no leading whitespace, ends with :)
        if (section && !inSection) {
            if (![line hasPrefix:@" "] && ![line hasPrefix:@"\t"]) {
                NSString *sectionCandidate = [trimmed stringByReplacingOccurrencesOfString:@":" withString:@""];
                sectionCandidate = [sectionCandidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([sectionCandidate isEqualToString:section]) {
                    inSection = YES;
                }
            }
            continue;
        }

        // If we were in a section and hit a new top-level key, stop
        if (section && inSection && ![line hasPrefix:@" "] && ![line hasPrefix:@"\t"]) {
            break;
        }

        // Match key
        NSString *prefix = [NSString stringWithFormat:@"%@:", key];
        if ([trimmed hasPrefix:prefix]) {
            NSString *value = [trimmed substringFromIndex:prefix.length];
            value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            // Strip inline comment first (before quote removal).
            // Be careful not to strip '#' inside quoted strings.
            if ([value hasPrefix:@"\""]) {
                // Find the closing quote, then strip any comment after it
                NSRange closeQuote = [value rangeOfString:@"\"" options:0 range:NSMakeRange(1, value.length - 1)];
                if (closeQuote.location != NSNotFound) {
                    value = [value substringToIndex:closeQuote.location + 1];
                }
            } else {
                NSRange commentRange = [value rangeOfString:@" #"];
                if (commentRange.location != NSNotFound) {
                    value = [[value substringToIndex:commentRange.location]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
            }
            // Strip surrounding quotes
            if (value.length >= 2 &&
                [value hasPrefix:@"\""] && [value hasSuffix:@"\""]) {
                value = [value substringWithRange:NSMakeRange(1, value.length - 2)];
            }
            return value;
        }
    }
    return @"";
}

/// Set a value in the YAML string.  If the key exists, replace; otherwise append under section.
static NSString *yamlWrite(NSString *yaml, NSString *keyPath, NSString *value) {
    NSArray<NSString *> *parts = [keyPath componentsSeparatedByString:@"."];
    NSString *section = parts.count > 1 ? parts[0] : nil;
    NSString *key = parts.lastObject;

    // Quote the value if it contains special chars or is empty
    NSString *quotedValue;
    if (value.length == 0 ||
        [value rangeOfString:@" "].location != NSNotFound ||
        [value rangeOfString:@"#"].location != NSNotFound ||
        [value rangeOfString:@":"].location != NSNotFound ||
        [value rangeOfString:@"\""].location != NSNotFound ||
        [value rangeOfString:@"$"].location != NSNotFound ||
        [value rangeOfString:@"@"].location != NSNotFound ||
        [value hasPrefix:@"wss://"] || [value hasPrefix:@"https://"] || [value hasPrefix:@"http://"]) {
        quotedValue = [NSString stringWithFormat:@"\"%@\"", value];
    } else {
        quotedValue = value;
    }

    NSMutableArray<NSString *> *lines = [[yaml componentsSeparatedByString:@"\n"] mutableCopy];
    BOOL inSection = (section == nil);
    BOOL found = NO;
    NSString *indent = section ? @"  " : @"";

    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;

        if (section && !inSection) {
            if (![line hasPrefix:@" "] && ![line hasPrefix:@"\t"]) {
                NSString *s = [trimmed stringByReplacingOccurrencesOfString:@":" withString:@""];
                s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([s isEqualToString:section]) {
                    inSection = YES;
                }
            }
            continue;
        }

        if (section && inSection && ![line hasPrefix:@" "] && ![line hasPrefix:@"\t"]) {
            // Went past our section — insert before this line
            NSString *newLine = [NSString stringWithFormat:@"%@%@: %@", indent, key, quotedValue];
            [lines insertObject:newLine atIndex:i];
            found = YES;
            break;
        }

        NSString *prefix = [NSString stringWithFormat:@"%@:", key];
        if ([trimmed hasPrefix:prefix]) {
            // Preserve any inline comment
            NSString *newLine = [NSString stringWithFormat:@"%@%@: %@", indent, key, quotedValue];
            lines[i] = newLine;
            found = YES;
            break;
        }
    }

    if (!found) {
        // Append at end of section or file
        if (section) {
            // Find end of section
            BOOL sectionFound = NO;
            NSInteger insertIdx = (NSInteger)lines.count;
            for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
                NSString *line = lines[i];
                NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (!sectionFound) {
                    if (![line hasPrefix:@" "] && ![line hasPrefix:@"\t"] && trimmed.length > 0 && ![trimmed hasPrefix:@"#"]) {
                        NSString *s = [trimmed stringByReplacingOccurrencesOfString:@":" withString:@""];
                        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        if ([s isEqualToString:section]) {
                            sectionFound = YES;
                        }
                    }
                } else {
                    if (![line hasPrefix:@" "] && ![line hasPrefix:@"\t"] && trimmed.length > 0 && ![trimmed hasPrefix:@"#"]) {
                        insertIdx = i;
                        break;
                    }
                }
            }
            if (!sectionFound) {
                // Add section
                [lines addObject:@""];
                [lines addObject:[NSString stringWithFormat:@"%@:", section]];
                insertIdx = (NSInteger)lines.count;
            }
            NSString *newLine = [NSString stringWithFormat:@"%@%@: %@", indent, key, quotedValue];
            [lines insertObject:newLine atIndex:insertIdx];
        } else {
            [lines addObject:[NSString stringWithFormat:@"%@: %@", key, quotedValue]];
        }
    }

    return [lines componentsJoinedByString:@"\n"];
}

// ─── Window Controller ──────────────────────────────────────────────

@interface SPSetupWizardWindowController ()

// General fields
@property (nonatomic, strong) NSPopUpButton *uiLanguagePopup;

// ASR fields
@property (nonatomic, strong) NSPopUpButton *asrProviderPopup;
@property (nonatomic, strong) NSTextField *asrAppKeyField;
@property (nonatomic, strong) NSTextField *asrAccessKeyField;
@property (nonatomic, strong) NSTextField *qwenApiKeyField;

// LLM fields
@property (nonatomic, strong) NSButton *llmEnabledCheckbox;
@property (nonatomic, strong) NSTextField *llmBaseUrlField;
@property (nonatomic, strong) NSTextField *llmApiKeyField;
@property (nonatomic, strong) NSTextField *llmModelField;
@property (nonatomic, strong) NSButton *llmTestButton;
@property (nonatomic, strong) NSTextField *llmTestResultLabel;

// Hotkey
@property (nonatomic, strong) NSPopUpButton *hotkeyPopup;

// Dictionary
@property (nonatomic, strong) NSTextView *dictionaryTextView;

// System Prompt
@property (nonatomic, strong) NSTextView *systemPromptTextView;

@property (nonatomic, strong) NSTabView *tabView;

@end

@implementation SPSetupWizardWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 580, 480)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:YES];
    window.title = L(@"wizard.window_title");
    window.minSize = NSMakeSize(520, 420);

    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
        [self loadCurrentValues];
    }
    return self;
}

- (void)showWindow:(id)sender {
    [self loadCurrentValues];
    [self.window center];
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

// ─── Build UI ───────────────────────────────────────────────────────

- (void)buildUI {
    NSView *content = self.window.contentView;

    // Tab view
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(16, 56, 548, 408)];
    self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [self.tabView addTabViewItem:[self buildGeneralTab]];
    [self.tabView addTabViewItem:[self buildAsrTab]];
    [self.tabView addTabViewItem:[self buildLlmTab]];
    [self.tabView addTabViewItem:[self buildHotkeyTab]];
    [self.tabView addTabViewItem:[self buildDictionaryTab]];
    [self.tabView addTabViewItem:[self buildSystemPromptTab]];

    [content addSubview:self.tabView];

    // Save button
    NSButton *saveButton = [NSButton buttonWithTitle:L(@"wizard.button.save") target:self action:@selector(saveConfig:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.keyEquivalent = @"\r";  // Enter key
    saveButton.frame = NSMakeRect(480, 14, 80, 32);
    saveButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:saveButton];

    // Cancel button
    NSButton *cancelButton = [NSButton buttonWithTitle:L(@"wizard.button.cancel") target:self action:@selector(cancelSetup:)];
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.keyEquivalent = @"\033";  // Escape key
    cancelButton.frame = NSMakeRect(392, 14, 80, 32);
    cancelButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:cancelButton];
}

- (NSTabViewItem *)buildGeneralTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    tab.label = L(@"wizard.tab.general");

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];

    CGFloat y = 310;
    CGFloat labelW = 120;
    CGFloat fieldX = 136;

    NSTextField *desc = [self descriptionLabel:L(@"wizard.general.description")];
    desc.frame = NSMakeRect(16, y - 10, 500, 40);
    [view addSubview:desc];
    y -= 60;

    [view addSubview:[self labelWithTitle:L(@"wizard.general.language_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.uiLanguagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 2, 220, 26) pullsDown:NO];
    [self.uiLanguagePopup addItemsWithTitles:@[L(@"wizard.lang.english"), L(@"wizard.lang.chinese")]];
    [self.uiLanguagePopup itemAtIndex:0].representedObject = @"en";
    [self.uiLanguagePopup itemAtIndex:1].representedObject = @"zh";
    [view addSubview:self.uiLanguagePopup];

    tab.view = view;
    return tab;
}

- (NSTabViewItem *)buildAsrTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"asr"];
    tab.label = L(@"wizard.tab.asr");

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];

    CGFloat y = 310;
    CGFloat labelW = 120;
    CGFloat fieldX = 136;
    CGFloat fieldW = 360;

    // Description
    NSTextField *desc = [self descriptionLabel:L(@"wizard.asr.description")];
    desc.frame = NSMakeRect(16, y - 10, 500, 48);
    [view addSubview:desc];
    y -= 70;

    // Provider
    [view addSubview:[self labelWithTitle:L(@"wizard.asr.provider_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.asrProviderPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y - 2, 220, 26) pullsDown:NO];
    [self.asrProviderPopup addItemsWithTitles:@[@"Doubao", @"Qwen"]];
    [self.asrProviderPopup itemAtIndex:0].representedObject = @"doubao";
    [self.asrProviderPopup itemAtIndex:1].representedObject = @"qwen";
    [self.asrProviderPopup setTarget:self];
    [self.asrProviderPopup setAction:@selector(asrProviderChanged:)];
    [view addSubview:self.asrProviderPopup];
    y -= 36;

    // Doubao App Key
    [view addSubview:[self labelWithTitle:L(@"wizard.asr.app_key_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.asrAppKeyField = [self textField:NSMakeRect(fieldX, y, fieldW, 22) placeholder:L(@"wizard.asr.placeholder.app_key")];
    [view addSubview:self.asrAppKeyField];
    y -= 36;

    // Doubao Access Key
    [view addSubview:[self labelWithTitle:L(@"wizard.asr.access_key_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.asrAccessKeyField = [self textField:NSMakeRect(fieldX, y, fieldW, 22) placeholder:L(@"wizard.asr.placeholder.access_key")];
    [view addSubview:self.asrAccessKeyField];
    y -= 36;

    // Qwen API Key
    [view addSubview:[self labelWithTitle:L(@"wizard.asr.qwen_api_key_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.qwenApiKeyField = [self textField:NSMakeRect(fieldX, y, fieldW, 22) placeholder:L(@"wizard.asr.placeholder.qwen_api_key")];
    [view addSubview:self.qwenApiKeyField];

    tab.view = view;
    return tab;
}

- (NSTabViewItem *)buildLlmTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"llm"];
    tab.label = L(@"wizard.tab.llm");

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];

    CGFloat y = 310;
    CGFloat labelW = 120;
    CGFloat fieldX = 136;
    CGFloat fieldW = 360;

    // Description
    NSTextField *desc = [self descriptionLabel:L(@"wizard.llm.description")];
    desc.frame = NSMakeRect(16, y - 30, 500, 80);
    [view addSubview:desc];
    y -= 100;

    // Enabled toggle
    self.llmEnabledCheckbox = [NSButton checkboxWithTitle:L(@"wizard.llm.enable")
                                                   target:self
                                                   action:@selector(llmEnabledToggled:)];
    self.llmEnabledCheckbox.frame = NSMakeRect(16, y, 300, 22);
    [view addSubview:self.llmEnabledCheckbox];
    y -= 36;

    // Base URL
    [view addSubview:[self labelWithTitle:L(@"wizard.llm.base_url_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.llmBaseUrlField = [self textField:NSMakeRect(fieldX, y, fieldW, 22) placeholder:@"https://api.openai.com/v1"];
    [view addSubview:self.llmBaseUrlField];
    y -= 36;

    // API Key
    [view addSubview:[self labelWithTitle:L(@"wizard.llm.api_key_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.llmApiKeyField = [self textField:NSMakeRect(fieldX, y, fieldW, 22) placeholder:@"sk-..."];
    [view addSubview:self.llmApiKeyField];
    y -= 36;

    // Model
    [view addSubview:[self labelWithTitle:L(@"wizard.llm.model_label") frame:NSMakeRect(16, y, labelW, 22)]];
    self.llmModelField = [self textField:NSMakeRect(fieldX, y, fieldW, 22) placeholder:@"gpt-4o-mini"];
    [view addSubview:self.llmModelField];
    y -= 42;

    // Test connection button + result label
    self.llmTestButton = [NSButton buttonWithTitle:L(@"wizard.llm.test_connection") target:self action:@selector(testLlmConnection:)];
    self.llmTestButton.bezelStyle = NSBezelStyleRounded;
    self.llmTestButton.frame = NSMakeRect(fieldX, y, 130, 28);
    [view addSubview:self.llmTestButton];

    self.llmTestResultLabel = [NSTextField labelWithString:@""];
    self.llmTestResultLabel.frame = NSMakeRect(fieldX + 140, y + 4, 250, 20);
    self.llmTestResultLabel.font = [NSFont systemFontOfSize:12];
    self.llmTestResultLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [view addSubview:self.llmTestResultLabel];

    tab.view = view;
    return tab;
}

- (NSTabViewItem *)buildHotkeyTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"hotkey"];
    tab.label = L(@"wizard.tab.hotkey");

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];

    CGFloat y = 310;

    NSTextField *desc = [self descriptionLabel:L(@"wizard.hotkey.description")];
    desc.frame = NSMakeRect(16, y - 10, 500, 48);
    [view addSubview:desc];
    y -= 70;

    [view addSubview:[self labelWithTitle:L(@"wizard.hotkey.trigger_key_label") frame:NSMakeRect(16, y, 120, 22)]];

    self.hotkeyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(136, y - 2, 220, 26) pullsDown:NO];
    [self.hotkeyPopup addItemsWithTitles:@[
        [SPLocalization tr:@"hotkey.fn_globe"],
        [SPLocalization tr:@"hotkey.left_option"],
        [SPLocalization tr:@"hotkey.right_option"],
        [SPLocalization tr:@"hotkey.left_command"],
        [SPLocalization tr:@"hotkey.right_command"],
    ]];
    // Tag each item with its config value for easy lookup
    [self.hotkeyPopup itemAtIndex:0].representedObject = @"fn";
    [self.hotkeyPopup itemAtIndex:1].representedObject = @"left_option";
    [self.hotkeyPopup itemAtIndex:2].representedObject = @"right_option";
    [self.hotkeyPopup itemAtIndex:3].representedObject = @"left_command";
    [self.hotkeyPopup itemAtIndex:4].representedObject = @"right_command";
    [view addSubview:self.hotkeyPopup];

    tab.view = view;
    return tab;
}

- (NSTabViewItem *)buildDictionaryTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"dictionary"];
    tab.label = L(@"wizard.tab.dictionary");

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];

    NSTextField *desc = [self descriptionLabel:L(@"wizard.dictionary.description")];
    desc.frame = NSMakeRect(16, 310, 500, 40);
    [view addSubview:desc];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 10, 496, 295)];
    scrollView.hasVerticalScroller = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.borderType = NSBezelBorder;

    self.dictionaryTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 490, 290)];
    self.dictionaryTextView.minSize = NSMakeSize(0, 290);
    self.dictionaryTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.dictionaryTextView.verticallyResizable = YES;
    self.dictionaryTextView.horizontallyResizable = NO;
    self.dictionaryTextView.autoresizingMask = NSViewWidthSizable;
    self.dictionaryTextView.textContainer.containerSize = NSMakeSize(490, FLT_MAX);
    self.dictionaryTextView.textContainer.widthTracksTextView = YES;
    self.dictionaryTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.dictionaryTextView.allowsUndo = YES;

    scrollView.documentView = self.dictionaryTextView;
    [view addSubview:scrollView];

    tab.view = view;
    return tab;
}

- (NSTabViewItem *)buildSystemPromptTab {
    NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:@"system_prompt"];
    tab.label = L(@"wizard.tab.system_prompt");

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];

    NSTextField *desc = [self descriptionLabel:L(@"wizard.system_prompt.description")];
    desc.frame = NSMakeRect(16, 310, 500, 40);
    [view addSubview:desc];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 10, 496, 295)];
    scrollView.hasVerticalScroller = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.borderType = NSBezelBorder;

    self.systemPromptTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 490, 290)];
    self.systemPromptTextView.minSize = NSMakeSize(0, 290);
    self.systemPromptTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.systemPromptTextView.verticallyResizable = YES;
    self.systemPromptTextView.horizontallyResizable = NO;
    self.systemPromptTextView.autoresizingMask = NSViewWidthSizable;
    self.systemPromptTextView.textContainer.containerSize = NSMakeSize(490, FLT_MAX);
    self.systemPromptTextView.textContainer.widthTracksTextView = YES;
    self.systemPromptTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.systemPromptTextView.allowsUndo = YES;

    scrollView.documentView = self.systemPromptTextView;
    [view addSubview:scrollView];

    tab.view = view;
    return tab;
}

// ─── UI Helpers ─────────────────────────────────────────────────────

- (NSTextField *)labelWithTitle:(NSString *)title frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:title];
    label.frame = frame;
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont systemFontOfSize:13];
    return label;
}

- (NSTextField *)textField:(NSRect)frame placeholder:(NSString *)placeholder {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.placeholderString = placeholder;
    field.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.usesSingleLineMode = YES;
    return field;
}

- (NSTextField *)descriptionLabel:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:12];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

// ─── Load / Save ────────────────────────────────────────────────────

- (void)loadCurrentValues {
    NSString *dir = configDirPath();

    // Load config.yaml
    NSString *configPath = configFilePath();
    NSString *yaml = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil] ?: @"";

    // UI language
    NSString *uiLanguage = yamlRead(yaml, @"ui.language");
    if (uiLanguage.length == 0) uiLanguage = @"en";
    for (NSInteger i = 0; i < self.uiLanguagePopup.numberOfItems; i++) {
        if ([[self.uiLanguagePopup itemAtIndex:i].representedObject isEqualToString:uiLanguage]) {
            [self.uiLanguagePopup selectItemAtIndex:i];
            break;
        }
    }

    // ASR
    NSString *asrProvider = yamlRead(yaml, @"asr.provider");
    if (asrProvider.length == 0) asrProvider = @"doubao";
    for (NSInteger i = 0; i < self.asrProviderPopup.numberOfItems; i++) {
        if ([[self.asrProviderPopup itemAtIndex:i].representedObject isEqualToString:asrProvider]) {
            [self.asrProviderPopup selectItemAtIndex:i];
            break;
        }
    }
    self.asrAppKeyField.stringValue = yamlRead(yaml, @"asr.app_key");
    self.asrAccessKeyField.stringValue = yamlRead(yaml, @"asr.access_key");
    self.qwenApiKeyField.stringValue = yamlRead(yaml, @"asr.qwen_api_key");
    [self updateAsrFieldsEnabled];

    // LLM
    NSString *enabled = yamlRead(yaml, @"llm.enabled");
    self.llmEnabledCheckbox.state = ([enabled isEqualToString:@"false"]) ? NSControlStateValueOff : NSControlStateValueOn;
    self.llmBaseUrlField.stringValue = yamlRead(yaml, @"llm.base_url");
    self.llmApiKeyField.stringValue = yamlRead(yaml, @"llm.api_key");
    self.llmModelField.stringValue = yamlRead(yaml, @"llm.model");
    [self updateLlmFieldsEnabled];

    // Hotkey
    NSString *triggerKey = yamlRead(yaml, @"hotkey.trigger_key");
    if (triggerKey.length == 0) triggerKey = @"fn";
    // Select the matching popup item
    for (NSInteger i = 0; i < self.hotkeyPopup.numberOfItems; i++) {
        if ([[self.hotkeyPopup itemAtIndex:i].representedObject isEqualToString:triggerKey]) {
            [self.hotkeyPopup selectItemAtIndex:i];
            break;
        }
    }

    // Reset test result label
    self.llmTestResultLabel.stringValue = @"";

    // Dictionary
    NSString *dictPath = [dir stringByAppendingPathComponent:kDictionaryFile];
    NSString *dictContent = [NSString stringWithContentsOfFile:dictPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    [self.dictionaryTextView setString:dictContent];

    // System Prompt
    NSString *promptPath = [dir stringByAppendingPathComponent:kSystemPromptFile];
    NSString *promptContent = [NSString stringWithContentsOfFile:promptPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    [self.systemPromptTextView setString:promptContent];
}

- (void)saveConfig:(id)sender {
    NSString *dir = configDirPath();

    // Ensure directory exists
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Read existing config.yaml (preserve structure)
    NSString *configPath = configFilePath();
    NSString *yaml = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil] ?: @"";

    // Update UI language
    NSString *selectedLanguage = self.uiLanguagePopup.selectedItem.representedObject ?: @"en";
    yaml = yamlWrite(yaml, @"ui.language", selectedLanguage);

    // Update ASR fields
    NSString *selectedAsrProvider = self.asrProviderPopup.selectedItem.representedObject ?: @"doubao";
    yaml = yamlWrite(yaml, @"asr.provider", selectedAsrProvider);
    yaml = yamlWrite(yaml, @"asr.app_key", self.asrAppKeyField.stringValue);
    yaml = yamlWrite(yaml, @"asr.access_key", self.asrAccessKeyField.stringValue);
    yaml = yamlWrite(yaml, @"asr.qwen_api_key", self.qwenApiKeyField.stringValue);

    // Update LLM fields
    NSString *enabledStr = (self.llmEnabledCheckbox.state == NSControlStateValueOn) ? @"true" : @"false";
    yaml = yamlWrite(yaml, @"llm.enabled", enabledStr);
    yaml = yamlWrite(yaml, @"llm.base_url", self.llmBaseUrlField.stringValue);
    yaml = yamlWrite(yaml, @"llm.api_key", self.llmApiKeyField.stringValue);
    yaml = yamlWrite(yaml, @"llm.model", self.llmModelField.stringValue);

    // Update hotkey
    NSString *selectedHotkey = self.hotkeyPopup.selectedItem.representedObject ?: @"fn";
    yaml = yamlWrite(yaml, @"hotkey.trigger_key", selectedHotkey);

    // Write config.yaml
    NSError *error = nil;
    [yaml writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"[Koe] Failed to write config.yaml: %@", error.localizedDescription);
        [self showAlert:L(@"wizard.error.save_config") info:error.localizedDescription];
        return;
    }

    // Write dictionary.txt
    NSString *dictPath = [dir stringByAppendingPathComponent:kDictionaryFile];
    [self.dictionaryTextView.string writeToFile:dictPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"[Koe] Failed to write dictionary.txt: %@", error.localizedDescription);
        [self showAlert:L(@"wizard.error.save_dictionary") info:error.localizedDescription];
        return;
    }

    // Write system_prompt.txt
    NSString *promptPath = [dir stringByAppendingPathComponent:kSystemPromptFile];
    [self.systemPromptTextView.string writeToFile:promptPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"[Koe] Failed to write system_prompt.txt: %@", error.localizedDescription);
        [self showAlert:L(@"wizard.error.save_prompt") info:error.localizedDescription];
        return;
    }

    NSLog(@"[Koe] Setup wizard: config saved");

    // Notify delegate to reload
    if ([self.delegate respondsToSelector:@selector(setupWizardDidSaveConfig)]) {
        [self.delegate setupWizardDidSaveConfig];
    }

    [self.window close];
}

- (void)cancelSetup:(id)sender {
    [self.window close];
}

- (void)llmEnabledToggled:(id)sender {
    [self updateLlmFieldsEnabled];
}

- (void)asrProviderChanged:(id)sender {
    [self updateAsrFieldsEnabled];
}

- (void)updateAsrFieldsEnabled {
    NSString *provider = self.asrProviderPopup.selectedItem.representedObject ?: @"doubao";
    BOOL isDoubao = [provider isEqualToString:@"doubao"];
    self.asrAppKeyField.enabled = isDoubao;
    self.asrAccessKeyField.enabled = isDoubao;
    self.qwenApiKeyField.enabled = !isDoubao;
}

- (void)updateLlmFieldsEnabled {
    BOOL enabled = (self.llmEnabledCheckbox.state == NSControlStateValueOn);
    self.llmBaseUrlField.enabled = enabled;
    self.llmApiKeyField.enabled = enabled;
    self.llmModelField.enabled = enabled;
    self.llmTestButton.enabled = enabled;
}

- (void)testLlmConnection:(id)sender {
    NSString *baseUrl = self.llmBaseUrlField.stringValue;
    NSString *apiKey = self.llmApiKeyField.stringValue;
    NSString *model = self.llmModelField.stringValue;

    if (baseUrl.length == 0 || apiKey.length == 0 || model.length == 0) {
        self.llmTestResultLabel.stringValue = L(@"wizard.llm.fill_all_fields");
        self.llmTestResultLabel.textColor = [NSColor systemOrangeColor];
        return;
    }

    self.llmTestButton.enabled = NO;
    self.llmTestResultLabel.stringValue = L(@"wizard.llm.testing");
    self.llmTestResultLabel.textColor = [NSColor secondaryLabelColor];

    // Build the chat completions request
    NSString *endpoint = [baseUrl stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    endpoint = [endpoint stringByAppendingString:@"/chat/completions"];
    NSURL *url = [NSURL URLWithString:endpoint];
    if (!url) {
        self.llmTestResultLabel.stringValue = L(@"wizard.llm.invalid_base_url");
        self.llmTestResultLabel.textColor = [NSColor systemRedColor];
        self.llmTestButton.enabled = YES;
        return;
    }

    NSDictionary *body = @{
        @"model": model,
        @"messages": @[@{@"role": @"user", @"content": @"Hi"}],
        @"max_tokens": @(10),
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = jsonData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = 15;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.llmTestButton.enabled = (self.llmEnabledCheckbox.state == NSControlStateValueOn);

            if (error) {
                self.llmTestResultLabel.stringValue = error.localizedDescription;
                self.llmTestResultLabel.textColor = [NSColor systemRedColor];
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                self.llmTestResultLabel.stringValue = L(@"wizard.llm.connection_successful");
                self.llmTestResultLabel.textColor = [NSColor systemGreenColor];
            } else {
                NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                // Try to extract error message from JSON response
                NSString *errMsg = nil;
                if (data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([json isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *errObj = json[@"error"];
                        if ([errObj isKindOfClass:[NSDictionary class]]) {
                            errMsg = errObj[@"message"];
                        }
                    }
                }
                self.llmTestResultLabel.stringValue = [NSString stringWithFormat:L(@"wizard.llm.http_error_format"),
                    (long)httpResponse.statusCode,
                    errMsg ?: body ?: L(@"wizard.llm.unknown_error")];
                self.llmTestResultLabel.textColor = [NSColor systemRedColor];
            }
        });
    }];
    [task resume];
}

- (void)showAlert:(NSString *)message info:(NSString *)info {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = info ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:L(@"wizard.alert.ok")];
    [alert runModal];
}

@end
