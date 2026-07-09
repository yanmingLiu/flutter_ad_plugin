import UIKit
import google_mobile_ads

private final class BottomScrimView: UIView {
  private let gradientLayer = CAGradientLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    gradientLayer.colors = [
      UIColor.clear.cgColor,
      UIColor.black.withAlphaComponent(0.74).cgColor,
      UIColor.black.withAlphaComponent(0.95).cgColor,
    ]
    gradientLayer.locations = [0, 0.42, 1]
    layer.insertSublayer(gradientLayer, at: 0)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    gradientLayer.frame = bounds
  }
}

private final class FullscreenNativeAdView: NativeAdView {
  private var fillConstraints: [NSLayoutConstraint] = []

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    pinToSuperview()
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil {
      NSLayoutConstraint.deactivate(fillConstraints)
      fillConstraints.removeAll()
    }
    super.willMove(toSuperview: newSuperview)
  }

  private func pinToSuperview() {
    guard let superview, fillConstraints.isEmpty else {
      return
    }
    translatesAutoresizingMaskIntoConstraints = false
    fillConstraints = [
      topAnchor.constraint(equalTo: superview.topAnchor),
      leadingAnchor.constraint(equalTo: superview.leadingAnchor),
      trailingAnchor.constraint(equalTo: superview.trailingAnchor),
      bottomAnchor.constraint(equalTo: superview.bottomAnchor),
    ]
    NSLayoutConstraint.activate(fillConstraints)
  }
}

public final class FullScreenNativeAdFactory: NSObject, FLTNativeAdFactory {
  public override init() {
    super.init()
  }

  public func createNativeAd(
    _ nativeAd: NativeAd,
    customOptions: [AnyHashable: Any]? = nil
  ) -> NativeAdView {
    let adView = FullscreenNativeAdView(frame: .zero)
    adView.backgroundColor = .black
    adView.translatesAutoresizingMaskIntoConstraints = false

    let mediaView = MediaView()
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    mediaView.contentMode = .scaleAspectFill
    mediaView.clipsToBounds = true
    mediaView.mediaContent = nativeAd.mediaContent
    adView.mediaView = mediaView
    adView.insertSubview(mediaView, at: 0)

    let fullClickView = UIView()
    fullClickView.translatesAutoresizingMaskIntoConstraints = false
    fullClickView.backgroundColor = .clear
    fullClickView.isUserInteractionEnabled = false
    adView.insertSubview(fullClickView, aboveSubview: mediaView)

    let adChoicesView = AdChoicesView()
    adChoicesView.translatesAutoresizingMaskIntoConstraints = false
    adChoicesView.backgroundColor = UIColor(white: 1, alpha: 0.9)
    adView.adChoicesView = adChoicesView

    let scrimView = BottomScrimView()
    scrimView.translatesAutoresizingMaskIntoConstraints = false
    adView.insertSubview(scrimView, aboveSubview: fullClickView)

    let headlineContainer = UIView()
    let bodyContainer = UIView()
    let iconContainer = UIView()
    let ctaContainer = UIView()
    [headlineContainer, bodyContainer, iconContainer, ctaContainer].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
    }

    let rowStack = UIStackView(arrangedSubviews: [iconContainer, bodyContainer])
    rowStack.translatesAutoresizingMaskIntoConstraints = false
    rowStack.axis = .horizontal
    rowStack.alignment = .center
    rowStack.spacing = 14

    let bottomStack = UIStackView(
      arrangedSubviews: [headlineContainer, rowStack, ctaContainer]
    )
    bottomStack.translatesAutoresizingMaskIntoConstraints = false
    bottomStack.axis = .vertical
    bottomStack.alignment = .fill
    bottomStack.spacing = 18
    adView.addSubview(bottomStack)
    adView.addSubview(adChoicesView)

    let adBadgeLabel = UILabel()
    adBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
    adBadgeLabel.text = "Ad"
    adBadgeLabel.textAlignment = .center
    adBadgeLabel.textColor = .white
    adBadgeLabel.backgroundColor = UIColor(
      red: 1,
      green: 0.8,
      blue: 0.4,
      alpha: 1
    )
    adBadgeLabel.font = .boldSystemFont(ofSize: 11)
    adBadgeLabel.layer.cornerRadius = 2
    adBadgeLabel.clipsToBounds = true
    adBadgeLabel.isUserInteractionEnabled = false
    adBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
    adBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    headlineContainer.addSubview(adBadgeLabel)

    let headlineLabel = UILabel()
    headlineLabel.translatesAutoresizingMaskIntoConstraints = false
    headlineLabel.text = nativeAd.headline
    headlineLabel.textColor = .white
    headlineLabel.font = .boldSystemFont(ofSize: 22)
    headlineLabel.numberOfLines = 2
    headlineLabel.isUserInteractionEnabled = false
    headlineContainer.addSubview(headlineLabel)
    adView.headlineView = headlineLabel

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
    ctaButton.backgroundColor = UIColor(
      red: 0.992,
      green: 0.965,
      blue: 0.322,
      alpha: 1
    )
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
      fullClickView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor),

      scrimView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      scrimView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      scrimView.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
      scrimView.heightAnchor.constraint(equalTo: adView.heightAnchor, multiplier: 0.42),

      adChoicesView.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
      adChoicesView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
      adChoicesView.widthAnchor.constraint(equalToConstant: 48),
      adChoicesView.heightAnchor.constraint(equalToConstant: 28),

      bottomStack.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 24),
      bottomStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -24),
      bottomStack.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -34),

      rowStack.heightAnchor.constraint(equalToConstant: 58),
      ctaContainer.heightAnchor.constraint(equalToConstant: 44),

      ctaButton.topAnchor.constraint(equalTo: ctaContainer.topAnchor),
      ctaButton.leadingAnchor.constraint(equalTo: ctaContainer.leadingAnchor),
      ctaButton.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor),
      ctaButton.bottomAnchor.constraint(equalTo: ctaContainer.bottomAnchor),

      iconContainer.widthAnchor.constraint(equalToConstant: 58),
      iconContainer.heightAnchor.constraint(equalToConstant: 58),

      iconImageView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
      iconImageView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
      iconImageView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
      iconImageView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),

      bodyLabel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
      bodyLabel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
      bodyLabel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
      bodyLabel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

      adBadgeLabel.leadingAnchor.constraint(equalTo: headlineContainer.leadingAnchor),
      adBadgeLabel.centerYAnchor.constraint(equalTo: headlineLabel.firstBaselineAnchor, constant: -5),
      adBadgeLabel.widthAnchor.constraint(equalToConstant: 24),
      adBadgeLabel.heightAnchor.constraint(equalToConstant: 16),

      headlineLabel.topAnchor.constraint(equalTo: headlineContainer.topAnchor),
      headlineLabel.leadingAnchor.constraint(equalTo: adBadgeLabel.trailingAnchor, constant: 6),
      headlineLabel.trailingAnchor.constraint(equalTo: headlineContainer.trailingAnchor),
      headlineLabel.bottomAnchor.constraint(equalTo: headlineContainer.bottomAnchor),
    ])

    adView.nativeAd = nativeAd
    return adView
  }
}
