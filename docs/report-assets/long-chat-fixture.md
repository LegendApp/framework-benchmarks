## Designing a desktop chat application

The window should stay readable while a long conversation scrolls underneath the composer. This example includes prose, headings, lists, and highlighted code so that the material has both fine detail and color to sample.

### A shared document model

Read the transcript once, index its records, and materialize messages when the visible list needs them. Keep the original text available for selection and copying. The same content should be presented whether the renderer uses native views, a web view, or GPU-drawn widgets.

```typescript
interface Message {
  id: string;
  role: "user" | "assistant";
  markdown: string;
}

function visibleMessages(messages: Message[], start: number) {
  return messages.slice(start, start + 30);
}
```

### Rendering and interaction

- Keep navigation and transcript scrolling independent.
- Render Markdown and syntax highlighting for visible messages.
- Overlay the composer above the scrolling content.
- Preserve enough bottom space to reach the final line.

The composer remains anchored near the bottom of the window. Text and colored code should continue behind it when the conversation is scrolled away from the end. Native Liquid Glass can alter its appearance around edges and nearby content; a conventional backdrop filter smooths the pixels behind the surface. A transparent panel alone leaves those pixels sharp.

### What to look for

Look at the horizontal lines of text immediately behind the input field, then compare the material at the rounded left and right edges. The placeholder and send button should remain clear while the underlying conversation is softened where a real blur is available.

This is synthetic demonstration content. It contains no private history, account details, local file paths, or messages from other people.
