use gpui::{
    App, Application, Bounds, Context, Render, TitlebarOptions, Window, WindowBounds,
    WindowOptions, div, prelude::*, px, rgb, size,
};

struct HelloWorld;

impl Render for HelloWorld {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div().size_full().flex().items_center().justify_center()
            .bg(rgb(0xffffff)).text_color(rgb(0x202124)).text_size(px(32.0))
            .child("Hello, world!")
    }
}

fn main() {
    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1280.0), px(720.0)), cx);
        cx.open_window(WindowOptions {
            focus: true,
            titlebar: Some(TitlebarOptions {
                title: Some("Hello World — GPUI".into()),
                ..Default::default()
            }),
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            ..Default::default()
        }, |_, cx| cx.new(|_| HelloWorld)).expect("failed to open Hello World");
        cx.activate(true);
    });
}
