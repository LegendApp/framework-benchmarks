#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <mach/mach_time.h>
#include <mutex>
#include <vector>
struct Event { const char *name; double start; double duration; bool main; long length; uint64_t thread; };
static std::mutex mutex_; static std::vector<Event> events; static NSString *path;
static double nowMs() { return NSProcessInfo.processInfo.systemUptime*1000; }
static void record(const char *name,double start,long length=0) { double end=nowMs();uint64_t thread;pthread_threadid_np(NULL,&thread);std::lock_guard<std::mutex> guard(mutex_);events.push_back({name,start,end-start,(bool)NSThread.isMainThread,length,thread}); }
static void wrapVoidObject(const char *className,const char *selector) {
 Class cls=objc_getClass(className); SEL sel=sel_registerName(selector);Method m=class_getInstanceMethod(cls,sel); if(!m)return; IMP old=method_getImplementation(m);
 IMP replacement=imp_implementationWithBlock(^(id obj,id arg){double t=nowMs();((void(*)(id,SEL,id))old)(obj,sel,arg);record(selector,t,[obj isKindOfClass:NSLayoutManager.class] ? (long)((NSLayoutManager *)obj).textStorage.length : ([arg respondsToSelector:@selector(length)]?(long)[arg length]:0));});
 class_replaceMethod(cls,sel,replacement,method_getTypeEncoding(m));
}
static void wrapVoid(const char *className,const char *selector) {
 Class cls=objc_getClass(className);SEL sel=sel_registerName(selector);Method m=class_getInstanceMethod(cls,sel);if(!m)return;IMP old=method_getImplementation(m);
 IMP replacement=imp_implementationWithBlock(^(id obj){double t=nowMs();((void(*)(id,SEL))old)(obj,sel);record(selector,t);});class_replaceMethod(cls,sel,replacement,method_getTypeEncoding(m));
}
static void installHooks() {
 @autoreleasepool {
 if(![NSProcessInfo.processInfo.processName isEqualToString:@"Legend Chat History"])return;
 path=NSProcessInfo.processInfo.environment[@"CHAT_NATIVE_TRACE"];if(!path)return;
 wrapVoidObject("NSLayoutManager","ensureLayoutForTextContainer:");
 wrapVoidObject("EnrichedMarkdownText","renderMarkdownContent:");
 wrapVoidObject("EnrichedMarkdown","renderMarkdownContent:");
 wrapVoidObject("EnrichedMarkdown","applyRenderedSegments:");
 wrapVoid("EnrichedMarkdown","layoutSubviews");
 wrapVoid("EnrichedMarkdown","prepareForRecycle");
 wrapVoidObject("EnrichedMarkdownText","applyRenderedText:");
 wrapVoid("EnrichedMarkdownText","layoutSubviews");
 wrapVoid("EnrichedMarkdownText","prepareForRecycle");
 Class cls=objc_getClass("ENRMMarkdownParser");SEL sel=@selector(parseMarkdown:flags:);Method m=class_getInstanceMethod(cls,sel);
 if(m){IMP old=method_getImplementation(m);class_replaceMethod(cls,sel,imp_implementationWithBlock(^id(id obj,id arg,id flags){double t=nowMs();id result=((id(*)(id,SEL,id,id))old)(obj,sel,arg,flags);record("markdown.parse",t,[arg length]);return result;}),method_getTypeEncoding(m));}
 cls=objc_getClass("EnrichedMarkdown");sel=sel_registerName("measureSize:");m=class_getInstanceMethod(cls,sel);
 if(m){IMP old=method_getImplementation(m);class_replaceMethod(cls,sel,imp_implementationWithBlock(^CGSize(id obj,CGFloat width){double t=nowMs();CGSize result=((CGSize(*)(id,SEL,CGFloat))old)(obj,sel,width);record("text.measureSize",t,(long)width);return result;}),method_getTypeEncoding(m));}
 static dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
 dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_SEC/10);
 dispatch_source_set_event_handler(timer,^{ @autoreleasepool { std::vector<Event> snapshot;{std::lock_guard<std::mutex> guard(mutex_);snapshot=events;}NSMutableArray *out=[NSMutableArray new];double offset=NSDate.date.timeIntervalSince1970*1000-nowMs();for(auto e:snapshot)[out addObject:@{@"name":@(e.name),@"startMs":@(e.start),@"durationMs":@(e.duration),@"main":@(e.main),@"length":@(e.length),@"thread":@(e.thread),@"epochEndMs":@(e.start+e.duration+offset)}];NSData *data=[NSJSONSerialization dataWithJSONObject:out options:0 error:nil];[data writeToFile:path atomically:YES]; }});dispatch_resume(timer);
 record("hooks.installed",nowMs());
 }
}

__attribute__((constructor)) static void registerHooks() {
 @autoreleasepool {
  if (![NSProcessInfo.processInfo.processName isEqualToString:@"Legend Chat History"]) return;
  [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) { installHooks(); }];
 }
}
