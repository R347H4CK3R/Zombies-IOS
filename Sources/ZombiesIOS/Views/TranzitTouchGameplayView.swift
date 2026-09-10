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
    @State private var jumpPulse = 0
    @State private var reloadPulse = 0
    @State private var health = 100
    @State private var ammo = 30
    @State private var kills = 0
    @State private var runtimeStatus = "Opening BO2 stream…"
    @State private var streamedBytes: UInt64 = 0
    @State private var streamOffset: UInt64 = 0
    @State private var streamProgress: Double = 0
    @State private var anchorSamples = 0
    @State private var runtimeError: String?
    @State private var streaming = false
    @State private var structureReport: FastFileStructureReport?
    @State private var prefetchedBytes: UInt64 = 0
    @State private var decodedPayloadReport: T6DecodedPayloadReport?
    @State private var assetProbeReport: T6ZoneAssetProbeReport?
    @State private var decodedSeed = 0

    private var area: TranzitArea { loadedArea.area }

    private var sceneSeed: Int {
        let base = loadedArea.fastFile.header.reduce(0xB02) { partial, byte in
            ((partial &* 16777619) ^ Int(byte)) & 0x7fffffff
        }
        return (base ^ decodedSeed) & 0x7fffffff
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                NativeFPSSceneView(
                    move: move,
                    look: look,
                    firing: firing,
                    aiming: aiming,
                    jumpPulse: jumpPulse,
                    reloadPulse: reloadPulse,
                    health: $health,
                    ammo: $ammo,
                    kills: $kills,
                    mapSeed: sceneSeed
                )
                .id(sceneSeed)
                .ignoresSafeArea()

                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(area.displayName.uppercased())
                                .font(.headline.monospaced()).foregroundStyle(.white)
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
                            Text(runtimeStatus)
                                .font(.caption2.bold()).foregroundStyle(runtimeError == nil ? .white.opacity(0.8) : .red)
                            Text(ByteCountFormatter.string(fromByteCount: loadedArea.fastFile.byteCount, countStyle: .file))
                                .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.58))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .background(.black.opacity(0.28))

                    if let report = decodedPayloadReport {
                        HStack(spacing: 9) {
                            Text("T6 PS3")
                            Text("XCHUNKS \(report.decodedChunkCount)")
                            Text("DECODED \(ByteCountFormatter.string(fromByteCount: Int64(report.decodedBytes), countStyle: .file))")
                            if let assets = assetProbeReport {
                                Text("ASSETS \(assets.candidateAssetCount)")
                                Text("MODELS \(assets.modelLikeCount)")
                            }
                        }
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(.green.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.34), in: Capsule())
                    } else if let report = structureReport {
                        HStack(spacing: 9) {
                            Text(report.summary)
                            Text("BO2 STREAM \(Int(streamProgress * 100))%")
                            Text("A \(anchorSamples)/3")
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.26), in: Capsule())
                    }

                    if let runtimeError {
                        Text(runtimeError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    }

                    Spacer()

                    Text("+")
                        .font(.system(size: aiming ? 22 : 34, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.96))
                        .shadow(radius: 2)

                    Spacer()
                }
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    controlZone(isMove: true)
                    controlZone(isMove: false)
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        stick(position: move, label: "MOVE")
                        Spacer()
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                actionButton("ADS", active: aiming) { aiming.toggle() }
                                fireButton
                            }
                            HStack(spacing: 12) {
                                actionButton("RELOAD", active: false) { reloadPulse &+= 1 }
                                actionButton("JUMP", active: false) { jumpPulse &+= 1 }
                            }
                        }
                        stick(position: look, label: "LOOK")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
        .navigationTitle("Playable Runtime")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await validateStream() }
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

    private func validateStream() async {
        streaming = true
        runtimeError = nil
        let reader = FastFileStreamReader(rootURL: rootURL, resource: loadedArea.fastFile)
        do {
            let samples = try await reader.sampleAnchors()
            let analysis = FastFileRuntimeAnalyzer.analyze(chunks: samples)
            anchorSamples = samples.count
            structureReport = analysis
            streamedBytes = UInt64(samples.reduce(0) { $0 + $1.data.count })
            runtimeStatus = analysis.looksStructured ? "BO2 DATA READY" : "BO2 DATA READABLE"
            streaming = false
            await prefetchInitialBurst()
            await decodeT6Payload()
        } catch {
            streaming = false
            runtimeStatus = "STREAM OFFLINE"
            runtimeError = "Runtime could not sample \(loadedArea.fastFile.fileName): \(error.localizedDescription)"
        }
    }

    private func prefetchInitialBurst() async {
        guard !streaming else { return }
        streaming = true
        let reader = FastFileStreamReader(rootURL: rootURL, resource: loadedArea.fastFile)
        let fileSize = UInt64(max(0, loadedArea.fastFile.byteCount))
        var offset = streamOffset < fileSize ? streamOffset : 0
        var total: UInt64 = 0
        var lastProgress = streamProgress

        do {
            for _ in 0..<8 {
                let chunk = try await reader.read(offset: offset, length: 64 * 1024)
                total += UInt64(chunk.data.count)
                lastProgress = chunk.progress
                offset = chunk.nextOffset
                if offset >= chunk.fileSize { break }
            }
            streamedBytes += total
            prefetchedBytes += total
            streamOffset = offset >= fileSize ? 0 : offset
            streamProgress = lastProgress
            runtimeStatus = "PLAYABLE + BO2 STREAM"
            runtimeError = nil
            streaming = false
        } catch {
            runtimeStatus = "PLAYABLE / STREAM ERROR"
            runtimeError = "Gameplay is running, but BO2 prefetch failed: \(error.localizedDescription)"
            streaming = false
        }
    }

    private func decodeT6Payload() async {
        let decoder = T6PS3PayloadDecoder()
        do {
            let report = try await decoder.decodePrefix(
                rootURL: rootURL,
                resource: loadedArea.fastFile,
                maxDecodedBytes: 4 * 1024 * 1024,
                maxChunks: 256
            )
            decodedPayloadReport = report
            decodedSeed = report.payloadPrefix.prefix(256).reduce(0x146) { partial, byte in
                ((partial &* 16777619) ^ Int(byte)) & 0x7fffffff
            }

            let assets = T6ZoneAssetProbe.analyze(report.payloadPrefix)
            assetProbeReport = assets

            if report.isUsable {
                runtimeStatus = assets.candidateAssetCount > 0 ? "T6 ASSET INDEX READY" : "PLAYABLE + T6 DECODE"
                runtimeError = nil
            } else {
                runtimeStatus = report.status
                runtimeError = report.firstError
            }
        } catch {
            runtimeStatus = "PLAYABLE / T6 DECODE ERROR"
            runtimeError = "Native map is playable, but the T6 PS3 payload decoder failed: \(error.localizedDescription)"
        }
    }

    private func controlZone(isMove: Bool) -> some View {
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
            Circle().fill(.black.opacity(0.28)).frame(width: 112, height: 112)
            Circle().stroke(.white.opacity(0.3), lineWidth: 1).frame(width: 112, height: 112)
            Circle().fill(.white.opacity(0.35)).frame(width: 48, height: 48).offset(position)
            Text(label).font(.caption2.bold()).foregroundStyle(.white.opacity(0.7)).offset(y: 72)
        }.frame(width: 130, height: 145)
    }

    private func actionButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2.bold()).foregroundStyle(.white)
                .frame(width: 72, height: 52)
                .background(active ? .white.opacity(0.38) : .black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.35)))
        }
    }
}
