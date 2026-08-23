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
static NSString *KBFixedSymbol(NSInteger index) {
    switch (index) {
        case 0: return @"doc.on.clipboard";
        case 1: return @"chevron.backward.circle";
        case 2: return @"chevron.right.circle";
        default: return @"keyboard.chevron.compact.down";
    }
}

static CGFloat KBFixedIconSize(NSInteger index) {
    switch (index) {
        case 0: return 17.0;
        case 1: case 2: return 20.5;
        default: return 18.0;
    }
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

static BOOL KBIsWebContentDelegate(id delegate) {
    Class webContentClass = NSClassFromString(@"WKContentView");
    return delegate && webContentClass &&
           [delegate isKindOfClass:webContentClass];
}

static BOOL KBExecuteWebEditCommand(id delegate, NSString *command) {
    SEL selector = NSSelectorFromString(@"executeEditCommandWithCallback:");
    if (!KBIsWebContentDelegate(delegate) ||
        ![delegate respondsToSelector:selector]) {
        return NO;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(delegate, selector, command);
    return YES;
}

static void KBSelectAll(id delegate) {
    if (KBExecuteWebEditCommand(delegate, @"selectAll")) return;

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

    if (KBExecuteWebEditCommand(delegate, @"copy")) {
        // WKContentView applies edit commands asynchronously.
    } else if ([delegate respondsToSelector:@selector(copy:)]) {
        [delegate copy:nil];
    } else if ([delegate respondsToSelector:@selector(selectedTextRange)] &&
               [delegate respondsToSelector:@selector(textInRange:)]) {
        UITextRange *range = [delegate selectedTextRange];
        NSString *text = range ? [delegate textInRange:range] : nil;
        if (text) [UIPasteboard generalPasteboard].string = text;
    }
    KBRefreshKeyboardState(keyboard);
}

static BOOL KBDelegateHasNonWhitespaceText(id delegate) {
    if (![delegate respondsToSelector:@selector(textInRange:)]) {
        return YES; // Cannot inspect safely; preserve the existing copy path.
    }
    UITextRange *range = KBFullTextRange(delegate);
    if (!range) return YES;
    NSString *text = [delegate textInRange:range];
    if (!text) return YES;
    return [text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
}

static void KBSelectAllAndCopy(void) {
    id delegate = KBCurrentInputDelegate(NULL);
    if (!delegate || !KBDelegateHasNonWhitespaceText(delegate)) return;
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

    // WKContentView's paste: implementation is intentionally inconsistent
    // across Safari/WKWebView fields. Insert through the active keyboard input
    // channel instead, which is also DockX's fallback for remote delegates.
    NSString *text = [UIPasteboard generalPasteboard].string;
    if (KBIsWebContentDelegate(delegate) && text.length > 0 &&
        [keyboard respondsToSelector:@selector(insertText:)]) {
        [keyboard insertText:text];
        KBRefreshKeyboardState(keyboard);
        return;
    }

    // Target the real input delegate directly instead of asking the responder
    // chain to discover the destination from the keyboard dock.
    if ([delegate respondsToSelector:@selector(paste:)]) {
        [delegate paste:nil];
        return;
    }

    // Fallback used by DockX for delegates without UIResponder paste support.
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
    if (KBExecuteWebEditCommand(delegate, left ? @"moveLeft" : @"moveRight")) {
        KBRefreshKeyboardState(keyboard);
        return;
    }
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
    NSString *webCommand = beginning ? @"moveToBeginningOfDocument"
                                     : @"moveToEndOfDocument";
    if (KBExecuteWebEditCommand(delegate, webCommand)) {
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

        if (KBIsWebContentDelegate(currentDelegate)) {
            KBSelectAll(currentDelegate);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(kSecondActionDelay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIKeyboardImpl *webKeyboard = nil;
                id webDelegate = KBCurrentInputDelegate(&webKeyboard);
                if ([webKeyboard respondsToSelector:@selector(deleteFromInput)]) {
                    [webKeyboard deleteFromInput];
                    KBRefreshKeyboardState(webKeyboard);
                } else if ([webDelegate respondsToSelector:@selector(deleteBackward)]) {
                    [webDelegate deleteBackward];
                } else {
                    KBExecuteWebEditCommand(webDelegate, @"deleteBackward");
                }
            });
            return;
        }

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
                                    CGPoint *rightAnchor,
                                    UIColor **systemTint) {
    CGFloat width = CGRectGetWidth(dock.bounds);
    CGFloat height = CGRectGetHeight(dock.bounds);
    if (width <= 0.0 || height <= 0.0) return NO;

    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    KBCollectSystemControls(dock, container, controls);

    BOOL foundLeft = NO;
    BOOL foundRight = NO;
    CGPoint bestLeft = CGPointZero;
    CGPoint bestRight = CGPointZero;
    UIControl *bestLeftControl = nil;
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
            bestLeftControl = control;
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
    if (systemTint) *systemTint = bestLeftControl.tintColor;
    return YES;
}

static void KBLayoutToolbarButtons(UIView *dock, UIView *container) {
    // Refresh values written by the Settings process before reading them in
    // the current application process.
    CGFloat width = CGRectGetWidth(dock.bounds);
    CGFloat height = CGRectGetHeight(dock.bounds);
    if (width <= 0.0 || height <= 0.0) return;

    const CGFloat buttonWidth = 60.0;
    const CGFloat buttonHeight = 44.0;

    // Use the real system globe/microphone centers when they can be found.
    // The fallback matches a six-column dock and places the row near the bottom.
    CGPoint leftAnchor = CGPointMake(width / 12.0, height - 30.0);
    CGPoint rightAnchor = CGPointMake(width * 11.0 / 12.0, height - 30.0);
    UIColor *systemTint = [UIColor labelColor];
    KBFindSystemDockAnchors(dock, container, &leftAnchor, &rightAnchor, &systemTint);
    UIColor *buttonTint = systemTint;

    for (NSInteger index = 0; index < 4; index++) {
        UIButton *button = (UIButton *)[container viewWithTag:kButtonTagBase + index];
        if (!button) continue;

        // Interpolate four positions between the system controls. Together the
        // globe, four custom buttons and microphone form six equal intervals.
        CGFloat progress = ((CGFloat)index + 1.0) / 5.0;
        CGFloat baseX = leftAnchor.x + (rightAnchor.x - leftAnchor.x) * progress;
        CGFloat baseY = leftAnchor.y + (rightAnchor.y - leftAnchor.y) * progress;
        CGFloat centerX = baseX;
        CGFloat centerY = baseY - 6.0;

        button.bounds = CGRectMake(0.0, 0.0, buttonWidth, buttonHeight);
        button.center = CGPointMake(centerX, centerY);
        button.tintColor = buttonTint;
        CGFloat iconPointSize = KBFixedIconSize(index);
        UIImageSymbolConfiguration *symbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:iconPointSize
                                                             weight:UIImageSymbolWeightRegular];
        UIImage *image = [UIImage systemImageNamed:KBFixedSymbol(index)
                                 withConfiguration:symbolConfiguration];
        [button setImage:image forState:UIControlStateNormal];
        for (UIGestureRecognizer *gesture in button.gestureRecognizers) {
            if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
                ((UILongPressGestureRecognizer *)gesture).minimumPressDuration =
                    0.3;
            }
        }
    }

}

%hook UIKeyboardDockView

- (void)layoutSubviews {
    %orig;

    UIView *container = [self viewWithTag:kToolbarTag];
    UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    container.hidden = isLandscape;
    if (isLandscape) return;

    if (!container) {
        container = [[KBPassthroughView alloc] initWithFrame:self.bounds];
        container.tag = kToolbarTag;
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
        container.backgroundColor = [UIColor clearColor];
        container.clipsToBounds = NO;

        NSArray *specs = @[
            @[@"doc.on.clipboard", @"kb_didTapPaste", @"kb_didLongPressPaste:",
              @"Paste", @"Long press to select all and copy"],
            @[@"chevron.backward.circle", @"kb_didTapLeft", @"kb_didLongPressLeft:",
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
            longPress.minimumPressDuration = 0.3;
            longPress.cancelsTouchesInView = YES;
            [button addGestureRecognizer:longPress];
            [container addSubview:button];
        }

        self.clipsToBounds = NO;
        [self addSubview:container];
    }

    container.hidden = NO;

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
