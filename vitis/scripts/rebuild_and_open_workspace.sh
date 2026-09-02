#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$script_dir/../.." && pwd)"
vitis_home="${SRCNN_VITIS_HOME:-/media/user3/data/tools/Vitis/2024.2}"
settings="${SRCNN_VITIS_SETTINGS:-$vitis_home/settings64.sh}"
workspace="${SRCNN_VITIS_WS:-$repo/build/vitis_workspace}"
xsa="${SRCNN_XSA:-$repo/vivado/output/SRCNN_NPU_wrapper.xsa}"

on_error() {
    local exit_code=$?
    echo "[FAIL] Vitis Workspace 재생성 또는 실행 실패 (exit=$exit_code)" >&2
    exit "$exit_code"
}
trap on_error ERR

if [[ ! -f "$settings" ]]; then
    echo "[FAIL] Vitis 2024.2 환경 설정 파일 없음: $settings" >&2
    echo "       다른 설치 위치는 SRCNN_VITIS_HOME 또는 SRCNN_VITIS_SETTINGS로 지정하세요." >&2
    exit 2
fi

if [[ ! -f "$xsa" ]]; then
    echo "[FAIL] 최종 XSA 없음: $xsa" >&2
    exit 2
fi

set +u
source "$settings"
set -u

if ! command -v vitis >/dev/null 2>&1; then
    echo "[FAIL] Vitis 실행 파일을 PATH에서 찾을 수 없습니다." >&2
    exit 2
fi

export SRCNN_REPO="$repo"
export SRCNN_VITIS_WS="$workspace"
export SRCNN_XSA="$xsa"

echo "=== SRCNN Final Vitis Workspace ==="
echo "Repository : $repo"
echo "Vitis      : $(command -v vitis)"
echo "XSA        : $xsa"
echo "Workspace  : $workspace"

cd "$repo"

echo "=== A. Platform 재생성 및 Build ==="
vitis -s vitis/scripts/create_platform.py

echo "=== B. Application 재생성 및 Build ==="
vitis -s vitis/scripts/create_application.py

echo "=== C. Vitis Unified IDE 실행 ==="
echo "[PASS] Workspace 생성 완료: $workspace"
exec vitis -w "$workspace"
