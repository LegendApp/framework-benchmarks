import SwiftUI

@main
struct HelloWorldApp: App {
    var body: some Scene {
        Window("Hello World — SwiftUI", id: "main") {
            Text("Hello, world!")
                .font(.system(size: 32))
                .foregroundStyle(Color(red: 32/255, green: 33/255, blue: 36/255))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1280, height: 720)
        .defaultPosition(.center)
    }
}
