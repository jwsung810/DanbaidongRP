#!/usr/bin/env python3
"""
미래엔 교과서 E-book PDF 추출 도구
===================================
ebook.mirae-n.com 뷰어에서 교과서 페이지를 캡처하여 PDF로 변환합니다.

사용법:
    pip install playwright Pillow
    playwright install chromium
    python extract_mirae_ebook.py --url "https://ebook.mirae-n.com/@kb2092/1" --pages 200 --output "화학2_미래엔.pdf"

주요 옵션:
    --url       E-book 뷰어 URL (기본값: 화학Ⅱ)
    --pages     총 페이지 수 (기본값: 200)
    --output    출력 PDF 파일명
    --delay     페이지 전환 대기 시간(초) (기본값: 2.0)
    --method    추출 방법: screenshot | network (기본값: screenshot)
"""

import argparse
import asyncio
import io
import os
import sys
import time
from pathlib import Path

# KB 코드 매핑 (미래엔 15개정 고등학교 과학)
KB_CODES = {
    "통합과학": "kb2083",
    "과학탐구실험": "kb2090",
    "물리학1": "kb2084",
    "물리학2": "kb2085",
    "화학1": "kb2091",
    "화학2": "kb2092",
    "생명과학1": "kb2086",
    "생명과학2": "kb2087",
    "지구과학1": "kb2088",
    "지구과학2": "kb2089",
}

DEFAULT_URL = "https://ebook.mirae-n.com/@kb2092/1"


async def extract_via_screenshot(url: str, total_pages: int, output: str, delay: float):
    """스크린샷 기반 추출: 각 페이지를 캡처 후 PDF로 합침."""
    from playwright.async_api import async_playwright

    print(f"[*] 스크린샷 방식으로 추출 시작")
    print(f"    URL: {url}")
    print(f"    페이지 수: {total_pages}")
    print(f"    출력: {output}")
    print(f"    딜레이: {delay}초")
    print()

    images = []

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)  # 렌더링을 위해 headless=False
        context = await browser.new_context(
            viewport={"width": 1400, "height": 1000},
            locale="ko-KR",
        )
        page = await context.new_page()

        print(f"[1] 페이지 로드 중: {url}")
        await page.goto(url, wait_until="networkidle", timeout=60000)
        await asyncio.sleep(3)  # 뷰어 초기화 대기

        # 뷰어 영역 탐지 시도
        viewer_selector = await _detect_viewer_area(page)
        if viewer_selector:
            print(f"[*] 뷰어 영역 감지됨: {viewer_selector}")
        else:
            print("[*] 뷰어 영역을 자동 감지하지 못함 - 전체 페이지 캡처")

        for i in range(1, total_pages + 1):
            print(f"\r[2] 캡처 중: {i}/{total_pages}", end="", flush=True)

            await asyncio.sleep(delay)

            # 캡처
            if viewer_selector:
                element = page.locator(viewer_selector).first
                screenshot = await element.screenshot(type="png")
            else:
                screenshot = await page.screenshot(type="png", full_page=False)

            images.append(screenshot)

            # 다음 페이지로 이동 (오른쪽 화살표 키)
            await page.keyboard.press("ArrowRight")

        print(f"\n[3] PDF 생성 중...")
        _images_to_pdf(images, output)

        await browser.close()

    print(f"[완료] PDF 저장됨: {output}")


