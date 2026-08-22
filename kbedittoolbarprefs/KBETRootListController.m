#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kKBETPreferencesDomain = @"cn.example.kbedittoolbar.preferences";
static NSString *const kKBETPreferencesChanged = @"cn.example.kbedittoolbar/preferencesChanged";

@interface KBETRootListController : PSListController
@end

@implementation KBETRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesSetAppValue(CFSTR("layoutVersion"),
                             (__bridge CFPropertyListRef)@2,
                             (__bridge CFStringRef)kKBETPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kKBETPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKBETPreferencesChanged,
                                         NULL, NULL, YES);
}

- (void)resetLayout {
    NSArray<NSString *> *keys = @[
        @"pasteX", @"pasteY",
        @"leftX", @"leftY",
        @"rightX", @"rightY",
        @"dismissX", @"dismissY",
    ];
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL,
                                 (__bridge CFStringRef)kKBETPreferencesDomain);
    }
    CFPreferencesSetAppValue(CFSTR("layoutVersion"),
                             (__bridge CFPropertyListRef)@2,
                             (__bridge CFStringRef)kKBETPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kKBETPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKBETPreferencesChanged,
                                         NULL, NULL, YES);
    [self reloadSpecifiers];
}

@end
