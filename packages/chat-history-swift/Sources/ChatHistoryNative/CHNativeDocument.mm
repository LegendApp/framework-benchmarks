#import "CHNativeDocument.h"
#include "core/NativeDocument.hpp"
#include <chrono>

using namespace margelo::nitro::legendapps::chathistory;
using Clock = std::chrono::steady_clock;
static NSString *text(const std::string &value) {
  return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding] ?: @"";
}

@implementation CHNativeDocument {
  std::unique_ptr<NativeDocument> _document;
}
- (nullable instancetype)initWithProvider:(NSString *)provider path:(NSString *)path error:(NSError **)error {
  self = [super init];
  if (!self) return nil;
  try {
    const auto started = Clock::now();
    std::atomic<uint64_t> generation{1};
    auto result = parseChatFile(provider.UTF8String, path.fileSystemRepresentation, 1, generation);
    _sourceBytes = result.source->size();
    _recordCount = result.recordCount;
    _warningCount = result.warningCount;
    _loadMs = result.mappedMs;
    _scanMs = result.scannedMs;
    _document = std::make_unique<NativeDocument>("swift", std::move(result), ChatDocumentTiming{});
    _rowCount = static_cast<NSUInteger>(_document->getRowCount());
    _nativeTotalMs = std::chrono::duration<double, std::milli>(Clock::now() - started).count();
    _parseMs = _nativeTotalMs - _loadMs - _scanMs;
    return self;
  } catch (const std::exception &exception) {
    if (error) *error = [NSError errorWithDomain:@"ChatHistoryNative" code:1
      userInfo:@{NSLocalizedDescriptionKey: text(exception.what())}];
    return nil;
  }
}
- (NSDictionary<NSString *, id> *)metadataAtIndex:(NSUInteger)index {
  const auto row = _document->getRowMetadata(index);
  NSMutableArray *images = [NSMutableArray array];
  for (size_t i = 0; i < row.imageCount; ++i) [images addObject:text(_document->getImageSource(index, i))];
  NSMutableArray *files = [NSMutableArray array];
  for (size_t i = 0; i < row.fileCount.value_or(0); ++i) {
    const auto file = _document->getFileChange(index, i);
    [files addObject:@{@"path": text(file.path), @"additions": @(file.additions), @"deletions": @(file.deletions)}];
  }
  return @{@"kind": text(row.kind), @"toolName": text(row.toolName.value_or("")),
    @"toolStatus": text(row.toolStatus.value_or("")), @"hasImagePlaceholder": @(row.hasImagePlaceholder),
    @"images": images, @"files": files};
}
- (NSString *)markdownAtIndex:(NSUInteger)index {
  // Work groups expose only their summary/preview, never the first hidden
  // assistant row's Markdown. RN uses the same metadata flag before asking.
  if (!_document->getRowMetadata(index).markdownBlockId) return @"";
  return text(_document->markdownForRow(index));
}
- (NSString *)previewAtIndex:(NSUInteger)index { return text(_document->getToolPreview(index, 64 * 1024)); }
- (NSString *)contentDigest { return text(_document->getContentDigest()); }
@end
