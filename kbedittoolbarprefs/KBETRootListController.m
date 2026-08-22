#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static NSString *const kKBETPreferencesDomain = @".GlobalPreferences";
static NSString *const kKBETPreferencesChanged = @"cn.example.kbedittoolbar/preferencesChanged";

@interface KBETRootListController : PSListController <UIColorPickerViewControllerDelegate>
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
        BOOL isPosition = [key hasSuffix:@"X"] || [key hasSuffix:@"Y"];
        BOOL isIconSize = [key hasSuffix:@"IconPointSize"];
        BOOL isTouchSize = [key isEqualToString:@"KBETTouchWidth"] ||
                           [key isEqualToString:@"KBETTouchHeight"];
        if (isPosition || isIconSize || isTouchSize) {
            double rounded = round([value doubleValue] * 10.0) / 10.0;
            value = [NSString stringWithFormat:@"%.1f", rounded];
        }
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

- (void)openColorPicker {
    NSString *hex = [self readPreferenceValue:[self specifierForID:@"customTintHex"]];
    NSString *clean = [[(hex ?: @"#000000") stringByReplacingOccurrencesOfString:@"#"
                                                                      withString:@""] uppercaseString];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgb];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.selectedColor = [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                                           green:((rgb >> 8) & 0xFF) / 255.0
                                            blue:(rgb & 0xFF) / 255.0
                                           alpha:1.0];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [viewController.selectedColor getRed:&red green:&green blue:&blue alpha:&alpha];
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X",
                     (int)lrint(red * 255.0), (int)lrint(green * 255.0),
                     (int)lrint(blue * 255.0)];
    PSSpecifier *specifier = [self specifierForID:@"customTintHex"];
    [self setPreferenceValue:hex specifier:specifier];
    [self reloadSpecifiers];
}

- (void)resetLayout {
    NSArray<NSString *> *keys = @[
        @"KBETPasteX", @"KBETPasteY",
        @"KBETLeftX", @"KBETLeftY",
        @"KBETRightX", @"KBETRightY",
        @"KBETDismissX", @"KBETDismissY",
        @"KBETPasteSymbol", @"KBETLeftSymbol",
        @"KBETRightSymbol", @"KBETDismissSymbol",
        @"KBETPasteIconPointSize", @"KBETLeftIconPointSize",
        @"KBETRightIconPointSize", @"KBETDismissIconPointSize",
        @"KBETLongPressDurationMS",
        @"KBETFollowSystemTint", @"KBETCustomTintHex",
        @"KBETTouchWidth", @"KBETTouchHeight",
        @"KBETShowTouchShadow", @"KBETShowLayoutGuides",
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
