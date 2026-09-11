// Deno Desktop serves its window from the local HTTP server, as in the product app.
type DesktopDeno = typeof Deno & {
  BrowserWindow: new (options: { title: string; width: number; height: number }) => {
    show(): void;
    focus(): void;
  };
};
const window = new (Deno as DesktopDeno).BrowserWindow({
  title: "Hello World — Deno", width: 1280, height: 720,
});
const files = new Map([
  ["/", ["index.html", "text/html"]],
  ["/renderer.js", ["renderer.js", "text/javascript"]],
  ["/renderer.css", ["renderer.css", "text/css"]],
]);
Deno.serve({ hostname: "127.0.0.1", port: 8000 }, async (request) => {
  const file = files.get(new URL(request.url).pathname);
  if (!file) return new Response("Not found", { status: 404 });
  return new Response(await Deno.readFile(new URL(`../dist/${file[0]}`, import.meta.url)), {
    headers: { "content-type": file[1] },
  });
});
window.show();
window.focus();
