#pragma once
#include <string>
#include <optional>
namespace margelo::nitro::legendapps::chathistory {

  /**
   * A struct which can be represented as a JavaScript object (ChatDocumentTiming).
   */
  struct ChatDocumentTiming final {
  public:
    double sourceBytes     ;
    double recordCount     ;
    double rowCount     ;
    double mappedMs     ;
    double scannedMs     ;
    double normalizedMs     ;
    double documentMs     ;
    double totalMs     ;

  public:
    ChatDocumentTiming() = default;
    explicit ChatDocumentTiming(double sourceBytes, double recordCount, double rowCount, double mappedMs, double scannedMs, double normalizedMs, double documentMs, double totalMs): sourceBytes(sourceBytes), recordCount(recordCount), rowCount(rowCount), mappedMs(mappedMs), scannedMs(scannedMs), normalizedMs(normalizedMs), documentMs(documentMs), totalMs(totalMs) {}

  public:
    friend bool operator==(const ChatDocumentTiming& lhs, const ChatDocumentTiming& rhs) = default;
  };

}
namespace margelo::nitro::legendapps::chathistory {

  /**
   * A struct which can be represented as a JavaScript object (ChatRowMetadata).
   */
  struct ChatRowMetadata final {
  public:
    double index     ;
    std::string kind     ;
    std::optional<std::string> markdownBlockId     ;
    std::optional<std::string> toolName     ;
    std::optional<std::string> toolStatus     ;
    bool hasToolPreview     ;
    bool hasImagePlaceholder     ;
    double imageCount     ;
    std::optional<double> fileCount     ;
    std::optional<double> fileAdditions     ;
    std::optional<double> fileDeletions     ;

  public:
    ChatRowMetadata() = default;
    explicit ChatRowMetadata(double index, std::string kind, std::optional<std::string> markdownBlockId, std::optional<std::string> toolName, std::optional<std::string> toolStatus, bool hasToolPreview, bool hasImagePlaceholder, double imageCount, std::optional<double> fileCount, std::optional<double> fileAdditions, std::optional<double> fileDeletions): index(index), kind(kind), markdownBlockId(markdownBlockId), toolName(toolName), toolStatus(toolStatus), hasToolPreview(hasToolPreview), hasImagePlaceholder(hasImagePlaceholder), imageCount(imageCount), fileCount(fileCount), fileAdditions(fileAdditions), fileDeletions(fileDeletions) {}

  public:
    friend bool operator==(const ChatRowMetadata& lhs, const ChatRowMetadata& rhs) = default;
  };

}
namespace margelo::nitro::legendapps::chathistory {

  /**
   * A struct which can be represented as a JavaScript object (ChatFileChange).
   */
  struct ChatFileChange final {
  public:
    std::string path     ;
    double additions     ;
    double deletions     ;

  public:
    ChatFileChange() = default;
    explicit ChatFileChange(std::string path, double additions, double deletions): path(path), additions(additions), deletions(deletions) {}

  public:
    friend bool operator==(const ChatFileChange& lhs, const ChatFileChange& rhs) = default;
  };

}
