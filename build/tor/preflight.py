#!/usr/bin/env python3
"""Reject build kernels that cannot support Tor's upstream sandbox tests."""
import ctypes
import os


def require_seccomp():
    libc = ctypes.CDLL(None, use_errno=True)
    prctl = libc.prctl
    prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                     ctypes.c_ulong, ctypes.c_ulong]
    prctl.restype = ctypes.c_int
    # Read the current mode without installing/changing any process filter.
    mode = prctl(21, 0, 0, 0, 0)  # PR_GET_SECCOMP
    if mode == -1:
        error = os.strerror(ctypes.get_errno())
        raise RuntimeError(
            f'Build kernel cannot inspect seccomp ({error}). '
            'Tor upstream sandbox tests require a Docker host with kernel support '
            'for the target architecture. QEMU user-mode emulation cannot provide '
            'this; use a native ARM64 host or a full-system ARM64 Linux VM '
            'for ARM64 builds. Tests remain enabled.')
    return mode


if __name__ == '__main__':
    print(f'Build kernel supports seccomp inspection (mode {require_seccomp()})')
