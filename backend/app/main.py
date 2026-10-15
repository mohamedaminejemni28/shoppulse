import base64
import hmac
import json
import os
import socket
import urllib.error
import urllib.request
from contextlib import contextmanager
from decimal import Decimal
from typing import Literal

import psycopg
from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from psycopg.rows import dict_row
from pydantic import BaseModel, EmailStr, Field


DATABASE_URL = os.environ["DATABASE_URL"]
API_KEY = os.getenv("SHOPPULSE_API_KEY", "")
KESTRA_URL = os.getenv("KESTRA_URL", "http://kestra:8080").rstrip("/")
KESTRA_USER = os.getenv("KESTRA_ADMIN_EMAIL", "")
KESTRA_PASSWORD = os.getenv("KESTRA_ADMIN_PASSWORD", "")

app = FastAPI(title="ShopPulse API", version="2.0.0", description="API opérationnelle, analytique et de supervision de ShopPulse")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "X-ShopPulse-API-Key"],
)


@contextmanager
def db():
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as connection:
        yield connection


def fetch_all(sql: str, params: tuple = ()):
    with db() as connection, connection.cursor() as cursor:
        cursor.execute(sql, params)
        return cursor.fetchall()


def fetch_one(sql: str, params: tuple = ()):
    with db() as connection, connection.cursor() as cursor:
        cursor.execute(sql, params)
        return cursor.fetchone()


def require_api_key(x_shoppulse_api_key: str | None = Header(default=None)) -> None:
    if not API_KEY:
        raise HTTPException(status_code=503, detail="SHOPPULSE_API_KEY n'est pas configurée")
    if not x_shoppulse_api_key or not hmac.compare_digest(x_shoppulse_api_key, API_KEY):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Clé API invalide")


class CustomerCreate(BaseModel):
    email: EmailStr
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)
    phone: str | None = None
    country_code: str = Field(default="NG", min_length=2, max_length=2)
    acquisition_channel: Literal["organic", "paid_search", "social", "email", "referral", "direct"] = "direct"


class OrderItemCreate(BaseModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=100)
    discount_amount: Decimal = Field(default=Decimal("0"), ge=0)


class OrderCreate(BaseModel):
    customer_id: int = Field(gt=0)
    source_channel: Literal["web", "mobile", "marketplace", "support"] = "web"
    shipping_amount: Decimal = Field(default=Decimal("0"), ge=0)
    items: list[OrderItemCreate] = Field(min_length=1, max_length=50)


@app.get("/health")
def health():
    row = fetch_one("SELECT current_database() AS database, now() AS checked_at")
    return {"status": "healthy", **row}


@app.get("/dashboard")
def dashboard():
    summary = fetch_one(
        """
        SELECT
            (SELECT count(*) FROM shop.customers) AS customers,
            (SELECT count(*) FROM shop.products WHERE is_active) AS active_products,
            (SELECT count(*) FROM shop.orders) AS orders,
            (SELECT count(*) FROM shop.events) AS events,
            coalesce((SELECT round(sum(total_amount), 2) FROM shop.orders
                      WHERE order_status IN ('paid','processing','shipped','completed','refunded')), 0) AS revenue,
            coalesce((SELECT round(avg(total_amount), 2) FROM shop.orders
                      WHERE order_status IN ('paid','processing','shipped','completed','refunded')), 0) AS average_order_value,
            coalesce((SELECT round(100.0 * count(*) FILTER (WHERE order_status IN ('paid','processing','shipped','completed','refunded')) / nullif(count(*), 0), 2)
                      FROM shop.orders), 0) AS paid_order_rate,
            coalesce((SELECT round(100.0 * sum(purchasing_sessions) / nullif(sum(sessions), 0), 2)
                      FROM analytics.v_conversion_funnel), 0) AS conversion_rate
        """
    )
    daily_sales = fetch_all(
        """SELECT order_date, coalesce(orders_paid, 0) AS orders_paid, coalesce(net_revenue, 0) AS net_revenue
           FROM analytics.v_daily_sales ORDER BY order_date DESC LIMIT 14"""
    )
    statuses = fetch_all("SELECT order_status AS status, count(*) AS total FROM shop.orders GROUP BY order_status ORDER BY total DESC")
    return {"summary": summary, "daily_sales": list(reversed(daily_sales)), "order_statuses": statuses}


@app.get("/orders")
def orders(limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0)):
    rows = fetch_all(
        """SELECT o.order_id, o.order_number, o.order_status, o.total_amount, o.currency,
                  o.source_channel, o.ordered_at, c.first_name || ' ' || c.last_name AS customer_name,
                  c.email, count(oi.order_item_id) AS item_count
           FROM shop.orders o JOIN shop.customers c ON c.customer_id = o.customer_id
           LEFT JOIN shop.order_items oi ON oi.order_id = o.order_id
           GROUP BY o.order_id, c.customer_id ORDER BY o.ordered_at DESC LIMIT %s OFFSET %s""",
        (limit, offset),
    )
    return {"items": rows, "total": fetch_one("SELECT count(*) AS total FROM shop.orders")["total"], "limit": limit, "offset": offset}


