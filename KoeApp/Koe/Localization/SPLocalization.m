#import "SPLocalization.h"
#import <sys/stat.h>

static NSString *const kDefaultLanguageCode = @"en";

static NSString *ConfigPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".koe/config.yaml"];
}

static BOOL IsTopLevelLine(NSString *line) {
    return ![line hasPrefix:@" "] && ![line hasPrefix:@"\t"];
}

static NSString *NormalizeLanguage(NSString *value) {
    NSString *lower = value.lowercaseString;
    if ([lower hasPrefix:@"zh"]) {
        return @"zh";
    }
    return kDefaultLanguageCode;
}

static NSString *ExtractValueFromYamlLine(NSString *trimmedLine, NSString *key) {
    NSString *prefix = [NSString stringWithFormat:@"%@:", key];
    if (![trimmedLine hasPrefix:prefix]) {
        return @"";
    }

    NSString *value = [trimmedLine substringFromIndex:prefix.length];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if ([value hasPrefix:@"\""]) {
        NSRange closeQuote = [value rangeOfString:@"\"" options:0 range:NSMakeRange(1, value.length - 1)];
        if (closeQuote.location != NSNotFound) {
            value = [value substringWithRange:NSMakeRange(1, closeQuote.location - 1)];
        } else {
            value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        }
    } else {
        NSRange commentRange = [value rangeOfString:@" #"];
        if (commentRange.location != NSNotFound) {
            value = [[value substringToIndex:commentRange.location]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return value;
}

static NSDictionary<NSString *, NSString *> *EnglishTable(void) {
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @{
            @"wizard.window_title": @"Koe Setup Wizard",
            @"wizard.button.save": @"Save",
            @"wizard.button.cancel": @"Cancel",
            @"wizard.alert.ok": @"OK",

            @"wizard.tab.general": @"General",
            @"wizard.tab.asr": @"ASR",
            @"wizard.tab.llm": @"LLM",
            @"wizard.tab.hotkey": @"Hotkey",
            @"wizard.tab.dictionary": @"Dictionary",
            @"wizard.tab.system_prompt": @"System Prompt",

            @"wizard.general.description": @"Configure app language.",
            @"wizard.general.language_label": @"Language:",
            @"wizard.lang.english": @"English",
            @"wizard.lang.chinese": @"Chinese",

            @"wizard.asr.description": @"Configure realtime ASR provider.\nDoubao requires Volcengine App/Access key. Qwen requires Bailian API Key.",
            @"wizard.asr.provider_label": @"Provider:",
            @"wizard.asr.app_key_label": @"App Key:",
            @"wizard.asr.access_key_label": @"Access Key:",
            @"wizard.asr.qwen_api_key_label": @"Qwen API Key:",
            @"wizard.asr.placeholder.app_key": @"Volcengine App ID",
            @"wizard.asr.placeholder.access_key": @"Volcengine Access Token",
            @"wizard.asr.placeholder.qwen_api_key": @"sk-... (Bailian API Key)",

            @"wizard.llm.description": @"Configure the LLM for post-correction of ASR output. Any OpenAI-compatible API works.\n\nIf disabled or not configured, Koe will directly use the raw ASR result - faster but less accurate (no capitalization fix, spacing normalization, or dictionary correction). If the configuration is invalid, Koe will automatically fallback to the raw ASR result.",
            @"wizard.llm.enable": @"Enable LLM Correction",
            @"wizard.llm.base_url_label": @"Base URL:",
            @"wizard.llm.api_key_label": @"API Key:",
            @"wizard.llm.model_label": @"Model:",
            @"wizard.llm.test_connection": @"Test Connection",
            @"wizard.llm.fill_all_fields": @"Please fill in all fields first.",
            @"wizard.llm.testing": @"Testing...",
            @"wizard.llm.invalid_base_url": @"Invalid Base URL.",
            @"wizard.llm.connection_successful": @"Connection successful!",
            @"wizard.llm.http_error_format": @"HTTP %ld: %@",
            @"wizard.llm.unknown_error": @"Unknown error",

            @"wizard.hotkey.description": @"Choose which key triggers voice input.\nHold the key to record, release to stop. Or double-press to toggle.",
            @"wizard.hotkey.trigger_key_label": @"Trigger Key:",

            @"wizard.dictionary.description": @"User dictionary - one term per line. These terms are prioritized during LLM correction.\nLines starting with # are comments.",
            @"wizard.system_prompt.description": @"System prompt sent to the LLM for text correction.\nEdit to customize the LLM's behavior.",

            @"wizard.error.save_config": @"Failed to save config.yaml",
            @"wizard.error.save_dictionary": @"Failed to save dictionary.txt",
            @"wizard.error.save_prompt": @"Failed to save system_prompt.txt",

            @"status.ready": @"Ready",
            @"status.listening": @"Listening...",
            @"status.connecting": @"Connecting...",
            @"status.recognizing": @"Recognizing...",
            @"status.thinking": @"Thinking...",
            @"status.pasting": @"Pasting...",
            @"status.error": @"Error",
            @"status.working": @"Working...",

            @"status.hotkey_prefix_format": @"Hotkey: %@",
            @"status.header.statistics": @"Statistics",
            @"status.header.permissions": @"Permissions",

            @"status.permissions.microphone_format": @"  Microphone: %@",
            @"status.permissions.accessibility_format": @"  Accessibility: %@",
            @"status.permissions.input_monitoring_format": @"  Input Monitoring: %@",
            @"status.permissions.notifications_format": @"  Notifications: %@",
            @"status.permissions.checking": @"Checking...",
            @"status.permissions.granted": @"Granted",
            @"status.permissions.not_granted": @"Not Granted",

            @"status.stats.total_format": @"  Total: %@",
            @"status.stats.total_no_data": @"No data yet",
            @"status.stats.chars_format": @"%ld chars",
            @"status.stats.words_format": @"%ld words",
            @"status.stats.time_format": @"  Time: %ld min %ld sec | %ld sessions",
            @"status.stats.time_empty": @"  Time: --",
            @"status.stats.speed_chars": @"  Speed: %.0f chars/min",
            @"status.stats.speed_words": @"  Speed: %.0f words/min",
            @"status.stats.speed_empty": @"  Speed: --",

            @"status.menu.microphone": @"Microphone",
            @"status.menu.system_default": @"System Default",
            @"status.menu.unavailable_format": @"%@ (Unavailable)",
            @"status.menu.setup_wizard": @"Setup Wizard...",
            @"status.menu.open_config": @"Open Config Folder...",
            @"status.menu.launch_at_login": @"Launch at Login",
            @"status.menu.quit": @"Quit Koe",

            @"hotkey.fn_globe": @"Fn (Globe)",
            @"hotkey.left_option": @"Left Option (\u2325)",
            @"hotkey.right_option": @"Right Option (\u2325)",
            @"hotkey.left_command": @"Left Command (\u2318)",
            @"hotkey.right_command": @"Right Command (\u2318)",

            @"overlay.listening": @"Listening…",
            @"overlay.connecting": @"Connecting…",
            @"overlay.recognizing": @"Recognizing…",
            @"overlay.thinking": @"Thinking…",
            @"overlay.pasting": @"Pasting…",
            @"overlay.error": @"Error",
            @"overlay.working": @"Working…",

            @"notification.warning_title": @"Koe Warning",
            @"notification.error_title": @"Koe Error",
        };
    });
    return table;
}

static NSDictionary<NSString *, NSString *> *ChineseTable(void) {
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @{
            @"wizard.window_title": @"Koe 设置向导",
            @"wizard.button.save": @"保存",
            @"wizard.button.cancel": @"取消",
            @"wizard.alert.ok": @"确定",

            @"wizard.tab.general": @"通用",
            @"wizard.tab.asr": @"ASR",
            @"wizard.tab.llm": @"LLM",
            @"wizard.tab.hotkey": @"快捷键",
            @"wizard.tab.dictionary": @"词典",
            @"wizard.tab.system_prompt": @"系统提示词",

            @"wizard.general.description": @"配置应用语言。",
            @"wizard.general.language_label": @"语言：",
            @"wizard.lang.english": @"英文",
            @"wizard.lang.chinese": @"中文",

            @"wizard.asr.description": @"配置实时 ASR 提供商。\nDoubao 需要火山引擎 App/Access Key。Qwen 需要百炼 API Key。",
            @"wizard.asr.provider_label": @"提供商：",
            @"wizard.asr.app_key_label": @"App Key：",
            @"wizard.asr.access_key_label": @"Access Key：",
            @"wizard.asr.qwen_api_key_label": @"Qwen API Key：",
            @"wizard.asr.placeholder.app_key": @"火山引擎 App ID",
            @"wizard.asr.placeholder.access_key": @"火山引擎 Access Token",
            @"wizard.asr.placeholder.qwen_api_key": @"sk-...（百炼 API Key）",

            @"wizard.llm.description": @"配置用于 ASR 后处理的 LLM。任何兼容 OpenAI 的 API 都可用。\n\n若关闭或未配置，Koe 将直接使用原始 ASR 结果 - 更快但准确性较低（不做大小写修正、空格规范化和词典纠错）。配置无效时，Koe 会自动回退到原始 ASR 结果。",
            @"wizard.llm.enable": @"启用 LLM 纠错",
            @"wizard.llm.base_url_label": @"Base URL：",
            @"wizard.llm.api_key_label": @"API Key：",
            @"wizard.llm.model_label": @"模型：",
            @"wizard.llm.test_connection": @"测试连接",
            @"wizard.llm.fill_all_fields": @"请先填写完整字段。",
            @"wizard.llm.testing": @"测试中...",
            @"wizard.llm.invalid_base_url": @"Base URL 无效。",
            @"wizard.llm.connection_successful": @"连接成功！",
            @"wizard.llm.http_error_format": @"HTTP %ld：%@",
            @"wizard.llm.unknown_error": @"未知错误",

            @"wizard.hotkey.description": @"选择触发语音输入的按键。\n按住开始录音，松开结束。也可双击切换。",
            @"wizard.hotkey.trigger_key_label": @"触发键：",

            @"wizard.dictionary.description": @"用户词典 - 每行一个词条。LLM 纠错时会优先使用这些词条。\n以 # 开头的行是注释。",
            @"wizard.system_prompt.description": @"发送给 LLM 的系统提示词。\n可编辑以自定义 LLM 行为。",

            @"wizard.error.save_config": @"保存 config.yaml 失败",
            @"wizard.error.save_dictionary": @"保存 dictionary.txt 失败",
            @"wizard.error.save_prompt": @"保存 system_prompt.txt 失败",

            @"status.ready": @"就绪",
            @"status.listening": @"监听中...",
            @"status.connecting": @"连接中...",
            @"status.recognizing": @"识别中...",
            @"status.thinking": @"思考中...",
            @"status.pasting": @"粘贴中...",
            @"status.error": @"错误",
            @"status.working": @"处理中...",

            @"status.hotkey_prefix_format": @"快捷键：%@",
            @"status.header.statistics": @"统计",
            @"status.header.permissions": @"权限",

            @"status.permissions.microphone_format": @"  麦克风：%@",
            @"status.permissions.accessibility_format": @"  辅助功能：%@",
            @"status.permissions.input_monitoring_format": @"  输入监控：%@",
            @"status.permissions.notifications_format": @"  通知：%@",
            @"status.permissions.checking": @"检测中...",
            @"status.permissions.granted": @"已授权",
            @"status.permissions.not_granted": @"未授权",

            @"status.stats.total_format": @"  总计：%@",
            @"status.stats.total_no_data": @"暂无数据",
            @"status.stats.chars_format": @"%ld 字",
            @"status.stats.words_format": @"%ld 词",
            @"status.stats.time_format": @"  时长：%ld 分 %ld 秒 | %ld 次会话",
            @"status.stats.time_empty": @"  时长：--",
            @"status.stats.speed_chars": @"  速度：%.0f 字/分",
            @"status.stats.speed_words": @"  速度：%.0f 词/分",
            @"status.stats.speed_empty": @"  速度：--",

            @"status.menu.microphone": @"麦克风",
            @"status.menu.system_default": @"系统默认",
            @"status.menu.unavailable_format": @"%@（不可用）",
            @"status.menu.setup_wizard": @"设置向导...",
            @"status.menu.open_config": @"打开配置目录...",
            @"status.menu.launch_at_login": @"开机自启",
            @"status.menu.quit": @"退出 Koe",

            @"hotkey.fn_globe": @"Fn（地球键）",
            @"hotkey.left_option": @"左 Option（\u2325）",
            @"hotkey.right_option": @"右 Option（\u2325）",
            @"hotkey.left_command": @"左 Command（\u2318）",
            @"hotkey.right_command": @"右 Command（\u2318）",

            @"overlay.listening": @"监听中…",
            @"overlay.connecting": @"连接中…",
            @"overlay.recognizing": @"识别中…",
            @"overlay.thinking": @"思考中…",
            @"overlay.pasting": @"粘贴中…",
            @"overlay.error": @"错误",
            @"overlay.working": @"处理中…",

            @"notification.warning_title": @"Koe 警告",
            @"notification.error_title": @"Koe 错误",
        };
    });
    return table;
}

