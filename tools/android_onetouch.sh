#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  미래엔 교과서 PDF 원터치 추출 (Android Termux)
# ============================================================
#
#  사용법 (둘 중 하나):
#
#    방법 A) 파일 다운로드 후 실행 (대화형 메뉴 지원):
#      curl -sLO https://raw.githubusercontent.com/jwsung810/DanbaidongRP/claude/extract-chemistry-pdf-L1owt/tools/android_onetouch.sh
#      bash android_onetouch.sh
#
#    방법 B) 파이프 실행 (화학2 기본값으로 바로 시작):
#      curl -sL https://raw.githubusercontent.com/jwsung810/DanbaidongRP/claude/extract-chemistry-pdf-L1owt/tools/android_onetouch.sh | bash
#
# ============================================================

# ── 색상 ──
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${G}[OK]${NC} $1"; }
warn() { echo -e "${Y}[!!]${NC} $1"; }
err()  { echo -e "${R}[ERR]${NC} $1"; }

echo ""
echo -e "${C}╔══════════════════════════════════════════╗${NC}"
echo -e "${C}║  미래엔 교과서 PDF 원터치 추출 (Android) ║${NC}"
echo -e "${C}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── python3 경로 결정 ──
PYTHON=""
for p in python3 python; do
  if command -v "$p" &>/dev/null; then
    PYTHON="$p"
    break
  fi
done

PIP=""
for p in pip3 pip; do
  if command -v "$p" &>/dev/null; then
    PIP="$p"
    break
  fi
done

# ── 과목 선택 ──
# pipe 실행인지 확인 (stdin이 터미널이 아니면 pipe)
KB="kb2092"
NAME="화학2"

if [ -t 0 ]; then
  # 터미널에서 직접 실행 → 대화형 메뉴
  echo -e "${C}── 과목 선택 ──${NC}"
  echo "  1) 화학Ⅱ  (kb2092)  ← 기본"
  echo "  2) 화학Ⅰ  (kb2091)"
  echo "  3) 물리학Ⅰ (kb2084)"
  echo "  4) 물리학Ⅱ (kb2085)"
  echo "  5) 생명과학Ⅰ (kb2086)"
  echo "  6) 생명과학Ⅱ (kb2087)"
  echo "  7) 지구과학Ⅰ (kb2088)"
  echo "  8) 지구과학Ⅱ (kb2089)"
  echo "  9) 통합과학 (kb2083)"
  echo ""
  echo -n "선택 [1]: "
  read -r choice
  case "${choice:-1}" in
    1) KB="kb2092"; NAME="화학2" ;;
    2) KB="kb2091"; NAME="화학1" ;;
    3) KB="kb2084"; NAME="물리학1" ;;
    4) KB="kb2085"; NAME="물리학2" ;;
    5) KB="kb2086"; NAME="생명과학1" ;;
    6) KB="kb2087"; NAME="생명과학2" ;;
    7) KB="kb2088"; NAME="지구과학1" ;;
    8) KB="kb2089"; NAME="지구과학2" ;;
    9) KB="kb2083"; NAME="통합과학" ;;
    *) KB="kb2092"; NAME="화학2" ;;
  esac
else
  # pipe 실행 → 기본값(화학2)으로 진행
  log "파이프 모드 - 화학Ⅱ(kb2092) 기본값으로 진행"
fi

URL="https://ebook.mirae-n.com/@${KB}/1"
OUTPUT="${NAME}_미래엔.pdf"
log "대상: ${NAME} → ${URL}"

# ═══════════════════════════════════════════
#  1단계: 패키지 설치
# ═══════════════════════════════════════════
echo ""
log "1단계: 패키지 설치..."

if ! command -v pkg &>/dev/null; then
  err "Termux 환경이 아닙니다. 이 스크립트는 Android Termux 전용입니다."
  exit 1
fi

# 스토리지 접근 확인
if [ ! -d "$HOME/storage" ]; then
  warn "스토리지 권한이 없습니다. 설정 중..."
  termux-setup-storage 2>/dev/null || true
  sleep 2
fi

# 필수 패키지 설치
log "시스템 패키지 업데이트..."
yes | pkg update 2>&1 | tail -1 || true

log "Python 설치..."
yes | pkg install -y python 2>&1 | tail -1 || true

# python3 재탐색
PYTHON=""
for p in python3 python; do
  if command -v "$p" &>/dev/null; then
    PYTHON="$p"
    break
  fi
done

