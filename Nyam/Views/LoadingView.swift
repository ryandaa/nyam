import SwiftUI

struct LoadingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "fork.knife.circle.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("Reading your plate…")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .onAppear { pulse = true }
    }
}

#Preview {
    LoadingView()
}
