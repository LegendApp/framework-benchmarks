// Run from the repository root:
// xcrun clang -fobjc-arc -fmodules -framework AppKit apps/chat-history-gpui/src/composer_glass.m apps/chat-history-gpui/tests/composer_glass_test.m -o .build/composer-glass-test && .build/composer-glass-test
#import <AppKit/AppKit.h>
extern void update_composer_glass(void *, bool, bool);
int main() { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,720) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  NSView *host = window.contentView;
  for (NSNumber *width in @[@1280,@900,@1600]) {
    [window setContentSize:NSMakeSize(width.doubleValue,720)];
    update_composer_glass((__bridge void *)host,true,false);
    [host layoutSubtreeIfNeeded];
    NSView *panel=host.subviews.lastObject.subviews.lastObject;
    NSRect frame=panel.frame;
    assert(host.subviews.count==1);
    assert(fabs(frame.size.width-MIN(860,width.doubleValue-308))<1);
    assert(fabs(frame.origin.x-((width.doubleValue-frame.size.width)/2+130))<1);
    assert(fabs(frame.origin.y-20)<1);
    assert(fabs(frame.size.height-60)<1);
  }
  update_composer_glass((__bridge void *)host,false,true);
  assert(host.subviews.count==1 && host.subviews.lastObject.subviews.lastObject.hidden);
  update_composer_glass((__bridge void *)host,false,false);
  assert(!host.subviews.lastObject.subviews.lastObject.hidden);
  puts("PASS: three widths, single retained overlay, theme update and settings visibility");
} return 0; }
