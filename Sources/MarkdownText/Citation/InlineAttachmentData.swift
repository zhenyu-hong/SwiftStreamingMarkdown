//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AttachmentType: String, Codable {
  case citation
}

struct InlineAttachmentData: Codable {
  let type: AttachmentType
  let title: String
  let accessibilityLabel: String
  let url: URL
  /// The site's icon, drawn before the title when `CitationIconCache` holds it.
  var iconURL: URL? = nil
  /// Whether the chip keeps room for an icon, drawn or not, so the chip keeps its width when
  /// the icon arrives.
  var reservesIcon = false
}

/// Images for citation chips, keyed by icon URL. A chip is drawn once, as it is parsed, so the
/// host puts an icon here before it writes a citation that names it; a chip whose icon is not
/// here draws its title alone.
public final class CitationIconCache: @unchecked Sendable {
  public static let shared = CitationIconCache()
  // Every access holds the lock; the images are only read once stored.
  private let lock = NSLock()
  private var images: [URL: MDImage] = [:]

  public init() {}

  public func setImage(_ image: MDImage, for url: URL) {
    lock.lock(); defer { lock.unlock() }
    images[url] = image
  }

  public func image(for url: URL) -> MDImage? {
    lock.lock(); defer { lock.unlock() }
    return images[url]
  }
}
