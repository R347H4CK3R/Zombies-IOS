import SwiftUI

struct TranzitTouchGameplayView: View {
    let loadedArea: TranzitLoadedArea
    let rootURL: URL
    let sharedContainers: [TranzitLoadedResource]
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
    @State private var runtimeStatus = "Opening Tranzit stream…"
    @State private var streamOffset: UInt64 = 0
    @State private var streamProgress: Double = 0
    @State private var anchorSamples = 0
    @State private var runtimeError: String?
    @State private var streaming = false
    @State private var structureReport: FastFileStructureReport?
    @State private var decodedPayloadReport: T6DecodedPayloadReport?
    @State private var assetProbeReport: T6ZoneAssetProbeReport?
    @State private var runtimeMesh: T6RuntimeMesh?
    @State private var decodedSourceName = ""
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
                    mapSeed: sceneSeed,
                    runtimeMesh: runtimeMesh
                )
                .id(sceneSeed)
                .ignoresSafeArea()

                hud
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    controlZone(isMove: true)
                    controlZone(isMove: false)
                }

                controls
            }
        }
        .navigationTitle("Tranzit")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await validateStream() }
    }

    private var hud: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRANZIT")
                        .font(.headline.monospaced())
                        .foregroundStyle(.white)
                    Text("SPAWN \(area.displayName.uppercased())")
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(.white.opacity(0.72))
                    Text("HP \(health)")
                        .font(.title3.bold().monospaced())
                        .foregroundStyle(health > 35 ? .white : .red)
                    Text("KILLS \(kills)")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer(minLength: 90)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(ammo) / 30")
                        .font(.title2.bold().monospaced())
                        .foregroundStyle(ammo > 5 ? .white : .orange)
                    Text(runtimeStatus)
                        .font(.caption2.bold())
                        .foregroundStyle(runtimeError == nil ? .white.opacity(0.8) : .red)
                    if !decodedSourceName.isEmpty {
                        Text(decodedSourceName)
                            .lineLimit(1)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .padding(.trailing, 92)
            }
            .padding(.leading)
            .padding(.top, 6)
            .background(.black.opacity(0.28))

            runtimeBanner

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
    }

    @ViewBuilder
    private var runtimeBanner: some View {
        if let report = decodedPayloadReport {
            HStack(spacing: 9) {
                Text("T6 PS3")
                Text("XCHUNKS \(report.decodedChunkCount)")
                Text("DECODED \(ByteCountFormatter.string(fromByteCount: Int64(report.decodedBytes), countStyle: .file))")
                if let assets = assetProbeReport {
                    if assets.topLevelParsed {
                        Text("XASSETS \(assets.topLevelAssetCount)")
                        Text("XMODELS \(assets.xModelAssetCount)")
                    } else {
                        Text("ASSETS \(assets.candidateAssetCount)")
                        Text("MODELS \(assets.modelLikeCount)")
                    }
                }
                if let mesh = runtimeMesh {
                    Text("WORLD \(mesh.vertices.count)V/\(mesh.triangleCount)T")
                    Text(mesh.byteOrder)
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
    }

    private var controls: some View {
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
        var lastProgress = streamProgress

        do {
            for _ in 0..<8 {
                let chunk = try await reader.read(offset: offset, length: 64 * 1024)
                lastProgress = chunk.progress
                offset = chunk.nextOffset
                if offset >= chunk.fileSize { break }
            }
            streamOffset = offset >= fileSize ? 0 : offset
            streamProgress = lastProgress
            runtimeStatus = "BO2 STREAM READY"
            runtimeError = nil
        } catch {
            runtimeStatus = "BO2 STREAM ERROR"
            runtimeError = "BO2 prefetch failed: \(error.localizedDescription)"
        }
        streaming = false
    }

    private func decodeT6Payload() async {
        let decoder = T6PS3PayloadDecoder()
        let candidates = decodeCandidates()
        var best: (
            resource: TranzitLoadedResource,
            report: T6DecodedPayloadReport,
            assets: T6ZoneAssetProbeReport,
            mesh: T6RuntimeMesh?
        )?
        var lastError: Error?

        for resource in candidates.prefix(8) {
            do {
                runtimeStatus = "T6 DEEP DECODING \(resource.fileName)"
                await Task.yield()

                let isMainTranzit = resource.fileName.lowercased() == "zm_transit.ff"
                let decodeBudget = isMainTranzit ? 128 * 1024 * 1024 : 48 * 1024 * 1024
                let report = try await decoder.decodePrefix(
                    rootURL: rootURL,
                    resource: resource,
                    maxDecodedBytes: decodeBudget,
                    maxChunks: isMainTranzit ? 4096 : 2048
                )

                runtimeStatus = isMainTranzit ? "TRANZIT GFXWORLD DECODE" : "T6 GFXWORLD DECODE"
                await Task.yield()

                let payload = report.payloadPrefix
                let analysis = await Task.detached(priority: .userInitiated) {
                    let assets = T6ZoneAssetProbe.analyze(payload)
                    let packedMesh = T6GfxSurfaceMeshExtractor.extract(from: payload, scanLimit: payload.count)
                    let mesh = packedMesh ?? T6GfxBoundsFallbackExtractor.extract(from: payload, scanLimit: payload.count)
                    return (assets, mesh)
                }.value

                let assets = analysis.0
                let mesh = analysis.1

                if best == nil || decodeScore(
                    resource: resource,
                    report: report,
                    assets: assets,
                    mesh: mesh
                ) > decodeScore(
                    resource: best!.resource,
                    report: best!.report,
                    assets: best!.assets,
                    mesh: best!.mesh
                ) {
                    best = (resource, report, assets, mesh)
                }

                if isMainTranzit, let mesh, mesh.triangleCount >= 90 {
                    break
                }
            } catch {
                lastError = error
            }
        }

        guard let best else {
            runtimeStatus = "T6 DECODE FAILED"
            runtimeError = "No T6 PS3 Tranzit container decoded successfully: \(lastError?.localizedDescription ?? "unknown decode failure")"
            return
        }

        decodedPayloadReport = best.report
        assetProbeReport = best.assets
        runtimeMesh = best.mesh
        decodedSourceName = best.resource.fileName
        decodedSeed = best.report.payloadPrefix.prefix(256).reduce(0x146) { partial, byte in
            ((partial &* 16777619) ^ Int(byte)) & 0x7fffffff
        } ^ (best.mesh?.vertexOffset ?? 0) ^ (best.mesh?.indexOffset ?? 0)

        if let mesh = best.mesh {
            let isFullMap = best.resource.fileName.lowercased() == "zm_transit.ff"
            let isBoundsRecovery = mesh.byteOrder.contains("BOUNDS")
            if isFullMap {
                runtimeStatus = isBoundsRecovery
                    ? "TRANZIT WORLD RECOVERED \(mesh.triangleCount) TRIANGLES"
                    : "TRANZIT WORLD \(mesh.triangleCount) TRIANGLES"
            } else {
                runtimeStatus = isBoundsRecovery
                    ? "T6 AREA WORLD RECOVERED \(mesh.triangleCount) TRIANGLES"
                    : "T6 AREA GEOMETRY \(mesh.triangleCount) TRIANGLES"
            }
            runtimeError = nil
        } else if best.assets.topLevelParsed || best.report.isUsable {
            runtimeStatus = "T6 WORLD DATA READY"
            runtimeError = nil
        } else {
            runtimeStatus = best.report.status
            runtimeError = best.report.firstError
        }
    }

    private func decodeCandidates() -> [TranzitLoadedResource] {
        let ff = sharedContainers.filter { $0.fileName.lowercased().hasSuffix(".ff") }
        let preferred = ff.sorted { lhs, rhs in
            let lp = decodePriority(lhs.fileName)
            let rp = decodePriority(rhs.fileName)
            if lp != rp { return lp < rp }
            return lhs.byteCount > rhs.byteCount
        }

        var ordered: [TranzitLoadedResource] = []
        if let main = preferred.first(where: { $0.fileName.lowercased() == "zm_transit.ff" }) {
            ordered.append(main)
        }
        ordered.append(loadedArea.fastFile)
        ordered.append(contentsOf: preferred)

        var seen = Set<String>()
        return ordered.filter { seen.insert($0.relativePath.lowercased()).inserted }
    }

    private func decodePriority(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower == "zm_transit.ff" { return 0 }
        if lower == "common_zm.ff" { return 1 }
        if lower.contains("zm_transit") { return 2 }
        if lower.contains("common") && lower.contains("zm") { return 3 }
        return 4
    }

    private func decodeScore(
        resource: TranzitLoadedResource,
        report: T6DecodedPayloadReport,
        assets: T6ZoneAssetProbeReport,
        mesh: T6RuntimeMesh?
    ) -> Int {
        var score = 0
        if resource.fileName.lowercased() == "zm_transit.ff", mesh != nil { score += 50_000 }
        if report.isUsable { score += 100 }
        score += min(500, report.decodedChunkCount)
        score += assets.topLevelParsed ? 2_000 : 0
        score += min(5_000, assets.topLevelAssetCount / 10)
        score += min(2_000, assets.xModelAssetCount * 10)
        score += min(500, assets.candidateAssetCount)
        if let mesh {
            score += 20_000
            score += min(10_000, mesh.triangleCount * 2)
            score += min(5_000, mesh.vertices.count)
        }
        return score
    }

    private func controlZone(isMove: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        let limited = CGSize(
                            width: max(-70, min(70, dx)),
                            height: max(-70, min(70, dy))
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

    private func actionButton(
        _ title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 72, height: 52)
                .background(
                    active ? .white.opacity(0.38) : .black.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.35)))
        }
    }
}