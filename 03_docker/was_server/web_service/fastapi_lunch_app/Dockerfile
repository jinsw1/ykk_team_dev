# BASE 이미지
FROM python:3.11-slim

# container 에 앱이 복사되는 폴더 ( /app 경로 이동됨 )
WORKDIR /app

# requirements.txt 파일을 현재경로(/app) 에 복사 해오기
COPY requirements.txt .

# 필요한 패키지 설치
RUN pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY src/ .

# 8000 port 를 사용한다고 명시하기
EXPOSE 8000

# FastAPI 실행 (uvicorn 사용)
# --host 0.0.0.0 은 컨테이너 외부 연결을 위해 필수입니다!
#CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
CMD ["uvicorn", "app_fastapi:app", "--host", "0.0.0.0", "--port", "8000"]