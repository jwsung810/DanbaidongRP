#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  미래엔 교과서 PDF 원터치 추출 (Android Termux)
# ============================================================
#
#  사용법: Termux에서 아래 한 줄 복사+붙여넣기
#
#    curl -sL https://raw.githubusercontent.com/jwsung810/DanbaidongRP/claude/extract-chemistry-pdf-L1owt/tools/android_onetouch.sh | bash
#
#  또는 로컬 실행:
#    bash android_onetouch.sh
#
# ============================================================

set -e

# ── 색상 ──
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

banner() {
  echo ""
  echo -e "${C}╔══════════════════════════════════════════╗${NC}"
  echo -e "${C}║  미래엔 교과서 PDF 원터치 추출 (Android) ║${NC}"
  echo -e "${C}╚══════════════════════════════════════════╝${NC}"
  echo ""
}

log()  { echo -e "${G}[✓]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err()  { echo -e "${R}[✗]${NC} $1"; }

# ── 과목 선택 메뉴 ──
select_subject() {
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
  echo "  0) 직접 입력"
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
    0)
      echo -n "KB 코드 입력 (예: kb2092): "
      read -r KB
      echo -n "파일명 입력 (예: 화학2): "
      read -r NAME
      ;;
    *) KB="kb2092"; NAME="화학2" ;;
  esac

  URL="https://ebook.mirae-n.com/@${KB}/1"
  OUTPUT="${NAME}_미래엔.pdf"
  log "선택: ${NAME} → ${URL}"
}

# ── 1단계: 환경 설정 ──
setup_environment() {
  log "1단계: 환경 설정 중..."

  # Termux 패키지 업데이트
  if command -v pkg &>/dev/null; then
    pkg update -y 2>/dev/null || true
    pkg install -y python chromium 2>/dev/null || {
      warn "chromium 설치 실패 - selenium 대신 playwright 시도"
      USE_PLAYWRIGHT=1
    }
  else
    err "Termux 환경이 아닙니다."
    err "이 스크립트는 Android Termux에서 실행해야 합니다."
    exit 1
  fi

  # Python 패키지 설치
  pip install --quiet --upgrade pip 2>/dev/null
  pip install --quiet Pillow 2>/dev/null

  if [ -z "$USE_PLAYWRIGHT" ]; then
    pip install --quiet selenium 2>/dev/null
    log "Selenium + Chromium 모드"
  else
    pip install --quiet playwright 2>/dev/null
    python -m playwright install chromium 2>/dev/null || {
      err "Playwright Chromium 설치 실패"
      err "수동 설치: pip install playwright && playwright install chromium"
      exit 1
    }
    log "Playwright 모드"
  fi

  log "환경 설정 완료"
}