if [ -z "$PYTHON" ]; then
  err "Python 설치 실패. 수동으로 실행: pkg install python"
  exit 1
fi
log "Python: $($PYTHON --version 2>&1)"

# pip 재탐색
PIP=""
for p in pip3 pip; do
  if command -v "$p" &>/dev/null; then
    PIP="$p"
    break
  fi
done

if [ -z "$PIP" ]; then
  # pip가 없으면 ensurepip
  $PYTHON -m ensurepip 2>/dev/null || true
  PIP="$PYTHON -m pip"
fi

log "Pillow 설치..."
$PIP install --quiet Pillow 2>&1 | tail -1 || true

# Chromium + Selenium 시도
USE_PLAYWRIGHT=0
log "Chromium 설치 시도..."
if yes | pkg install -y chromium 2>&1 | tail -1; then
  log "Selenium 설치..."
  $PIP install --quiet selenium 2>&1 | tail -1 || true
  ENGINE="selenium"
  log "엔진: Selenium + Chromium"
else
  warn "Chromium 사용 불가 - Playwright로 전환..."
  $PIP install --quiet playwright 2>&1 | tail -1 || true
  $PYTHON -m playwright install chromium 2>&1 | tail -1 || {
    err "Playwright Chromium 설치도 실패"
    err "수동 설치 후 다시 시도: pkg install chromium && pip3 install selenium"
    exit 1
  }
  ENGINE="playwright"
  log "엔진: Playwright"
fi

log "설치 완료!"

# ═══════════════════════════════════════════
#  2단계: 추출 스크립트 생성 + 실행
# ═══════════════════════════════════════════
echo ""
log "2단계: PDF 추출 시작..."

WORK_DIR="$HOME/mirae_ebook"
mkdir -p "$WORK_DIR"

# Python 스크립트 생성
cat > "$WORK_DIR/_extract.py" << 'PYEOF'
#!/usr/bin/env python3
"""Android Termux 미래엔 e-book PDF 추출."""
import argparse, io, os, sys, time, glob

def find_chromium():
    """Termux chromium 바이너리 경로 탐색."""
    candidates = [
        "/data/data/com.termux/files/usr/bin/chromium-browser",
        "/data/data/com.termux/files/usr/bin/chromium",
        "/data/data/com.termux/files/usr/bin/chrome",
        "/data/data/com.termux/files/usr/bin/google-chrome",
    ]
    # glob으로 추가 탐색
    candidates += glob.glob("/data/data/com.termux/files/usr/lib/chromium*/chrome")
    candidates += glob.glob("/data/data/com.termux/files/usr/share/chromium/chrome")
    for p in candidates:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None

def find_chromedriver():
    """chromedriver 경로 탐색."""
    candidates = [
        "/data/data/com.termux/files/usr/bin/chromedriver",
    ]
    candidates += glob.glob("/data/data/com.termux/files/usr/lib/chromium*/chromedriver")
    for p in candidates:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None

def extract_selenium(url, total_pages, output, delay):
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.keys import Keys
    from selenium.webdriver.common.by import By

    print(f"[Selenium] URL: {url}")

    opts = Options()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--disable-software-rasterizer")
    opts.add_argument("--window-size=1200,900")
    opts.add_argument("--lang=ko-KR")
    opts.add_argument("--user-agent=Mozilla/5.0 (Linux; Android 14) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/120.0.0.0 Mobile Safari/537.36")

    chromium = find_chromium()
    if chromium:
        opts.binary_location = chromium
        print(f"  Chromium: {chromium}")

    service_kwargs = {}
    chromedriver = find_chromedriver()
    if chromedriver:
        service_kwargs["executable_path"] = chromedriver
        print(f"  ChromeDriver: {chromedriver}")

    service = Service(**service_kwargs) if service_kwargs else Service()
    driver = webdriver.Chrome(service=service, options=opts)
    driver.set_page_load_timeout(60)

    try:
        print("[1/3] 페이지 로드 중...")
        driver.get(url)
        time.sleep(5)

        images = []
        body = driver.find_element(By.TAG_NAME, "body")

        for i in range(1, total_pages + 1):
            sys.stdout.write(f"\r[2/3] 캡처: {i}/{total_pages}")
            sys.stdout.flush()
            time.sleep(delay)
            png = driver.get_screenshot_as_png()
            images.append(png)
            body.send_keys(Keys.ARROW_RIGHT)

        print(f"\n[3/3] PDF 생성 중... ({len(images)}p)")
        save_pdf(images, output)
    finally:
        driver.quit()

