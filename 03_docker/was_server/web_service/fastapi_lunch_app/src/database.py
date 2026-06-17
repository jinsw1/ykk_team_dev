import os
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase

# DB 연결 주소 설정
DB_URL = (
    f"postgresql+asyncpg://"
    f"{os.getenv('DB_USER', 'scott')}:"       
    f"{os.getenv('DB_PASSWORD', 'tiger')}@"   
    f"{os.getenv('DB_HOST', 'db')}:"   
    f"{os.getenv('DB_PORT', '5432')}/"        
    f"{os.getenv('DB_NAME', 'lunch_db')}"     
)

# 비동기 엔진 및 세션 생성
engine = create_async_engine(DB_URL, echo=False, pool_size=10, max_overflow=5)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

# 모델 클래스의 부모가 될 Base 객체
class Base(DeclarativeBase):
    pass