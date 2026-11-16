# TonTon automatic iCloud saves

TonTon syncs committed saves using the signed app's CloudKit private
database. It uses the existing `TonTonSaveV1` records and the same
`DMSYNC1` save archives as the compatibility build. Launch a title to check
for progress from another device. The game sends committed progress while
playing and tries to flush when the app goes to the background. Sign in to
the same Apple Account on each device. No folder selection is needed.

The Mac frontend displays the original private-container account and existing
backup count separately from upstream's optional iCloud Drive / folder sync.
Both features remain available: a selected folder owns that game's session,
and the broker leaves the original container unchanged. With the optional
folder channel off, the original backups remain the default. The read-only
check requests `digest` metadata, never downloads a save asset or uploads data.
The same native `DMSYNC1` folder format can be used with upstream NX2Apple;
an upstream app without this container's entitlement cannot read the private
CloudKit database directly.

On the Mac, the signed TonTon broker accepts installed game bundles in
subfolders of the local Applications directories, resolving compatibility
links before validation. Moving a bundle does not choose a new save: the
broker passes the existing `~/Library/Application Support/nxnative/<id>/save`
to the game unless a player explicitly chose another location. TonTon builds
do not create the upstream portable-library marker. Changing transports or
organizing apps does not move or overwrite the player's saves.

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

## TonTon deployment and verification

The paid TonTon deployment uses these existing identities with
`iCloud.com.tonytan.tonton.saves` in Development:

| Platform | App identifier (without the team prefix) | Verification |
| --- | --- | --- |
| iPhone and iPad | `com.tonytan.nxgamelibrary.paid` | The two iPads transferred a disposable save. The Air compatibility build has logged a successful CloudKit save upload; a fresh cross-device readback on Air is still pending. |
| Mac | `com.tonytan.nxgamelibrary.mac` | A probe signed for the registered Mac mini uploaded a new disposable save and restored it on a second launch. This does not verify every separately packed Mac game. |
| Apple TV compatibility build | `org.nxnative.0100f43008c44000.tv` | The explicit App ID is associated with the same container and the development profile includes the registered Apple TVs. The read-only probe passed local signature verification; wireless installation timed out before an on-device restore could be checked. |

These checks used disposable saves or existing upload logs. They did not
move or overwrite the player's local saves. The source tests also cover
the save format, the folder fallback, automatic exchange using a
simulated private database, account separation and conflicting updates.
For end-to-end acceptance, use an entitled app and the same iCloud account
on each device: save under a disposable title, restore on a second device,
then verify the return trip.
