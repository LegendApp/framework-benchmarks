#pragma once

#include "ChatDocument.hpp"



#include <mutex>

namespace margelo::nitro::legendapps::chathistory {

struct ChatDisplayRow {
  size_t firstRow = 0;
  size_t rowCount = 1;
  bool isWorkGroup = false;
  ChatRowMetadata metadata;
};

class NativeDocument final {
public:
  NativeDocument(std::string documentId, ChatParseResult result, ChatDocumentTiming timing);
  ~NativeDocument();

  std::string getContentDigest();
  std::string getDocumentId();
  double getRowCount();
  double getWarningCount();
  std::string getRowKind(double index);
  ChatRowMetadata getRowMetadata(double index);
  std::string getToolPreview(double index, double maximumBytes);
  std::string getImageSource(double index, double imageIndex);
  ChatFileChange getFileChange(double index, double fileIndex);
  ChatDocumentTiming getTiming();
  double releaseNativeResources();

  std::string markdownForRow(size_t index);
  void setTiming(ChatDocumentTiming timing);

protected:
  size_t getExternalMemorySize() noexcept;

private:
  void buildDisplayRows();
  std::string computeContentDigest() const;
  ChatRowMetadata createRowMetadata(size_t displayIndex) const;
  std::string decodeRanges(const std::vector<JsonRange>& ranges, size_t maximumBytes = 0) const;
  std::string workGroupLabel(const ChatDisplayRow& displayRow) const;
  std::string workGroupPreview(const ChatDisplayRow& displayRow, size_t maximumBytes) const;
  std::string workGroupStatus(const ChatDisplayRow& displayRow) const;
  size_t checkedIndex(double index) const;
  size_t checkedFileIndex(const ChatRow& row, double fileIndex) const;
  size_t checkedImageIndex(const ChatRow& row, double imageIndex) const;

  std::string documentId_;
  std::string contentDigest_;
  std::once_flag contentDigestOnce_;
  mutable std::mutex mutex_;
  std::shared_ptr<const ChatSource> source_;
  std::vector<ChatRow> rows_;
  std::vector<ChatDisplayRow> displayRows_;
  size_t warningCount_ = 0;
  ChatDocumentTiming timing_;
};

} // namespace margelo::nitro::legendapps::chathistory
