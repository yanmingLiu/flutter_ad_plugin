Pod::Spec.new do |s|
  s.name             = 'flutter_ad_plugin'
  s.version          = '0.1.0'
  s.summary          = 'Reusable Flutter ad plugin with configurable placements.'
  s.description      = 'Reusable Flutter ad plugin with configurable placements, policies and analytics hooks.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'flutter_ad_plugin' => 'example@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'google_mobile_ads'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
