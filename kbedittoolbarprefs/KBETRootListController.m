#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kKBETPreferencesDomain = @".GlobalPreferences";
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

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [specifier propertyForKey:@"default"];

    CFPropertyListRef value = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kKBETPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    return value ? CFBridgingRelease(value) : [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        CFPreferencesSetValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)value,
                              (__bridge CFStringRef)kKBETPreferencesDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
    }
    CFPreferencesSetValue(CFSTR("KBETLayoutVersion"),
                          (__bridge CFPropertyListRef)@3,
                          (__bridge CFStringRef)kKBETPreferencesDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kKBETPreferencesDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKBETPreferencesChanged,
                                         NULL, NULL, YES);
}

- (void)resetLayout {
    NSArray<NSString *> *keys = @[
        @"KBETPasteX", @"KBETPasteY",
        @"KBETLeftX", @"KBETLeftY",
        @"KBETRightX", @"KBETRightY",
        @"KBETDismissX", @"KBETDismissY",
        @"KBETIconPointSize",
    ];
    for (NSString *key in keys) {
        CFPreferencesSetValue((__bridge CFStringRef)key, NULL,
                              (__bridge CFStringRef)kKBETPreferencesDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
    }
    CFPreferencesSetValue(CFSTR("KBETLayoutVersion"),
                          (__bridge CFPropertyListRef)@3,
                          (__bridge CFStringRef)kKBETPreferencesDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kKBETPreferencesDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKBETPreferencesChanged,
                                         NULL, NULL, YES);
    [self reloadSpecifiers];
}

@end
