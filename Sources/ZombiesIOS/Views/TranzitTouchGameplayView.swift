import SwiftUI

struct TranzitTouchGameplayView: View {
    let package: ConvertedRuntimePackage

    @State private var move = CGSize.zero
    @State private var look = CGSize.zero
    @State private var firing = false
    @State private var aiming = false
    @State private var jumpPulse = 0
    @State private var reloadPulse = 0
    @State private var health = 100
    @State private var ammo = 30
    @State private var kills = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ConvertedTranzitSceneView(
                    package: package,
                    move: move,
                    look: look,
                    firing: firing,
                    aiming: aiming,
                    jumpPulse: jumpPulse,
                    reloadPulse: reloadPulse,
                    health: $health,
                    ammo: $ammo,
                    kills: $kills
                )
                .ignoresSafeArea()

                hud
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    inputZone(size: proxy.size, isMove: true)
                    inputZone(size: proxy.size, isMove: false)
                }

                controls
            }
        }
        .navigationTitle("Tranzit")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var hud: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRANZIT")
                        .font(.headline.monospaced())
                        .foregroundStyle(.white)
                    Text("CONVERTED ASSET RUNTIME")
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(.green.opacity(0.9))
                    Text("HP \(health)")
                        .font(.title3.bold().monospaced())
                        .foregroundStyle(health > 35 ? .white : .red)
                    Text("KILLS \(kills)")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(ammo) / 30")
                        .font(.title2.bold().monospaced())
                        .foregroundStyle(ammo > 5 ? .white : .orange)
                    Text("WORLD \(package.worldMesh.positions.count)V / \(package.worldMesh.indices.count / 3)T")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.75))
                    Text(package.materialManifest.fullFidelity ? "MATERIALS READY" : "MATERIAL FALLBACK ACTIVE")
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(package.materialManifest.fullFidelity ? .green : .orange)
                }
                .padding(.trailing, 10)
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .background(.black.opacity(0.30))

            Spacer()

            Text("+")
                .font(.system(size: aiming ? 22 : 34, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(radius: 2)

            Spacer()
        }
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 14) {
                stick(position: move, label: "MOVE")
                Spacer()
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton("ADS", active: aiming) { aiming.toggle() }
                        fireButton
                    }
                    HStack(spacing: 10) {
                        actionButton("RELOAD", active: false) { reloadPulse &+= 1 }
                        actionButton("JUMP", active: false) { jumpPulse &+= 1 }
                    }
                }
                stick(position: look, label: "LOOK")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private var fireButton: some View {
        Text("FIRE")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 72, height: 52)
            .background(firing ? .white.opacity(0.38) : .black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.4)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in firing = true }
                    .onEnded { _ in firing = false }
            )
    }

    private func actionButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 72, height: 44)
                .background(active ? .white.opacity(0.32) : .black.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.35)))
        }
    }

    private func stick(position: CGSize, label: String) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.24))
                .overlay(Circle().stroke(.white.opacity(0.28)))
            Circle()
                .fill(.white.opacity(0.28))
                .frame(width: 42, height: 42)
                .offset(position)
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.62))
                .offset(y: 50)
        }
        .frame(width: 116, height: 116)
        .allowsHitTesting(false)
    }

    private func inputZone(size: CGSize, isMove: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: size.width * 0.5, height: size.height)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let center = CGPoint(x: size.width * 0.25, y: size.height * 0.72)
                        let raw = CGSize(width: value.location.x - center.x, height: value.location.y - center.y)
                        let clamped = clamp(raw, radius: isMove ? 34 : 52)
                        if isMove { move = clamped } else { look = clamped }
                    }
                    .onEnded { _ in
                        if isMove { move = .zero } else { look = .zero }
                    }
            )
    }

    private func clamp(_ value: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(value.width * value.width + value.height * value.height)
        guard length > radius, length > 0 else { return value }
        let scale = radius / length
        return CGSize(width: value.width * scale, height: value.height * scale)
    }
}
