#!/bin/bash
echo "--- Starting Full Project Sentinel Setup ---"

# --- Clean Slate ---
rm -rf backend frontend

# --- Create Directories ---
echo "Creating directories..."
mkdir -p backend/src/services frontend/src

# --- Create Backend Files ---
echo "Creating backend files..."
cat <<'PYREQ' > backend/requirements.txt
fastapi
pydantic
pydantic-settings
python-dotenv
alpaca-trade-api
binance-connector
boto3
pandas
uvicorn
PYREQ

touch backend/src/__init__.py
touch backend/src/services/__init__.py

cat <<'PYCONF' > backend/src/config.py
from dotenv import load_dotenv
from pydantic_settings import BaseSettings
load_dotenv()
class Settings(BaseSettings):
    alpaca_api_key: str; alpaca_secret_key: str
    binance_api_key: str; binance_secret_key: str
    class Config: { "env_file": ".env" }
settings = Settings()
PYCONF

cat <<'PYSERV' > backend/src/services/alpaca_service.py
import alpaca_trade_api as tradeapi
from ..config import settings
def get_alpaca_api_client():
    return tradeapi.REST(
        key_id=settings.alpaca_api_key,
        secret_key=settings.alpaca_secret_key,
        base_url='https://paper-api.alpaca.markets'
    )
def get_account_info():
    try:
        acc = get_alpaca_api_client().get_account()
        return {
            "account_number": acc.account_number, "cash": float(acc.cash),
            "portfolio_value": float(acc.portfolio_value), "status": acc.status
        }
    except Exception as e:
        return {"error": str(e)}
PYSERV

cat <<'PYMAIN' > backend/src/main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from .services import alpaca_service
app = FastAPI(title="Sentinel API")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)
@app.get("/")
def root(): return {"status": "ok"}
@app.get("/api/v1/account/alpaca")
def get_alpaca():
    info = alpaca_service.get_account_info()
    if "error" in info:
        raise HTTPException(500, info["error"])
    return info
PYMAIN

# --- Create Frontend Files ---
echo "Creating frontend files..."
cat <<'HTML' > frontend/index.html
<!doctype html><html lang="en"><head><title>Project Sentinel</title></head>
<body><h1>Sentinel Dashboard</h1><h2>Alpaca Account:</h2>
<pre id="data">Loading...</pre><script type="module" src="/src/main.js"></script>
</body></html>
HTML

cat <<'JS' > frontend/src/main.js
const display = document.getElementById('data');
const backendHost = window.location.hostname.replace('5173', '8000');
const backendUrl = `${window.location.protocol}//${backendHost}`;
async function fetchData() {
  try {
    const res = await fetch(`${backendUrl}/api/v1/account/alpaca`);
    const data = await res.json();
    display.textContent = JSON.stringify(data, null, 2);
  } catch (err) {
    display.textContent = `Error: ${err.message}`;
  }
}
fetchData();
JS

cat <<'JSON' > frontend/package.json
{"name":"sentinel","type":"module","scripts":{"dev":"vite"},"devDependencies":{"vite":"^5.2.0"}}
JSON

# --- Install All Dependencies ---
echo "Installing dependencies..."
pip install -r backend/requirements.txt
(cd frontend && npm install)

echo ""
echo "--- ✅ Setup Complete! ---"
echo "Your project is ready. Now:"
echo "1. In terminal 1, run: cd backend"
echo "2. Create your .env file with API keys."
echo "3. Run: uvicorn src.main:app --reload"
echo ""
echo "4. In terminal 2, run: cd frontend && npm run dev"
