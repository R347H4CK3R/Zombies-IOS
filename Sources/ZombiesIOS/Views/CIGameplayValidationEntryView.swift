import SwiftUI

struct CIGameplayValidationEntryView: View {
    @State private var health = 100
    @State private var ammo = 30
    @State private var kills = 0

    var body: some View {
        ZStack {
            NativeFPSSceneView(
                move: .zero,
                look: .zero,
                firing: false,
                aiming: false,
                jumpPulse: 0,
                reloadPulse: 0,
                health: $health,
                ammo: $ammo,
                kills: $kills,
                mapSeed: 0xC1,
                runtimeMesh: CIRuntimeMeshFixture.make()
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text("CI GAMEPLAY VALIDATION")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.green)
                    Spacer()
                    Text("30 / 30")
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
