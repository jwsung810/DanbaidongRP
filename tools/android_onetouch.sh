#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  미래엔 교과서 PDF 원터치 추출 (Android Termux)
# ============================================================
#
#  사용법:
#    curl -sLO https://raw.githubusercontent.com/jwsung810/DanbaidongRP/claude/extract-chemistry-pdf-L1owt/tools/android_onetouch.sh
#    bash android_onetouch.sh
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

# ── 과목 선택 ──
KB="kb2092"; NAME="화학2"
if [ -t 0 ]; then
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
  log "파이프 모드 - 화학Ⅱ(kb2092) 기본값"
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
  err "Termux가 아닙니다."
  exit 1
fi

# 스토리지 권한
if [ ! -d "$HOME/storage" ]; then
  warn "스토리지 권한 설정..."
  termux-setup-storage 2>/dev/null || true
  sleep 2
fi

# Python 설치
log "Python 설치..."
yes | pkg update -y 2>&1 | tail -3
yes | pkg install -y python 2>&1 | tail -1

# python3/pip3 탐색
PY=""; for p in python3 python; do command -v "$p" &>/dev/null && PY="$p" && break; done
PP=""; for p in pip3 pip; do command -v "$p" &>/dev/null && PP="$p" && break; done
if [ -z "$PY" ]; then err "Python 없음"; exit 1; fi
if [ -z "$PP" ]; then PP="$PY -m pip"; fi
log "Python: $($PY --version 2>&1)"

# Pillow
log "Pillow 설치..."
$PP install --quiet Pillow 2>&1 | tail -1 || true

# ── Chromium 설치: tur-repo 시도 ──
CHROMIUM_OK=0

log "Chromium 설치 시도 (tur-repo)..."
yes | pkg install -y tur-repo 2>&1 | tail -1 || true
if yes | pkg install -y chromium 2>&1 | tail -1; then
  CHROMIUM_OK=1
fi

if [ "$CHROMIUM_OK" -eq 0 ]; then
  # x11-repo도 시도
  log "x11-repo에서 시도..."
  yes | pkg install -y x11-repo 2>&1 | tail -1 || true
  if yes | pkg install -y chromium 2>&1 | tail -1; then
    CHROMIUM_OK=1
  fi
fi

if [ "$CHROMIUM_OK" -eq 1 ]; then
  log "Selenium 설치..."
  $PP install --quiet selenium 2>&1 | tail -1 || true
  ENGINE="selenium"
  log "엔진: Selenium + Chromium (Termux)"
else
  # ── Chromium 실패: Android Chrome + CDP 방식 ──
  warn "Termux Chromium 설치 불가"
  warn "Android Chrome + CDP(DevTools Protocol) 방식으로 전환"
  $PP install --quiet selenium 2>&1 | tail -1 || true
  ENGINE="cdp"
  log "엔진: Android Chrome (CDP)"
fi

log "설치 완료!"

# ═══════════════════════════════════════════
#  2단계: 추출 스크립트 생성 + 실행
# ═══════════════════════════════════════════
echo ""
log "2단계: PDF 추출..."

WORK_DIR="$HOME/mirae_ebook"
mkdir -p "$WORK_DIR"

cat > "$WORK_DIR/_extract.py" << 'PYEOF'
#!/usr/bin/env python3
"""Android Termux 미래엔 e-book PDF 추출 (3가지 엔진)."""
import argparse, io, os, sys, time, glob, subprocess, json

def find_binary(names, search_dirs=None):
    dirs = search_dirs or [
        "/data/data/com.termux/files/usr/bin",
        "/data/data/com.termux/files/usr/lib",
    ]
    for name in names:
        for d in dirs:
            for path in glob.glob(os.path.join(d, "**", name), recursive=True):
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    return path
    return None

