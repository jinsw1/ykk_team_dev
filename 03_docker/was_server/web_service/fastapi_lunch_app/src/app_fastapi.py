from fastapi import Request, Form, FastAPI, HTTPException, Depends, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from datetime import datetime, time
from contextlib import asynccontextmanager
from typing import AsyncGenerator
import shutil
import os

from sqlalchemy import func, select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from database import engine, SessionLocal
from models import Member, Reservation, Menu

os.makedirs("static/uploads", exist_ok=True)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session  

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield  
    await engine.dispose()

app = FastAPI(title="사내 점심 예약 시스템", lifespan=lifespan)
app.add_middleware(SessionMiddleware, secret_key="super-secret-key")
templates = Jinja2Templates(directory="templates")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_methods=["*"],
    allow_headers=["*"],
)

DEADLINE = time(11, 30)

def is_open():
    return datetime.now().time() < DEADLINE

def calculate_badge(remaining, is_popular):
    if remaining == 0:
        return "품절", "soldout"
    elif remaining <= 5:
        return "마감 임박", "urgent"
    elif is_popular:
        return "인기 메뉴", "popular"
    return None, None

class ReserveRequest(BaseModel):
    menu_id: int

class AdminLoginRequest(BaseModel):
    admin_id: str
    admin_pw: str

class MenuAddRequest(BaseModel):
    name: str
    description: str
    kcal: int
    total: int
    emoji: str

class MenuUpdateRequest(BaseModel):
    total: int
    remaining: int
    is_popular: bool

class MemberRequest(BaseModel):
    employee_id: str
    name: str
    password: str
    department: str

class MemberUpdateRequest(BaseModel):
    name: str
    password: str
    department: str

@app.get("/", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse(request=request, name="login.html")

@app.post("/login")
async def login(request: Request, emp_no: str = Form(...), password: str = Form(...), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Member).where(Member.employee_id == emp_no, Member.password == password))
    user = result.scalars().first()
    if user:
        request.session["employee_id"] = user.employee_id
        request.session["name"] = user.name
        request.session["department"] = user.department
        return RedirectResponse(url="/reserve", status_code=303)
    return RedirectResponse(url="/?error=invalid", status_code=303)

@app.post("/api/logout")
async def logout_employee(request: Request):
    request.session.pop("employee_id", None)
    request.session.pop("name", None)
    request.session.pop("department", None)
    return {"success": True}

@app.get("/reserve", response_class=HTMLResponse)
async def reserve_page(request: Request):
    if not request.session.get("employee_id"):
        return RedirectResponse(url="/", status_code=303)
    return templates.TemplateResponse(request=request, name="reserve.html")

@app.get("/api/menus")
async def get_menus(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Menu).order_by(Menu.id))
    db_menus = result.scalars().all()
    
    menus_data = []
    total_rem = 0
    for m in db_menus:
        badge, badge_type = calculate_badge(m.remaining, m.is_popular)
        menus_data.append({
            "id": m.id, "name": m.name, "description": m.description, "kcal": m.kcal,
            "total": m.total, "remaining": m.remaining, "is_popular": m.is_popular,
            "badge": badge, "badge_type": badge_type, "emoji": m.emoji, "image_url": m.image_url, "price": m.price
        })
        total_rem += m.remaining
        
    return {"menus": menus_data, "deadline": "11:30 AM", "total_remaining": total_rem, "is_open": is_open()}

