#!/bin/sh
# 배포 전 게이트 — 여기서 실패하면 DeployBar 가 아카이브를 만들지 않는다.
#
# 사용법:
#   sh scripts/predeploy.sh
#
# 다국어(.xcstrings) 검사는 DeployBar 에 내장돼 있으므로 여기서 다시 하지 않는다.
#
# ⚠️ CODE_SIGNING_ALLOWED=NO 로 빌드를 빠르게 만들지 말 것.
#    entitlements 가 빠지면 CloudKit(피드백 허브 컨테이너)·App Group 처럼
#    실제 배포 경로에서만 터지는 문제를 게이트가 놓친다.
set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SCHEME="DontGoMart"
PROJECT="DontGoMart.xcodeproj"
VERSION_XCCONFIG="Config/Version.xcconfig"

# ── 1. 버전이 두 곳에서 어긋나지 않는지 ──────────────────────────────────
# 이 앱은 타겟 빌드 설정(project.pbxproj)에 MARKETING_VERSION 이 직접 박혀 있고,
# 그게 Version.xcconfig 를 이긴다. 그래서 xcconfig 만 올리면 조용히 옛 버전이
# 올라가고, 업로드가 "이미 있는 버전" 으로 거절되고 나서야 드러난다.
# 두 곳이 같은 값인지 여기서 먼저 확인한다.
echo "🔢 [1/3] 버전 동기화 확인"
if [ ! -f "$VERSION_XCCONFIG" ]; then
  echo "❌ $VERSION_XCCONFIG 가 없습니다 — deploy.env 의 VERSION_XCCONFIG 와 어긋납니다"
  exit 1
fi

XC_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$VERSION_XCCONFIG" | head -1)"
XC_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$VERSION_XCCONFIG" | head -1)"
if [ -z "$XC_VERSION" ] || [ -z "$XC_BUILD" ]; then
  echo "❌ $VERSION_XCCONFIG 에 MARKETING_VERSION / CURRENT_PROJECT_VERSION 이 없습니다"
  exit 1
fi

for KEY in MARKETING_VERSION CURRENT_PROJECT_VERSION; do
  case "$KEY" in
    MARKETING_VERSION) WANT="$XC_VERSION" ;;
    *)                 WANT="$XC_BUILD" ;;
  esac
  # pbxproj 에 적힌 값들 중 xcconfig 와 다른 게 하나라도 있으면 중단
  ODD="$(grep -E "^[[:space:]]*$KEY = " "$PROJECT/project.pbxproj" \
         | sed 's/.*= *//; s/;.*//' | sort -u | grep -vx "$WANT" || true)"
  if [ -n "$ODD" ]; then
    echo "❌ $KEY 가 어긋납니다 — $VERSION_XCCONFIG 는 '$WANT' 인데"
    echo "   project.pbxproj 에는 다음 값이 남아 있습니다:"
    echo "$ODD" | sed 's/^/     /'
    echo "   두 곳을 같은 값으로 맞춰 주세요 (pbxproj 쪽이 이깁니다)"
    exit 1
  fi
done
echo "   $XC_VERSION ($XC_BUILD) · xcconfig 와 pbxproj 일치"

# ── 2. 테스트 ───────────────────────────────────────────────────────────
# 휴무 규칙 엔진(ClosureRuleEngine)과 팁 상품 로드(SKTestSession)를 검증한다.
# UI 계층은 여기서 검증되지 않는다 — 3단계 Release 빌드까지가 한계다.
echo "🧪 [2/3] 테스트 (DontGoMartTests)"
DEST_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d.get("isAvailable") and "iPhone" in d.get("name", ""):
            if best is None or version > best[0]:
                best = (version, d["udid"])
print(best[1] if best else "")
')"
if [ -z "$DEST_ID" ]; then
  echo "❌ 사용 가능한 iPhone 시뮬레이터가 없습니다"
  xcrun simctl list devices available | head -30
  exit 1
fi

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$DEST_ID" \
  -quiet

# ── 3. Release 빌드가 서는지 ────────────────────────────────────────────
# 아카이브가 Release 로 지어지므로 Release 로 확인한다. Debug 만 보면
# 최적화가 켜져야 드러나는 것들을 게이트가 통과시켜 버린다.
# 앱 스킴을 지으면 위젯 확장(CalendarWidgetExtension)도 딸려 지어진다.
echo "🔨 [3/3] Release 빌드 ($SCHEME · 위젯 확장 포함)"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$DEST_ID" \
  -quiet

echo ""
echo "✅ 게이트 통과 — 배포 가능"
