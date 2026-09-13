import SwiftUI

struct HijackedTouchGameplayView: View {
    let session: BO2MapRuntimeSession

    @State private var move = CGSize.zero
    @State private var look = CGSize.zero
    @State private var firing = false
    @State private var aiming = false
    @State private var jumpPulse = 0
    @State private var reloadPulse = 0

    var body: some View {
        GeometryReader { _ in
            ZStack {
                QuakeGameplayView(
                    move: move,
                    look: look,
                    firing: firing,
                    aiming: aiming,
                    jumpPulse: jumpPulse,
                    reloadPulse: reloadPulse,
                    package: session.package
                )
                .ignoresSafeArea()

                hud.allowsHitTesting(false)

                HStack(spacing: 0) {
                    controlZone(isMove: true)
                    controlZone(isMove: false)
                }

                controls
            }
        }
        .navigationTitle("Hijacked")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var hud: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HIJACKED")
                        .font(.caption.bold().monospaced())
                    Text("QUAKE III NATIVE • \(session.package.triangleCount) TRIANGLES")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(.white)
                Spacer()
            }
            .padding()
            Spacer()
            Text("+")
                .font(.system(size: 34, weight: .light, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                stick(position: move, label: "MOVE")
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        actionButton("JUMP") { jumpPulse &+= 1 }
                        actionButton("RELOAD") { reloadPulse &+= 1 }
                    }
                    HStack(spacing: 8) {
                        Button {
                            aiming.toggle()
                        } label: {
                            Text("AIM")
                                .font(.caption.bold())
                                .frame(width: 72, height: 52)
                                .background(aiming ? .white.opacity(0.38) : .black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .foregroundStyle(.white)

                        Text("FIRE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 64)
                            .background(firing ? .red.opacity(0.65) : .black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18))
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in firing = true }
                                    .onEnded { _ in firing = false }
                            )
                    }
                }
                stick(position: look, label: "LOOK")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func controlZone(isMove: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let limited = CGSize(
                            width: max(-70, min(70, value.translation.width)),
                            height: max(-70, min(70, value.translation.height))
                        )
                        if isMove { move = limited } else { look = limited }
                    }
                    .onEnded { _ in
                        if isMove { move = .zero } else { look = .zero }
                    }
            )
    }

    private func stick(position: CGSize, label: String) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.28)).frame(width: 112, height: 112)
            Circle().stroke(.white.opacity(0.3), lineWidth: 1).frame(width: 112, height: 112)
            Circle().fill(.white.opacity(0.35)).frame(width: 48, height: 48).offset(position)
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.7))
                .offset(y: 72)
        }
        .frame(width: 130, height: 145)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 72, height: 52)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.35)))
        }
    }
}