@app.post("/api/reserve")
async def reserve(req: ReserveRequest, request: Request, db: AsyncSession = Depends(get_db)):
    emp = request.session.get("employee_id")
    name = request.session.get("name")
    if not emp or not name:
        raise HTTPException(401, "세션이 만료되었거나 로그인이 필요합니다.")

    dup = await db.execute(select(Reservation).where(Reservation.employee_id == emp, func.date(Reservation.reserved_at) == datetime.now().date()))
    if dup.scalars().first():
        raise HTTPException(400, "오늘 이미 예약하셨습니다.")
    
    menu_res = await db.execute(select(Menu).where(Menu.id == req.menu_id).with_for_update())
    menu = menu_res.scalars().first()
    
    if not menu:
        raise HTTPException(404, "메뉴를 찾을 수 없습니다.")
    if menu.remaining <= 0:
        raise HTTPException(400, "해당 메뉴는 품절되었습니다.")
        
    menu.remaining -= 1
    
    now = datetime.now()
    reservation = Reservation(employee_id=emp, menu_id=menu.id, menu_name=menu.name, reserved_at=now)
    db.add(reservation)
    await db.commit()

    return {
        "success": True,
        "message": f"'{menu.name}' 예약이 완료되었습니다!",
        "reservation": {
            "id": reservation.id, "menu_id": menu.id, "menu_name": menu.name,
            "name": name, "employee_id": emp, "reserved_at": now.strftime("%Y-%m-%d %H:%M:%S")
        }
    }

@app.get("/api/my-reservation")
async def my_reservation(request: Request, db: AsyncSession = Depends(get_db)):
    emp = request.session.get("employee_id")
    if not emp:
        return {"success": False}
    result = await db.execute(select(Reservation).where(Reservation.employee_id == emp, func.date(Reservation.reserved_at) == datetime.now().date()))
    reservation = result.scalars().first()
    if not reservation:
        return {"success": False, "reservation": None}
    return {
        "success": True,
        "reservation": {
            "id": reservation.id, "menu_id": reservation.menu_id, "menu_name": reservation.menu_name, 
            "name": request.session.get("name"), "employee_id": emp, 
            "reserved_at": reservation.reserved_at.strftime("%Y-%m-%d %H:%M:%S")
        }
    }

@app.post("/api/cancel")
async def cancel(request: Request, db: AsyncSession = Depends(get_db)):
    emp = request.session.get("employee_id")
    if not emp:
        raise HTTPException(401, "세션이 만료되었습니다.")
        
    result = await db.execute(select(Reservation).where(Reservation.employee_id == emp, func.date(Reservation.reserved_at) == datetime.now().date()))
    reservation = result.scalars().first()
    if not reservation:
        raise HTTPException(404, "오늘 예약 내역이 없습니다.")
        
    menu_res = await db.execute(select(Menu).where(Menu.id == reservation.menu_id).with_for_update())
    menu = menu_res.scalars().first()
    if menu:
        menu.remaining += 1
        
    await db.delete(reservation)
    await db.commit()
    return {"success": True, "message": "예약이 취소되었습니다."}

@app.post("/api/admin/login")
async def admin_login(req: AdminLoginRequest, request: Request):
    if req.admin_id == "admin" and req.admin_pw == "admin":
        request.session["is_admin"] = True
        return {"success": True}
    return {"success": False, "message": "관리자 정보가 일치하지 않습니다."}

@app.get("/admin", response_class=HTMLResponse)
async def admin_page(request: Request):
    if not request.session.get("is_admin"):
        return RedirectResponse(url="/", status_code=303)
    return templates.TemplateResponse(request=request, name="admin.html")

