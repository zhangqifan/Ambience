//
//  ContentView.swift
//  animated artworks
//
//  Created by Shuhari on 2024/10/12.
//

import Ambience
import MusicKit
import SwiftUI

struct ContentView: View {
    @StateObject private var musicService = MusicService()
    @State private var term: String = ""
    @State private var selectedUserMusicItemURL: URL?

    var body: some View {
        NavigationStack {
            List {
                hintSectionView
                recommendationItemsSectionView
                ambiencePreviewSectionView
            }
            .navigationTitle("Ambience Companion")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $term, placement: .navigationBarDrawer, prompt: Text("Your Music Item Link"))
            #else
            .searchable(text: $term, prompt: Text("Your Music Item Link"))
            #endif
            .onSubmit(of: .search) {
                if let url = URL(string: term) {
                    selectedUserMusicItemURL = url
                }
            }
        }
    }

    private var hintSectionView: some View {
        Section {
            HintView()
        }
#if os(macOS)
        .listRowBackground(Color(nsColor: .quaternarySystemFill))
#else
        .listRowBackground(Color(uiColor: .quaternarySystemFill))
#endif
    }

    private var recommendationItemsSectionView: some View {
        Section {
            if musicService.isRetrievingRecommendations {
                ProgressView()
            } else {
                RecommendationView(musicItems: musicService.recommendation) { selectedUserMusicItem in
                    self.selectedUserMusicItemURL = selectedUserMusicItem.url
                }
            }
        } header: {
            Text("Personal Recommendations")
        }
    }

    private var ambiencePreviewSectionView: some View {
        Section {
            AmbiencePreviewView(userMusicItemURL: selectedUserMusicItemURL)
        } header: {
            Text("Ambience Preview")
        }
    }
}

struct HintView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "music.quarternote.3")
                .font(.headline)

            Text("Share links from ")
                + Text("[Apple Music app](music://)")
                .underline()
                + Text(" ")
                + Text(Image(systemName: "arrow.up.right"))
                .font(.footnote)
                + Text(" or find music on the ")
                + Text("[Apple Music Web Player](https://music.apple.com/)")
                .underline()
                + Text(" ")
                + Text(Image(systemName: "arrow.up.right"))
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
    }
}

struct RecommendationView: View {
    let musicItems: [UserMusicItem]
    let onItemSelected: (UserMusicItem) -> Void

    private let spacing: CGFloat = 10
    private let itemSizeSide: CGFloat = 64

    @State private var selectedUserMusicItem: UserMusicItem?

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3), spacing: spacing) {
                    ForEach(musicItems, id: \.self) { musicItem in
                        itemView(with: musicItem)
                            .id(musicItem)
                            .frame(width: proxy.size.width * 0.8)
                            .onTapGesture {
                                if selectedUserMusicItem != musicItem {
                                    selectedUserMusicItem = musicItem
                                    onItemSelected(musicItem)
                                    #if os(iOS)
                                    let impact = UIImpactFeedbackGenerator(style: .soft)
                                    impact.impactOccurred()
                                    #endif
                                }
                            }
                    }
                }
            }
        }
        .frame(height: itemSizeSide * 3 + 2 * spacing)
    }

    @ViewBuilder
    private func itemView(with item: UserMusicItem) -> some View {
        HStack {
            AsyncImage(url: item.artwork?.url(width: 300, height: 300)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                case .failure:
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.gray)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: itemSizeSide, height: itemSizeSide)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    #if os(macOS)
                    .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 0.5)
                    #else
                    .stroke(Color(uiColor: .quaternarySystemFill), lineWidth: 0.5)
                    #endif
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.itemName ?? "<Unknown>")
                    .lineLimit(2)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(item.artistName ?? "<Unknown>")
                    .lineLimit(1)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AmbiencePreviewView: View {
    let userMusicItemURL: URL?
    @State private var ambienceURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else if let url = ambienceURL {
                AmbienceArtworkPlayer(url: url)
                    #if os(macOS)
                    .ambienceArtworkContentMode(.resizeAspect)
                    #else
                    .ambienceArtworkContentMode(.scaleAspectFit)
                    #endif
                    .ambienceLooping(true)
                    .ambienceAutoPlay(true)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                Text("No ambience available.")
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: userMusicItemURL) { newValue in
            if let newValue {
                loadAmbienceURL(for: newValue)
            } else {
                errorMessage = "Invalid music item URL."
                isLoading = false
                ambienceURL = nil
            }
        }
    }

    private func loadAmbienceURL(for url: URL) {
        isLoading = true
        errorMessage = nil
        ambienceURL = nil

        Task {
            do {
                let configURL = try await AmbienceService.fetchAmbienceAsset(from: url)

                await MainActor.run {
                    ambienceURL = configURL
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load ambience: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
