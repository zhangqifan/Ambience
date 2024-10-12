//
//  UserMusicItem.swift
//  animated artworks
//
//  Created by Shuhari on 2024/10/12.
//

import Foundation
import MusicKit

protocol UserMusicItemTransferable {
    func toUserMusicItem() -> UserMusicItem
}

struct UserMusicItem: MusicItem {
    var id: MusicItemID
    var artwork: Artwork?
    var itemName: String?
    var artistName: String?
    var url: URL?
}

extension UserMusicItem: Identifiable {}
extension UserMusicItem: Equatable {}
extension UserMusicItem: Hashable {}

// Mock Data
let mockMusicItems: [UserMusicItem] = [
    UserMusicItem(id: MusicItemID("1"), artwork: nil, itemName: "Bohemian Rhapsody", artistName: "Queen", url: URL(string: "https://music.apple.com/us/album/bohemian-rhapsody/1440806041?i=1440806768")),
    UserMusicItem(id: MusicItemID("2"), artwork: nil, itemName: "Stairway to Heaven", artistName: "Led Zeppelin", url: URL(string: "https://music.apple.com/us/album/stairway-to-heaven/580708279?i=580708305")),
    UserMusicItem(id: MusicItemID("3"), artwork: nil, itemName: "Imagine", artistName: "John Lennon", url: URL(string: "https://music.apple.com/us/album/imagine/1440764621?i=1440764623")),
    UserMusicItem(id: MusicItemID("4"), artwork: nil, itemName: "Smells Like Teen Spirit", artistName: "Nirvana", url: URL(string: "https://music.apple.com/us/album/smells-like-teen-spirit/1440783617?i=1440783621")),
    UserMusicItem(id: MusicItemID("5"), artwork: nil, itemName: "Billie Jean", artistName: "Michael Jackson", url: URL(string: "https://music.apple.com/us/album/billie-jean/269572838?i=269573364")),
    UserMusicItem(id: MusicItemID("6"), artwork: nil, itemName: "Like a Rolling Stone", artistName: "Bob Dylan", url: URL(string: "https://music.apple.com/us/album/like-a-rolling-stone/201281514?i=201281531")),
    UserMusicItem(id: MusicItemID("7"), artwork: nil, itemName: "I Want to Hold Your Hand", artistName: "The Beatles", url: URL(string: "https://music.apple.com/us/album/i-want-to-hold-your-hand/1441164670?i=1441164672")),
    UserMusicItem(id: MusicItemID("8"), artwork: nil, itemName: "Purple Rain", artistName: "Prince", url: URL(string: "https://music.apple.com/us/album/purple-rain/214145240?i=214145503")),
    UserMusicItem(id: MusicItemID("9"), artwork: nil, itemName: "What's Going On", artistName: "Marvin Gaye", url: URL(string: "https://music.apple.com/us/album/whats-going-on/1440781665?i=1440781696")),
    UserMusicItem(id: MusicItemID("10"), artwork: nil, itemName: "Respect", artistName: "Aretha Franklin", url: URL(string: "https://music.apple.com/us/album/respect/1440819301?i=1440819307")),
]

extension Album: UserMusicItemTransferable {
    func toUserMusicItem() -> UserMusicItem {
        UserMusicItem(id: self.id, artwork: self.artwork, itemName: self.title, artistName: self.artistName, url: self.url)
    }
}

extension Playlist: UserMusicItemTransferable {
    func toUserMusicItem() -> UserMusicItem {
        UserMusicItem(id: self.id, artwork: self.artwork, itemName: self.name, artistName: self.curatorName, url: self.url)
    }
}
