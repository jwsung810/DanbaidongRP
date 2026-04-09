# 미래엔 교과서 E-book PDF 추출 가이드

## 대상
- **화학Ⅱ**: `https://ebook.mirae-n.com/@kb2092/1`
- **화학Ⅰ**: `https://ebook.mirae-n.com/@kb2091/1`

---

## 방법 1: Python 스크립트 (권장)

### 설치
```bash
pip install playwright Pillow
playwright install chromium
```

### 실행
```bash
# 화학2 추출 (기본값)
python tools/extract_mirae_ebook.py

# 페이지 수와 딜레이 조정
python tools/extract_mirae_ebook.py --pages 250 --delay 3.0

# 뷰어 구조 분석 (첫 실행 시 권장)
python tools/extract_mirae_ebook.py --method console
```

---

## 방법 2: 브라우저 개발자도구 (수동)

### 단계 1: 뷰어 구조 파악
1. Chrome에서 `https://ebook.mirae-n.com/@kb2092/1` 열기
2. F12 (개발자도구) → Network 탭 열기
3. 페이지를 넘기면서 로드되는 이미지 URL 패턴 확인
4. 이미지 URL의 패턴을 파악 (예: `/pages/1.jpg`, `/pages/2.jpg` 등)

### 단계 2: 콘솔에서 URL 추출
```javascript
// 개발자도구 Console에서 실행
// 현재 로드된 모든 이미지 확인
document.querySelectorAll('img').forEach(img => {
    if (img.naturalWidth > 200) {
        console.log(img.src, img.naturalWidth + 'x' + img.naturalHeight);
    }
});

// canvas 기반 뷰어인 경우
document.querySelectorAll('canvas').forEach((c, i) => {
    console.log(`Canvas ${i}: ${c.width}x${c.height}`);
});

// 배경 이미지 확인
document.querySelectorAll('div').forEach(d => {
    const bg = getComputedStyle(d).backgroundImage;
    if (bg && bg !== 'none' && bg.includes('url')) {
        console.log(bg);
    }
});
```

### 단계 3: Network 탭에서 이미지 URL 패턴 확인
1. Network 탭 → Img 필터 선택
2. 페이지를 한 장 넘김
3. 새로 로드된 이미지 요청의 URL 패턴 확인
4. URL에서 페이지 번호 부분 파악

### 단계 4: 일괄 다운로드 (URL 패턴 파악 후)
```javascript
// 예시: URL 패턴이 확인된 후
// (실제 URL 패턴은 단계 3에서 확인한 것으로 교체)
const baseUrl = 'CDN_BASE_URL_HERE';
const totalPages = 200;

for (let i = 1; i <= totalPages; i++) {
    const url = `${baseUrl}/page_${i}.jpg`;  // 패턴에 맞게 수정
    const a = document.createElement('a');
    a.href = url;
    a.download = `page_${String(i).padStart(3, '0')}.jpg`;
    a.click();
    await new Promise(r => setTimeout(r, 500));
}
```

---

## 방법 3: 인쇄 기능 활용

1. 뷰어에서 인쇄 버튼 클릭 (있는 경우)
2. 프린터를 "PDF로 저장" 선택
3. 전체 페이지 범위 설정 후 저장

---

## KB 코드 참조 (미래엔 15개정 고등학교 과학)

| 과목 | KB 코드 | URL |
|------|---------|-----|
| 통합과학 | kb2083 | `/@kb2083/1` |
| 과학탐구실험 | kb2090 | `/@kb2090/1` |
| 물리학Ⅰ | kb2084 | `/@kb2084/1` |
| 물리학Ⅱ | kb2085 | `/@kb2085/1` |
| 화학Ⅰ | kb2091 | `/@kb2091/1` |
| 화학Ⅱ | kb2092 | `/@kb2092/1` |
| 생명과학Ⅰ | kb2086 | `/@kb2086/1` |
| 생명과학Ⅱ | kb2087 | `/@kb2087/1` |
| 지구과학Ⅰ | kb2088 | `/@kb2088/1` |
| 지구과학Ⅱ | kb2089 | `/@kb2089/1` |

---

## 이미 추출된 버전 (Scribd)

화학2 미래엔 교과서가 Scribd에 업로드되어 있는 것이 확인되었습니다:
- 고2 과학 화학2 미래앤 (15개정교과서): Scribd document/849157583
