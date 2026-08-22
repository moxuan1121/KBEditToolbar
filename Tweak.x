#import <UIKit/UIKit.h>
#import <objc/message.h>

// ============================================================================
// KBEditToolbar — keyboard toolbar with 4 buttons:
//   Paste / Cursor-Left / Cursor-Right / Dismiss.
//
// Short press:
//   Paste / move one character left / move one character right / dismiss.
// Long press:
//   Select all + copy / beginning of document / end of document / clear all.
//
// Editing actions use UIKeyboardImpl's input delegate, matching DockX's proven
// approach. The normal responder chain is only kept as a compatibility fallback.
// ============================================================================

@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
@property (nonatomic, readonly, assign) id privateInputDelegate;
@property (nonatomic, readonly, assign) id inputDelegate;
- (void)insertText:(id)text;
- (void)deleteFromInput;
- (void)clearInputWithCandidatesCleared:(BOOL)candidatesCleared;
- (void)clearTransientState;
- (void)clearAnimations;
- (void)setCaretBlinks:(BOOL)blinks;
- (void)dismissKeyboard;
@end

// UIKeyboardDockView is a private UIKit class. Declaring it as a UIView subclass
// lets the compiler resolve UIView methods/properties inside the hook.
@interface UIKeyboardDockView : UIView
// Our %new methods — declared so the compiler can resolve [self kb_...] calls.
- (void)kb_haptic;
- (void)kb_didTapPaste;
- (void)kb_didTapLeft;
- (void)kb_didTapRight;
- (void)kb_didTapDismiss;
- (void)kb_didLongPressPaste:(UILongPressGestureRecognizer *)recognizer;
- (void)kb_didLongPressLeft:(UILongPressGestureRecognizer *)recognizer;
- (void)kb_didLongPressRight:(UILongPressGestureRecognizer *)recognizer;
- (void)kb_didLongPressDismiss:(UILongPressGestureRecognizer *)recognizer;
@end

// The container occupies the dock so it can position buttons independently,
// but its transparent area must not intercept the system globe/microphone.
@interface KBPassthroughView : UIView
@end

@implementation KBPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    return hitView == self ? nil : hitView;
}
@end

static const NSInteger kToolbarTag = 0x4B54; // 'KT'
static const NSInteger kButtonTagBase = 0x4B60;
static const NSTimeInterval kSecondActionDelay = 0.05; // same delay as DockX
// Third-party app sandboxes cannot reliably read another app-specific domain.
// Unique, prefixed keys in the global domain are served cross-process by
// cfprefsd and work in system apps, WeChat, TikTok and other sandboxed apps.
static NSString *const kPreferencesDomain = @".GlobalPreferences";

static NSArray<NSString *> *KBButtonXPreferenceKeys(void) {
    return @[@"KBETPasteX", @"KBETLeftX", @"KBETRightX", @"KBETDismissX"];
}

static NSArray<NSString *> *KBButtonYPreferenceKeys(void) {
    return @[@"KBETPasteY", @"KBETLeftY", @"KBETRightY", @"KBETDismissY"];
}

static NSArray<NSString *> *KBButtonSymbolNames(void) {
    return @[@"arrow.up.doc.on.clipboard", @"arrow.left.circle",
             @"arrow.right.circle", @"keyboard.chevron.compact.down"];
}

static CGFloat KBPreferenceFloatWithDefault(NSString *key, CGFloat defaultValue) {
    CFPropertyListRef value = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    CGFloat result = defaultValue;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        result = [(__bridge NSNumber *)value doubleValue];
    }
    if (value) CFRelease(value);
    return result;
}

static CGFloat KBPreferenceFloat(NSString *key) {
    return KBPreferenceFloatWithDefault(key, 0.0);
}

