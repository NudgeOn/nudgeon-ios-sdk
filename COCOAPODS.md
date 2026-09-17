# CocoaPods distribution preparation

The core and notification extension podspecs consume the existing public Git tag
`0.2.2`. This does not modify the tag or publish a CocoaPods trunk release. SPM
remains available as documented in the README. RN/Flutter's pod dependencies must
resolve through an explicit podspec source until trunk publication is complete.

## Validate

```sh
pod spec lint NudgeOnSDK.podspec --platforms=ios --allow-warnings
pod lib lint NudgeOnNotificationService.podspec \
  --external-podspecs=NudgeOnSDK.podspec --platforms=ios --allow-warnings
```

Verified on 2026-09-18 KST with CocoaPods 1.15.2 and Xcode 27. The first command
downloads the core from the public 0.2.2 tag. The second builds the local extension
source with the core downloaded through its podspec. Neither is a physical push
test. CI repeats both validations.

`--allow-warnings` permits the published 0.2.2 core's existing explicit-self and
Sendable migration warnings under newer Xcode. Compilation/import validation
remains enabled. The specs select Swift 5.9; Swift 6 strict mode is not certified.

For a consumer build before trunk publication, the app Podfile can declare the
core with `:podspec` pointing to this specification (a pinned Git commit URL for
reproducible remote use, or the absolute local podspec path for development).
The podspec's source still downloads public 0.2.2 rather than local Swift files.
Do not add the same core to the same app target through both SPM and CocoaPods.

## Publish after maintainer login

```sh
pod trunk me
pod trunk push NudgeOnSDK.podspec --allow-warnings
pod trunk push NudgeOnNotificationService.podspec --allow-warnings
```

After both pushes, validate a clean consumer using only:

```ruby
pod 'NudgeOnSDK', '= 0.2.2'
# In the notification service extension target:
pod 'NudgeOnNotificationService', '= 0.2.2'
```

Do not mark registry distribution complete until a fresh CocoaPods resolution
succeeds without `:podspec` overrides. Keep the bridge wrappers' native dependency
versions aligned. See the [official CocoaPods release guide](https://guides.cocoapods.org/making/making-a-cocoapod.html#release).
