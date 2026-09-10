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
    @State private var runtimeStatus = "Opening BO2 stream…"
    @State private var streamedBytes: UInt64 = 0
    @State private var streamOffset: UInt64 = 0
    @State private var streamProgress: Double = 0
    @State private var anchorSamples = 0
    @State private var runtimeError: String?
    @State private var streaming = false
    @State private var structureReport: FastFileStructureReport?
    @State private var prefetchedBytes: UInt64 = 0

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

                    ProgressView(value: streamProgress)
                        .padding(.horizontal)
                        .tint(.white)

                    HStack(spacing: 12) {
                        Text("READ \(ByteCountFormatter.string(fromByteCount: Int64(streamedBytes), countStyle: .file))")
                        Text("PREFETCH \(ByteCountFormatter.string(fromByteCount: Int64(prefetchedBytes), countStyle: .file))")
                        Text("ANCHORS \(anchorSamples)/3")
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.55))

                    if let report = structureReport {
                        VStack(spacing: 2) {
                            HStack(spacing: 10) {
                                Text(report.summary)
                                Text("UNIQUE \(report.uniqueByteCount)")
                                Text(String(format: "NONZERO %.0f%%", report.nonZeroRatio * 100))
                                Text(String(format: "ASCII %.0f%%", report.printableRatio * 100))
                            }
                            Text("SIG \(report.signatureHex)")
                                .lineLimit(1)
                            if !report.asciiTokens.isEmpty {
                                Text(report.asciiTokens.prefix(3).joined(separator: " • "))
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal)
                    }

                    HStack(spacing: 12) {
                        Text("SHARED \(sharedContainerCount)")
                        Text("AUDIO \(audioBankCount)")
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.5))

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
                                actionButton(streaming ? "READ…" : "STREAM", active: streaming) { streamNextChunk() }
                                actionButton("PREFETCH", active: streaming) { prefetchBurst() }
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
        .task { await validateStream() }
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
            streamNextChunk()
        } catch {
            streaming = false
            runtimeStatus = "STREAM OFFLINE"
            runtimeError = "Runtime could not sample \(loadedArea.fastFile.fileName): \(error.localizedDescription)"
        }
    }

    private func streamNextChunk() {
        guard !streaming else { return }
        streaming = true
        runtimeError = nil

        Task {
            let reader = FastFileStreamReader(rootURL: rootURL, resource: loadedArea.fastFile)
            do {
                let fileSize = UInt64(max(0, loadedArea.fastFile.byteCount))
                let offset = streamOffset < fileSize ? streamOffset : 0
                let chunk = try await reader.read(offset: offset)
                await MainActor.run {
                    streamedBytes += UInt64(chunk.data.count)
                    streamOffset = chunk.nextOffset >= chunk.fileSize ? 0 : chunk.nextOffset
                    streamProgress = chunk.progress
                    runtimeStatus = "STREAMING BO2 DATA"
                    runtimeError = nil
                    streaming = false
                }
            } catch {
                await MainActor.run {
                    runtimeStatus = "STREAM ERROR"
                    runtimeError = "Incremental read failed: \(error.localizedDescription)"
                    streaming = false
                }
            }
        }
    }

    private func prefetchBurst() {
        guard !streaming else { return }
        streaming = true
        runtimeError = nil

        Task {
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

                await MainActor.run {
                    streamedBytes += total
                    prefetchedBytes += total
                    streamOffset = offset >= fileSize ? 0 : offset
                    streamProgress = lastProgress
                    runtimeStatus = "PREFETCH READY"
                    runtimeError = nil
                    streaming = false
                }
            } catch {
                await MainActor.run {
                    runtimeStatus = "PREFETCH ERROR"
                    runtimeError = "Bounded prefetch failed: \(error.localizedDescription)"
                    streaming = false
                }
            }
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
                .frame(width: 72, height: 52)
                .background(active ? .white.opacity(0.35) : .white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3)))
        }
    }
}
