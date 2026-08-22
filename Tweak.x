#import <UIKit/UIKit.h>

// ============================================================================
// KBEditToolbar — keyboard toolbar with 4 buttons:
//   Paste / Cursor-Left / Cursor-Right / Dismiss.
// Hooks UIKeyboardDockView -layoutSubviews to inject the button row.
// Paste goes through the responder chain; cursor moves manipulate the focused
// UITextInput's selectedTextRange; dismiss talks to UIKeyboardImpl.
// ============================================================================

@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
- (void)dismissKeyboard;
@end

// UIKeyboardDockView is a private UIKit class. Declaring it as a UIView subclass
// lets the compiler resolve UIView methods/properties (viewWithTag:, addSubview:,
// centerXAnchor, bottomAnchor, ...) on `self` inside the hook.
@interface UIKeyboardDockView : UIView
@end

static const NSInteger kToolbarTag = 0x4B54; // 'KT'

// --- Find the current first responder if it is a text input ------------------
static __weak id gCaptured;

%hook UIResponder
%new
- (void)kb_capture:(id)sender { gCaptured = self; }
%end

static id<UITextInput> KBCurrentTextInput(void) {
    gCaptured = nil;
    // to:nil routes the action to whoever is first responder; inside kb_capture:
    // `self` IS that responder, which we stash into gCaptured.
    [[UIApplication sharedApplication] sendAction:@selector(kb_capture:)
                                              to:nil from:nil forEvent:nil];
    id r = gCaptured;
    if (r && [r conformsToProtocol:@protocol(UITextInput)]) return (id<UITextInput>)r;
    return nil;
}

static void KBMoveCaret(BOOL left) {
    id<UITextInput> ti = KBCurrentTextInput();
    if (!ti) return;
    UITextRange *sel = [ti selectedTextRange];
    if (!sel) return;
    UITextPosition *anchor = left ? sel.start : sel.end;
    UITextPosition *pos = [ti positionFromPosition:anchor offset:(left ? -1 : 1)];
    if (!pos) pos = anchor;                     // clamp at string ends
    UITextRange *nr = [ti textRangeFromPosition:pos toPosition:pos];
    if (nr) [ti setSelectedTextRange:nr];
}

%hook UIKeyboardDockView

- (void)layoutSubviews {
    %orig;

    // Dedupe: layoutSubviews fires repeatedly — only build the row once.
    UIStackView *existing = (UIStackView *)[self viewWithTag:kToolbarTag];
    if (existing) { [self bringSubviewToFront:existing]; return; }

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.tag = kToolbarTag;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray *specs = @[
        @[@"doc.on.clipboard",              @"kb_didTapPaste"],
        @[@"chevron.left",                  @"kb_didTapLeft"],
        @[@"chevron.right",                 @"kb_didTapRight"],
        @[@"keyboard.chevron.compact.down", @"kb_didTapDismiss"],
    ];
    for (NSArray *spec in specs) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setImage:[UIImage systemImageNamed:spec[0]] forState:UIControlStateNormal];
        b.tintColor = [UIColor labelColor];
        [b addTarget:self action:NSSelectorFromString(spec[1])
            forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:b];
    }

    [self addSubview:stack];
    [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0].active = YES;
}

%new
- (void)kb_haptic {
    UIImpactFeedbackGenerator *g =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g prepare];
    [g impactOccurred];
}

%new
- (void)kb_didTapPaste {
    [self kb_haptic];
    [[UIApplication sharedApplication] sendAction:@selector(paste:)
                                              to:nil from:self forEvent:nil];
}

%new
- (void)kb_didTapLeft  { [self kb_haptic]; KBMoveCaret(YES); }

%new
- (void)kb_didTapRight { [self kb_haptic]; KBMoveCaret(NO); }

%new
- (void)kb_didTapDismiss {
    [self kb_haptic];
    UIKeyboardImpl *impl = [%c(UIKeyboardImpl) activeInstance];
    if ([impl respondsToSelector:@selector(dismissKeyboard)]) [impl dismissKeyboard];
}

%end
