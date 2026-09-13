import SwiftUI
import Combine
import simd

struct BO2GameplayView: View {
    let asset: WorldRuntimeAsset
    @ObservedObject var coordinator: BO2GameCoordinator
    @State private var lastLook = CGSize.zero
    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            MetalWorldView(
                asset: asset,
                playerPosition: coordinator.movement.playerPosition,
                yaw: coordinator.movement.yaw,
                pitch: coordinator.movement.pitch
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            coordinator.movement.setMovement(
                                forward: Float(max(-1, min(1, -value.translation.height / 70))),
                                right: Float(max(-1, min(1, value.translation.width / 70)))
                            )
                        }
                        .onEnded { _ in coordinator.movement.setMovement(forward: 0, right: 0) })
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = value.translation.width - lastLook.width
                            let dy = value.translation.height - lastLook.height
                            lastLook = value.translation
                            coordinator.movement.addLook(yaw: Float(dx) * 0.15, pitch: Float(-dy) * 0.12)
                        }
                        .onEnded { _ in lastLook = .zero })
            }

            BO2Crosshair()

            VStack {
                topHUD
                Spacer()
                if let message = coordinator.objectiveMessages.last {
                    Text(message)
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                controls
            }
        }
        .foregroundStyle(.white)
        .onReceive(ticker) { _ in coordinator.step(seconds: 1.0 / 60.0) }
        .onDisappear {
            coordinator.setFireHeld(false)
            coordinator.movement.setAim(false)
            coordinator.movement.setMovement(forward: 0, right: 0)
        }
    }

    private var topHUD: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BO2 QUAKE").font(.caption.bold())
                Text(asset.id).font(.caption2.monospaced())
                gameModeHUD
            }
            .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(coordinator.weapon.definition.id).font(.caption2.bold())
                if coordinator.weapon.reloading { Text("RELOADING").font(.caption2.bold()) }
                Text("\(coordinator.weapon.magazine) / \(coordinator.weapon.reserve)")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
            }
            .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }

    @ViewBuilder private var gameModeHUD: some View {
        switch coordinator.gameMode {
        case .zombies(let director):
            Text("ROUND \(director.round)  •  \(director.points) PTS").font(.caption2.bold())
        case .multiplayer(let rules):
            if let team = rules.winningTeam {
                Text("WINNER \(team)").font(.caption2.bold())
            } else {
                Text("MULTIPLAYER").font(.caption2.bold())
            }
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom) {
            Text("MOVE")
                .font(.caption2.bold()).frame(width: 70, height: 70)
                .background(.ultraThinMaterial, in: Circle())
            Spacer()
            VStack(spacing: 9) {
                HStack(spacing: 9) {
                    holdButton("AIM") { coordinator.movement.setAim($0) }
                    holdButton("FIRE") { pressed in
                        coordinator.setFireHeld(pressed)
                        if pressed { coordinator.fire(direction: coordinator.aimDirection) }
                    }
                }
                HStack(spacing: 9) {
                    Button("RELOAD") { coordinator.beginReload() }.buttonStyle(BO2GameButtonStyle())
                    Button("JUMP") { coordinator.movement.requestJump() }.buttonStyle(BO2GameButtonStyle())
                }
            }
        }
        .padding()
    }

    private func holdButton(_ title: String, set: @escaping (Bool) -> Void) -> some View {
        Text(title).font(.caption.bold()).frame(width: 72, height: 48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in set(true) }.onEnded { _ in set(false) })
    }
}

private struct BO2Crosshair: View {
    var body: some View {
        ZStack {
            Rectangle().frame(width: 14, height: 1)
            Rectangle().frame(width: 1, height: 14)
        }
        .opacity(0.8)
        .allowsHitTesting(false)
    }
}

private struct BO2GameButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.bold()).frame(width: 72, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
