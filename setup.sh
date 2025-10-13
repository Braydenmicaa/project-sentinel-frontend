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
# ... (The rest of the script is the same)
