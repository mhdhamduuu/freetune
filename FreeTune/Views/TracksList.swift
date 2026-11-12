import SwiftUI

/// Shared track list with loading skeletons, empty state, error retry and
/// infinite scroll pagination.
struct TracksList: View {
    @ObservedObject var viewModel: TracksViewModel
    var showsOnboardingGate: Bool = true

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if viewModel.needsJamendoKey && settings.effectiveClientID.isEmpty && showsOnboardingGate {
            OnboardingCard()
        } else if viewModel.isLoading && viewModel.tracks.isEmpty {
            VStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    TrackRowSkeleton()
                }
            }
        } else if viewModel.tracks.isEmpty && viewModel.errorMessage == nil {
            VStack(spacing: 10) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No tracks found")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    viewModel.reload()
                } label: {
                    Text("Try Again").bold()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 4) {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, queue: viewModel.tracks, index: index)
                        .onAppear { viewModel.loadMoreIfNeeded(current: track) }
                }
            }
        }
    }
}

struct TrackRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 12)
                    .opacity(0.8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 120, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
