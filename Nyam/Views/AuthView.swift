import SwiftUI

struct AuthView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle.fill")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .foregroundStyle(Color.accentColor)

                    Text("Nyam")
                        .font(.system(size: 44, weight: .bold, design: .rounded))

                    Text("Measure your meal, not guess.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        auth.signInAsGuest()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Text("Your meal photos are sent to OpenAI for nutrition analysis. We don't store them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}
