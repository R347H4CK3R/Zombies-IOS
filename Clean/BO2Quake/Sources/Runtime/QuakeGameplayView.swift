import SwiftUI
import Combine

struct QuakeGameplayView: View {
    let asset: WorldRuntimeAsset
    @ObservedObject var controller: QuakeRuntimeController
    @State private var lastLook = CGSize.zero
    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            MetalWorldView(
                asset: asset,
                playerPosition: controller.playerPosition,
                yaw: controller.yaw,
                pitch: controller.pitch
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            controller.setMovement(
                                forward: Float(max(-1, min(1, -value.translation.height / 70))),
                                right: Float(max(-1, min(1, value.translation.width / 70)))
                            )
                        }
                        .onEnded { _ in controller.setMovement(forward: 0, right: 0) })
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = value.translation.width - lastLook.width
                            let dy = value.translation.height - lastLook.height
                            lastLook = value.translation
                            controller.addLook(yaw: Float(dx) * 0.15, pitch: Float(-dy) * 0.12)
                        }
                        .onEnded { _ in lastLook = .zero })
            }

            Crosshair()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BO2 QUAKE").font(.caption.bold())
                        Text(asset.id).font(.caption2.monospaced())
                    }
                    .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        if controller.reloading { Text("RELOADING").font(.caption2.bold()) }
                        Text("\(controller.magazine) / \(controller.reserve)")
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    }
                    .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }.padding()
                Spacer()
                HStack(alignment: .bottom) {
                    Text("MOVE")
                        .font(.caption2.bold()).frame(width: 70, height: 70)
                        .background(.ultraThinMaterial, in: Circle())
                    Spacer()
                    VStack(spacing: 9) {
                        HStack(spacing: 9) {
                            holdButton("AIM") { controller.setAim($0) }
                            holdButton("FIRE") { controller.setFire($0) }
                        }
                        HStack(spacing: 9) {
                            Button("RELOAD") { controller.requestReload() }.buttonStyle(GameButtonStyle())
                            Button("JUMP") { controller.requestJump() }.buttonStyle(GameButtonStyle())
                        }
                    }
                }.padding()
            }
        }
        .foregroundStyle(.white)
        .onReceive(ticker) { _ in controller.step(seconds: 1.0 / 60.0) }
        .onDisappear { controller.setFire(false); controller.setAim(false); controller.setMovement(forward: 0, right: 0) }
    }

    private func holdButton(_ title: String, set: @escaping (Bool) -> Void) -> some View {
        Text(title).font(.caption.bold()).frame(width: 72, height: 48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in set(true) }.onEnded { _ in set(false) })
    }
}

private struct Crosshair: View {
    var body: some View {
        ZStack {
            Rectangle().frame(width: 14, height: 1)
            Rectangle().frame(width: 1, height: 14)
        }.opacity(0.8).allowsHitTesting(false)
    }
}

private struct GameButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.bold()).frame(width: 72, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
