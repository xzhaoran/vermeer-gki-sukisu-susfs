#!/usr/bin/env python3
"""AVC log spoofing glue for the SukiSU-Nova *builtin* branch.

The builtin branch implements AVC log spoofing as a SUSFS command
(CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING -> susfs_set_avc_log_spoofing) and has no
KSU_FEATURE_AVC_SPOOF, while the manager release (v3.0.0) addresses it through
the feature API with id 10003.  This patch:

  1. defaults the SUSFS static key to *on* (DEFINE_STATIC_KEY_TRUE), and
  2. teaches ksu_get_feature()/ksu_set_feature() about feature id 10003,
     returning the real key state.

Important: the state must be read with static_key_enabled(&key.key), NOT with
static_branch_unlikely().  The latter is a jump-label site; when the key was
defined as STATIC_KEY_TRUE its polarity does not match and the read always
returns 0, which looks like "the switch does nothing".

Usage: patch_avc_compat.py <KernelSU-dir> <kernel-dir>
"""
import pathlib
import sys

FEATURE_ID = 10003
MARKER = "KSU_FEATURE_AVC_SPOOF_COMPAT"

BLOCK = f'''#ifdef CONFIG_KSU_SUSFS
/*
 * Compat shim: manager releases address AVC log spoofing through the feature
 * API (KSU_FEATURE_AVC_SPOOF == {FEATURE_ID} on the main branch).  This tree keeps the
 * implementation behind the SUSFS command, so answer that feature id by
 * driving the very same static key.
 */
#define KSU_FEATURE_AVC_SPOOF_COMPAT {FEATURE_ID}u
extern struct static_key_false susfs_is_avc_log_spoofing_enabled;

static int ksu_avc_spoof_compat_get(u64 *value, bool *supported)
{{
    *supported = true;
    /* Plain flag read; static_branch_*() only reflects the patched site. */
    *value = static_key_enabled(&susfs_is_avc_log_spoofing_enabled.key) ? 1 : 0;
    return 0;
}}

static int ksu_avc_spoof_compat_set(u64 value)
{{
    if (value)
        static_branch_enable(&susfs_is_avc_log_spoofing_enabled);
    else
        static_branch_disable(&susfs_is_avc_log_spoofing_enabled);
    return 0;
}}
#endif /* CONFIG_KSU_SUSFS */

'''


def patch_feature_c(ks: pathlib.Path) -> None:
    p = ks / "kernel/policy/feature.c"
    s = p.read_text()
    if MARKER in s:
        print("feature.c: already patched")
        return

    anchor = "static const struct ksu_feature_handler *feature_handlers[KSU_FEATURE_MAX];"
    if anchor not in s:
        raise SystemExit("feature.c: handler table anchor not found")
    s = s.replace(anchor, BLOCK + anchor, 1)

    get_head = (
        "int ksu_get_feature(u32 feature_id, u64 *value, bool *supported)\n"
        "{\n    int ret = 0;"
    )
    set_head = "int ksu_set_feature(u32 feature_id, u64 value)\n{\n    int ret = 0;"
    if get_head not in s or set_head not in s:
        raise SystemExit("feature.c: ksu_get_feature/ksu_set_feature signature drifted")

    s = s.replace(get_head, get_head + f'''
#ifdef CONFIG_KSU_SUSFS
    if (feature_id == KSU_FEATURE_AVC_SPOOF_COMPAT) {{
        if (!value || !supported)
            return -EINVAL;
        return ksu_avc_spoof_compat_get(value, supported);
    }}
#endif''', 1)

    s = s.replace(set_head, set_head + '''
#ifdef CONFIG_KSU_SUSFS
    if (feature_id == KSU_FEATURE_AVC_SPOOF_COMPAT)
        return ksu_avc_spoof_compat_set(value);
#endif''', 1)

    p.write_text(s)
    print("feature.c: AVC compat handler added")


def patch_susfs_key(kernel: pathlib.Path) -> None:
    p = kernel / "fs/susfs.c"
    s = p.read_text()
    false_def = "DEFINE_STATIC_KEY_FALSE(susfs_is_avc_log_spoofing_enabled);"
    true_def = "DEFINE_STATIC_KEY_TRUE(susfs_is_avc_log_spoofing_enabled);"
    if true_def in s:
        print("susfs.c: key already defaults to enabled")
        return
    if false_def not in s:
        raise SystemExit("susfs.c: avc log spoofing key not found")
    p.write_text(s.replace(false_def, true_def, 1))
    print("susfs.c: AVC log spoofing defaults to enabled")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    patch_feature_c(pathlib.Path(sys.argv[1]))
    patch_susfs_key(pathlib.Path(sys.argv[2]))


if __name__ == "__main__":
    main()
