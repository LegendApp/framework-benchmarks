#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// A real native material above GPUI's Metal surface, not a screenshot or a
// behind-window blur. The host owns the view; the overlay tracks its size without
// imposing Auto Layout size constraints on GPUI's window.
@interface BenchmarkComposerGlass : NSView
@property NSView *effect;
@property NSTextField *placeholder;
@end
@implementation BenchmarkComposerGlass
- (NSView *)hitTest:(NSPoint)point { return nil; } // Matches the inert GPUI demo composer.
@end

@interface BenchmarkComposerContainer : NSView
@property BenchmarkComposerGlass *panel;
@end
@implementation BenchmarkComposerContainer
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; self.needsLayout = YES; }
- (void)layout {
    [super layout];
    CGFloat width = MAX(0, MIN(860, self.bounds.size.width - 308));
    self.panel.frame = NSMakeRect((self.bounds.size.width - width) / 2 + 130, 20, width, 60);
}
@end

void update_composer_glass(void *viewPointer, bool dark, bool hidden) {
    NSView *host = (__bridge NSView *)viewPointer;
    static char associationKey;
    BenchmarkComposerGlass *panel = objc_getAssociatedObject(host, &associationKey);
    if (!panel) {
        panel = [BenchmarkComposerGlass new];
        panel.translatesAutoresizingMaskIntoConstraints = YES;
        panel.wantsLayer = YES;
        panel.layer.cornerRadius = 26;
        panel.layer.borderWidth = 1;
        panel.layer.shadowOpacity = 0.22;
        panel.layer.shadowRadius = 24;
        panel.layer.shadowOffset = CGSizeMake(0, -10);
        NSView *content = [NSView new];
        if (@available(macOS 26, *)) {
            NSGlassEffectView *glass = [NSGlassEffectView new];
            glass.style = NSGlassEffectViewStyleRegular;
            glass.cornerRadius = 26;
            glass.contentView = content;
            panel.effect = glass;
        } else {
            NSVisualEffectView *effect = [NSVisualEffectView new];
            effect.material = NSVisualEffectMaterialContentBackground;
            effect.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            effect.state = NSVisualEffectStateActive;
            effect.wantsLayer = YES;
            effect.layer.cornerRadius = 26;
            effect.layer.masksToBounds = YES;
            [effect addSubview:content];
            content.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor], [content.topAnchor constraintEqualToAnchor:effect.topAnchor], [content.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor]]];
            panel.effect = effect;
        }
        panel.effect.translatesAutoresizingMaskIntoConstraints = NO;
        [panel addSubview:panel.effect];
        panel.placeholder = [NSTextField labelWithString:@"Send a test message that doesn't actually do anything"];
        panel.placeholder.font = [NSFont systemFontOfSize:15];
        panel.placeholder.lineBreakMode = NSLineBreakByTruncatingTail;
        panel.placeholder.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:panel.placeholder];
        NSTextField *send = [NSTextField labelWithString:@"↑"];
        send.alignment = NSTextAlignmentCenter;
        send.font = [NSFont systemFontOfSize:24 weight:NSFontWeightSemibold];
        send.textColor = NSColor.whiteColor;
        send.wantsLayer = YES;
        send.layer.backgroundColor = [NSColor colorWithSRGBRed:96.0/255 green:165.0/255 blue:250.0/255 alpha:0.3].CGColor;
        send.layer.cornerRadius = 18;
        send.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:send];
        BenchmarkComposerContainer *container = [[BenchmarkComposerContainer alloc] initWithFrame:host.bounds];
        container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        container.panel = panel;
        [container addSubview:panel];
        [host addSubview:container];
        [container layout];
        [NSLayoutConstraint activateConstraints:@[
            [panel.effect.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor], [panel.effect.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor], [panel.effect.topAnchor constraintEqualToAnchor:panel.topAnchor], [panel.effect.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
            [panel.placeholder.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16], [panel.placeholder.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
            [panel.placeholder.trailingAnchor constraintLessThanOrEqualToAnchor:send.leadingAnchor constant:-12],
            [send.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16], [send.centerYAnchor constraintEqualToAnchor:content.centerYAnchor], [send.widthAnchor constraintEqualToConstant:36], [send.heightAnchor constraintEqualToConstant:36]
        ]];
        objc_setAssociatedObject(host, &associationKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    panel.hidden = hidden;
    panel.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    panel.placeholder.textColor = dark ? [NSColor colorWithWhite:0.64 alpha:1] : [NSColor colorWithWhite:0.42 alpha:1];
    panel.layer.borderColor = [NSColor colorWithWhite:dark ? 0.25 : 0.82 alpha:1].CGColor;
    if (@available(macOS 26, *)) {
        ((NSGlassEffectView *)panel.effect).tintColor = dark ? [NSColor colorWithSRGBRed:32.0/255 green:33.0/255 blue:36.0/255 alpha:0.4] : [NSColor colorWithWhite:1 alpha:112.0/255];
    }
}