static void KBMigrateLegacyLayoutIfNeeded(void) {
    CFPropertyListRef versionValue = CFPreferencesCopyValue(
        CFSTR("KBETLayoutVersion"),
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    NSInteger version = 0;
    if (versionValue && CFGetTypeID(versionValue) == CFNumberGetTypeID()) {
        version = [(__bridge NSNumber *)versionValue integerValue];
    }
    if (versionValue) CFRelease(versionValue);
    if (version >= 3) return;

    // Earlier releases stored offsets in a private app-specific domain, which
    // sandboxed apps could not read reliably. Start the global-domain layout
    // cleanly once after upgrading.
    for (NSString *key in [KBButtonXPreferenceKeys()
                           arrayByAddingObjectsFromArray:KBButtonYPreferenceKeys()]) {
        CFPreferencesSetValue((__bridge CFStringRef)key, NULL,
                              (__bridge CFStringRef)kPreferencesDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
    }
    CFPreferencesSetValue(CFSTR("KBETLayoutVersion"),
                          (__bridge CFPropertyListRef)@3,
                          (__bridge CFStringRef)kPreferencesDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kPreferencesDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
}

// --- Resolve the text input owned by the active keyboard --------------------
static __weak id gCaptured;

%hook UIResponder
%new
- (void)kb_capture:(id)sender { gCaptured = self; }
%end

static UIKeyboardImpl *KBActiveKeyboard(void) {
    return [%c(UIKeyboardImpl) activeInstance];
}

static id KBCurrentInputDelegate(UIKeyboardImpl **keyboardOut) {
    UIKeyboardImpl *keyboard = KBActiveKeyboard();
    if (keyboardOut) *keyboardOut = keyboard;

    id delegate = nil;
    if ([keyboard respondsToSelector:@selector(privateInputDelegate)]) {
        delegate = [keyboard privateInputDelegate];
    }
    if (!delegate && [keyboard respondsToSelector:@selector(inputDelegate)]) {
        delegate = [keyboard inputDelegate];
    }

    // Compatibility fallback for iOS/app combinations that expose neither
    // UIKeyboardImpl delegate property.
    if (!delegate) {
        gCaptured = nil;
        [[UIApplication sharedApplication] sendAction:@selector(kb_capture:)
                                                  to:nil from:nil forEvent:nil];
        delegate = gCaptured;
    }
    return delegate;
}

static void KBRefreshKeyboardState(UIKeyboardImpl *keyboard) {
    if ([keyboard respondsToSelector:@selector(clearTransientState)]) {
        [keyboard clearTransientState];
    }
    if ([keyboard respondsToSelector:@selector(clearAnimations)]) {
        [keyboard clearAnimations];
    }
    if ([keyboard respondsToSelector:@selector(setCaretBlinks:)]) {
        [keyboard setCaretBlinks:YES];
    }
}

static UITextRange *KBFullTextRange(id delegate) {
    if (![delegate respondsToSelector:@selector(beginningOfDocument)] ||
        ![delegate respondsToSelector:@selector(endOfDocument)] ||
        ![delegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)]) {
        return nil;
    }

    UITextPosition *beginning = [delegate beginningOfDocument];
    UITextPosition *end = [delegate endOfDocument];
    if (!beginning || !end) return nil;
    return [delegate textRangeFromPosition:beginning toPosition:end];
}

static void KBSelectAll(id delegate) {
    if ([delegate respondsToSelector:@selector(selectAll:)]) {
        [delegate selectAll:nil];
        return;
    }

    UITextRange *range = KBFullTextRange(delegate);
    if (range && [delegate respondsToSelector:@selector(setSelectedTextRange:)]) {
        [delegate setSelectedTextRange:range];
    }
}

static void KBCopySelection(void) {
    UIKeyboardImpl *keyboard = nil;
    id delegate = KBCurrentInputDelegate(&keyboard);
    if (!delegate) return;

    if ([delegate respondsToSelector:@selector(copy:)]) {
        [delegate copy:nil];
    } else if ([delegate respondsToSelector:@selector(selectedTextRange)] &&
               [delegate respondsToSelector:@selector(textInRange:)]) {
        UITextRange *range = [delegate selectedTextRange];
        NSString *text = range ? [delegate textInRange:range] : nil;
        if (text) [UIPasteboard generalPasteboard].string = text;
    }
    KBRefreshKeyboardState(keyboard);
}

static void KBSelectAllAndCopy(void) {
    id delegate = KBCurrentInputDelegate(NULL);
    if (!delegate) return;
    KBSelectAll(delegate);

    // Some remote input delegates apply selectAll asynchronously. DockX uses
    // this short delay before its second edit action for the same reason.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kSecondActionDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        KBCopySelection();
    });
}

static void KBPaste(void) {
    UIKeyboardImpl *keyboard = nil;
    id delegate = KBCurrentInputDelegate(&keyboard);

    // This is the key fix: target the real input delegate directly instead of
    // asking the responder chain to discover the destination from the dock.
    if ([delegate respondsToSelector:@selector(paste:)]) {
        [delegate paste:nil];
        return;
    }

    // Fallback used by DockX for delegates without UIResponder paste support.
    NSString *text = [UIPasteboard generalPasteboard].string;
    if (!text) return;
    if ([keyboard respondsToSelector:@selector(insertText:)]) {
        [keyboard insertText:text];
        KBRefreshKeyboardState(keyboard);
    } else if ([delegate respondsToSelector:@selector(insertText:)]) {
        [delegate insertText:text];
    }
}

