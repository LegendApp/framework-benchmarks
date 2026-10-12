import Combine
import Foundation

/// The same local, unsaved composer demo as the RN app. It never performs I/O.
@MainActor
public final class ChatDemo: ObservableObject {
  @Published public private(set) var rows: [ChatRow] = []
  public var onChange: (() -> Void)?
  private var task: Task<Void, Never>?
  public init() {}
  public func reset() {
    task?.cancel()
    task = nil
    rows = []
  }
  private func row(_ kind: ChatRowKind, _ text: String, id: String) -> ChatRow {
    ChatRow(
      fileChanges: [], hasImagePlaceholder: false, id: id, imageSources: [], kind: kind,
      markdown: text, toolName: "", toolPreview: "", toolStatus: .none)
  }
  public func send(_ input: String) {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return }
    task?.cancel()
    let id = UUID().uuidString
    rows.append(row(.user, input, id: id + ":user"))
    onChange?()
    task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard let self, !Task.isCancelled else { return }
      let index = rows.count
      rows.append(row(.assistant, "", id: id + ":assistant"))
      var text = ""
      for word in Self.response.components(separatedBy: " ") {
        guard !Task.isCancelled else { return }
        text += (text.isEmpty ? "" : " ") + word
        rows[index] = row(.assistant, text, id: id + ":assistant")
        onChange?()
        try? await Task.sleep(for: .milliseconds(30))
      }
    }
  }
  public static let response = """
    This is a deliberately long fake streamed response. Nothing was sent to a model, no network request was made, and none of this text will be saved to the transcript. The purpose of this response is to make the test turn substantially taller than the visible conversation area so that the anchored-end behavior can be evaluated while content grows, after it finishes growing, and while you manually scroll through the completed result.

    At the beginning of the stream, the new user message should remain positioned just below the titlebar. The assistant response should then expand underneath it one word at a time without pushing that user message away from its anchored position. As the response becomes taller, LegendList should reduce the synthetic space at the end by the same amount. The important invariant is that synthetic space and real message content replace each other rather than accumulating together and making the transcript artificially taller.

    Once this paragraph appears, the response should already occupy a meaningful portion of the window. You can drag the scrollbar toward the bottom before the stream finishes and compare the reachable end with the end after all words have arrived. A correct implementation should always expose the complete response, but it should not leave an additional viewport-sized empty region after the final line. If that empty region remains, the problem is likely in how the native scroll extent reacts when anchoredEndSpace shrinks rather than in the size of the assistant message itself.

    This test also exercises recycled, variable-height rows. The user message is short and right aligned, while this assistant message has no bubble and is intentionally much taller. Its measured height changes repeatedly during streaming. Those updates should flow into the list layout, the calculated content below the anchor, and the trailing content-container padding. The physical scroll range should therefore track the latest measurement instead of retaining the largest padding value that existed near the start of the stream.

    There is enough text here to continue beyond a typical macOS chat viewport even when the window is fairly wide. That matters because a short response can hide a stale-tail bug: the generated anchor space dominates the content and makes every offset look plausible. With a long response, the real row height eventually consumes all available anchor space. At that point the trailing padding should reach zero, leaving only the normal bottom spacing owned by the transcript and composer layout.

    You should now be able to scroll through several full paragraphs of fake content. Try moving to the absolute bottom, then slightly upward, then back to the bottom again. The last line should be reachable and should stop at the expected bottom edge. There should be no second blank screen after it, no rubber-band range that behaves like permanent content, and no sudden jump when the final streamed word causes the anchor calculation to update.

    The response continues for another paragraph to make the test unambiguous on large displays. While reading it, notice that the content itself is ordinary selectable text and that the composer remains visible below the list. The demo is still intentionally inert: sending only mutates the temporary in-memory data source used by this screen. Switching chats or reopening the application discards the generated turn, and no provider session, local transcript, or remote model is affected.

    This is the final portion of the fake response. By now the assistant row should be at least one screen tall, and on most window sizes it should be considerably taller. The final sentence marks the true end of the generated content so it is easy to identify whether LegendList stops at the correct location: this line should be the end, with only the normal small amount of bottom spacing after it.
    """
}