@app.get("/orders/{order_id}")
def order(order_id: int):
    header = fetch_one(
        """SELECT o.*, c.first_name || ' ' || c.last_name AS customer_name, c.email
           FROM shop.orders o JOIN shop.customers c USING (customer_id) WHERE o.order_id = %s""", (order_id,)
    )
    if not header:
        raise HTTPException(status_code=404, detail="Commande introuvable")
    header["items"] = fetch_all(
        """SELECT order_item_id, product_id, product_name_snapshot AS product_name,
                  sku_snapshot AS sku, unit_price, quantity, discount_amount, line_total
           FROM shop.order_items WHERE order_id = %s ORDER BY order_item_id""", (order_id,)
    )
    return header


@app.post("/orders", status_code=201, dependencies=[Depends(require_api_key)])
def create_order(payload: OrderCreate):
    product_ids = [item.product_id for item in payload.items]
    if len(set(product_ids)) != len(product_ids):
        raise HTTPException(status_code=422, detail="Un produit ne peut apparaître qu'une seule fois")
    with db() as connection, connection.cursor() as cursor:
        cursor.execute("SELECT customer_id FROM shop.customers WHERE customer_id = %s", (payload.customer_id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Client introuvable")
        cursor.execute(
            """INSERT INTO shop.orders (order_number, customer_id, order_status, source_channel, shipping_amount)
               VALUES ('SP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), %s, 'pending_payment', %s, %s)
               RETURNING order_id""", (payload.customer_id, payload.source_channel, payload.shipping_amount)
        )
        order_id = cursor.fetchone()["order_id"]
        for item in payload.items:
            cursor.execute(
                """SELECT p.product_id, p.product_name, p.sku, p.unit_price, p.unit_cost,
                          i.quantity_on_hand - i.quantity_reserved AS available
                   FROM shop.products p JOIN shop.inventory i USING (product_id)
                   WHERE p.product_id = %s AND p.is_active FOR UPDATE""", (item.product_id,)
            )
            product = cursor.fetchone()
            if not product:
                raise HTTPException(status_code=404, detail=f"Produit {item.product_id} introuvable")
            if product["available"] < item.quantity:
                raise HTTPException(status_code=409, detail=f"Stock insuffisant pour {product['product_name']}")
            if item.discount_amount > product["unit_price"] * item.quantity:
                raise HTTPException(status_code=422, detail=f"Remise excessive pour {product['product_name']}")
            cursor.execute(
                """INSERT INTO shop.order_items
                   (order_id, product_id, product_name_snapshot, sku_snapshot, unit_price, unit_cost, quantity, discount_amount)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                (order_id, product["product_id"], product["product_name"], product["sku"],
                 product["unit_price"], product["unit_cost"], item.quantity, item.discount_amount)
            )
        cursor.execute("SELECT order_id, order_number, order_status, total_amount, ordered_at FROM shop.orders WHERE order_id = %s", (order_id,))
        return cursor.fetchone()


@app.get("/customers")
def customers(limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0)):
    rows = fetch_all(
        """SELECT customer_id, first_name, last_name, email, country_code, acquisition_channel,
                  signup_at, all_orders, paid_orders, lifetime_gross_revenue, customer_segment
           FROM analytics.v_customer_summary ORDER BY signup_at DESC LIMIT %s OFFSET %s""", (limit, offset)
    )
    return {"items": rows, "total": fetch_one("SELECT count(*) AS total FROM shop.customers")["total"], "limit": limit, "offset": offset}


@app.post("/customers", status_code=201, dependencies=[Depends(require_api_key)])
def create_customer(payload: CustomerCreate):
    try:
        with db() as connection, connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO shop.customers (email, first_name, last_name, phone, country_code, acquisition_channel)
                   VALUES (%s, %s, %s, %s, %s, %s)
                   RETURNING customer_id, customer_key, email, first_name, last_name, signup_at""",
                (payload.email.lower(), payload.first_name.strip(), payload.last_name.strip(),
                 payload.phone, payload.country_code.upper(), payload.acquisition_channel)
            )
            return cursor.fetchone()
    except psycopg.errors.UniqueViolation as exc:
        raise HTTPException(status_code=409, detail="Cette adresse e-mail existe déjà") from exc


@app.get("/products")
def products(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    rows = fetch_all(
        """SELECT p.product_id, p.sku, p.product_name, c.category_name, p.unit_price, p.currency, p.is_active,
                  i.quantity_on_hand, i.quantity_reserved, i.quantity_on_hand - i.quantity_reserved AS quantity_available,
                  CASE WHEN i.quantity_on_hand - i.quantity_reserved <= 0 THEN 'out_of_stock'
                       WHEN i.quantity_on_hand - i.quantity_reserved <= i.reorder_level THEN 'reorder'
                       ELSE 'healthy' END AS inventory_status
           FROM shop.products p JOIN shop.categories c USING (category_id) JOIN shop.inventory i USING (product_id)
           ORDER BY p.product_name LIMIT %s OFFSET %s""", (limit, offset)
    )
    return {"items": rows, "total": fetch_one("SELECT count(*) AS total FROM shop.products")["total"], "limit": limit, "offset": offset}


@app.get("/analytics/products")
def product_performance(limit: int = Query(10, ge=1, le=100)):
    return fetch_all(
        """SELECT product_id, sku, product_name, category_name, product_views, units_sold,
                  item_revenue, gross_margin, view_to_order_rate_pct
           FROM analytics.v_product_performance ORDER BY item_revenue DESC, product_views DESC LIMIT %s""", (limit,)
    )


@app.get("/analytics/customers")
def top_customers(limit: int = Query(10, ge=1, le=100)):
    return fetch_all(
        """SELECT customer_id, first_name || ' ' || last_name AS customer_name, email,
                  paid_orders, lifetime_gross_revenue, customer_segment
           FROM analytics.v_customer_summary ORDER BY lifetime_gross_revenue DESC, paid_orders DESC LIMIT %s""", (limit,)
    )


@app.get("/analytics/conversion")
def conversion(days: int = Query(30, ge=1, le=365)):
    return fetch_one(
        """SELECT coalesce(sum(sessions), 0) AS sessions, coalesce(sum(product_view_sessions), 0) AS product_views,
                  coalesce(sum(cart_sessions), 0) AS carts, coalesce(sum(checkout_sessions), 0) AS checkouts,
                  coalesce(sum(purchasing_sessions), 0) AS purchases,
                  coalesce(round(100.0 * sum(purchasing_sessions) / nullif(sum(sessions), 0), 2), 0) AS conversion_rate
           FROM analytics.v_conversion_funnel WHERE session_date >= current_date - %s""", (days,)
    )


@app.get("/events/recent")
def recent_events(limit: int = Query(20, ge=1, le=100)):
    return fetch_all(
        """SELECT e.event_id, e.event_type, e.event_time, e.customer_id, e.product_id, e.order_id,
                  c.first_name || ' ' || c.last_name AS customer_name, p.product_name
           FROM shop.events e LEFT JOIN shop.customers c USING (customer_id) LEFT JOIN shop.products p USING (product_id)
           ORDER BY e.event_time DESC LIMIT %s""", (limit,)
    )


def tcp_status(host: str, port: int) -> dict:
    try:
        with socket.create_connection((host, port), timeout=2):
            return {"status": "healthy", "detail": f"{host}:{port}"}
    except OSError as exc:
        return {"status": "unhealthy", "detail": str(exc)}


def kestra_executions() -> tuple[str, list]:
    request = urllib.request.Request(f"{KESTRA_URL}/api/v1/main/executions/search?size=8")
    if KESTRA_USER and KESTRA_PASSWORD:
        token = base64.b64encode(f"{KESTRA_USER}:{KESTRA_PASSWORD}".encode()).decode()
        request.add_header("Authorization", f"Basic {token}")
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            payload = json.loads(response.read().decode())
            return "healthy", payload.get("results", payload if isinstance(payload, list) else [])
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return "unavailable", []


@app.get("/supervision")
def supervision():
    freshness = fetch_all(
        "SELECT source_name, latest_record_at, data_age::text AS data_age, row_count FROM analytics.v_data_freshness ORDER BY source_name"
    )
    pipeline_runs = fetch_all(
        """SELECT pipeline_name, run_status, started_at, finished_at, rows_read, rows_written, rows_rejected, error_message
           FROM meta.pipeline_runs ORDER BY started_at DESC LIMIT 10"""
    )
    warehouse_runs = fetch_all(
        """SELECT pipeline_name, status, started_at, finished_at, fact_sales, fact_events
           FROM warehouse.etl_runs ORDER BY started_at DESC LIMIT 5"""
    )
    kestra_status, executions = kestra_executions()
    return {
        "services": {
            "postgres": {"status": "healthy", "detail": "requête API réussie"},
            "kestra": {"status": kestra_status, "detail": KESTRA_URL},
            "minio": tcp_status("minio", 9000),
            "kafka": tcp_status("kafka", 29092),
        },
        "freshness": freshness,
        "pipeline_runs": pipeline_runs,
        "warehouse_runs": warehouse_runs,
        "kestra_executions": executions,
    }
