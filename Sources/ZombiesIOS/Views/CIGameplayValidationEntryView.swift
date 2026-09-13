import SwiftUI

struct CIGameplayValidationEntryView: View {
    private let package = CIRuntimeMeshFixture.makePackage()

    var body: some View {
        ZStack {
            QuakeGameplayView(
                move: .zero,
                look: .zero,
                firing: false,
                aiming: false,
                jumpPulse: 0,
                reloadPulse: 0,
                package: package
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text("CI QUAKE RUNTIME")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.green)
                    Spacer()
                    Text("NATIVE METAL")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.white)
                }
                .padding()
                Spacer()
                Text("+")
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .background(.black)
        .preferredColorScheme(.dark)
    }
}
