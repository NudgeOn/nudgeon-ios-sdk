# CocoaPods 0.2.9 distribution

The core and notification extension specs target Git tag `0.2.9`. This is a
release candidate until the tag exists and remote-source lint passes. CocoaPods
trunk publication is separate from SPM/Git availability.

## Validate the candidate before tagging

```sh
pod lib lint NudgeOnSDK.podspec --platforms=ios --allow-warnings
pod lib lint NudgeOnNotificationService.podspec \
  --include-podspecs=NudgeOnSDK.podspec --platforms=ios --allow-warnings
```

CI validates the checked-out source, including the SQLite link. After publishing
the tag, validate the downloadable source before pushing either pod:

```sh
pod spec lint NudgeOnSDK.podspec --platforms=ios --allow-warnings
pod spec lint NudgeOnNotificationService.podspec \
  --external-podspecs=NudgeOnSDK.podspec --platforms=ios --allow-warnings
```

The specs select Swift 5.9. `--allow-warnings` permits migration warnings under
newer Xcode; compilation/import validation remains enabled. These commands do
not certify physical-device push delivery.

## Publish after maintainer login

```sh
pod trunk me
pod trunk push NudgeOnSDK.podspec --allow-warnings
pod trunk push NudgeOnNotificationService.podspec --allow-warnings
```

After both pushes, validate a clean consumer using only:

```ruby
pod 'NudgeOnSDK', '= 0.2.9'
# In the notification service extension target:
pod 'NudgeOnNotificationService', '= 0.2.9'
```

Before trunk publication, a consumer may use the podspec at the immutable `0.2.9`
Git tag explicitly. That downloads tagged source but does **not** establish
registry-only distribution. Do not add the core through both SPM and CocoaPods
to the same app target. RN/Flutter candidates pin both native cores to 0.2.9;
keep those versions aligned.
