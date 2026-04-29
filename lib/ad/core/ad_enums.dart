typedef PlacementType = String;

class Placements {
  static const String open = 'open';
  static const String home = 'home';
  static const String message = 'message';
  static const String chatBack = 'chatBack';
  static const String chatSession = 'chatSession';
  static const String liveVideo = 'liveVideo';
  static const List<String> values = [
    open,
    home,
    message,
    chatBack,
    chatSession,
    liveVideo,
  ];
}

enum AdType { open, interstitial, rewarded, native }

enum AdSource { admob, max, topon }

enum AdEventType {
  loadRequested,
  loadSucceeded,
  loadFailed,
  show,
  showSuccess,
  clicked,
  income,
  close,
  rewardEarned,
  showFail,
  blockedByGuard,
}
