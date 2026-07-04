import SwiftUI

/// Every Jellyseerr request, each cancelable — mirroring Jellyseerr's Requests
/// page. Requests only carry TMDB ids, so each row's artwork and title are
/// fetched and cached here.
struct RequestsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.detailPush) private var push

    @State private var items: [EnrichedRequest] = []
    @State private var loading = true
    @State private var loadError: String?

    struct EnrichedRequest: Identifiable {
        let request: SeerRequest
        let details: SeerDetails?
        var id: Int { request.id }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Requests")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 80)
                    .padding(.top, 120)

                if loading {
                    ProgressView().tint(Theme.accentB).scaleEffect(1.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 100)
                } else if let loadError, items.isEmpty {
                    message(loadError)
                } else if items.isEmpty {
                    message("You haven't requested anything yet.")
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(items) { item in
                            RequestRow(item: item,
                                       onOpen: { open(item) },
                                       onDelete: { delete(item) })
                        }
                    }
                    .padding(.horizontal, 80)
                    .focusSection()
                }
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .detailBackButton()
        .task { await load() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 100)
    }

    private func open(_ item: EnrichedRequest) {
        guard let details = item.details else { return }
        push(.seer(details.asResult(mediaType: item.request.mediaType)))
    }

    private func delete(_ item: EnrichedRequest) {
        guard let seer = appState.jellyseerr else { return }
        Task {
            try? await seer.deleteRequest(id: item.request.id)
            items.removeAll { $0.id == item.id }
        }
    }

    private func load() async {
        guard let seer = appState.jellyseerr else { loading = false; return }
        loadError = nil
        do {
            let requests = try await seer.requests(take: 40, sort: "modified")
            let details = await enrich(requests, seer: seer)
            items = requests.map { EnrichedRequest(request: $0, details: details[$0.id] ?? nil) }
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    /// Fetch each request's title/artwork concurrently, keyed by request id.
    private func enrich(_ requests: [SeerRequest], seer: JellyseerrClient) async -> [Int: SeerDetails?] {
        await withTaskGroup(of: (Int, SeerDetails?).self) { group in
            for request in requests {
                group.addTask {
                    guard let tmdbId = request.media.tmdbId else { return (request.id, nil) }
                    return (request.id, try? await seer.details(mediaType: request.mediaType, id: tmdbId))
                }
            }
            var map: [Int: SeerDetails?] = [:]
            for await (id, details) in group { map[id] = details }
            return map
        }
    }
}

// MARK: - Row

private struct RequestRow: View {
    let item: RequestsView.EnrichedRequest
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var details: SeerDetails? { item.details }
    private var title: String { details?.displayTitle ?? "Request #\(item.request.id)" }

    private var seasonsLabel: String? {
        guard item.request.mediaType == "tv", let count = item.request.seasons?.count, count > 0 else { return nil }
        return count == 1 ? "1 Season" : "\(count) Seasons"
    }

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onOpen) {
                ZStack(alignment: .leading) {
                    RemoteImage(url: details?.backdropURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 172)
                        .clipped()

                    LinearGradient(
                        colors: [.black.opacity(0.9), .black.opacity(0.55), .black.opacity(0.2)],
                        startPoint: .leading, endPoint: .trailing)

                    HStack(spacing: 20) {
                        RemoteImage(url: details?.posterURL)
                            .frame(width: 96, height: 144)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 7) {
                            if let year = details?.year {
                                Text(year)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Text(title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                if item.request.isPendingApproval {
                                    Badge(text: "Pending Approval",
                                          tint: Color(hex: 0xC77D1A).opacity(0.9))
                                } else {
                                    StatusBadge(status: item.request.mediaStatus)
                                }
                                if let seasonsLabel {
                                    Badge(text: seasonsLabel, tint: .white.opacity(0.15))
                                }
                            }
                            if let when = item.request.createdLabel {
                                Text("Requested \(when)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                }
                .frame(height: 172)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(RequestCardStyle())

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(DeleteButtonStyle())
        }
    }
}

// MARK: - Styles

private struct RequestCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CardBody(configuration: configuration) }

    private struct CardBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isFocused ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear),
                                      lineWidth: 4)
                }
                .shadow(color: isFocused ? .black.opacity(0.5) : .clear, radius: 18, y: 10)
                .scaleEffect(isFocused ? 1.012 : 1)
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}

private struct DeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { DeleteBody(configuration: configuration) }

    private struct DeleteBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 210)
                .padding(.vertical, 20)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isFocused ? Color(hex: 0xE0453E) : Color(hex: 0xB53229).opacity(0.85))
                }
                .scaleEffect(isFocused ? 1.06 : 1)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}
