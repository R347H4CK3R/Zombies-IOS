import SwiftUI

struct TranzitTouchGameplayView: View {
    let loadedArea: TranzitLoadedArea
    let rootURL: URL
    let sharedContainerCount: Int
    let audioBankCount: Int

    @State private var move = CGSize.zero
    @State private var look = CGSize.zero
    @State private var firing = false
    @State private var aiming = false
    @State private var runtimeStatus = "Checking BO2 stream…"
    @State private var probedBytes = 0
    @State private var runtimeError: String?

    private var area: TranzitArea { loadedArea.area }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.black, .gray.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(area.displayName.uppercased())
                                .font(.headline.monospaced()).foregroundStyle(.white)
                            Text(loadedArea.fastFile.fileName)
                                .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(runtimeStatus)
                                .font(.caption.bold()).foregroundStyle(runtimeError == nil ? .white : .red)
                            Text(ByteCountFormatter.string(fromByteCount: loadedArea.fastFile.byteCount, countStyle: .file))
                                .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.65))
                        }
                    }.padding(.horizontal).padding(.top, 8)

                    HStack(spacing: 12) {
                        Text("STREAM \(probedBytes) B")
                        Text("SHARED \(sharedContainerCount)")
                        Text("AUDIO \(audioBankCount)")
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.55))

                    if let runtimeError {
                        Text(runtimeError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

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
                                actionButton("USE", active: false) { probeRuntimeResource() }
                                actionButton("JUMP", active: false) { }
                            }
                        }
                        stick(position: look, label: "LOOK")
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Touch Runtime")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { probeRuntimeResource() }
    }

    private func probeRuntimeResource() {
        let fileURL = rootURL.appendingPathComponent(loadedArea.fastFile.relativePath)
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 4096) ?? Data()
            guard !data.isEmpty else {
                throw CocoaError(.fileReadUnknown)
            }
            probedBytes = data.count
            runtimeStatus = "BO2 STREAM ONLINE"
            runtimeError = nil
        } catch {
            probedBytes = 0
            runtimeStatus = "STREAM OFFLINE"
            runtimeError = "Runtime could not continue reading \(loadedArea.fastFile.fileName): \(error.localizedDescription)"
        }
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
