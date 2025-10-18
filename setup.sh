#!/bin/bash
echo "--- Starting Full Project Sentinel Setup ---"
rm -rf backend frontend
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

touch backend/src/__init__.py; touch backend/src/services/__init__.py

cat <<'PYCONF' > backend/src/config.py
from dotenv import load_dotenv; from pydantic_settings import BaseSettings
load_dotenv();
class Settings(BaseSettings):
    alpaca_api_key: str; alpaca_secret_key: str; binance_api_key: str; binance_secret_key: str
    AWS_ACCESS_KEY_ID: str; AWS_SECRET_ACCESS_KEY: str; AWS_DEFAULT_REGION: str
    class Config:
        env_file = ".env"
settings = Settings()
PYCONF

cat <<'PYSERV' > backend/src/services/alpaca_service.py
import alpaca_trade_api as tradeapi; from alpaca_trade_api.rest import TimeFrame; from ..config import settings
api=tradeapi.REST(key_id=settings.alpaca_api_key,secret_key=settings.alpaca_secret_key,base_url='https://paper-api.alpaca.markets')
def get_account_info():
    try: acc=api.get_account(); return {"account_number":acc.account_number,"cash":float(acc.cash),"portfolio_value":float(acc.portfolio_value),"status":acc.status}
    except Exception as e: return {"error":str(e)}
def get_positions():
    try: pos=api.list_positions(); return [{"symbol":p.symbol,"quantity":float(p.qty),"market_value":float(p.market_value),"cost_basis":float(p.cost_basis),"unrealized_pl":float(p.unrealized_pl)} for p in pos]
    except Exception as e: return {"error":str(e)}
def get_latest_bar(s):
    try: b=api.get_latest_bar(s); return {"symbol":s,"open":b.o,"high":b.h,"low":b.l,"close":b.c,"volume":b.v}
    except Exception as e: return {"error":str(e)}
def place_order(s,q,side):
    try: o=api.submit_order(symbol=s,qty=q,side=side,type='market',time_in_force='day'); return {"status":"success","order_id":o.id,"symbol":o.symbol}
    except Exception as e: return {"status":"error","message":str(e)}
def get_historical_data(s,limit=200):
    try: return api.get_bars(s,TimeFrame.Day,limit=limit).df
    except Exception as e: return None
PYSERV

cat <<'PYBINA' > backend/src/services/binance_service.py
from binance.spot import Spot as Client; from ..config import settings
client=Client(api_key=settings.binance_api_key,api_secret=settings.binance_secret_key)
def get_account_info():
    try:
        acc=client.account(); bal=[b for b in acc.get('balances',[]) if float(b['free'])>0]; return {"accountType":acc.get('accountType'),"canTrade":acc.get('canTrade'),"balances":bal}
    except Exception as e: return {"error":str(e)}
PYBINA

cat <<'PYDB' > backend/src/services/database_service.py
import boto3; from datetime import datetime; from ..config import settings
dynamodb=boto3.resource('dynamodb',region_name=settings.AWS_DEFAULT_REGION,aws_access_key_id=settings.AWS_ACCESS_KEY_ID,aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY)
table=dynamodb.Table('sentinel-trades')
def save_trade(o,s,side,q,p):
    try:
        t=datetime.utcnow().isoformat();v=q*p
        table.put_item(Item={'trade_id':o,'timestamp':t,'symbol':s,'side':side,'quantity':str(q),'price':str(p),'total_value':str(v)})
        print(f"  💾 Trade {o} saved to database.")
    except Exception as e: print(f"  ❌ DB save failed: {e}")
def get_all_trades():
    try: return table.scan().get('Items',[])
    except Exception as e: print(f"  ❌ DB fetch failed: {e}"); return {"error":str(e)}
PYDB

