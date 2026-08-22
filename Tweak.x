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

static const NSInteger kToolbarTag = 0x4B54; // 'KT'
static const NSTimeInterval kSecondActionDelay = 0.05; // same delay as DockX

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
    id delegate = KBCurrentInputDelegate(NULL);
    if (!delegate) return;
    KBSelectAll(delegate);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kSecondActionDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIKeyboardImpl *keyboard = nil;
        id currentDelegate = KBCurrentInputDelegate(&keyboard);
        if ([keyboard respondsToSelector:@selector(deleteFromInput)]) {
            [keyboard deleteFromInput];
            KBRefreshKeyboardState(keyboard);
        } else if ([currentDelegate respondsToSelector:@selector(deleteBackward)]) {
            [currentDelegate deleteBackward];
        }
    });
}

%hook UIKeyboardDockView

- (void)layoutSubviews {
    %orig;

    // Dedupe: layoutSubviews fires repeatedly — only build the row once.
    UIStackView *existing = (UIStackView *)[self viewWithTag:kToolbarTag];
    if (existing) {
        [self bringSubviewToFront:existing];
        return;
    }

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.tag = kToolbarTag;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray *specs = @[
        @[@"doc.on.clipboard", @"kb_didTapPaste", @"kb_didLongPressPaste:",
          @"Paste", @"Long press to select all and copy"],
        @[@"chevron.left", @"kb_didTapLeft", @"kb_didLongPressLeft:",
          @"Move cursor left", @"Long press to move to the beginning"],
        @[@"chevron.right", @"kb_didTapRight", @"kb_didLongPressRight:",
          @"Move cursor right", @"Long press to move to the end"],
        @[@"keyboard.chevron.compact.down", @"kb_didTapDismiss",
          @"kb_didLongPressDismiss:", @"Dismiss keyboard",
          @"Long press to clear all text"],
    ];
    for (NSArray *spec in specs) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
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
        [stack addArrangedSubview:button];
    }

    [self addSubview:stack];
    [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0].active = YES;
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