@app.get("/api/admin/dashboard")
async def admin_dashboard(request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    
    today_count = await db.execute(select(func.count(Reservation.id)).where(func.date(Reservation.reserved_at) == datetime.now().date()))
    total_reserved = today_count.scalar()
    
    menu_res = await db.execute(select(Menu).order_by(Menu.id))
    menus = menu_res.scalars().all()
    
    menus_data = []
    total_capacity = 0
    total_remaining = 0
    
    for m in menus:
        badge, badge_type = calculate_badge(m.remaining, m.is_popular)
        menus_data.append({
            "id": m.id, "name": m.name, "description": m.description, "kcal": m.kcal,
            "total": m.total, "remaining": m.remaining, "is_popular": m.is_popular,
            "emoji": m.emoji, "image_url": m.image_url, "price": m.price
        })
        total_capacity += m.total
        total_remaining += m.remaining
        
    return {
        "success": True, "total_capacity": total_capacity, "total_reserved": total_reserved,
        "total_remaining": total_remaining, "menus": menus_data
    }

@app.post("/api/admin/menus")
async def admin_add_menu(req: MenuAddRequest, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    new_menu = Menu(name=req.name, description=req.description, kcal=req.kcal, total=req.total, remaining=req.total, emoji=req.emoji)
    db.add(new_menu)
    await db.commit()
    return {"success": True}

@app.put("/api/admin/menus/{menu_id}")
async def admin_update_menu(menu_id: int, req: MenuUpdateRequest, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Menu).where(Menu.id == menu_id))
    menu = result.scalars().first()
    if not menu:
        raise HTTPException(404, "메뉴를 찾을 수 없습니다.")
    menu.total = req.total
    menu.remaining = req.remaining
    menu.is_popular = req.is_popular
    await db.commit()
    return {"success": True}

@app.delete("/api/admin/menus/{menu_id}")
async def admin_delete_menu(menu_id: int, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Menu).where(Menu.id == menu_id))
    menu = result.scalars().first()
    if menu:
        await db.delete(menu)
        await db.commit()
    return {"success": True}

@app.post("/api/admin/menus/{menu_id}/image")
async def admin_upload_menu_image(menu_id: int, request: Request, file: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Menu).where(Menu.id == menu_id))
    menu = result.scalars().first()
    if not menu:
        raise HTTPException(404, "메뉴를 찾을 수 없습니다.")
    
    file_ext = os.path.splitext(file.filename)[1]
    file_name = f"menu_{menu_id}_{int(datetime.now().timestamp())}{file_ext}"
    file_path = f"static/uploads/{file_name}"
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    menu.image_url = f"/{file_path}"
    await db.commit()
    return {"success": True, "image_url": menu.image_url}

@app.delete("/api/admin/menus/{menu_id}/image")
async def admin_delete_menu_image(menu_id: int, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Menu).where(Menu.id == menu_id))
    menu = result.scalars().first()
    if menu:
        menu.image_url = None
        await db.commit()
    return {"success": True}

@app.get("/api/admin/members")
async def admin_get_members(request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Member).order_by(Member.employee_id))
    members = result.scalars().all()
    return {"success": True, "members": [{"employee_id": m.employee_id, "name": m.name, "password": m.password, "department": m.department} for m in members]}

@app.post("/api/admin/members")
async def admin_add_member(req: MemberRequest, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    existing = await db.execute(select(Member).where(Member.employee_id == req.employee_id))
    if existing.scalars().first():
        return {"success": False, "message": "이미 등록된 사원번호입니다."}
    
    new_member = Member(employee_id=req.employee_id, name=req.name, password=req.password, department=req.department)
    db.add(new_member)
    await db.commit()
    return {"success": True}

@app.put("/api/admin/members/{emp_id}")
async def admin_update_member(emp_id: str, req: MemberUpdateRequest, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Member).where(Member.employee_id == emp_id))
    member = result.scalars().first()
    if not member:
        return {"success": False, "message": "사원을 찾을 수 없습니다."}
    
    member.name = req.name
    member.password = req.password
    member.department = req.department
    await db.commit()
    return {"success": True}

@app.delete("/api/admin/members/{emp_id}")
async def admin_delete_member(emp_id: str, request: Request, db: AsyncSession = Depends(get_db)):
    if not request.session.get("is_admin"):
        raise HTTPException(401)
    result = await db.execute(select(Member).where(Member.employee_id == emp_id))
    member = result.scalars().first()
    if not member:
        return {"success": False, "message": "사원을 찾을 수 없습니다."}
    
    await db.execute(delete(Reservation).where(Reservation.employee_id == emp_id))
    await db.delete(member)
    await db.commit()
    return {"success": True}

@app.post("/api/admin/logout")
async def admin_logout(request: Request):
    request.session.pop("is_admin", None)
    return {"success": True}

app.mount("/static", StaticFiles(directory="static"), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app_fastapi:app", host="0.0.0.0", port=8000, reload=True)