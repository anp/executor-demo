pod 'React',
  :path => "../js/node_modules/react-native",
  :subspecs => [
    "Core",
    "CxxBridge",
    "DevSupport",
    "RCTAnimation",
    "RCTImage",
    "RCTNetwork",
    "RCTText",
    "RCTWebSocket",
    "ART",
    "RCTActionSheet",
    "RCTBlob",
    "RCTCameraRoll",
    "RCTGeolocation",
    "RCTSettings",
    "RCTVibration",
    "RCTLinkingIOS",
    "RCTPushNotification"
  ],
  :inhibit_warnings => true
pod 'yoga',
  :path => "../js/node_modules/react-native/ReactCommon/yoga",
  :inhibit_warnings => true
pod 'DoubleConversion',
  :podspec => "../js/node_modules/react-native/third-party-podspecs/DoubleConversion.podspec",
  :inhibit_warnings => true
pod 'Folly',
  :podspec => "../js/node_modules/react-native/third-party-podspecs/Folly.podspec",
  :inhibit_warnings => true
pod 'glog',
  :podspec => "../js/node_modules/react-native/third-party-podspecs/glog.podspec",
  :inhibit_warnings => true