# ═══════════════════════════════════════
#  엔진 1: Selenium + Termux Chromium
# ═══════════════════════════════════════
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

    chromium = find_binary(["chromium-browser", "chromium", "chrome"])
    if chromium:
        opts.binary_location = chromium
        print(f"  Chromium: {chromium}")

    chromedriver = find_binary(["chromedriver"])
    svc = Service(executable_path=chromedriver) if chromedriver else Service()
    driver = webdriver.Chrome(service=svc, options=opts)
    driver.set_page_load_timeout(60)

    try:
        print("[1/3] 로드...")
        driver.get(url)
        time.sleep(5)
        images = []
        body = driver.find_element(By.TAG_NAME, "body")
        for i in range(1, total_pages + 1):
            sys.stdout.write(f"\r[2/3] 캡처: {i}/{total_pages}")
            sys.stdout.flush()
            time.sleep(delay)
            images.append(driver.get_screenshot_as_png())
            body.send_keys(Keys.ARROW_RIGHT)
        print(f"\n[3/3] PDF ({len(images)}p)...")
        save_pdf(images, output)
    finally:
        driver.quit()

# ═══════════════════════════════════════
#  엔진 2: Android Chrome via CDP
# ═══════════════════════════════════════
def extract_cdp(url, total_pages, output, delay):
    """Android Chrome을 DevTools Protocol로 제어."""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.common.keys import Keys
    from selenium.webdriver.common.by import By

    CDP_PORT = 9222

    print("[CDP] Android Chrome 제어 모드")
    print("")
    print("="*50)
    print("  준비 작업 (최초 1회)")
    print("="*50)
    print("")
    print("  Chrome을 디버그 모드로 시작해야 합니다.")
    print("")
    print("  방법 A) Chrome 플래그 설정:")
    print("    1. Chrome 주소창에 chrome://flags 입력")
    print("    2. 'command line' 검색")
    print("    3. 'Enable command line on non-rooted devices' → Enabled")
    print("    4. Chrome 재시작")
    print("")
    print("  방법 B) Termux에서 실행:")
    print(f"    am start -n com.android.chrome/com.google.android.apps.chrome.Main \\")
    print(f"      -d '{url}'")
    print("")
    print("="*50)
    print("")

    # Chrome이 이미 디버그 포트를 열고 있는지 확인
    import urllib.request
    debug_ready = False
    try:
        req = urllib.request.urlopen(f"http://localhost:{CDP_PORT}/json/version", timeout=3)
        info = json.loads(req.read())
        print(f"[OK] Chrome 디버그 포트 감지: {info.get('Browser','Chrome')}")
        debug_ready = True
    except Exception:
        pass

    if not debug_ready:
        # adb forward 시도 (Wireless Debugging 또는 USB ADB)
        print("[*] Chrome 디버그 포트 연결 시도 중...")

        # 1) adb forward를 통해 Chrome devtools 소켓 연결
        try:
            subprocess.run(
                ["adb", "forward", f"tcp:{CDP_PORT}", "localabstract:chrome_devtools_remote"],
                capture_output=True, timeout=5
            )
            # 재확인
            req = urllib.request.urlopen(f"http://localhost:{CDP_PORT}/json/version", timeout=3)
            info = json.loads(req.read())
            print(f"[OK] ADB forward 성공: {info.get('Browser','Chrome')}")
            debug_ready = True
        except Exception:
            pass

    if not debug_ready:
        print("")
        err_msg = """[!] Chrome 디버그 포트에 연결할 수 없습니다.

다음 중 하나를 시도하세요:

  (1) Chrome을 디버그 모드로 실행:
      Termux에서:
        am start -a android.intent.action.MAIN \\
          -n com.android.chrome/com.google.android.apps.chrome.Main

      그리고 Wireless Debugging 활성화 후:
        adb forward tcp:9222 localabstract:chrome_devtools_remote

  (2) 더 간단한 방법 - 북마클릿 사용:
      Chrome에서 직접 ebook.mirae-n.com 열고
      북마클릿 실행 (bookmarklet.html 참조)

  (3) PC에서 실행:
      pip install playwright Pillow
      playwright install chromium
      python extract_mirae_ebook.py
"""
        print(err_msg)

        # 대안: 북마클릿 서버 제공
        print("[*] 대안: 로컬 북마클릿 서버를 시작합니다...")
        start_bookmarklet_server(url, total_pages, delay)
        return

    # CDP로 Selenium 연결
    opts = Options()
    opts.add_experimental_option("debuggerAddress", f"127.0.0.1:{CDP_PORT}")

    driver = webdriver.Chrome(options=opts)
    print(f"[1/3] {url} 로드...")
    driver.get(url)
    time.sleep(5)

    images = []
    body = driver.find_element(By.TAG_NAME, "body")
    for i in range(1, total_pages + 1):
        sys.stdout.write(f"\r[2/3] 캡처: {i}/{total_pages}")
        sys.stdout.flush()
        time.sleep(delay)
        images.append(driver.get_screenshot_as_png())
        body.send_keys(Keys.ARROW_RIGHT)

    print(f"\n[3/3] PDF ({len(images)}p)...")
    save_pdf(images, output)
    # CDP 모드에서는 브라우저 닫지 않음

