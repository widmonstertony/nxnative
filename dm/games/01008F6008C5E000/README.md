# Pokemon Violet

Current preparation: owned update 4.0.0, main build `709bfd66115298640155fcc4979dba15`, SDK 13.3.13, plus two add-on licences. The RomFS/code survey is complete; no playable profile is registered here. The provisional profile, shader work, IPA and gameplay/device validation remain open.

Two exact-build observation sites adapt the camera and HUD to the actual window. Reference: the author's [Violet ultrawide source patch](https://github.com/Fl4sh9174/Switch-Emulator-Ultrawide-FPS-Mods). The camera observation follows the original `LDR S16,[x19,#0x190]` and multiplies its saved scalar lane by `device aspect / (16/9)`. The HUD observation redirects saved x8 before the original two LDP instructions, using thread-local storage instead of changing the original table. There are no runtime executable writes or borrowed code caves. The source patch's separate NOP at `main+0x1526d64` is not carried over: its role is unverified, and the owned binary has a live stack store there.

The saved-frame layout was checked against `entry.S`: Q registers begin at byte 256, with NZCV/FPSR/FPCR after byte 768. Callback tests cover 76:35, 683:512 and 4:3, verify exact module/gate guards, and verify every other GPR/SIMD/flags byte stays unchanged. Instruction-level rewrite and actual device display validation must pass before declaring fullscreen complete.

Frame timing, 120 fps, internal resolution scaling and interpolation are still open. The shared input surface keeps every native button and keyboard direction; compilation does not certify game compatibility.
