# Independent compute bindings on the legacy NVN backend

Upstream commit `8b21049d2a59b900d45019b40d47bb581be5c791` separates compute and graphics bindings. This port applies the same semantics to the iOS 16/17 backend, including dispatch and submit dependency indexing. Graphics-only prediction ignores compute-only program changes.

A current Witcher 3 command-buffer capture bound a program with mask `0x03`, then bound NULL with mask `0x3c`. The old handler returned NULL for the compute bit and erased the effective graphics program, dropping subsequent draws. The corrected handler clears only the selected stages and keeps compute in its own state field.

Validation: two regression tests execute the actual production binding handler under ASan/UBSan, including the captured sequence, mixed-stage masks, zero masks and compute/graphics interleaving. The complete iOS 16.1 Xcode build passed. M2 host 20261101.38 was installed with all existing game frameworks, 84 or more CPU tables and ten save files read back unchanged. Game rendering after this installation remains for user validation. Shader resources and chain identity are unchanged.