# ── 2단계: 추출 스크립트 생성 + 실행 ──
run_extraction() {
  log "2단계: PDF 추출 시작..."

  WORK_DIR="$HOME/mirae_ebook"
  mkdir -p "$WORK_DIR"

  # Python 추출 스크립트 생성
  cat > "$WORK_DIR/_extract.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""Android Termux용 미래엔 e-book PDF 추출."""
import argparse
import io
import os
import sys
import time

def extract_selenium(url, total_pages, output, delay):
    """Selenium + Chromium 방식."""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.keys import Keys
    from selenium.webdriver.common.by import By
    from PIL import Image

    print(f"[Selenium] 시작: {url}")

    opts = Options()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--window-size=1200,900")
    opts.add_argument("--lang=ko-KR")
    opts.add_argument("--user-agent=Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")

    # Termux chromium 경로 자동 감지
    chromium_paths = [
        "/data/data/com.termux/files/usr/bin/chromium-browser",
        "/data/data/com.termux/files/usr/bin/chromium",
        "/data/data/com.termux/files/usr/bin/chrome",
    ]
    for p in chromium_paths:
        if os.path.exists(p):
            opts.binary_location = p
            break

    driver = webdriver.Chrome(options=opts)
    driver.set_page_load_timeout(60)

    try:
        print("[1/3] 페이지 로드 중...")
        driver.get(url)
        time.sleep(5)  # 뷰어 초기화 대기

        images = []
        body = driver.find_element(By.TAG_NAME, "body")

        for i in range(1, total_pages + 1):
            sys.stdout.write(f"\r[2/3] 캡처: {i}/{total_pages}")
            sys.stdout.flush()

            time.sleep(delay)

            # 스크린샷 캡처
            png = driver.get_screenshot_as_png()
            images.append(png)

            # 다음 페이지
            body.send_keys(Keys.ARROW_RIGHT)

        print(f"\n[3/3] PDF 생성 중... ({len(images)}페이지)")
        _save_pdf(images, output)

    finally:
        driver.quit()


def extract_playwright(url, total_pages, output, delay):
    """Playwright + Chromium 방식."""
    import asyncio

    async def _run():
        from playwright.async_api import async_playwright
        from PIL import Image

        print(f"[Playwright] 시작: {url}")

        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=True,
                args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
            )
            context = await browser.new_context(
                viewport={"width": 1200, "height": 900},
                locale="ko-KR",
                user_agent="Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            )
            page = await context.new_page()

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

            print(f"\n[3/3] PDF 생성 중... ({len(images)}페이지)")
            _save_pdf(images, output)

            await browser.close()

    asyncio.run(_run())


def _save_pdf(image_data_list, output_path):
    """이미지 리스트 → PDF."""
    from PIL import Image

    pil_images = []
    for data in image_data_list:
        if isinstance(data, bytes):
            img = Image.open(io.BytesIO(data))
        else:
            img = data
        if img.mode != "RGB":
            img = img.convert("RGB")
        pil_images.append(img)

    if not pil_images:
        print("[오류] 이미지 없음")
        return

    first = pil_images[0]
    rest = pil_images[1:]
    first.save(output_path, "PDF", save_all=True, append_images=rest, resolution=150)
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"[완료] {output_path} ({len(pil_images)}p, {size_mb:.1f}MB)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--pages", type=int, default=200)
    parser.add_argument("--output", default="output.pdf")
    parser.add_argument("--delay", type=float, default=2.5)
    parser.add_argument("--engine", choices=["selenium", "playwright"], default="selenium")
    args = parser.parse_args()

    if args.engine == "selenium":
        extract_selenium(args.url, args.pages, args.output, args.delay)
    else:
        extract_playwright(args.url, args.pages, args.output, args.delay)
PYTHON_SCRIPT

  # 엔진 선택
  if [ -z "$USE_PLAYWRIGHT" ]; then
    ENGINE="selenium"
  else
    ENGINE="playwright"
  fi

  # 실행
  cd "$WORK_DIR"
  python _extract.py \
    --url "$URL" \
    --pages 200 \
    --output "$OUTPUT" \
    --delay 2.5 \
    --engine "$ENGINE"

  # 결과 확인
  if [ -f "$OUTPUT" ]; then
    log "PDF 생성 완료: $WORK_DIR/$OUTPUT"
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    log "파일 크기: $SIZE"

    # 다운로드 폴더에 복사
    if [ -d "/storage/emulated/0/Download" ]; then
      cp "$OUTPUT" "/storage/emulated/0/Download/$OUTPUT" 2>/dev/null && \
        log "다운로드 폴더에 복사됨: /storage/emulated/0/Download/$OUTPUT" || \
        warn "다운로드 폴더 복사 실패 - termux-setup-storage 실행 필요"
    fi
  else
    err "PDF 생성 실패"
    exit 1
  fi
}

# ── 메인 ──
banner
select_subject
setup_environment
run_extraction

echo ""
echo -e "${G}══════════════════════════════════════════${NC}"
echo -e "${G}  완료! PDF 파일이 생성되었습니다.${NC}"
echo -e "${G}══════════════════════════════════════════${NC}"
echo ""
