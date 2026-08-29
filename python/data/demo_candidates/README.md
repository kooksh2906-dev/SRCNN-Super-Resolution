# SRCNN 데모 이미지 후보

`cvpr_dataset`의 16,227장(모두 256×256)에서 윤곽선 밀도와 대비를 기준으로 1차 선별하고, 실제 Python INT16 Backend로 Bicubic 대비 Y-PSNR 개선을 확인한 이미지다.

| 순서 | 파일 | 주요 비교 영역 | Bicubic | SRCNN | 개선 |
|---:|---|---|---:|---:|---:|
| 1 | `01_glass_roof.jpg` | 유리 천장 격자와 방사형 직선 | 21.346 dB | 22.721 dB | +1.374 dB |
| 2 | `02_aerial_city.jpg` | 건물, 도로, 도시 격자 | 20.825 dB | 22.145 dB | +1.320 dB |
| 3 | `03_ice_waterfall.jpg` | 얼음, 바위, 나뭇가지 | 21.250 dB | 22.033 dB | +0.783 dB |
| 4 | `04_snow_cabin.jpg` | 얇은 나뭇가지와 오두막 윤곽 | 19.945 dB | 20.596 dB | +0.650 dB |
| 5 | `05_reeds.jpg` | 반복되는 가는 갈대 질감 | 20.561 dB | 21.111 dB | +0.550 dB |
| 6 | `06_beard.jpg` | 수염과 얼굴 윤곽 | 24.329 dB | 25.022 dB | +0.693 dB |
| 7 | `07_hair.jpg` | 머리카락과 눈썹 | 22.248 dB | 22.809 dB | +0.561 dB |
| 8 | `08_scarf_texture.jpg` | 스카프의 반복 패턴 | 20.064 dB | 20.512 dB | +0.449 dB |

최종 시연 1순위는 `01_glass_roof.jpg`, 인물 비교 1순위는 `06_beard.jpg`다. 모든 이미지는 평가용 HR 256×256이므로 Web UI가 내부에서 LR 128×128을 생성하고 HR/Bicubic/SRCNN Y-PSNR을 표시한다.

원본 `cvpr_dataset` 파일은 수정하지 않았으며 이 폴더에는 복사본만 저장했다.
