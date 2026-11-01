"""Helper koneksi ke database harga_pangan untuk notebook.

Contoh:
    from src.db import query
    df = query("SELECT * FROM mart.dim_wilayah")
"""
import os

import pandas as pd
from sqlalchemy import create_engine, text

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://localhost/harga_pangan")
_engine = None


def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1))
    return _engine


def query(sql, **params):
    """Jalankan SELECT dan kembalikan DataFrame. Parameter ditulis :nama di SQL."""
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn, params=params)
