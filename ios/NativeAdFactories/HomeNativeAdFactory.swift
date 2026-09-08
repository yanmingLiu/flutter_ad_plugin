import UIKit
import google_mobile_ads

final class HomeNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(
    _ nativeAd: NativeAd,
    customOptions: [AnyHashable: Any]? = nil
  ) -> NativeAdView {
    let root = NativeAdView(frame: .zero)
    root.backgroundColor = UIColor.clear

    let card = UIView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.layer.cornerRadius = 14
    card.layer.masksToBounds = true
    card.backgroundColor = UIColor(white: 0.08, alpha: 1)
    root.addSubview(card)

    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      card.topAnchor.constraint(equalTo: root.topAnchor),
      card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      card.heightAnchor.constraint(equalToConstant: 250),
    ])

    let mediaView = MediaView()
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(mediaView)

    let overlay = UIView()
    overlay.translatesAutoresizingMaskIntoConstraints = false
    overlay.backgroundColor = UIColor.clear
    card.addSubview(overlay)

    NSLayoutConstraint.activate([
      mediaView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      mediaView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      mediaView.topAnchor.constraint(equalTo: card.topAnchor),
      mediaView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
      overlay.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      overlay.topAnchor.constraint(equalTo: card.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: card.bottomAnchor),
    ])
    applyOverlayGradient(on: overlay)

    let content = UIView()
    content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
      content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
      content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
    ])

    let adChip = UILabel()
    adChip.translatesAutoresizingMaskIntoConstraints = false
    adChip.text = "Ad"
    adChip.font = UIFont.systemFont(ofSize: 10, weight: .bold)
    adChip.textColor = UIColor(white: 0.07, alpha: 1)
    adChip.backgroundColor = UIColor(red: 0.95, green: 0.83, blue: 0.38, alpha: 1)
    adChip.layer.cornerRadius = 5
    adChip.layer.masksToBounds = true
    adChip.textAlignment = .center
    content.addSubview(adChip)

    let adChoices = AdChoicesView()
    adChoices.translatesAutoresizingMaskIntoConstraints = false
    adChoices.backgroundColor = UIColor.white.withAlphaComponent(0.22)
    adChoices.layer.cornerRadius = 12
    adChoices.layer.masksToBounds = true
    content.addSubview(adChoices)

    let iconView = UIImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentMode = .scaleAspectFill
    iconView.layer.cornerRadius = 6
    iconView.layer.masksToBounds = true
    iconView.backgroundColor = UIColor.white.withAlphaComponent(0.2)
    content.addSubview(iconView)

    let ctaButton = UIButton(type: .system)
    ctaButton.translatesAutoresizingMaskIntoConstraints = false
    ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .bold)
    ctaButton.setTitleColor(UIColor(white: 0.07, alpha: 1), for: .normal)
    ctaButton.backgroundColor = UIColor(red: 0.95, green: 0.83, blue: 0.38, alpha: 1)
    ctaButton.layer.cornerRadius = 6
    ctaButton.clipsToBounds = true
    content.addSubview(ctaButton)

    let headline = UILabel()
    headline.translatesAutoresizingMaskIntoConstraints = false
    headline.font = UIFont.systemFont(ofSize: 14, weight: .bold)
    headline.textColor = .white
    headline.numberOfLines = 2
    content.addSubview(headline)

    let body = UILabel()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.font = UIFont.systemFont(ofSize: 10, weight: .regular)
    body.textColor = UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    body.numberOfLines = 1
    content.addSubview(body)

    NSLayoutConstraint.activate([
      adChip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      adChip.topAnchor.constraint(equalTo: content.topAnchor),
      adChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
      adChip.heightAnchor.constraint(equalToConstant: 18),

      adChoices.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      adChoices.topAnchor.constraint(equalTo: content.topAnchor),
      adChoices.widthAnchor.constraint(equalToConstant: 24),
      adChoices.heightAnchor.constraint(equalToConstant: 24),

      iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      iconView.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -6),
      iconView.widthAnchor.constraint(equalToConstant: 30),
      iconView.heightAnchor.constraint(equalToConstant: 30),

      ctaButton.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      ctaButton.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      ctaButton.widthAnchor.constraint(equalToConstant: 58),
      ctaButton.heightAnchor.constraint(equalToConstant: 28),

      headline.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
      headline.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      headline.bottomAnchor.constraint(equalTo: body.topAnchor, constant: -2),

      body.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
      body.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      body.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])

    root.mediaView = mediaView
    root.iconView = iconView
    root.headlineView = headline
    root.bodyView = body
    root.callToActionView = ctaButton
    root.adChoicesView = adChoices

    headline.text = nativeAd.headline
    body.text = nativeAd.body
    body.isHidden = nativeAd.body?.isEmpty ?? true

    if let icon = nativeAd.icon?.image {
      iconView.image = icon
      iconView.isHidden = false
    } else {
      iconView.isHidden = true
    }

    if let cta = nativeAd.callToAction, !cta.isEmpty {
      ctaButton.setTitle(cta, for: .normal)
      ctaButton.isHidden = false
    } else {
      ctaButton.isHidden = true
    }

    mediaView.mediaContent = nativeAd.mediaContent
    root.nativeAd = nativeAd
    return root
  }

  private func applyOverlayGradient(on view: UIView) {
    let gradient = CAGradientLayer()
    gradient.colors = [
      UIColor.black.withAlphaComponent(0.10).cgColor,
      UIColor.black.withAlphaComponent(0.24).cgColor,
      UIColor.black.withAlphaComponent(0.46).cgColor,
    ]
    gradient.locations = [0.0, 0.55, 1.0]
    gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
    gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
    gradient.frame = CGRect(x: 0, y: 0, width: 1000, height: 250)
    view.layer.insertSublayer(gradient, at: 0)
  }
}