static void KBMoveCaret(BOOL left) {
    UIKeyboardImpl *keyboard = nil;
    id delegate = KBCurrentInputDelegate(&keyboard);
    if (![delegate respondsToSelector:@selector(selectedTextRange)] ||
        ![delegate respondsToSelector:@selector(positionFromPosition:offset:)] ||
        ![delegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)] ||
        ![delegate respondsToSelector:@selector(setSelectedTextRange:)]) {
        return;
    }

    UITextRange *selection = [delegate selectedTextRange];
    if (!selection) return;
    UITextPosition *anchor = left ? selection.start : selection.end;
    UITextPosition *position =
        [delegate positionFromPosition:anchor offset:(left ? -1 : 1)];
    if (!position) position = anchor; // clamp at the document boundaries
    UITextRange *range =
        [delegate textRangeFromPosition:position toPosition:position];
    if (range) [delegate setSelectedTextRange:range];
    KBRefreshKeyboardState(keyboard);
}

static void KBMoveCaretToBoundary(BOOL beginning) {
    UIKeyboardImpl *keyboard = nil;
    id delegate = KBCurrentInputDelegate(&keyboard);
    if (!delegate) return;

    // WKContentView requires WebKit's edit command; this is the compatibility
    // branch used by DockX for Safari and other WKWebView inputs.
    SEL webCommand = NSSelectorFromString(@"executeEditCommandWithCallback:");
    if ([delegate isKindOfClass:NSClassFromString(@"WKContentView")] &&
        [delegate respondsToSelector:webCommand]) {
        NSString *command = beginning ? @"moveToBeginningOfDocument"
                                      : @"moveToEndOfDocument";
        ((void (*)(id, SEL, id))objc_msgSend)(delegate, webCommand, command);
        KBRefreshKeyboardState(keyboard);
        return;
    }

    if (![delegate respondsToSelector:@selector(beginningOfDocument)] ||
        ![delegate respondsToSelector:@selector(endOfDocument)] ||
        ![delegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)] ||
        ![delegate respondsToSelector:@selector(setSelectedTextRange:)]) {
        return;
    }
    UITextPosition *position = beginning ? [delegate beginningOfDocument]
                                         : [delegate endOfDocument];
    if (!position) return;
    UITextRange *range =
        [delegate textRangeFromPosition:position toPosition:position];
    if (range) [delegate setSelectedTextRange:range];
    KBRefreshKeyboardState(keyboard);
}

static void KBClearAllText(void) {
    UIKeyboardImpl *keyboard = nil;
    id delegate = KBCurrentInputDelegate(&keyboard);
    if (!delegate) return;

    // Clearing only the delegate's marked range leaves the keyboard composer's
    // raw Pinyin/candidate buffer alive; the next key then restores old text.
    // DockX clears both the composer input and its candidates through this API.
    if ([keyboard respondsToSelector:@selector(clearInputWithCandidatesCleared:)]) {
        [keyboard clearInputWithCandidatesCleared:YES];
    }

    // Pinyin/Japanese and other IMEs keep uncommitted keystrokes in a marked
    // text range. Calling UIKeyboardImpl deleteFromInput at this point removes
    // only one composing key. Remove the marked range first and end composition.
    UITextRange *markedRange = nil;
    if ([delegate respondsToSelector:@selector(markedTextRange)]) {
        markedRange = [delegate markedTextRange];
    }
    if (markedRange &&
        [delegate respondsToSelector:@selector(replaceRange:withText:)]) {
        [delegate replaceRange:markedRange withText:@""];
    } else if (markedRange &&
               [delegate respondsToSelector:@selector(setMarkedText:selectedRange:)]) {
        [delegate setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
    }
    if ([delegate respondsToSelector:@selector(unmarkText)]) {
        [delegate unmarkText];
    }
    KBRefreshKeyboardState(keyboard);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kSecondActionDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIKeyboardImpl *currentKeyboard = nil;
        id currentDelegate = KBCurrentInputDelegate(&currentKeyboard);
        UITextRange *fullRange = KBFullTextRange(currentDelegate);

        // Replacing the complete document range bypasses the IME's one-key
        // delete behavior and clears both committed and composing text.
        if (fullRange &&
            [currentDelegate respondsToSelector:@selector(replaceRange:withText:)]) {
            [currentDelegate replaceRange:fullRange withText:@""];
            KBRefreshKeyboardState(currentKeyboard);
            return;
        }

        // Compatibility fallback for input delegates that cannot replace a
        // range directly: select all, then let the keyboard delete selection.
        KBSelectAll(currentDelegate);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kSecondActionDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIKeyboardImpl *fallbackKeyboard = nil;
            id fallbackDelegate = KBCurrentInputDelegate(&fallbackKeyboard);
            if ([fallbackKeyboard respondsToSelector:@selector(deleteFromInput)]) {
                [fallbackKeyboard deleteFromInput];
                KBRefreshKeyboardState(fallbackKeyboard);
            } else if ([fallbackDelegate respondsToSelector:@selector(deleteBackward)]) {
                [fallbackDelegate deleteBackward];
            }
        });
    });
}

