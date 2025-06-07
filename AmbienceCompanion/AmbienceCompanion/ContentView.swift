//
//  ContentView.swift
//  animated artworks
//
//  Created by Shuhari on 2024/10/12.
//

import Ambience
import MusicKit
import SwiftUI
import AVFoundation

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
    
    @State private var localAmbienceURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shareableURL: URL?
#if os(iOS)
    @State private var isSharePresented = false
#endif

    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
            } else if let url = localAmbienceURL {
                AmbienceArtworkPlayer(url: url)
                    #if os(macOS)
                    .ambienceArtworkContentMode(.resizeAspect)
                    #else
                    .ambienceArtworkContentMode(.scaleAspectFit)
                    #endif
                    .ambienceLooping(true)
                    .ambienceAutoPlay(true)
                    .aspectRatio(16 / 9, contentMode: .fit)
                // 分享按钮
                shareButton(for: url)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                Text("No ambience available.")
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: userMusicItemURL) { newValue in
            Task {
                await loadAmbience(for: newValue)
            }
        }
        .onAppear {
             Task {
                await loadAmbience(for: userMusicItemURL)
            }
        }
    }
    
    private func loadAmbience(for url: URL?) async {
        guard let url = url else {
            // Reset view to initial state if URL is nil
            localAmbienceURL = nil
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        localAmbienceURL = nil

        do {
            let remoteURL = try await AmbienceService.fetchAmbienceAsset(from: url, adjustRegion: false)
            localAmbienceURL = remoteURL
        } catch {
            errorMessage = "Failed to load ambience: \(error.localizedDescription)"
        }
        isLoading = false
    }

    @ViewBuilder
    private func shareButton(for url: URL) -> some View {
        Button {
            Task {
                // HLS assets are directories, so we zip it for sharing
                shareableURL = await zipDirectory(at: url)
                #if os(iOS)
                if shareableURL != nil {
                    isSharePresented = true
                }
                #elseif os(macOS)
                if let shareableURL = shareableURL {
                    showMacShare(url: shareableURL)
                }
                #endif
            }
        } label: {
            Label("分享此文件", systemImage: "square.and.arrow.up")
        }
        .padding(.top, 8)
        #if os(iOS)
        .sheet(isPresented: $isSharePresented) {
            if let shareableURL = shareableURL {
                ShareSheet(activityItems: [shareableURL])
            }
        }
        #endif
    }
    
    private func zipDirectory(at directoryURL: URL) async -> URL? {
        // Zipping can be slow, so run it in a background thread.
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let zipURL = fileManager.temporaryDirectory.appendingPathComponent(directoryURL.lastPathComponent).appendingPathExtension("zip")
            try? fileManager.removeItem(at: zipURL)
            
            do {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                     return nil // Not a directory, cannot zip
                }
                
                let coordinator = NSFileCoordinator()
                var error: NSError?
                var zipResultURL: URL?

                coordinator.coordinate(readingItemAt: directoryURL, options: [.forUploading], error: &error) { (zippedURL) in
                    do {
                        try fileManager.moveItem(at: zippedURL, to: zipURL)
                        zipResultURL = zipURL
                    } catch {
                        print("Failed to move zipped file: \(error)")
                    }
                }
                
                if let error = error {
                    print("Failed to zip directory: \(error)")
                    return nil
                }
                return zipResultURL
                
            } catch {
                print("Zipping failed with error: \(error)")
                return nil
            }
        }.value
    }

#if os(macOS)
    private func showMacShare(url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
#endif
}

// iOS 分享 Sheet 封装
#if os(iOS)
import UIKit
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    ContentView()
}
