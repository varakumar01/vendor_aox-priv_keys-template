#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Populates varakumar01/vendor_aox-priv_keys-template with real signing
# keys, using the same keys.sh/make_key.sh tooling Jammy555 actually ran
# to completion for his own vendor_evolution-priv_keys-template.
#
# Why not `gk -s`: Axion's own key-gen alias wipes this directory and
# reduces keys.mk to 3 lines, dropping every APEX certificate override --
# and its own APEX-generation mode (`gk -f`) is dead code (a `case`
# statement bug always falls through to help text), so it can never
# produce them anyway. This script runs the fuller, actually-complete
# flow instead: base keys + AVB + every APEX override keys.mk lists.
#
# MUST be run from inside a real, synced AOSP source tree, from exactly
# vendor/lineage-priv/keys (every path in keys.sh/make_key.sh is
# ../../../-relative to development/tools/make_key and external/avb/).
# This will NOT run standalone or from this offline working copy.
#
# Usage:
#   cd <your synced AOSP tree>
#   croot   # or: cd "$ANDROID_BUILD_TOP"
#   cd vendor/lineage-priv/keys
#   bash /path/to/axion_generate_keys.sh
#
# Safe to re-run: keys.sh only ever creates/overwrites files in the
# current directory, never deletes anything first (unlike `gk -s`).

set -euo pipefail

# --- 0. Sanity checks -------------------------------------------------
if [[ ! -f keys.sh || ! -f keys.mk || ! -f make_key.sh ]]; then
    echo "ERROR: run this from inside vendor/lineage-priv/keys" \
         "(keys.sh/keys.mk/make_key.sh not found in $(pwd))" >&2
    exit 1
fi
if [[ ! -d ../../../development/tools ]]; then
    echo "ERROR: ../../../development/tools not found -- this needs to run" \
         "from a real, synced AOSP source tree at vendor/lineage-priv/keys," \
         "not a standalone clone of the keys repo." >&2
    exit 1
fi

echo "== Working in $(pwd) =="

# --- 1. Back up keys.mk before editing --------------------------------
cp keys.mk keys.mk.orig
echo "== Backed up keys.mk -> keys.mk.orig =="

# --- 2. Repath keys.mk from evolution-priv to lineage-priv -------------
# (This repo is checked out at vendor/lineage-priv/keys per
#  .claude/claude-local-manifest.xml, but the template's keys.mk still
#  says vendor/evolution-priv/keys/ everywhere -- same 2-line fix Jammy555
#  applied to his own copy.)
sed -i 's#vendor/evolution-priv/keys#vendor/lineage-priv/keys#g' keys.mk

# --- 3. Default cert: releasekey, not testkey --------------------------
# Matches Jammy555's own choice. testkey is the template default; a real
# signing setup should use releasekey.
sed -i \
    's#^PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/testkey#PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey#' \
    keys.mk

echo "== keys.mk repathed to vendor/lineage-priv/, default cert set to releasekey =="
diff -u keys.mk.orig keys.mk || true

# --- 4. Optional: set your own certificate subject ----------------------
# make_key.sh currently hardcodes the generic AOSP subject
# ('/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/
#  emailAddress=android@android.com'). Uncomment and edit this block to
# use your own identity instead -- do this BEFORE running keys.sh, since
# every key gets stamped with whatever subject is in make_key.sh at
# generation time.
#
# sed -i "s#/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com#/C=US/ST=YourState/L=YourCity/O=YourOrg/OU=YourOrg/CN=YourName/emailAddress=you@example.com#" make_key.sh

# --- 5. Generate everything ---------------------------------------------
# This runs make_key.sh once per base key (from
# build/make/target/product/security/*.pk8's names) + avb + every APEX
# override keys.mk still lists, then regenerates Android.bp from that
# list. Interactive password prompts are already stripped by make_key.sh.
echo "== Running keys.sh (this generates every key + Android.bp) =="
chmod +x keys.sh make_key.sh
./keys.sh

echo "== Done. Generated files: =="
ls -la *.pk8 *.x509.pem avb_custom_key.bin 2>/dev/null | head -30

# --- 6. Verify against a build, if one exists ---------------------------
if [[ -f check_keys.py ]]; then
    echo
    echo "== To verify a build is fully signed with these keys, run: =="
    echo "   pip install -r requirements.txt"
    echo "   ./check_keys.py \$ANDROID_PRODUCT_OUT"
    echo "   (com.android.apex.cts.shim.v1_prebuilt is EXPECTED to still show"
    echo "    as vendor-key-signed -- see README.md, that's normal.)"
fi

echo
echo "== Next steps =="
echo "1. Review the diff above and 'git status' in this directory."
echo "2. If this repo is public, consider making it private before committing"
echo "   real private keys -- GitHub secret scanning won't block a .pk8 blob."
echo "3. git add -A && git commit -m 'Generate signing keys' && git push"
echo "4. Rebuild -- BUILD_KEYS should now read 'release-keys' instead of"
echo "   'test-keys'/'dev-keys' (gated on the literal vendor/lineage-priv/"
echo "   prefix in PRODUCT_DEFAULT_DEV_CERTIFICATE, which step 3 set)."
