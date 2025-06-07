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

class HLSDownloader: NSObject, ObservableObject, AVAssetDownloadDelegate {
    @Published var localURL: URL?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var downloadSession: AVAssetDownloadURLSession!
    private var downloadTask: AVAssetDownloadTask?

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.ambience.hlsdownload")
        downloadSession = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }

    func downloadHLS(from remoteURL: URL) async{
        isLoading = true
        errorMessage = nil
        localURL = nil

        let asset = AVURLAsset(url: remoteURL)
        
        // 异步加载变体信息
        guard let variants = try? await asset.load(.variants) else {return}
                        
                // 筛选分辨率不超过 800x800 的变体
                let filteredVariants = variants.filter { variant in
                    guard let size = variant.videoAttributes?.presentationSize else {
                        return false
                    }
                    return size.width >= 800 && size.height >= 800
                }
                
                // 从符合条件的变体中选择码率最高的（质量最好的）
        let selectedVariant = filteredVariants.min { $0.averageBitRate! < $1.averageBitRate!}!// 备选：选择分辨率最小的
                
                var options: [String: Any] = [:]
        print("选择的变体 - 分辨率: \(selectedVariant.videoAttributes?.presentationSize), 码率: \(selectedVariant.peakBitRate ?? 0) bps")
                    options[AVAssetDownloadTaskMinimumRequiredMediaBitrateKey] = selectedVariant.peakBitRate
                self.downloadTask = self.downloadSession.makeAssetDownloadTask(
                    asset: asset, 
                    assetTitle: "Ambience", 
                    assetArtworkData: nil, 
                    options: options.isEmpty ? nil : options
                )
                self.downloadTask?.resume()
            
        
    }

    // 下载完成回调
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        DispatchQueue.main.async {
            self.localURL = location
            self.isLoading = false
        }
    }

    // 错误处理
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

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
    @StateObject private var hlsDownloader = HLSDownloader()
#if os(iOS)
    @State private var isSharePresented = false
#endif

    var body: some View {
        VStack {
            if hlsDownloader.isLoading {
                ProgressView()
            } else if let url = hlsDownloader.localURL {
                AmbienceArtworkPlayer(url: url)
                    #if os(macOS)
                    .ambienceArtworkContentMode(.resizeAspect)
                    #else
                    .ambienceArtworkContentMode(.scaleAspectFit)
                    #endif
                    .ambienceLooping(true)
                    .ambienceAutoPlay(true)
                    .rotation3DEffect(.degrees(30), axis: (1,0,0))
                    .aspectRatio(16 / 9, contentMode: .fit)
                // 分享按钮
                shareButton(for: url)
            } else if let error = hlsDownloader.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                Text("No ambience available.")
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: userMusicItemURL) { newValue in
            if let newValue {
                // 先获取远程 m3u8 地址
                Task {
                    do {
                        let remoteURL = try await AmbienceService.fetchAmbienceAsset(from: newValue, adjustRegion: false)
                        await hlsDownloader.downloadHLS(from: remoteURL)
                    } catch {
                        hlsDownloader.errorMessage = error.localizedDescription
                    }
                }
            } else {
                hlsDownloader.errorMessage = "Invalid music item URL."
                hlsDownloader.isLoading = false
                hlsDownloader.localURL = nil
            }
        }
    }

    @ViewBuilder
    private func shareButton(for url: URL) -> some View {
#if os(iOS)
        Button {
            isSharePresented = true
        } label: {
            Label("分享此文件", systemImage: "square.and.arrow.up")
        }
        .padding(.top, 8)
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(activityItems: [url])
        }
#elseif os(macOS)
        Button {
            showMacShare(url: url)
        } label: {
            Label("分享此文件", systemImage: "square.and.arrow.up")
        }
        .padding(.top, 8)
#endif
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