# ═══════════════════════════════════════
#  대안: 로컬 북마클릿 서버
# ═══════════════════════════════════════
def start_bookmarklet_server(ebook_url, total_pages, delay_sec):
    """로컬 HTTP 서버로 북마클릿 페이지 제공 → Chrome에서 열기."""
    import http.server, threading, webbrowser

    PORT = 8765
    delay_ms = int(delay_sec * 1000)

    html = f'''<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PDF 추출</title>
<style>
body{{font-family:sans-serif;background:#111;color:#eee;padding:20px;text-align:center}}
.btn{{display:block;width:90%;max-width:400px;margin:16px auto;padding:16px;
border:none;border-radius:12px;font-size:1.1em;font-weight:bold;cursor:pointer}}
.blue{{background:#2563eb;color:#fff}}.green{{background:#059669;color:#fff}}
.code{{background:#222;color:#0f0;padding:12px;border-radius:8px;font:0.7em monospace;
word-break:break-all;text-align:left;margin:12px 0;user-select:all}}
#status{{margin:16px 0;padding:12px;border-radius:8px;display:none}}
</style></head><body>
<h2>미래엔 교과서 PDF 추출</h2>
<p style="color:#999">Step 1: 교과서를 엽니다</p>
<a class="btn blue" href="{ebook_url}" target="_blank"
   onclick="document.getElementById('s2').style.display='block'">
  교과서 열기</a>
<div id="s2" style="display:none">
<p style="color:#999">Step 2: 뷰어가 로드되면 아래 코드를 복사합니다</p>
<p style="color:#fbbf24;font-size:0.85em">Chrome 주소창에 붙여넣기 → 실행</p>
<div class="code" id="bmcode"></div>
<button class="btn green" onclick="copyCode()">코드 복사</button>
<div id="status"></div>
</div>
<script>
var bm="javascript:void(function(){{var d=document,total={total_pages},delay={delay_ms};"
+"var s=d.createElement('script');"
+"s.src='https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';"
+"s.onload=function(){{var st=d.createElement('div');"
+"st.style.cssText='position:fixed;top:10px;left:50%;transform:translateX(-50%);z-index:99999;"
+"background:rgba(0,0,0,0.9);color:#0f0;padding:15px 25px;border-radius:12px;"
+"font:16px monospace;text-align:center;min-width:250px';"
+"d.body.appendChild(st);var pages=[],pg=0;"
+"function grab(){{var b=null,mx=0;d.querySelectorAll('canvas').forEach(function(c){{"
+"var a=c.width*c.height;if(a>mx){{mx=a;b=c}}}});"
+"if(b)try{{return b.toDataURL('image/jpeg',0.85)}}catch(e){{}}"
+"b=null;mx=0;d.querySelectorAll('img').forEach(function(m){{"
+"var a=m.naturalWidth*m.naturalHeight;if(a>mx){{mx=a;b=m}}}});"
+"if(b)return b.src;return null}}"
+"function cap(){{pg++;st.textContent='캡처: '+pg+'/'+total;"
+"var src=grab();if(src)pages.push(src);"
+"if(pg>=total){{st.textContent='PDF 생성 중...('+pages.length+'p)';"
+"setTimeout(function(){{mk(pages,st)}},500);return}}"
+"var e=new KeyboardEvent('keydown',{{key:'ArrowRight',code:'ArrowRight',keyCode:39,bubbles:true}});"
+"d.dispatchEvent(e);d.body.dispatchEvent(e);"
+"d.querySelectorAll('[class*=next],[class*=right],[class*=forward]')"
+".forEach(function(el){{try{{el.click()}}catch(x){{}}}});setTimeout(cap,delay)}}"
+"function mk(p,st){{if(!p.length){{st.textContent='ERROR: 이미지 없음';return}}"
+"var J=window.jspdf.jsPDF,im=new Image;im.onload=function(){{"
+"var w=im.width,h=im.height,pdf=new J({{orientation:w>h?'l':'p',unit:'px',format:[w,h]}});"
+"for(var i=0;i<p.length;i++){{st.textContent='PDF: '+(i+1)+'/'+p.length;"
+"if(i>0)pdf.addPage([w,h],w>h?'l':'p');"
+"try{{pdf.addImage(p[i],'JPEG',0,0,w,h)}}catch(x){{}}}}"
+"pdf.save('미래엔_교과서.pdf');st.textContent='완료! ('+p.length+'p)';"
+"st.style.background='#006400'}};im.src=p[0]}}"
+"setTimeout(cap,2000)}};d.head.appendChild(s)}}())";
document.getElementById('bmcode').textContent=bm;
function copyCode(){{
  navigator.clipboard.writeText(bm).then(
    function(){{show('복사 완료! Chrome 주소창에 붙여넣기','#059669')}},
    function(){{
      var r=document.createRange();
      r.selectNodeContents(document.getElementById('bmcode'));
      window.getSelection().removeAllRanges();
      window.getSelection().addRange(r);
      show('텍스트 선택됨 - 수동 복사하세요','#d97706')
    }}
  )
}}
function show(t,c){{var e=document.getElementById('status');e.style.display='block';e.style.background=c;e.textContent=t}}
</script></body></html>'''

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html.encode())
        def log_message(self, format, *args):
            pass  # 로그 숨김

    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    local_url = f"http://127.0.0.1:{PORT}"
    print(f"")
    print(f"[OK] 로컬 서버 시작: {local_url}")
    print(f"")
    print(f"  Chrome에서 이 주소를 여세요: {local_url}")
    print(f"")

    # Chrome 자동 열기 시도
    try:
        subprocess.run(
            ["am", "start", "-a", "android.intent.action.VIEW", "-d", local_url],
            capture_output=True, timeout=5
        )
        print("[OK] Chrome이 열렸습니다. 화면의 안내를 따라주세요.")
    except Exception:
        print("[!!] 수동으로 Chrome에서 위 주소를 열어주세요.")

    print("")
    print("서버 실행 중... (Ctrl+C로 종료)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n서버 종료.")

