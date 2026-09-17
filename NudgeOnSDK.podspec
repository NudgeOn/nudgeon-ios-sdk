Pod::Spec.new do |s|
  s.name = "NudgeOnSDK"
  s.version = "0.2.2"
  s.summary = "NudgeOn event tracking, identity and push notification core."
  s.homepage = "https://github.com/NudgeOn/nudgeon-ios-sdk"
  s.license = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author = { "NudgeOn" => "dev@nudgeon.io" }
  s.source = { :git => "https://github.com/NudgeOn/nudgeon-ios-sdk.git", :tag => s.version.to_s }
  s.ios.deployment_target = "15.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/NudgeOnSDK/**/*.swift"
  s.frameworks = "Foundation", "UIKit", "UserNotifications"
end
