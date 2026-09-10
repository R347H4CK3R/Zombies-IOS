import SwiftUI

struct TranzitTouchGameplayView: View {
    let area: TranzitArea
    @State private var move = CGSize.zero
    @State private var look = CGSize.zero
    @State private var firing = false
    @State private var aiming = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.black, .gray.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        Text(area.displayName.uppercased())
                            .font(.headline.monospaced()).foregroundStyle(.white)
                        Spacer()
                        Text("FIRST PLAYABLE")
                            .font(.caption.bold()).foregroundStyle(.white.opacity(0.75))
                    }.padding()
                    Spacer()
                    Text("+").font(.system(size: 34, weight: .light, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }

                HStack(spacing: 0) {
                    controlZone(size: geo.size, isMove: true)
                    controlZone(size: geo.size, isMove: false)
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        stick(position: move, label: "MOVE")
                        Spacer()
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                actionButton("ADS", active: aiming) { aiming.toggle() }
                                actionButton("FIRE", active: firing) { firing.toggle() }
                            }
                            HStack(spacing: 14) {
                                actionButton("USE", active: false) { }
                                actionButton("JUMP", active: false) { }
                            }
                        }
                        stick(position: look, label: "LOOK")
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Touch Gameplay")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func controlZone(size: CGSize, isMove: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let limited = CGSize(width: max(-70, min(70, dx)), height: max(-70, min(70, dy)))
                if isMove { move = limited } else { look = limited }
            }.onEnded { _ in
                if isMove { move = .zero } else { look = .zero }
            })
    }

    private func stick(position: CGSize, label: String) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.10)).frame(width: 112, height: 112)
            Circle().stroke(.white.opacity(0.28), lineWidth: 1).frame(width: 112, height: 112)
            Circle().fill(.white.opacity(0.35)).frame(width: 48, height: 48).offset(position)
            Text(label).font(.caption2.bold()).foregroundStyle(.white.opacity(0.65)).offset(y: 72)
        }.frame(width: 130, height: 145)
    }

    private func actionButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 66, height: 52)
                .background(active ? .white.opacity(0.35) : .white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3)))
        }
    }
}
