# TonTon automatic iCloud saves

TonTon syncs committed saves using the signed app's CloudKit private
database. It uses the existing `TonTonSaveV1` records and the same
`DMSYNC1` save archives as the compatibility build. Launch a title to check
for progress from another device. The game sends committed progress while
playing and tries to flush when the app goes to the background. Sign in to
the same Apple Account on each device. No folder selection is needed.

This covers games using the native host save mounts; a third-party engine
needs its own integration. A title's normal and device saves are transferred
together. The sender does
not replace a remote save that changed after the last comparison. When
both copies diverge, including a first sync with independent progress,
the runtime keeps both and continues locally. Only an explicit choice
bound to the exact remote revision can replace one of those copies; the
displaced save is kept in the local save backups. The automatic settings
row does not yet offer a conflict picker. If iCloud is unavailable the
game can continue with its local save.

## Signing the same container across devices

The existing paid-team Air and M2 artifacts use
`iCloud.com.tonytan.tonton.saves` in **Development**. The Mac game app and
Apple TV target need their own explicit app identifiers and provisioning
profiles authorized for that same CloudKit container **and** environment.
A Production build does not read Development records. The app identifier
on each platform can be different; do not change an existing app identifier
to add the capability. Do not switch environments for a deployed library
without planning a save migration.

- **iPhone and iPad:** Prepare the Xcode project normally. Use
  `dm/tools/cloudkit_signing.py` with its existing entitlements plist,
  generated `Gen/Info.plist`, exact app identifier, and the target's
  profile. Use the resulting Info.plist and CloudKit entitlements in that
  prepared project before signing. Use `DM_ENTITLEMENTS` or
  `CODE_SIGN_ENTITLEMENTS` to carry the generated entitlements rather than
  replacing other required capabilities. An ad-hoc IPA signature alone
  does not grant CloudKit access.
- **Mac:** The Mac Gamebox opens each game's Mac app. Pack that game with
  `dm/mac/pack_app.py --cloudkit-profile <profile>
  --cloudkit-app-identifier <app-id> --cloudkit-container <container>
  --cloudkit-environment Development --sign <identity>` plus its usual
  game inputs. The packer embeds the profile, signs both the game host
  and launcher, and verifies the staged bundle before publishing it.
  Build the host from a source revision with CloudKit support.
- **Apple TV:** Use the [tvOS compatibility project](https://github.com/widmonstertony/nxnative/tree/a86d90baf72c52349460907040f97b9634df2ed5/dm/tvos),
  which already compiles the private CloudKit transport. Prepare its
  target and stage its Info.plist and entitlements with the same tool
  using the tvOS profile. Keep the existing tvOS host and shader chain.

See Apple's [CloudKit capability setup](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)
and [provisioning profile reference](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles).
The staging tool validates the app identity, profile expiration, container
and environment before writing to a fresh output directory.

Local validation covers the save format, the folder fallback, automatic
exchange using a simulated private database, account separation and
conflicting updates. Cross-device verification still requires an
entitled build on each platform: use a disposable title/save, write on
one device, relaunch and verify on another, then verify the return trip.
