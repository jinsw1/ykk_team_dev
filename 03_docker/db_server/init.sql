--
-- PostgreSQL database dump
--

\restrict Ref2w919dY4M7mdz3V7h84Cv4q0RqoNaIIFE2wu9hcXEIuchDY6ilvFtDzgnZ0t

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg13+1)
-- Dumped by pg_dump version 16.14 (Debian 16.14-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: members; Type: TABLE; Schema: public; Owner: scott
--

CREATE TABLE public.members (
    employee_id character varying(20) NOT NULL,
    name character varying(50) NOT NULL,
    password character varying(50) NOT NULL,
    department character varying(50),
    created_at timestamp without time zone
);


ALTER TABLE public.members OWNER TO scott;

--
-- Name: reservations; Type: TABLE; Schema: public; Owner: scott
--

CREATE TABLE public.reservations (
    id integer NOT NULL,
    employee_id character varying(20) NOT NULL,
    menu_id integer NOT NULL,
    menu_name character varying(100) NOT NULL,
    reserved_at timestamp without time zone
);


ALTER TABLE public.reservations OWNER TO scott;

--
-- Name: reservations_id_seq; Type: SEQUENCE; Schema: public; Owner: scott
--

CREATE SEQUENCE public.reservations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservations_id_seq OWNER TO scott;

--
-- Name: reservations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: scott
--

ALTER SEQUENCE public.reservations_id_seq OWNED BY public.reservations.id;


--
-- Name: reservations id; Type: DEFAULT; Schema: public; Owner: scott
--

ALTER TABLE ONLY public.reservations ALTER COLUMN id SET DEFAULT nextval('public.reservations_id_seq'::regclass);


--
-- Data for Name: members; Type: TABLE DATA; Schema: public; Owner: scott
--

INSERT INTO public.members VALUES ('EMP001', '김철수', '1234', '개발팀', '2026-06-17 04:52:27.163623');
INSERT INTO public.members VALUES ('EMP002', '이영희', '1234', '마케팅팀', '2026-06-17 04:52:27.163629');
INSERT INTO public.members VALUES ('EMP003', '박민준', '1234', '인사팀', '2026-06-17 04:52:27.16363');
INSERT INTO public.members VALUES ('EMP004', '최지은', '1234', '디자인팀', '2026-06-17 04:52:27.163631');
INSERT INTO public.members VALUES ('EMP005', '정수현', '1234', '영업팀', '2026-06-17 04:52:27.163631');
INSERT INTO public.members VALUES ('ykk001', '김현경', '1234', '개발팀', '2026-06-17 06:59:32.295055');
INSERT INTO public.members VALUES ('ykk002', '진승우', '1234', '개발팀', '2026-06-17 06:59:44.252777');
INSERT INTO public.members VALUES ('ykk003', '강윤주', '1234', '개발팀', '2026-06-17 07:00:06.64186');
INSERT INTO public.members VALUES ('ykk004', '조용빈', '1234', '개발팀', '2026-06-17 07:00:23.59148');
INSERT INTO public.members VALUES ('ykk005', '한지우', '1234', '개발팀', '2026-06-17 07:00:39.811053');


--
-- Data for Name: reservations; Type: TABLE DATA; Schema: public; Owner: scott
--



--
-- Name: reservations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: scott
--

SELECT pg_catalog.setval('public.reservations_id_seq', 1, false);


--
-- Name: members members_pkey; Type: CONSTRAINT; Schema: public; Owner: scott
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT members_pkey PRIMARY KEY (employee_id);


--
-- Name: reservations reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: scott
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_pkey PRIMARY KEY (id);


--
-- Name: reservations reservations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: scott
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.members(employee_id);

--
-- 메뉴 테이블 및 초기 데이터 추가
--

CREATE TABLE public.menus (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(255),
    kcal integer,
    total integer,
    remaining integer,
    is_popular boolean,
    emoji character varying(10),
    image_url character varying(255),
    price integer
);

CREATE SEQUENCE public.menus_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE public.menus_id_seq OWNED BY public.menus.id;
ALTER TABLE ONLY public.menus ALTER COLUMN id SET DEFAULT nextval('public.menus_id_seq'::regclass);
ALTER TABLE ONLY public.menus ADD CONSTRAINT menus_pkey PRIMARY KEY (id);

INSERT INTO public.menus (name, description, kcal, total, remaining, is_popular, emoji, price) VALUES
('제육볶음 도시락', '매콤한 제육볶음과 다양한 반찬', 560, 50, 28, true, '🥩', 8500),
('치킨마요 덮밥', '고소한 치킨마요 소스와 튼튼한 덮밥', 610, 50, 32, true, '🍗', 7500),
('김치볶음밥', '매콤한 김치볶음밥과 계란후라이', 590, 30, 15, false, '🍳', 7000),
('돈까스 도시락', '바삭한 돈까스와 신선한 샐러드', 650, 40, 18, false, '🍱', 9000);

SELECT pg_catalog.setval('public.menus_id_seq', 4, true);

--
-- PostgreSQL database dump complete
--

\unrestrict Ref2w919dY4M7mdz3V7h84Cv4q0RqoNaIIFE2wu9hcXEIuchDY6ilvFtDzgnZ0t