async def extract_via_network(url: str, total_pages: int, output: str, delay: float):
    """네트워크 인터셉트 방식: 뷰어가 로드하는 원본 이미지를 캡처."""
    from playwright.async_api import async_playwright

    print(f"[*] 네트워크 인터셉트 방식으로 추출 시작")
    print(f"    URL: {url}")
    print(f"    페이지 수: {total_pages}")
    print(f"    출력: {output}")
    print()

    captured_images = {}

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)
        context = await browser.new_context(
            viewport={"width": 1400, "height": 1000},
            locale="ko-KR",
        )
        page = await context.new_page()

        # 네트워크 응답 인터셉트
        async def handle_response(response):
            content_type = response.headers.get("content-type", "")
            req_url = response.url
            if any(
                ct in content_type
                for ct in ["image/jpeg", "image/png", "image/webp"]
            ):
                # 페이지 이미지로 보이는 큰 이미지만 캡처
                try:
                    body = await response.body()
                    if len(body) > 50000:  # 50KB 이상만 (작은 아이콘 제외)
                        idx = len(captured_images)
                        captured_images[idx] = body
                        print(f"\r    이미지 캡처: {idx + 1}개 ({len(body)//1024}KB) - {req_url[:80]}...", end="", flush=True)
                except Exception:
                    pass

        page.on("response", handle_response)

        print(f"[1] 페이지 로드 중: {url}")
        await page.goto(url, wait_until="networkidle", timeout=60000)
        await asyncio.sleep(3)

        print(f"[2] 페이지 순회 중...")
        for i in range(1, total_pages + 1):
            await page.keyboard.press("ArrowRight")
            await asyncio.sleep(delay)

        print(f"\n[3] PDF 생성 중... (캡처된 이미지: {len(captured_images)}개)")

        if captured_images:
            sorted_images = [captured_images[k] for k in sorted(captured_images.keys())]
            _images_to_pdf(sorted_images, output)
            print(f"[완료] PDF 저장됨: {output}")
        else:
            print("[오류] 캡처된 이미지가 없습니다. screenshot 방식을 사용해보세요.")

        await browser.close()


async def extract_via_console(url: str, total_pages: int, output: str, delay: float):
    """
    브라우저 콘솔을 통해 뷰어 DOM에서 이미지 URL을 직접 추출하는 방식.
    뷰어 구조에 따라 작동하지 않을 수 있음.
    """
    from playwright.async_api import async_playwright

    print(f"[*] DOM 분석 방식으로 추출 시작")
    print(f"    URL: {url}")
    print()

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)
        context = await browser.new_context(
            viewport={"width": 1400, "height": 1000},
            locale="ko-KR",
        )
        page = await context.new_page()

        print(f"[1] 페이지 로드 중...")
        await page.goto(url, wait_until="networkidle", timeout=60000)
        await asyncio.sleep(5)

        # DOM 구조 분석
        print(f"[2] DOM 구조 분석 중...")
        structure = await page.evaluate("""() => {
            const result = {
                title: document.title,
                iframes: Array.from(document.querySelectorAll('iframe')).map(f => f.src),
                canvases: document.querySelectorAll('canvas').length,
                largeImages: Array.from(document.querySelectorAll('img'))
                    .filter(img => img.naturalWidth > 200)
                    .map(img => ({src: img.src, w: img.naturalWidth, h: img.naturalHeight})),
                allImages: Array.from(document.querySelectorAll('img')).map(img => img.src),
                objectTags: Array.from(document.querySelectorAll('object, embed')).map(o => o.data || o.src),
                svgs: document.querySelectorAll('svg').length,
                divWithBg: Array.from(document.querySelectorAll('div'))
                    .filter(d => {
                        const bg = getComputedStyle(d).backgroundImage;
                        return bg && bg !== 'none' && bg.includes('url');
                    })
                    .map(d => getComputedStyle(d).backgroundImage)
                    .slice(0, 20),
            };
            return result;
        }""")

        print(f"\n=== 뷰어 구조 분석 결과 ===")
        print(f"  제목: {structure.get('title', 'N/A')}")
        print(f"  iframe 수: {len(structure.get('iframes', []))}")
        for iframe_url in structure.get('iframes', []):
            print(f"    - {iframe_url}")
        print(f"  canvas 수: {structure.get('canvases', 0)}")
        print(f"  큰 이미지 수: {len(structure.get('largeImages', []))}")
        for img in structure.get('largeImages', []):
            print(f"    - {img['w']}x{img['h']}: {img['src'][:100]}")
        print(f"  전체 이미지 수: {len(structure.get('allImages', []))}")
        print(f"  object/embed 수: {len(structure.get('objectTags', []))}")
        for obj_url in structure.get('objectTags', []):
            print(f"    - {obj_url}")
        print(f"  SVG 수: {structure.get('svgs', 0)}")
        print(f"  배경 이미지 div 수: {len(structure.get('divWithBg', []))}")
        for bg in structure.get('divWithBg', [])[:5]:
            print(f"    - {bg[:100]}")
        print(f"===========================\n")

        # 분석 결과에 따라 이미지 URL 패턴 파악
        print("[*] 이 정보를 바탕으로 스크립트를 커스터마이즈할 수 있습니다.")
        print("[*] screenshot 방식이 가장 안정적입니다.")

        input("\n[Enter를 눌러 브라우저를 닫습니다...]")
        await browser.close()