cat <<'PYBOT' > backend/src/services/bot_service.py
import time; from . import alpaca_service,trading_logic_service,database_service
WATCHLIST=['AAPL','MSFT','GOOG','NVDA','TSLA','JPM','V','JNJ','PFE','AMZN','WMT','SPY','QQQ','BTC/USD','ETH/USD','XRP/USD']
def run_trading_cycle():
    print("--- Starting new trading cycle ---")
    for s in WATCHLIST:
        print(f"Checking {s}...")
        sig_d=trading_logic_service.generate_signal(s);sig=sig_d.get('signal')
        if sig in['BUY','SELL']:
            print(f"  Signal for {s}: {sig}! Reason: {sig_d.get('reason')}")
            price_d=alpaca_service.get_latest_bar(s)
            if'error'in price_d: print(f"  Price error for {s}. Skip."); continue
            p=price_d['close']
            if p<=0: print(f"  Invalid price for {s}. Skip."); continue
            q=1000/p;print(f"  Placing {sig} for {q:.4f} shares of {s}...")
            order_res=alpaca_service.place_order(symbol=s,qty=q,side=sig.lower())
            if order_res.get('status')=='success':
                o_id=order_res.get('order_id');print(f"  ✅ Order success! ID: {o_id}")
                database_service.save_trade(order_id=o_id,symbol=s,side=sig,qty=q,price=p)
            else: print(f"  ❌ Order failed: {order_res.get('message')}")
        else: print(f"  Signal is {sig}. No action.")
        time.sleep(1)
    print("--- Trading cycle complete ---")
def start_bot_loop():
    while True: run_trading_cycle();print("\nSleeping for 5 minutes...\n");time.sleep(300)
PYBOT

cat <<'PYLOGIC' > backend/src/services/trading_logic_service.py
import pandas as pd; from . import alpaca_service
def generate_signal(s,sw=20,lw=50):
    d=alpaca_service.get_historical_data(s,limit=lw+5)
    if d is None or len(d)<2: return {"signal":"HOLD","reason":"Not enough historical data for analysis."}
    d['short_ma']=d['close'].rolling(window=sw).mean(); d['long_ma']=d['close'].rolling(window=lw).mean()
    sma,lma=d['short_ma'].iloc[-1],d['long_ma'].iloc[-1]; psma,plma=d['short_ma'].iloc[-2],d['long_ma'].iloc[-2]
    if sma>lma and psma<=plma: return {"signal":"BUY","reason":f"Short MA ({sma:.2f}) crossed above Long MA ({lma:.2f})"}
    elif sma<lma and psma>=plma: return {"signal":"SELL","reason":f"Short MA ({sma:.2f}) crossed below Long MA ({lma:.2f})"}
    else: return {"signal":"HOLD","reason":"No crossover event."}
PYLOGIC

cat <<'PYMAIN' > backend/src/main.py
import threading; from fastapi import FastAPI,HTTPException; from fastapi.middleware.cors import CORSMiddleware; from pydantic import BaseModel; from .services import alpaca_service,trading_logic_service,binance_service,bot_service,database_service
app=FastAPI(title="Sentinel API")
@app.on_event("startup")
def on_startup(): print("--- Starting Sentinel Bot ---"); threading.Thread(target=bot_service.start_bot_loop,daemon=True).start()
class OrderData(BaseModel): symbol:str; qty:float; side:str
app.add_middleware(CORSMiddleware,allow_origins=["*"],allow_credentials=True,allow_methods=["*"],allow_headers=["*"])
@app.get("/")
def root(): return {"status":"ok"}
@app.get("/api/v1/trades")
def get_trades():
    trades=database_service.get_all_trades()
    if"error"in trades: raise HTTPException(500,trades["error"])
    return trades
@app.get("/api/v1/account/binance")
def get_binance():
    info=binance_service.get_account_info();
    if"error"in info: raise HTTPException(500,info["error"])
    return info
@app.get("/api/v1/account/alpaca")
def get_alpaca():
    info=alpaca_service.get_account_info();
    if"error"in info: raise HTTPException(500,info["error"])
    return info
@app.get("/api/v1/portfolio/positions")
def get_positions():
    pos=alpaca_service.get_positions();
    if"error"in pos: raise HTTPException(500,pos["error"])
    return pos
@app.get("/api/v1/signals/{s}")
def get_signal(s:str): return trading_logic_service.generate_signal(s.upper())
@app.get("/api/v1/market/bars/{s}")
def get_bar(s:str):
    b=alpaca_service.get_latest_bar(s.upper());
    if"error"in b: raise HTTPException(404,f"No data for {s}")
    return b
@app.post("/api/v1/orders")
def create_order(o:OrderData):
    res=alpaca_service.place_order(symbol=o.symbol.upper(),qty=o.qty,side=o.side);
    if res["status"]=="error": raise HTTPException(400,res["message"])
    return res
PYMAIN

