// SPDX-FileCopyrightText: 2026 Alzimer Ahmed
//
// SPDX-License-Identifier: GPL-3.0

import AppIntentsLibrary
import AppLibraryTV
import CommonLibrary
import Foundation
import TVServices
import UIKit

/// Top Shelf extension principal class (see `TopShelf.plist`:
/// `NSExtensionPrincipalClass`, point identifier `com.apple.tv-top-shelf`).
///
/// Reads the profile list through the same `QuickConnectContext` plumbing
/// the Intents extension uses (keychain-backed profiles) and the shared
/// tunnel state from the App Group, then delegates row layout/ordering to
/// the unit-tested `TopShelfContentBuilder`. Selecting an item opens the
/// app via the `ghosttunnel://connect/<uuid>` deep link.
///
/// Looked up via `NSExtensionPrincipalClass` as
/// `$(PRODUCT_MODULE_NAME).TopShelfProvider` (no `@objc` rename, so the
/// module-qualified Swift name resolves).
final class TopShelfProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            completionHandler(await content())
        }
    }

    // MARK: Helpers

    private func content() async -> TVTopShelfContent? {
        do {
            let ctx = try QuickConnectContext()
            try await ctx.profileManager.observeLocal()
            let profiles = await ctx.profileManager.allProfiles()
            let headers = profiles.map {
                $0.abiHeaderWithBogusFlagsAndRequirements()
            }
            let state = TunnelWidgetStatusStore(
                defaults: ctx.appConfiguration.makeTunnelDefaults()
            ).load()
            let models = TopShelfContentBuilder.items(
                headers: headers,
                lastUsedProfileId: ctx.preferences[\.lastUsedProfileId],
                tunnelState: state
            )
            guard !models.isEmpty else {
                return nil
            }
            return sectionedContent(from: models)
        } catch {
            pspLog(.core, .error, "Top Shelf: unable to load profiles: \(error)")
            return nil
        }
    }

    private func sectionedContent(from models: [TopShelfItemModel]) -> TVTopShelfSectionedContent {
        let collection = TVTopShelfItemCollection(items: models.map(item(from:)))
        collection.title = AppLibraryTVLocalization.string(
            "views.tv.topshelf.section.profiles",
            fallback: "Profiles"
        )
        return TVTopShelfSectionedContent(sections: [collection])
    }

    private func item(from model: TopShelfItemModel) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: model.identifier)
        item.title = model.title
        item.imageShape = .hdtv
        if let url = model.url {
            item.displayAction = TVTopShelfAction(url: url)
        }
        if let imageURL = topShelfImageURL(named: "TopShelfImageWide") {
            item.setImageURL(imageURL, for: .screenScale1x)
            item.setImageURL(imageURL, for: .screenScale2x)
        }
        return item
    }

    /// Renders the bundled brand image to a temporary file URL (Top Shelf
    /// consumes image URLs, not asset names). Returns `nil` when the asset
    /// is missing — the system then shows its placeholder.
    private func topShelfImageURL(named assetName: String) -> URL? {
        guard let image = UIImage(named: assetName) else {
            pspLog(.core, .info, "Top Shelf: image asset not found: \(assetName)")
            return nil
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(assetName).png")
        do {
            try image.pngData()?.write(to: url)
        } catch {
            pspLog(.core, .error, "Top Shelf: unable to write image: \(error)")
            return nil
        }
        return url
    }
}
