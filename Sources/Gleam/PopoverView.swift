import SwiftUI
import AppKit

/// The popover UI — minimal, warm, focused.
struct PopoverView: View {

    @ObservedObject var pipeline: SmilePipeline
    let photoManager: PhotoManager
    let statsManager: StatsManager

    @State private var todayCount: Int = 0
    @State private var weekCount: Int = 0
    @State private var peakHour: Int? = nil
    @State private var recentPhotos: [PhotoManager.SmilePhoto] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statsSection
            Divider()
            recentGrid
            Divider()
            footer
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .task { await refreshStats() }
        // onChange(of:) two-argument form required for macOS 14+
        .onChange(of: pipeline.lastCaptureDate) { _, _ in
            Task { await refreshStats() }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gleam")
                    .font(.headline)
                Text(pipeline.isRunning ? "Watching for your smile…" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Smile intensity ring
            SmileRing(intensity: Double(pipeline.smileIntensity))
                .frame(width: 36, height: 36)
        }
        .padding(14)
    }

    private var statsSection: some View {
        HStack {
            StatTile(value: "\(todayCount)", label: "Today")
            Divider().frame(height: 30)
            StatTile(value: "\(weekCount)", label: "This Week")
            Divider().frame(height: 30)
            StatTile(value: peakHour.map { formatHour($0) } ?? "—", label: "Happiest Hour")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    private var recentGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent moments")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            if recentPhotos.isEmpty {
                Text("Your first smile is coming 😊")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recentPhotos.prefix(8)) { photo in
                            PhotoThumb(url: photo.url)
                                .onTapGesture { NSWorkspace.shared.open(photo.url) }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            Button(pipeline.isRunning ? "Pause" : "Resume") {
                pipeline.isRunning ? pipeline.stop() : pipeline.start()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("Open Library") {
                NSWorkspace.shared.open(URL.gleamPhotosDirectory)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func refreshStats() async {
        todayCount = await statsManager.todayCount()
        weekCount  = await statsManager.weeklyCount()
        peakHour   = await statsManager.peakHourThisWeek()
        recentPhotos = await photoManager.todayPhotos()
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }
}

// MARK: - Subcomponents

struct SmileRing: View {
    var intensity: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: intensity)
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: intensity)
            Image(systemName: "face.smiling")
                .font(.caption)
                .foregroundStyle(intensity > 0.3 ? .yellow : .secondary)
        }
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.monospacedDigit().bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PhotoThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task { image = NSImage(contentsOf: url) }
    }
}