async def _detect_viewer_area(page):
    """뷰어의 메인 콘텐츠 영역을 자동 감지."""
    selectors_to_try = [
        # 일반적인 ebook 뷰어 셀렉터들
        "#viewer",
        "#book-viewer",
        ".book-viewer",
        ".viewer-container",
        "#page-container",
        ".page-container",
        "#content-viewer",
        ".content-area",
        'canvas[class*="page"]',
        'canvas[id*="page"]',
        'div[class*="viewer"]',
        'div[class*="book"]',
        "#nexbook-viewer",
        ".nexbook-container",
        'div[class*="nexbook"]',
        # FlipBook 관련
        'div[class*="flip"]',
        ".turn-page",
        "#flipbook",
    ]

    for selector in selectors_to_try:
        try:
            count = await page.locator(selector).count()
            if count > 0:
                box = await page.locator(selector).first.bounding_box()
                if box and box["width"] > 300 and box["height"] > 300:
                    return selector
        except Exception:
            continue

    return None


def _images_to_pdf(image_data_list: list, output_path: str):
    """이미지 데이터 리스트를 PDF로 변환."""
    from PIL import Image

    if not image_data_list:
        print("[오류] 변환할 이미지가 없습니다.")
        return

    pil_images = []
    for data in image_data_list:
        img = Image.open(io.BytesIO(data))
        if img.mode == "RGBA":
            img = img.convert("RGB")
        elif img.mode != "RGB":
            img = img.convert("RGB")
        pil_images.append(img)

    if pil_images:
        first = pil_images[0]
        rest = pil_images[1:] if len(pil_images) > 1 else []
        first.save(output_path, "PDF", save_all=True, append_images=rest, resolution=150)
        print(f"    → {len(pil_images)}페이지, 크기: {os.path.getsize(output_path) // 1024}KB")


def main():
    parser = argparse.ArgumentParser(
        description="미래엔 교과서 E-book PDF 추출 도구",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 화학Ⅱ 추출 (기본)
  python extract_mirae_ebook.py

  # 화학Ⅰ 추출
  python extract_mirae_ebook.py --url "https://ebook.mirae-n.com/@kb2091/1"

  # 네트워크 인터셉트 방식
  python extract_mirae_ebook.py --method network

  # DOM 분석 (뷰어 구조 확인용)
  python extract_mirae_ebook.py --method console

KB 코드 목록 (미래엔 15개정 고등학교):
  통합과학: kb2083    과학탐구실험: kb2090
  물리학Ⅰ: kb2084    물리학Ⅱ: kb2085
  화학Ⅰ:   kb2091    화학Ⅱ:   kb2092
  생명과학Ⅰ: kb2086  생명과학Ⅱ: kb2087
  지구과학Ⅰ: kb2088  지구과학Ⅱ: kb2089
        """,
    )

    parser.add_argument(
        "--url", default=DEFAULT_URL,
        help="E-book 뷰어 URL (기본값: 화학Ⅱ)",
    )
    parser.add_argument(
        "--pages", type=int, default=200,
        help="총 페이지 수 (기본값: 200)",
    )
    parser.add_argument(
        "--output", default="화학2_미래엔.pdf",
        help="출력 PDF 파일명 (기본값: 화학2_미래엔.pdf)",
    )
    parser.add_argument(
        "--delay", type=float, default=2.0,
        help="페이지 전환 대기 시간(초) (기본값: 2.0)",
    )
    parser.add_argument(
        "--method", choices=["screenshot", "network", "console"],
        default="screenshot",
        help="추출 방법 (기본값: screenshot)",
    )

    args = parser.parse_args()

    print("=" * 60)
    print("  미래엔 교과서 E-book PDF 추출 도구")
    print("=" * 60)
    print()

    if args.method == "screenshot":
        asyncio.run(extract_via_screenshot(args.url, args.pages, args.output, args.delay))
    elif args.method == "network":
        asyncio.run(extract_via_network(args.url, args.pages, args.output, args.delay))
    elif args.method == "console":
        asyncio.run(extract_via_console(args.url, args.pages, args.output, args.delay))


if __name__ == "__main__":
    main()
