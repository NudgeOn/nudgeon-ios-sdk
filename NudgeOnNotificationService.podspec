Pod::Spec.new do |s|
  s.name = "NudgeOnNotificationService"
  s.version = "0.2.2"
  s.summary = "NudgeOn notification service extension for delivery receipts and rich push."
  s.homepage = "https://github.com/NudgeOn/nudgeon-ios-sdk"
  s.license = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author = { "NudgeOn" => "dev@nudgeon.io" }
  s.source = { :git => "https://github.com/NudgeOn/nudgeon-ios-sdk.git", :tag => s.version.to_s }
  s.ios.deployment_target = "15.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/NudgeOnNotificationService/**/*.swift"
  s.frameworks = "Foundation", "UserNotifications"
  s.dependency "NudgeOnSDK", "= 0.2.2"
end
