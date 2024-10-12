//
//  Utilities.swift
//  animated artworks
//
//  Created by Shuhari on 2024/10/12.
//

import Foundation
import MusicKit

class MusicService: ObservableObject {
    @Published var isRetrievingRecommendations: Bool = false
    @Published var recommendation: [UserMusicItem] = []
    
    init() {
        Task { @MainActor in
            if MusicAuthorization.currentStatus != .authorized {
                let status = await MusicAuthorization.request()
                guard status == .authorized else { return }
            }
            
            do {
                self.isRetrievingRecommendations = true
                let recommendations = try await retrievePersonalRecommendations()
                self.recommendation = recommendations
                self.isRetrievingRecommendations = false
            } catch {
                print("Error retrieving recommendations: \(error)")
                self.isRetrievingRecommendations = false
            }
        }
    }
    
    private func retrievePersonalRecommendations() async throws -> [UserMusicItem] {
        let request = MusicPersonalRecommendationsRequest()
        let collections = try await request.response().recommendations
        
        var items: [UserMusicItem] = []
        
        collections.forEach { recommendation in
            items.append(contentsOf: recommendation.albums.map { $0.toUserMusicItem() })
            items.append(contentsOf: recommendation.playlists.map { $0.toUserMusicItem() })
        }
        
        return items
    }
}
