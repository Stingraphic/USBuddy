import SwiftUI

struct MeshGlassBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [
                    Color(white: 0.12).opacity(0.55),
                    Color.black
                ],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}
