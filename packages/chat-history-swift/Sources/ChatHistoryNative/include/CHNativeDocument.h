#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns the mapped source and immutable native row ranges for its lifetime.
@interface CHNativeDocument : NSObject
- (nullable instancetype)initWithProvider:(NSString *)provider path:(NSString *)path error:(NSError **)error;
@property(nonatomic, readonly) NSUInteger rowCount;
@property(nonatomic, readonly) NSUInteger recordCount;
@property(nonatomic, readonly) NSUInteger sourceBytes;
@property(nonatomic, readonly) NSUInteger warningCount;
@property(nonatomic, readonly) double loadMs;
@property(nonatomic, readonly) double scanMs;
@property(nonatomic, readonly) double parseMs;
@property(nonatomic, readonly) double nativeTotalMs;
- (NSDictionary<NSString *, id> *)metadataAtIndex:(NSUInteger)index;
- (NSString *)markdownAtIndex:(NSUInteger)index;
- (NSString *)previewAtIndex:(NSUInteger)index;
- (NSString *)contentDigest;
@end
NS_ASSUME_NONNULL_END