def extract_playwright(url, total_pages, output, delay):
    import asyncio
    async def _run():
        from playwright.async_api import async_playwright
        print(f"[Playwright] URL: {url}")
        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=True,
                args=["--no-sandbox","--disable-dev-shm-usage","--disable-gpu"],
            )
            ctx = await browser.new_context(
                viewport={"width":1200,"height":900}, locale="ko-KR",
            )
            page = await ctx.new_page()
            print("[1/3] 페이지 로드 중...")
            await page.goto(url, wait_until="networkidle", timeout=60000)
            await asyncio.sleep(5)
            images = []
            for i in range(1, total_pages + 1):
                sys.stdout.write(f"\r[2/3] 캡처: {i}/{total_pages}")
                sys.stdout.flush()
                await asyncio.sleep(delay)
                png = await page.screenshot(type="png", full_page=False)
                images.append(png)
                await page.keyboard.press("ArrowRight")
            print(f"\n[3/3] PDF 생성 중... ({len(images)}p)")
            save_pdf(images, output)
            await browser.close()
    asyncio.run(_run())

def save_pdf(image_list, path):
    from PIL import Image
    pil = []
    for data in image_list:
        img = Image.open(io.BytesIO(data)) if isinstance(data, bytes) else data
        if img.mode != "RGB":
            img = img.convert("RGB")
        pil.append(img)
    if not pil:
        print("[ERR] 캡처된 이미지 없음")
        return
    pil[0].save(path, "PDF", save_all=True, append_images=pil[1:], resolution=150)
    mb = os.path.getsize(path) / (1024*1024)
    print(f"[OK] {path} ({len(pil)}p, {mb:.1f}MB)")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--pages", type=int, default=200)
    ap.add_argument("--output", default="output.pdf")
    ap.add_argument("--delay", type=float, default=2.5)
    ap.add_argument("--engine", choices=["selenium","playwright"], default="selenium")
    args = ap.parse_args()
    print("="*50)
    print("  미래엔 교과서 PDF 추출 실행")
    print("="*50)
    if args.engine == "selenium":
        extract_selenium(args.url, args.pages, args.output, args.delay)
    else:
        extract_playwright(args.url, args.pages, args.output, args.delay)
PYEOF

log "추출 스크립트 생성 완료"

# 실행
cd "$WORK_DIR"
log "실행: $PYTHON _extract.py --engine $ENGINE"
echo ""

$PYTHON _extract.py \
  --url "$URL" \
  --pages 200 \
  --output "$OUTPUT" \
  --delay 2.5 \
  --engine "$ENGINE"

RESULT=$?

echo ""

# ═══════════════════════════════════════════
#  3단계: 결과 확인 + 복사
# ═══════════════════════════════════════════
if [ $RESULT -eq 0 ] && [ -f "$WORK_DIR/$OUTPUT" ]; then
  log "PDF 생성 완료: $WORK_DIR/$OUTPUT"
  SIZE=$(du -h "$WORK_DIR/$OUTPUT" | cut -f1)
  log "파일 크기: $SIZE"

  # 다운로드 폴더에 복사
  DL_DIR="/storage/emulated/0/Download"
  if [ -d "$DL_DIR" ]; then
    cp "$WORK_DIR/$OUTPUT" "$DL_DIR/$OUTPUT" 2>/dev/null && \
      log "다운로드 폴더에 복사됨: $DL_DIR/$OUTPUT" || \
      warn "다운로드 폴더 복사 실패. 실행: termux-setup-storage"
  else
    warn "다운로드 폴더 없음. PDF 위치: $WORK_DIR/$OUTPUT"
    warn "스토리지 접근 허용: termux-setup-storage"
  fi

  echo ""
  echo -e "${G}════════════════════════════════════════${NC}"
  echo -e "${G}  완료! PDF 파일이 생성되었습니다.${NC}"
  echo -e "${G}════════════════════════════════════════${NC}"
else
  err "PDF 생성 실패 (exit code: $RESULT)"
  err "로그 확인 후 다시 시도하세요."
  echo ""
  echo "디버깅 팁:"
  echo "  1) $PYTHON --version"
  echo "  2) $PIP list | grep -i -E 'selenium|playwright|pillow'"
  echo "  3) which chromium-browser || which chromium"
  echo "  4) 수동 실행: cd $WORK_DIR && $PYTHON _extract.py --url '$URL' --pages 10 --output test.pdf --engine $ENGINE"
  exit 1
fi