@implementation SPLocalization

+ (NSString *)currentLanguageCode {
    static NSString *cachedLanguage = @"en";
    static time_t cachedMtime = 0;

    NSString *path = ConfigPath();
    struct stat st = {0};
    time_t currentMtime = 0;
    if (stat(path.UTF8String, &st) == 0) {
        currentMtime = st.st_mtime;
    }

    @synchronized(self) {
        if (currentMtime == cachedMtime && cachedLanguage.length > 0) {
            return cachedLanguage;
        }

        NSString *yaml = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (yaml.length == 0) {
            cachedLanguage = kDefaultLanguageCode;
            cachedMtime = currentMtime;
            return cachedLanguage;
        }

        BOOL inUiSection = NO;
        NSString *language = kDefaultLanguageCode;
        NSArray<NSString *> *lines = [yaml componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) {
                continue;
            }

            if (IsTopLevelLine(line)) {
                if ([trimmed isEqualToString:@"ui:"]) {
                    inUiSection = YES;
                    continue;
                }
                if (inUiSection) {
                    break;
                }
            }

            if (inUiSection) {
                NSString *value = ExtractValueFromYamlLine(trimmed, @"language");
                if (value.length > 0) {
                    language = NormalizeLanguage(value);
                    break;
                }
            }
        }

        cachedLanguage = language;
        cachedMtime = currentMtime;
        return cachedLanguage;
    }
}

+ (NSString *)tr:(NSString *)key {
    NSString *language = [self currentLanguageCode];
    NSDictionary<NSString *, NSString *> *table = [language isEqualToString:@"zh"] ? ChineseTable() : EnglishTable();

    NSString *value = table[key];
    if (value.length > 0) {
        return value;
    }

    NSString *fallback = EnglishTable()[key];
    return fallback.length > 0 ? fallback : key;
}

+ (NSString *)displayNameForTriggerKey:(NSString *)triggerKey {
    if ([triggerKey isEqualToString:@"left_option"]) {
        return [self tr:@"hotkey.left_option"];
    }
    if ([triggerKey isEqualToString:@"right_option"]) {
        return [self tr:@"hotkey.right_option"];
    }
    if ([triggerKey isEqualToString:@"left_command"]) {
        return [self tr:@"hotkey.left_command"];
    }
    if ([triggerKey isEqualToString:@"right_command"]) {
        return [self tr:@"hotkey.right_command"];
    }
    return [self tr:@"hotkey.fn_globe"];
}

@end

