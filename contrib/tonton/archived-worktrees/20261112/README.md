# Retained build-tree experiments

These are the uncommitted changes in the four historical Mac build worktrees
when the repository branches were consolidated on 2026-11-12. All committed
branch tips are ancestors of the consolidated main. The working directories
and their caches remain in place, detached at their original commits.

The current main contains the newer desktop/CloudKit/packing implementations
and upstream asynchronous video decoder and linear-texture fixes. The older
NDVE movie shortcut and decoder experiments are retained here for review;
they are not applied over the newer engine. No gameplay acceptance of that
experimental shortcut is claimed by the consolidation.

Each patch is against the `base` in manifest.json. To inspect it, create a
separate worktree at that commit and apply the patch there. Untracked source
snapshots are listed separately in the manifest. Do not apply these patches
blindly to current main or to a running/installed game.
