# Need for Speed Hot Pursuit Remastered 1.0.3. Keep the full build gate and
# original instruction assertion: these offsets do not apply to other builds.
# The associated timing fields are maintained by hle_fpslock.c. Reference:
# masagrator/FPSLocker-Warehouse, 799D1061182C1302.yaml (theboy181/masagrator).
CUTS = {
    '799d1061182c1302e08e706b84ce76e5': [
        (0x4835a4, '2cffff54', '1f2003d5',
         'Remove engine busy-wait back-edge; host pacing and matching NFS timer/2D/3D frame targets remain active'),
    ],
}
CAPABILITIES = {'799d1061182c1302e08e706b84ce76e5': ('NFS_TIMING',)}