# --- Create Frontend Files ---
echo "Creating frontend files..."
cat <<'HTML' > frontend/index.html
<!doctype html><html lang="en"><head><title>Project Sentinel</title></head><body><div class="header"><h1>Sentinel Dashboard</h1><div id="exchange-switcher"><button id="btn-alpaca" class="active">Stocks (Alpaca)</button><button id="btn-binance">Crypto (Binance)</button></div></div><div id="metrics-container" class="grid-container"></div><div id="main-content" class="grid-container"></div><div id="trade-history-container" class="card"></div><script type="module" src="/src/main.js"></script></body></html>
HTML
cat <<'CSS' > frontend/src/style.css
:root{font-family:system-ui,sans-serif;background-color:#f0f4f8;color:#333}body{padding:2rem}h1{color:#0056b3}.header{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #cceeff;padding-bottom:1rem}#exchange-switcher button{background-color:#fff;border:1px solid #ccc;padding:.5rem 1rem;cursor:pointer;border-radius:5px}#exchange-switcher button.active{background-color:#007bff;color:#fff;border-color:#007bff}.grid-container{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:1rem;margin-top:2rem}.card{background-color:#fff;border-radius:8px;padding:1.5rem;border:1px solid #e0f2f7;box-shadow:0 4px 8px rgba(0,0,0,.05);margin-top:2rem}.data-card{background-color:#fff;border-radius:8px;padding:1.5rem;border:1px solid #e0f2f7;box-shadow:0 4px 8px rgba(0,0,0,.05)}.data-card h3,.chart-card h3{margin-top:0;font-size:1rem;color:#666;text-transform:uppercase;letter-spacing:.5px}.data-card p{font-size:2.25rem;margin-bottom:0;font-weight:300;color:#007bff}#signal-display{margin-top:1.5rem;border-top:1px solid #e0f2f7;padding-top:1.5rem}.buy{color:#28a745;font-weight:700}.sell{color:#dc3545;font-weight:700}.hold{color:#6c757d;font-weight:700}table{width:100%;border-collapse:collapse;margin-top:1rem}th,td{text-align:left;padding:.75rem;border-bottom:1px solid #e0f2f7}th{color:#0056b3}
CSS
cat <<'JS' > frontend/src/main.js
import'./style.css';import Chart from'chart.js/auto';let cE='alpaca';let cI=null;const mC=document.getElementById('metrics-container');const mCt=document.getElementById('main-content');const tHC=document.getElementById('trade-history-container');const bA=document.getElementById('btn-alpaca');const bB=document.getElementById('btn-binance');const bH=window.location.hostname.replace('5173','8000');const bU=`${window.location.protocol}//${bH}`;bA.addEventListener('click',()=>sE('alpaca'));bB.addEventListener('click',()=>sE('binance'));function sE(e){cE=e;bA.classList.toggle('active',e==='alpaca');bB.classList.toggle('active',e==='binance');iD()}async function iD(){mC.innerHTML='<p>Loading...</p>';mCt.innerHTML='';mCt.style.display='none';tHC.style.display='none';if(cI)cI.destroy();if(cE==='alpaca'){await rAD()}else{await rBD()}}async function rAD(){mCt.innerHTML=`<div class="chart-card"><h3>Portfolio Allocation</h3><canvas id="allocation-chart"></canvas></div><div class="chart-card" id="market-data-card"><h3>Live Market Data</h3><form id="market-form"><input type="text" id="symbol-input" placeholder="Enter Symbol (e.g., AAPL)" required><button type="submit">Get Price & Signal</button></form><div id="market-data-display"></div><div id="signal-display"></div><div id="trade-actions"></div></div>`;mCt.style.display='grid';tHC.style.display='block';document.getElementById('market-form').addEventListener('submit',hAFS);await rTH();try{const[aR,pR]=await Promise.all([fetch(`${bU}/api/v1/account/alpaca`),fetch(`${bU}/api/v1/portfolio/positions`)]);if(!aR.ok||!pR.ok)throw new Error('Failed to fetch Alpaca data.');const aD=await aR.json();const pD=await pR.json();const tI=pD.reduce((s,p)=>s+p.cost_basis,0);const tP=pD.reduce((s,p)=>s+p.unrealized_pl,0);const roi=tI>0?(tP/tI)*100:0;mC.innerHTML='';mC.appendChild(cMC('Balance',aD.portfolio_value));mC.appendChild(cMC('Profit',tP));mC.appendChild(cMC('Invested',tI));mC.appendChild(cMC('ROI',roi,false));const cC=document.getElementById('allocation-chart');if(pD.length>0){cI=new Chart(cC,{type:'pie',data:{labels:pD.map(p=>p.symbol),datasets:[{data:pD.map(p=>p.market_value),backgroundColor:['#007bff','#ffc107','#28a745','#dc3545','#17a2b8']}]}})}else{document.querySelector('#main-content .chart-card h3').textContent="No positions to display"}}catch(e){mC.innerHTML=`<p>Error: ${e.message}`}}async function rBD(){try{const r=await fetch(`${bU}/api/v1/account/binance`);if(!r.ok)throw new Error('Failed to fetch Binance data.');const d=await r.json();mC.innerHTML='';mC.appendChild(cMC('Can Trade?',d.canTrade?'Yes':'No',false));let aH='<h3>Your Balances:</h3><ul>';d.balances.forEach(a=>{aH+=`<li>${a.asset}: ${a.free}</li>`});aH+='</ul>';mCt.innerHTML=aH;mCt.style.display='block'}catch(e){mC.innerHTML=`<p>Error: ${e.message}`}}async function hAFS(e){e.preventDefault();const sI=document.getElementById('symbol-input');const s=sI.value.trim().toUpperCase();if(!s)return;const mD=document.getElementById('market-data-display');const sD=document.getElementById('signal-display');const tA=document.getElementById('trade-actions');mD.textContent=`Fetching for ${s}...`;sD.innerHTML='';tA.innerHTML='';try{const[bR,sR]=await Promise.all([fetch(`${bU}/api/v1/market/bars/${s}`),fetch(`${bU}/api/v1/signals/${s}`)]);if(!bR.ok||!sR.ok)throw new Error('Failed to get data/signal.');const bD=await bR.json();const sD=await sR.json();mD.innerHTML=`<h4>${bD.symbol}: $${bD.close.toLocaleString()}</h4>`;sD.innerHTML=`<h4>Signal: <span class="${sD.signal.toLowerCase()}">${sD.signal}</span></h4><p><em>${sD.reason}</em></p>`;if(sD.signal==='BUY'||sD.signal==='SELL'){const tB=document.createElement('button');tB.textContent=`Execute ${sD.signal}`;tB.onclick=()=>eT(s,sD.signal,bD.close);tA.appendChild(tB)}}catch(err){mD.textContent=`Error: ${err.message}`}}async function eT(s,side,p){const q=1000/p;const tA=document.getElementById('trade-actions');tA.innerHTML=`<p>Placing order...</p>`;try{const r=await fetch(`${bU}/api/v1/orders`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({symbol:s,qty:q,side:side.toLowerCase()})});if(!r.ok){const eD=await r.json();throw new Error(eD.detail||'Order failed.')}const res=await r.json();tA.innerHTML=`<p class="buy">✅ Success! ID: ${res.order_id}</p>`;setTimeout(iD,2000)}catch(err){tA.innerHTML=`<p class="sell">❌ Error: ${err.message}`}}async function rTH(){tHC.innerHTML='<h3>Trade History</h3><p>Loading...</p>';try{const r=await fetch(`${bU}/api/v1/trades`);const trades=await r.json();if(trades.length===0){tHC.innerHTML='<h3>Trade History</h3><p>No trades recorded.</p>';return}trades.sort((a,b)=>new Date(b.timestamp)-new Date(a.timestamp));let tH=`<h3>Trade History</h3><table><thead><tr><th>Date</th><th>Symbol</th><th>Side</th><th>Qty</th><th>Price</th><th>Value</th></tr></thead><tbody>`;trades.forEach(t=>{const tD=new Date(t.timestamp).toLocaleString();const sC=t.side.toLowerCase();tH+=`<tr><td>${tD}</td><td>${t.symbol}</td><td><span class="${sC}">${t.side}</span></td><td>${parseFloat(t.quantity).toFixed(4)}</td><td>$${parseFloat(t.price).toFixed(2)}</td><td>$${parseFloat(t.total_value).toLocaleString()}</td></tr>`});tH+='</tbody></table>';tHC.innerHTML=tH}catch(e){tHC.innerHTML=`<h3>Trade History</h3><p>Error: ${e.message}</p>`}}function cMC(t,v,iC=true){const c=document.createElement('div');c.className='data-card';const fV=iC?`$${Number(v).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2})}`:(typeof v==='string'?v:`${Number(v).toFixed(2)}%`);c.innerHTML=`<h3>${t}</h3><p>${fV}</p>`;return c}iD();
JS
cat <<'JSON' > frontend/package.json
{"name":"sentinel","type":"module","scripts":{"dev":"vite"},"devDependencies":{"vite":"^5.2.0","chart.js":"^4.4.0"}}
JSON

# --- Install All Dependencies ---
echo "Installing dependencies..."
pip install -r backend/requirements.txt
(cd frontend && npm install)

echo ""
echo "--- ✅ Setup Complete! ---"
