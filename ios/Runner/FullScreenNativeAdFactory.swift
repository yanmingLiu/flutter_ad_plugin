import Flutter
import google_mobile_ads
import UIKit

final class FullScreenNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(
    _ nativeAd: NativeAd,
    customOptions: [AnyHashable: Any]? = nil
  ) -> NativeAdView? {
    let adView = NativeAdView()
    adView.backgroundColor = .black
    adView.translatesAutoresizingMaskIntoConstraints = false

    let mediaView = MediaView()
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    mediaView.mediaContent = nativeAd.mediaContent
    adView.mediaView = mediaView
    adView.addSubview(mediaView)

    let fullClickView = UIView()
    fullClickView.translatesAutoresizingMaskIntoConstraints = false
    fullClickView.backgroundColor = .clear
    adView.addSubview(fullClickView)
    adView.headlineView = fullClickView

    let adChoicesView = AdChoicesView()
    adChoicesView.translatesAutoresizingMaskIntoConstraints = false
    adChoicesView.backgroundColor = UIColor(white: 1, alpha: 0.9)
    adView.adChoicesView = adChoicesView
    adView.addSubview(adChoicesView)

    let headlineContainer = UIView()
    let bodyContainer = UIView()
    let iconContainer = UIView()
    let ctaContainer = UIView()
    [headlineContainer, bodyContainer, iconContainer, ctaContainer].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      adView.addSubview($0)
    }

    let headlineLabel = UILabel()
    headlineLabel.translatesAutoresizingMaskIntoConstraints = false
    headlineLabel.text = nativeAd.headline
    headlineLabel.textColor = .white
    headlineLabel.font = .boldSystemFont(ofSize: 22)
    headlineLabel.numberOfLines = 2
    headlineLabel.isUserInteractionEnabled = false
    headlineContainer.addSubview(headlineLabel)

    let bodyLabel = UILabel()
    bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    bodyLabel.text = nativeAd.body
    bodyLabel.textColor = UIColor(white: 0.86, alpha: 1)
    bodyLabel.font = .systemFont(ofSize: 18)
    bodyLabel.numberOfLines = 2
    bodyLabel.isUserInteractionEnabled = false
    bodyContainer.addSubview(bodyLabel)
    adView.bodyView = bodyContainer
    bodyContainer.isHidden = nativeAd.body?.isEmpty ?? true

    let iconImageView = UIImageView()
    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    iconImageView.contentMode = .scaleAspectFill
    iconImageView.clipsToBounds = true
    iconImageView.layer.cornerRadius = 4
    iconImageView.image = nativeAd.icon?.image
    iconImageView.isUserInteractionEnabled = false
    iconContainer.addSubview(iconImageView)
    adView.iconView = iconContainer
    iconContainer.isHidden = nativeAd.icon == nil

    let ctaButton = UIButton(type: .system)
    ctaButton.translatesAutoresizingMaskIntoConstraints = false
    ctaButton.setTitle(nativeAd.callToAction, for: .normal)
    ctaButton.setTitleColor(.black, for: .normal)
    ctaButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
    ctaButton.backgroundColor = UIColor(red: 0.992, green: 0.965, blue: 0.322, alpha: 1)
    ctaButton.layer.cornerRadius = 14
    ctaButton.isUserInteractionEnabled = false
    ctaContainer.addSubview(ctaButton)
    adView.callToActionView = ctaContainer
    ctaContainer.isHidden = nativeAd.callToAction?.isEmpty ?? true

    NSLayoutConstraint.activate([
      mediaView.topAnchor.constraint(equalTo: adView.topAnchor),
      mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      mediaView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      mediaView.bottomAnchor.constraint(equalTo: adView.bottomAnchor),

      fullClickView.topAnchor.constraint(equalTo: adView.topAnchor),
      fullClickView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      fullClickView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      fullClickView.bottomAnchor.constraint(equalTo: adView.bottomAnchor),

      adChoicesView.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
      adChoicesView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
      adChoicesView.widthAnchor.constraint(equalToConstant: 48),
      adChoicesView.heightAnchor.constraint(equalToConstant: 28),

      ctaContainer.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 24),
      ctaContainer.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -24),
      ctaContainer.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -34),
      ctaContainer.heightAnchor.constraint(equalToConstant: 44),

      ctaButton.topAnchor.constraint(equalTo: ctaContainer.topAnchor),
      ctaButton.leadingAnchor.constraint(equalTo: ctaContainer.leadingAnchor),
      ctaButton.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor),
      ctaButton.bottomAnchor.constraint(equalTo: ctaContainer.bottomAnchor),

      iconContainer.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 24),
      iconContainer.bottomAnchor.constraint(equalTo: ctaContainer.topAnchor, constant: -24),
      iconContainer.widthAnchor.constraint(equalToConstant: 58),
      iconContainer.heightAnchor.constraint(equalToConstant: 58),

      iconImageView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
      iconImageView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
      iconImageView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
      iconImageView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),

      bodyContainer.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
      bodyContainer.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -24),
      bodyContainer.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

      bodyLabel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
      bodyLabel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
      bodyLabel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
      bodyLabel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

      headlineContainer.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 24),
      headlineContainer.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -24),
      headlineContainer.bottomAnchor.constraint(equalTo: iconContainer.topAnchor, constant: -18),

      headlineLabel.topAnchor.constraint(equalTo: headlineContainer.topAnchor),
      headlineLabel.leadingAnchor.constraint(equalTo: headlineContainer.leadingAnchor),
      headlineLabel.trailingAnchor.constraint(equalTo: headlineContainer.trailingAnchor),
      headlineLabel.bottomAnchor.constraint(equalTo: headlineContainer.bottomAnchor),
    ])

    adView.nativeAd = nativeAd
    return adView
  }
}
