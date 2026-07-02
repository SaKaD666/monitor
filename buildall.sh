#!/usr/bin/env bash
set -euo pipefail

# macOS equivalent of monitor\buildall.bat
# Default GWSH for macOS GowinIDE; can be overridden by exporting GWSH in the environment.
GWSH="${GWSH:-/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/bin/gw_sh}"

# If GWSH is not executable and not on PATH => fail early
if ! [ -x "$GWSH" ] && ! command -v "$GWSH" >/dev/null 2>&1; then
  echo "ERROR: gw_sh not found or not executable at '$GWSH'."
  echo "Export GWSH to point to gw_sh or install GowinIDE."
  exit 1
fi

# Resolve actual gw_sh location (respect PATH) to find the corresponding lib directory
if command -v "$GWSH" >/dev/null 2>&1; then
  GWSH_PATH="$(command -v "$GWSH")"
else
  GWSH_PATH="$GWSH"
fi

GWSH_DIR="$(cd "$(dirname "$GWSH_PATH")" >/dev/null 2>&1 && pwd -P || true)"
GOWIN_LIB_DIR=""
if [ -n "$GWSH_DIR" ]; then
  candidate="$GWSH_DIR/../lib"
  if [ -d "$candidate" ]; then
    GOWIN_LIB_DIR="$(cd "$candidate" && pwd -P)"
  fi
fi

if [ -n "$GOWIN_LIB_DIR" ]; then
  # prepend to DYLD_* only if not already present
  case ":${DYLD_LIBRARY_PATH:-}:" in
    *":$GOWIN_LIB_DIR:") : ;;
    *) export DYLD_LIBRARY_PATH="$GOWIN_LIB_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" ;;
  esac
  case ":${DYLD_FALLBACK_LIBRARY_PATH:-}:" in
    *":$GOWIN_LIB_DIR:") : ;;
    *) export DYLD_FALLBACK_LIBRARY_PATH="$GOWIN_LIB_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}" ;;
  esac
  case ":${DYLD_FALLBACK_FRAMEWORK_PATH:-}:" in
    *":$GOWIN_LIB_DIR:") : ;;
    *) export DYLD_FALLBACK_FRAMEWORK_PATH="$GOWIN_LIB_DIR${DYLD_FALLBACK_FRAMEWORK_PATH:+:$DYLD_FALLBACK_FRAMEWORK_PATH}" ;;
  esac
  echo "Added Gowin lib dir to DYLD paths: $GOWIN_LIB_DIR"
fi

# Run from script dir so relative paths behave like the .bat counterpart
cd "$(dirname "$0")"

# echo/nano20k commented out in original .bat; keep parity
# "$GWSH" build.tcl nano20k

#echo
#echo "============ Building primer25k with ds2 controller ==============="
#echo
#"$GWSH" build.tcl primer25k ds2
#if [ $? -ne 0 ]; then
#  exit 1
#fi

#echo
#echo "============ Building mega60k with ds2 controller ==============="
#echo
#"$GWSH" build.tcl mega60k ds2
#if [ $? -ne 0 ]; then
#  exit 1
#fi

#echo
#echo "============ Building mega138k with ds2 controller ==============="
#echo
#"$GWSH" build.tcl mega138k ds2
#if [ $? -ne 0 ]; then
#  exit 1
#fi

#echo
#echo "============ Building mega138k_31002 with ds2 controller ==============="
#echo
#"$GWSH" build.tcl mega138k_31002 ds2
#if [ $? -ne 0 ]; then
#  exit 1
#fi

echo
echo "============ Building console60k with ds2 controller ==============="
echo
"$GWSH" build.tcl console60k ds2
if [ $? -ne 0 ]; then
  exit 1
fi

echo
echo "============ Building console138k with ds2 controller ==============="
echo
"$GWSH" build.tcl console138k ds2
if [ $? -ne 0 ]; then
  exit 1
fi

# List PNR .fs files (equivalent to `dir impl\\pnr\\*.fs`)
echo
ls -1 impl/pnr/*.fs 2>/dev/null || true

echo "All done."