static void KBCollectSystemControls(UIView *view,
                                    UIView *excludedView,
                                    NSMutableArray<UIControl *> *controls) {
    for (UIView *subview in view.subviews) {
        if (subview == excludedView || subview.hidden || subview.alpha < 0.01) {
            continue;
        }
        if ([subview isKindOfClass:[UIControl class]]) {
            [controls addObject:(UIControl *)subview];
        }
        KBCollectSystemControls(subview, excludedView, controls);
    }
}

static BOOL KBFindSystemDockAnchors(UIView *dock,
                                    UIView *container,
                                    CGPoint *leftAnchor,
                                    CGPoint *rightAnchor) {
    CGFloat width = CGRectGetWidth(dock.bounds);
    CGFloat height = CGRectGetHeight(dock.bounds);
    if (width <= 0.0 || height <= 0.0) return NO;

    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    KBCollectSystemControls(dock, container, controls);

    BOOL foundLeft = NO;
    BOOL foundRight = NO;
    CGPoint bestLeft = CGPointZero;
    CGPoint bestRight = CGPointZero;
    CGFloat bottomBandTop = height - MIN(80.0, height * 0.28);

    for (UIControl *control in controls) {
        CGRect rect = [control convertRect:control.bounds toView:dock];
        CGFloat controlWidth = CGRectGetWidth(rect);
        CGFloat controlHeight = CGRectGetHeight(rect);
        CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));

        // System globe/dictation controls are compact, live in the bottom band,
        // and sit in the outer quarters. Keyboard character keys are excluded.
        if (controlWidth < 10.0 || controlHeight < 10.0 ||
            controlWidth > 110.0 || controlHeight > 110.0 ||
            center.y < bottomBandTop) {
            continue;
        }

        if (center.x < width * 0.28 &&
            (!foundLeft || center.y > bestLeft.y)) {
            bestLeft = center;
            foundLeft = YES;
        }
        if (center.x > width * 0.72 &&
            (!foundRight || center.y > bestRight.y)) {
            bestRight = center;
            foundRight = YES;
        }
    }

    if (!foundLeft || !foundRight || bestRight.x <= bestLeft.x) return NO;
    if (leftAnchor) *leftAnchor = bestLeft;
    if (rightAnchor) *rightAnchor = bestRight;
    return YES;
}

static void KBLayoutToolbarButtons(UIView *dock, UIView *container) {
    // Refresh values written by the Settings process before reading them in
    // the current application process.
    CFPreferencesSynchronize((__bridge CFStringRef)kPreferencesDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    KBMigrateLegacyLayoutIfNeeded();

    CGFloat width = CGRectGetWidth(dock.bounds);
    CGFloat height = CGRectGetHeight(dock.bounds);
    if (width <= 0.0 || height <= 0.0) return;

    NSArray<NSString *> *xKeys = KBButtonXPreferenceKeys();
    NSArray<NSString *> *yKeys = KBButtonYPreferenceKeys();
    NSArray<NSString *> *symbolNames = KBButtonSymbolNames();
    const CGFloat buttonWidth = 60.0;
    const CGFloat buttonHeight = 44.0;
    CGFloat iconPointSize = KBPreferenceFloatWithDefault(@"KBETIconPointSize", 22.0);
    iconPointSize = MIN(44.0, MAX(12.0, iconPointSize));
    UIImageSymbolConfiguration *symbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:iconPointSize
                                                         weight:UIImageSymbolWeightRegular];

    // Use the real system globe/microphone centers when they can be found.
    // The fallback matches a six-column dock and places the row near the bottom.
    CGPoint leftAnchor = CGPointMake(width / 12.0, height - 30.0);
    CGPoint rightAnchor = CGPointMake(width * 11.0 / 12.0, height - 30.0);
    KBFindSystemDockAnchors(dock, container, &leftAnchor, &rightAnchor);

    for (NSInteger index = 0; index < 4; index++) {
        UIButton *button = (UIButton *)[container viewWithTag:kButtonTagBase + index];
        if (!button) continue;

        // Interpolate four positions between the system controls. Together the
        // globe, four custom buttons and microphone form six equal intervals.
        CGFloat progress = ((CGFloat)index + 1.0) / 5.0;
        CGFloat baseX = leftAnchor.x + (rightAnchor.x - leftAnchor.x) * progress;
        CGFloat baseY = leftAnchor.y + (rightAnchor.y - leftAnchor.y) * progress;
        CGFloat centerX = baseX + KBPreferenceFloat(xKeys[index]);
        CGFloat centerY = baseY + KBPreferenceFloat(yKeys[index]);

        button.bounds = CGRectMake(0.0, 0.0, buttonWidth, buttonHeight);
        button.center = CGPointMake(centerX, centerY);
        [button setImage:[UIImage systemImageNamed:symbolNames[index]
                                  withConfiguration:symbolConfiguration]
                forState:UIControlStateNormal];
    }
}

