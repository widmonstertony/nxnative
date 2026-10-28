# Camera, HUD and variable frame-time consumers verified against Arceus 1.1.1.
# Geometry reference: Fl4sh9174/Switch-Emulator-Ultrawide-FPS-Mods.
display_obs = [
    (0x1261ba0, 2079, "b9024008", "Device camera aspect in w8 after the original MOV/MOVK pair"),
    (0x191ddd8, 2079, "b9024288", "Device camera aspect in w8 after the original MOV/MOVK pair"),
    (0x19336c4, 2079, "b902329f", "Device camera aspect in w8 after the original MOV/MOVK pair"),
    (0x275065c, 2079, "b9024008", "Device camera aspect in w8 after the original MOV/MOVK pair"),
    (0x124ee04, 2335, "b9002109", "Device camera aspect in w9 after the original MOV/MOVK pair"),
    (0x194a664, 2335, "d29999aa", "Device camera aspect in w9 after the original MOV/MOVK pair"),
    (0x124eac4, 2591, "b902410a", "Preserve device aspect when a camera descriptor supplies the original 16:9 in w10"),
    (0x2abe894, 32, "2d408500", "Device HUD rectangle through saved x8; original LDP pairs read four floats"),
    (0x2a7e734, 35, "b9419022", "Publish real elapsed frame nanoseconds before the rendering frame"),
    (0x29faf98, 291, "1e270101", "Animation time step through w8 before the original FMOV s1,w8"),
    (0x2af25fc, 291, "1e270100", "Animation time step through w8 before the original FMOV s0,w8"),
    (0x2aa2790, 547, "b940ee6a", "Select interval one through saved w1 before the NVN setter"),
]
OBS = {"aee8f150dda1b5a838806e1a5ea6827a": display_obs}

CAPABILITIES = {"aee8f150dda1b5a838806e1a5ea6827a": ("ARCEUS_TIMING",)}
