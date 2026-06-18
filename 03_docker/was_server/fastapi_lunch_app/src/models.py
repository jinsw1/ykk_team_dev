from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class Member(Base):
    __tablename__ = "members"
    employee_id = Column(String(20), primary_key=True)   
    name        = Column(String(50),  nullable=False)
    password    = Column(String(50),  nullable=False, default="1234")    
    department  = Column(String(50))                     
    created_at  = Column(DateTime, default=datetime.now) 
    reservations = relationship("Reservation", back_populates="member")

class Menu(Base):
    __tablename__ = "menus"
    id          = Column(Integer, primary_key=True, autoincrement=True)
    name        = Column(String(100), nullable=False)
    description = Column(String(255))
    kcal        = Column(Integer)
    total       = Column(Integer, default=50)
    remaining   = Column(Integer, default=50)
    is_popular  = Column(Boolean, default=False)
    emoji       = Column(String(10))
    image_url   = Column(String(255), nullable=True)
    price       = Column(Integer, default=0)

class Reservation(Base):
    __tablename__ = "reservations"
    id          = Column(Integer, primary_key=True, autoincrement=True)
    employee_id = Column(String(20), ForeignKey("members.employee_id"), nullable=False)  
    menu_id     = Column(Integer, ForeignKey("menus.id"), nullable=False)
    menu_name   = Column(String(100), nullable=False)
    reserved_at = Column(DateTime, default=datetime.now)
    member = relationship("Member", back_populates="reservations")