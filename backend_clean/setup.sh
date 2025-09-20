#!/bin/bash
# This is a setup script for a new environment

echo "--- Starting Project Sentinel Backend Setup ---"

# Create the backend directory and move into it
mkdir backend_new && cd backend_new

# --- Create Serverless Configuration ---
echo "Creating serverless.yml..."
cat <<'EOM' > serverless.yml
service: project-sentinel-backend
provider:
  name: aws
  runtime: python3.9
  region: ap-southeast-2
  iam:
    role:
      statements:
        - Effect: "Allow"
          Action: ["ssm:GetParameter"]
          Resource: "arn:aws:ssm:ap-southeast-2:246766637985:parameter/*"
        - Effect: "Allow"
          Action: ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:GetItem"]
          Resource: 
            - "arn:aws:dynamodb:ap-southeast-2:246766637985:table/trades"
            - "arn:aws:dynamodb:ap-southeast-2:246766637985:table/trades/index/*"
            - "arn:aws:dynamodb:ap-southeast-2:246766637985:table/processed_articles"
        - Effect: "Allow"
          Action: ["sns:Publish"]
          Resource: "arn:aws:sns:ap-southeast-2:246766637985:trading-bot-notifications"
package:
  patterns: ['src/**']
plugins:
  - serverless-python-requirements
custom:
  pythonRequirements:
    layer: true
functions:
  tradingBot:
    handler: src.handler.main
    layers:
      - Ref: PythonRequirementsLambdaLayer
    events:
      - schedule: rate(5 minutes)
  getTrades:
    handler: src.api.handler
    layers:
      - Ref: PythonRequirementsLambdaLayer
    events:
      - http:
          path: trades
          method: get
          cors: true
EOM

# --- Create Python Requirements ---
echo "Creating requirements.txt..."
cat <<'EOM' > requirements.txt
boto3
pandas
pandas-ta
tweepy
binance-connector
requests
textblob
EOM

# --- Create Source Code Directory ---
mkdir src

# --- Create Placeholder Python Files ---
# You can copy your more advanced logic into these later
echo "Creating src/handler.py..."
cat <<'EOM' > src/handler.py
import json
def main(event, context):
    return {"statusCode": 200, "body": json.dumps({"message": "Hello from handler!"})}
EOM

echo "Creating src/api.py..."
cat <<'EOM' > src/api.py
import json
def handler(event, context):
    return {"statusCode": 200, "body": json.dumps({"message": "Hello from API!"})}
EOM

# --- Install Dependencies ---
echo "Setting up Python virtual environment and installing libraries..."
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

echo "Installing Serverless plugins..."
npm install --save-dev serverless-python-requirements

echo "---"
echo "✅ Setup Complete!"
echo "Next steps in your new workspace:"
echo "1. cd backend_new"
echo "2. source venv/bin/activate"
echo "3. aws configure (enter your credentials)"
echo "4. serverless deploy"