%hook UIKeyboardDockView

- (void)layoutSubviews {
    %orig;

    UIView *container = [self viewWithTag:kToolbarTag];
    if (!container) {
        container = [[KBPassthroughView alloc] initWithFrame:self.bounds];
        container.tag = kToolbarTag;
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
        container.backgroundColor = [UIColor clearColor];
        container.clipsToBounds = NO;

        NSArray *specs = @[
            @[@"arrow.up.doc.on.clipboard", @"kb_didTapPaste", @"kb_didLongPressPaste:",
              @"Paste", @"Long press to select all and copy"],
            @[@"arrow.left.circle", @"kb_didTapLeft", @"kb_didLongPressLeft:",
              @"Move cursor left", @"Long press to move to the beginning"],
            @[@"arrow.right.circle", @"kb_didTapRight", @"kb_didLongPressRight:",
              @"Move cursor right", @"Long press to move to the end"],
            @[@"keyboard.chevron.compact.down", @"kb_didTapDismiss",
              @"kb_didLongPressDismiss:", @"Dismiss keyboard",
              @"Long press to clear all text"],
        ];
        for (NSUInteger index = 0; index < specs.count; index++) {
            NSArray *spec = specs[index];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = kButtonTagBase + index;
            [button setImage:[UIImage systemImageNamed:spec[0]]
                    forState:UIControlStateNormal];
            button.tintColor = [UIColor labelColor];
            button.accessibilityLabel = spec[3];
            button.accessibilityHint = spec[4];
            [button addTarget:self action:NSSelectorFromString(spec[1])
               forControlEvents:UIControlEventTouchUpInside];

            UILongPressGestureRecognizer *longPress =
                [[UILongPressGestureRecognizer alloc]
                    initWithTarget:self action:NSSelectorFromString(spec[2])];
            longPress.minimumPressDuration = 0.5;
            longPress.cancelsTouchesInView = YES;
            [button addGestureRecognizer:longPress];
            [container addSubview:button];
        }

        self.clipsToBounds = NO;
        [self addSubview:container];
    }

    container.frame = self.bounds;
    KBLayoutToolbarButtons(self, container);
    [self bringSubviewToFront:container];
}

%new
- (void)kb_haptic {
    UIImpactFeedbackGenerator *generator =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleLight];
    [generator prepare];
    [generator impactOccurred];
}

%new
- (void)kb_didTapPaste {
    [self kb_haptic];
    KBPaste();
}

%new
- (void)kb_didTapLeft {
    [self kb_haptic];
    KBMoveCaret(YES);
}

%new
- (void)kb_didTapRight {
    [self kb_haptic];
    KBMoveCaret(NO);
}

%new
- (void)kb_didTapDismiss {
    [self kb_haptic];
    UIKeyboardImpl *keyboard = KBActiveKeyboard();
    if ([keyboard respondsToSelector:@selector(dismissKeyboard)]) {
        [keyboard dismissKeyboard];
    }
}

%new
- (void)kb_didLongPressPaste:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self kb_haptic];
    KBSelectAllAndCopy();
}

%new
- (void)kb_didLongPressLeft:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self kb_haptic];
    KBMoveCaretToBoundary(YES);
}

%new
- (void)kb_didLongPressRight:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self kb_haptic];
    KBMoveCaretToBoundary(NO);
}

%new
- (void)kb_didLongPressDismiss:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self kb_haptic];
    KBClearAllText();
}

%end
