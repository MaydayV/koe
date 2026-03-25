#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPLocalization : NSObject

/// Returns "en" (default) or "zh" based on ~/.koe/config.yaml ui.language.
+ (NSString *)currentLanguageCode;

/// Localized text by key with fallback to English and then key itself.
+ (NSString *)tr:(NSString *)key;

/// Localized display name for configured hotkey key values.
+ (NSString *)displayNameForTriggerKey:(NSString *)triggerKey;

@end

NS_ASSUME_NONNULL_END

