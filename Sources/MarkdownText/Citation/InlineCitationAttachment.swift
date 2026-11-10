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
import UniformTypeIdentifiers

final class InlineCitationAttachment: NSTextAttachment {
  /// The decoded citation data - available immediately without JSON parsing
  private(set) var citationData: InlineAttachmentData?

  /// Styling resolved from the active `CitationConfig`. Exposed so the live
  /// label provider can mirror the same look as the precomputed preview image.
  let font: MDFont
  let textColor: MDColor
  let backgroundColor: MDColor

  // MARK: - Precomputed preview images

  private var lightPreviewImage: MDImage?
  private var darkPreviewImage: MDImage?
  private var assignedImage: MDImage?

  // MARK: - Shared Layout

  static let textInsets = MDEdgeInsets(top: 3, left: 4, bottom: 3, right: 6)
  static let iconGap: CGFloat = 4
  /// Kept for AppKit; on UIKit the chip is a capsule, its radius half its height.
  static let cornerRadius: CGFloat = 6

  #if canImport(UIKit)
  override var image: UIImage? {
    get {
      if let assignedImage { return assignedImage }
      let app = AppAppearance.$current.read({ $0 })
      switch app {
      case .dark: return darkPreviewImage
      case .light: return lightPreviewImage
      }
    }
    set { assignedImage = newValue }
  }
  #elseif canImport(AppKit)
  override var image: NSImage? {
    get {
      if let assignedImage { return assignedImage }
      let app = AppAppearance.$current.read({ $0 })
      switch app {
      case .dark: return darkPreviewImage
      case .light: return lightPreviewImage
      }
    }
    set { assignedImage = newValue }
  }
  #endif

  /// Called during markdown parsing (background queue). Rasterizes both
  /// light/dark previews here so the getter never does work on the main thread.
  init(payload: Data, citationConfig: MarkdownRenderConfig.CitationConfig) {
    let decoded = try? JSONDecoder().decode(InlineAttachmentData.self, from: payload)
    let citationData = (decoded?.type == .citation) ? decoded : nil
    self.citationData = citationData

    self.font = citationConfig.font
    self.textColor = MDColor(citationConfig.textColor)
    self.backgroundColor = MDColor(citationConfig.backgroundColor)

    if let title = citationData?.title {
      let icon = citationData?.iconURL.flatMap { CitationIconCache.shared.image(for: $0) }
      let reservesIcon = citationData?.reservesIcon ?? false
      self.lightPreviewImage = Self.renderCitationImage(
        title: title, icon: icon, reservesIcon: reservesIcon, font: self.font,
        textColor: self.textColor, backgroundColor: self.backgroundColor,
        appearance: .light
      )
      self.darkPreviewImage = Self.renderCitationImage(
        title: title, icon: icon, reservesIcon: reservesIcon, font: self.font,
        textColor: self.textColor, backgroundColor: self.backgroundColor,
        appearance: .dark
      )
    } else {
      self.lightPreviewImage = nil
      self.darkPreviewImage = nil
    }

    super.init(data: payload, ofType: UTType.url.identifier)
  }

  /// The baseline offset that centres the chip on the cap height of `font`, the text it sits in.
  ///
  /// Offsetting by the font's descender put the chip's bottom on the descender line, so its
  /// centre sat about 2pt below that of the capitals and CJK glyphs beside it.
  func centeredBaselineOffset(in font: MDFont) -> CGFloat {
    let height = image?.size.height ?? 0
    guard height > 0 else { return font.descender }
    // A chip taller than the capitals is held to 2pt above them, hanging lower instead: reaching
    // higher made its line taller than the lines around it.
    let centred = ((font.capHeight - height) / 2).rounded()
    return min(centred, (font.capHeight + 2 - height).rounded())
  }

  /// Create citation attachment directly from data struct
  convenience init?(citationData: InlineAttachmentData, citationConfig: MarkdownRenderConfig.CitationConfig) {
    guard citationData.type == .citation,
          let payload = try? JSONEncoder().encode(citationData) else {
      return nil
    }
    self.init(payload: payload, citationConfig: citationConfig)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  // MARK: - Preview Image Rendering

  private static func renderCitationImage(
    title: String, icon: MDImage?, reservesIcon: Bool, font: MDFont,
    textColor: MDColor, backgroundColor: MDColor,
    appearance: AppAppearance
  ) -> MDImage {
    // Resolve colors for the target appearance
    #if canImport(UIKit)
    let traitCollection = UITraitCollection(userInterfaceStyle: appearance.platformType)
    let resolvedTextColor = textColor.resolvedColor(with: traitCollection)
    let resolvedBackgroundColor = backgroundColor.resolvedColor(with: traitCollection)
    #elseif canImport(AppKit)
    var resolvedTextColor = textColor
    var resolvedBackgroundColor = backgroundColor
    appearance.platformType?.performAsCurrentDrawingAppearance {
      resolvedTextColor = textColor.usingColorSpace(.sRGB) ?? textColor
      resolvedBackgroundColor = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
    }
    #endif

    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: resolvedTextColor]
    let textSize = (title as NSString).size(withAttributes: attributes)
    // An icon is as tall as the title's line, with a small gap before the title. Its room stays,
    // empty, while the icon is on its way, so the chip does not widen when it arrives.
    #if canImport(UIKit)
    // A touch taller than the title's capitals, centred with it.
    let iconSide: CGFloat = icon == nil && !reservesIcon ? 0 : (font.pointSize * 1.1).rounded()
    #else
    let iconSide: CGFloat = 0
    #endif
    let iconSpace = iconSide > 0 ? iconSide + iconGap : 0
    let contentHeight = max(ceil(textSize.height), iconSide)
    let totalSize = CGSize(
      width: iconSpace + ceil(textSize.width) + textInsets.left + textInsets.right,
      height: contentHeight + textInsets.top + textInsets.bottom
    )

    // Render the citation pill image
    #if canImport(UIKit)
    let renderer = UIGraphicsImageRenderer(size: totalSize)
    return renderer.image { _ in
      let rect = CGRect(origin: .zero, size: totalSize)
      let path = UIBezierPath(roundedRect: rect, cornerRadius: totalSize.height / 2)
      resolvedBackgroundColor.setFill()
      path.fill()

      if let icon, iconSide > 0 {
        let iconRect = CGRect(x: textInsets.left, y: (totalSize.height - iconSide) / 2, width: iconSide, height: iconSide)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(ovalIn: iconRect).addClip()
        icon.draw(in: iconRect)
        UIGraphicsGetCurrentContext()?.restoreGState()
      }
      let textRect = CGRect(x: textInsets.left + iconSpace, y: (totalSize.height - ceil(textSize.height)) / 2,
                            width: ceil(textSize.width), height: ceil(textSize.height))
      (title as NSString).draw(in: textRect, withAttributes: attributes)
    }
    #elseif canImport(AppKit)
    return NSImage(size: totalSize, flipped: false) { rect in
      let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
      resolvedBackgroundColor.setFill()
      path.fill()

      let textRect = CGRect(x: Self.textInsets.left, y: Self.textInsets.bottom,
                            width: ceil(textSize.width), height: ceil(textSize.height))
      (title as NSString).draw(in: textRect, withAttributes: attributes)
      return true
    }
    #endif
  }
}