# ═══════════════════════════════════════
#  공통: PDF 저장
# ═══════════════════════════════════════
def save_pdf(image_list, path):
    from PIL import Image
    pil = []
    for data in image_list:
        img = Image.open(io.BytesIO(data)) if isinstance(data, bytes) else data
        if img.mode != "RGB": img = img.convert("RGB")
        pil.append(img)
    if not pil:
        print("[ERR] 이미지 없음")
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
    ap.add_argument("--engine", choices=["selenium","cdp"], default="selenium")
    args = ap.parse_args()
    print("="*50)
    print("  미래엔 교과서 PDF 추출")
    print("="*50)
    if args.engine == "selenium":
        extract_selenium(args.url, args.pages, args.output, args.delay)
    else:
        extract_cdp(args.url, args.pages, args.output, args.delay)
PYEOF

log "스크립트 생성 완료"

# 실행
cd "$WORK_DIR"
log "실행: $PY _extract.py --engine $ENGINE"
echo ""

$PY _extract.py \
  --url "$URL" \
  --pages 200 \
  --output "$OUTPUT" \
  --delay 2.5 \
  --engine "$ENGINE"

RESULT=$?
echo ""

# ═══════════════════════════════════════════
#  3단계: 결과
# ═══════════════════════════════════════════
if [ $RESULT -eq 0 ] && [ -f "$WORK_DIR/$OUTPUT" ]; then
  log "PDF 완료: $WORK_DIR/$OUTPUT"
  SIZE=$(du -h "$WORK_DIR/$OUTPUT" | cut -f1)
  log "크기: $SIZE"

  DL="/storage/emulated/0/Download"
  if [ -d "$DL" ]; then
    cp "$WORK_DIR/$OUTPUT" "$DL/$OUTPUT" 2>/dev/null && \
      log "다운로드 폴더: $DL/$OUTPUT" || \
      warn "복사 실패. 실행: termux-setup-storage"
  fi

  echo ""
  echo -e "${G}════════════════════════════════════════${NC}"
  echo -e "${G}  완료! PDF가 생성되었습니다.${NC}"
  echo -e "${G}════════════════════════════════════════${NC}"
fi
