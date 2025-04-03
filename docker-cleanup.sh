#!/bin/bash

# 크기를 바이트로 변환하는 함수
function convert_to_bytes {
  local size=$1
  local number=$(echo $size | sed 's/[^0-9.]//g')
  local unit=$(echo $size | sed 's/[0-9.]//g')
  
  case "$unit" in
    K|k)
      echo $(awk "BEGIN {print $number * 1024}")
      ;;
    M|m)
      echo $(awk "BEGIN {print $number * 1024 * 1024}")
      ;;
    G|g)
      echo $(awk "BEGIN {print $number * 1024 * 1024 * 1024}")
      ;;
    T|t)
      echo $(awk "BEGIN {print $number * 1024 * 1024 * 1024 * 1024}")
      ;;
    *)
      echo $number
      ;;
  esac
}

# 스크립트 이름과 사용법을 표시하는 함수
function show_usage {
  echo "사용법: $0 [옵션]"
  echo "옵션:"
  echo "  -p, --path PATH     정리할 디렉토리 경로 (기본값: /var/lib/docker/overlay2/*/merged/tmp/)"
  echo "  -n, --number NUM    정리할 최대 디렉토리 수 (기본값: 5)"
  echo "  -s, --size SIZE     정리할 최소 크기 (예: 10M, 기본값: 0)"
  echo "  -d, --dry-run       실제 삭제하지 않고 삭제될 파일만 표시"
  echo "  -h, --help          도움말 표시"
  exit 1
}

# 기본 변수 설정
DOCKER_TMP_PATH="/var/lib/docker/overlay2/*/merged/tmp/"
MAX_DIRS=5
MIN_SIZE="0"
DRY_RUN=false

# 명령줄 인자 파싱
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--path)
      DOCKER_TMP_PATH="$2"
      shift 2
      ;;
    -n|--number)
      MAX_DIRS="$2"
      shift 2
      ;;
    -s|--size)
      MIN_SIZE="$2"
      shift 2
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      echo "알 수 없는 옵션: $1"
      show_usage
      ;;
  esac
done

# 루트 권한 확인
if [ "$(id -u)" -ne 0 ]; then
  echo "이 스크립트는 루트 권한으로 실행해야 합니다."
  exit 1
fi

echo "시작 시간: $(date)"
echo "Docker 컨테이너 임시 파일 정리를 시작합니다..."

# 정리 전 디스크 사용량 표시
echo "정리 전 디스크 사용량:"
df -h | grep -E '(Filesystem|/$)'

# 모든 컨테이너의 tmp 디렉토리 반복
for TMP_DIR in $DOCKER_TMP_PATH; do
  if [ -d "$TMP_DIR" ]; then
    echo "========================================"
    echo "디렉토리 정리 중: $TMP_DIR"
    
    # 현재 디렉토리의 큰 파일/폴더 찾기
    echo "가장 큰 $MAX_DIRS 개 디렉토리 (최소 크기: $MIN_SIZE):"
    LARGE_DIRS=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sort -rh | head -n "$MAX_DIRS")
    echo "$LARGE_DIRS"
    
    # 큰 디렉토리 처리
    echo "$LARGE_DIRS" | while read SIZE DIR; do
      # 크기가 MIN_SIZE보다 큰지 확인 (사람이 읽기 쉬운 형식을 숫자로 변환)
      DIR_SIZE_BYTES=$(convert_to_bytes "$SIZE")
      MIN_SIZE_BYTES=$(convert_to_bytes "$MIN_SIZE")
      
      if (( DIR_SIZE_BYTES < MIN_SIZE_BYTES )); then
        echo "스킵: $DIR ($SIZE) - 최소 크기 $MIN_SIZE 보다 작음"
        continue
      fi
      
      echo "처리 중: $DIR ($SIZE)"
      if [ "$DRY_RUN" = true ]; then
        echo "드라이 런 모드: $DIR/* 파일들이 삭제됩니다."
      else
        rm -rf "$DIR"/* 2>/dev/null
        RESULT=$?
        if [ $RESULT -eq 0 ]; then
          echo "✓ 성공적으로 삭제되었습니다: $DIR/*"
        else
          echo "✗ 삭제 중 오류 발생: $DIR/*"
        fi
      fi
    done
  fi
done

# 정리 후 디스크 사용량 표시
echo "========================================"
echo "정리 후 디스크 사용량:"
df -h | grep -E '(Filesystem|/$)'

echo "완료 시간: $(date)"
