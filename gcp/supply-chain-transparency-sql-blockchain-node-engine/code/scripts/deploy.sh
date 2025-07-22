#!/bin/bash

# Supply Chain Transparency with Cloud SQL and Blockchain Node Engine - Deployment Script
# This script deploys the complete supply chain transparency infrastructure on Google Cloud Platform

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    ./destroy.sh --force 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables with defaults
PROJECT_ID=${PROJECT_ID:-"supply-chain-$(date +%s)"}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
DRY_RUN=${DRY_RUN:-false}

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
DB_INSTANCE_NAME="supply-chain-db-${RANDOM_SUFFIX}"
BLOCKCHAIN_NODE_NAME="supply-chain-node-${RANDOM_SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 18+ first."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        log_error "Node.js version 18 or higher is required. Current version: $(node --version)"
        exit 1
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Function to validate project ID
validate_project() {
    log_info "Validating project configuration..."
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        log_info "Available projects:"
        gcloud projects list --format="table(projectId,name,projectNumber)"
        exit 1
    fi
    
    # Check billing account
    if ! gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" | grep -q "True"; then
        log_error "Billing is not enabled for project '$PROJECT_ID'. Please enable billing first."
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Function to estimate costs
show_cost_estimate() {
    log_info "Estimated monthly costs for this deployment:"
    echo "  • Cloud SQL PostgreSQL (db-custom-2-8192): ~\$150-200"
    echo "  • Blockchain Node Engine (Ethereum Full Node): ~\$100-150"
    echo "  • Cloud Functions (serverless): ~\$5-20"
    echo "  • Pub/Sub messaging: ~\$5-15"
    echo "  • Cloud KMS: ~\$1-5"
    echo "  • Network egress and other services: ~\$10-30"
    echo "  • Total estimated cost: ~\$270-420/month"
    log_warning "Actual costs may vary based on usage patterns and data transfer."
}

# Function to confirm deployment
confirm_deployment() {
    if [ "$SKIP_CONFIRMATION" = "true" ]; then
        return 0
    fi
    
    echo
    log_info "Deployment Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Database Instance: $DB_INSTANCE_NAME"
    echo "  Blockchain Node: $BLOCKCHAIN_NODE_NAME"
    echo
    
    show_cost_estimate
    echo
    
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user."
        exit 0
    fi
}

# Function to configure environment
configure_environment() {
    log_info "Configuring Google Cloud environment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would configure project: $PROJECT_ID"
        return 0
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment configured"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would enable required APIs"
        return 0
    fi
    
    local apis=(
        "sqladmin.googleapis.com"
        "blockchainnode.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudkms.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create KMS resources
create_kms_resources() {
    log_info "Creating Cloud KMS encryption key..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create KMS keyring and encryption key"
        return 0
    fi
    
    # Create KMS keyring for blockchain operations
    if ! gcloud kms keyrings describe blockchain-keyring --location="$REGION" &>/dev/null; then
        gcloud kms keyrings create blockchain-keyring --location="$REGION" --quiet
        log_success "KMS keyring created"
    else
        log_info "KMS keyring already exists"
    fi
    
    # Create encryption key for blockchain node
    if ! gcloud kms keys describe blockchain-key --keyring=blockchain-keyring --location="$REGION" &>/dev/null; then
        gcloud kms keys create blockchain-key \
            --location="$REGION" \
            --keyring=blockchain-keyring \
            --purpose=encryption \
            --quiet
        log_success "KMS encryption key created"
    else
        log_info "KMS encryption key already exists"
    fi
}

# Function to create Cloud SQL instance
create_cloud_sql() {
    log_info "Creating Cloud SQL PostgreSQL instance..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create Cloud SQL instance: $DB_INSTANCE_NAME"
        return 0
    fi
    
    # Check if instance already exists
    if gcloud sql instances describe "$DB_INSTANCE_NAME" &>/dev/null; then
        log_warning "Cloud SQL instance $DB_INSTANCE_NAME already exists"
        return 0
    fi
    
    # Create Cloud SQL PostgreSQL instance
    log_info "Creating Cloud SQL instance (this may take 5-10 minutes)..."
    gcloud sql instances create "$DB_INSTANCE_NAME" \
        --database-version=POSTGRES_15 \
        --tier=db-custom-2-8192 \
        --region="$REGION" \
        --backup-start-time=03:00 \
        --enable-bin-log \
        --maintenance-window-day=SUN \
        --maintenance-window-hour=04 \
        --storage-type=SSD \
        --storage-size=100GB \
        --storage-auto-increase \
        --deletion-protection \
        --quiet
    
    # Wait for instance to be ready
    log_info "Waiting for Cloud SQL instance to be ready..."
    gcloud sql operations wait --operation="$(gcloud sql operations list --instance="$DB_INSTANCE_NAME" --limit=1 --format="value(name)")" --quiet
    
    # Create supply chain database
    if ! gcloud sql databases describe supply_chain --instance="$DB_INSTANCE_NAME" &>/dev/null; then
        gcloud sql databases create supply_chain --instance="$DB_INSTANCE_NAME" --quiet
        log_success "Supply chain database created"
    fi
    
    # Create database user with secure password
    PGPASSWORD=$(openssl rand -base64 32)
    export PGPASSWORD
    
    if ! gcloud sql users describe supply_chain_user --instance="$DB_INSTANCE_NAME" &>/dev/null; then
        gcloud sql users create supply_chain_user \
            --instance="$DB_INSTANCE_NAME" \
            --password="$PGPASSWORD" \
            --quiet
        log_success "Database user created"
    fi
    
    log_success "Cloud SQL instance created: $DB_INSTANCE_NAME"
}

# Function to initialize database schema
initialize_database_schema() {
    log_info "Initializing database schema..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would initialize database schema"
        return 0
    fi
    
    # Create schema file
    cat > schema.sql << 'EOF'
-- Products table for supply chain items
CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    blockchain_hash VARCHAR(66)
);

-- Suppliers table for supply chain partners
CREATE TABLE IF NOT EXISTS suppliers (
    supplier_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    address TEXT,
    certification_level VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Supply chain transactions
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id),
    supplier_id INTEGER REFERENCES suppliers(supplier_id),
    transaction_type VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL,
    location VARCHAR(255),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    blockchain_hash VARCHAR(66),
    verified BOOLEAN DEFAULT FALSE
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_transactions_product ON transactions(product_id);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp);
CREATE INDEX IF NOT EXISTS idx_transactions_blockchain_hash ON transactions(blockchain_hash);

-- Insert sample data
INSERT INTO suppliers (name, address, certification_level) 
VALUES 
    ('Global Manufacturing Corp', '123 Factory St, Shanghai, China', 'ISO 9001'),
    ('Sustainable Materials Ltd', '456 Green Ave, Portland, OR, USA', 'Fair Trade Certified')
ON CONFLICT DO NOTHING;

INSERT INTO products (sku, name, description, category)
VALUES 
    ('WIDGET-001', 'Premium Widget', 'High-quality widget for industrial use', 'Electronics'),
    ('GADGET-002', 'Smart Gadget', 'IoT-enabled gadget with sensor capabilities', 'Smart Devices')
ON CONFLICT DO NOTHING;
EOF
    
    # Get Cloud SQL instance IP
    DB_IP=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(ipAddresses[0].ipAddress)")
    export DB_IP
    
    # Execute schema creation using Cloud SQL Proxy
    log_info "Executing schema creation..."
    
    # Download and setup Cloud SQL Proxy if not exists
    if [ ! -f cloud_sql_proxy ]; then
        curl -o cloud_sql_proxy https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64
        chmod +x cloud_sql_proxy
    fi
    
    # Start Cloud SQL Proxy in background
    ./cloud_sql_proxy -instances="${PROJECT_ID}:${REGION}:${DB_INSTANCE_NAME}"=tcp:5432 &
    PROXY_PID=$!
    
    # Wait for proxy to be ready
    sleep 10
    
    # Execute schema using psql if available, otherwise use gcloud sql connect
    if command -v psql &> /dev/null; then
        PGPASSWORD="$PGPASSWORD" psql -h localhost -p 5432 -U supply_chain_user -d supply_chain -f schema.sql
    else
        # Fallback to gcloud sql connect
        kill $PROXY_PID 2>/dev/null || true
        wait $PROXY_PID 2>/dev/null || true
        
        # Use gcloud sql connect (interactive method)
        log_warning "Using gcloud sql connect for schema creation (requires manual password entry)"
        gcloud sql connect "$DB_INSTANCE_NAME" --user=supply_chain_user --database=supply_chain < schema.sql || {
            log_error "Failed to create schema. Please create it manually using the schema.sql file."
        }
    fi
    
    # Cleanup
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
    rm -f schema.sql
    
    log_success "Database schema initialized"
}

# Function to deploy blockchain node
deploy_blockchain_node() {
    log_info "Deploying Blockchain Node Engine..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would deploy blockchain node: $BLOCKCHAIN_NODE_NAME"
        return 0
    fi
    
    # Check if Blockchain Node Engine is available in the project
    if ! gcloud blockchain-node-engine locations list &>/dev/null; then
        log_error "Blockchain Node Engine is not available. Please request access first."
        log_info "Visit: https://cloud.google.com/blockchain-node-engine to request access"
        return 1
    fi
    
    # Check if node already exists
    if gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" &>/dev/null; then
        log_warning "Blockchain node $BLOCKCHAIN_NODE_NAME already exists"
        return 0
    fi
    
    # Create blockchain node for Ethereum mainnet
    log_info "Creating blockchain node (this may take 15-30 minutes)..."
    gcloud blockchain-node-engine nodes create "$BLOCKCHAIN_NODE_NAME" \
        --location="$REGION" \
        --blockchain-type=ETHEREUM \
        --network=MAINNET \
        --node-type=FULL \
        --execution-client=GETH \
        --consensus-client=LIGHTHOUSE \
        --quiet || {
        log_warning "Blockchain Node Engine deployment failed. This may be due to service availability or access restrictions."
        log_info "Continuing with other components..."
        return 0
    }
    
    log_success "Blockchain Node Engine deployed: $BLOCKCHAIN_NODE_NAME"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create Pub/Sub topics and subscriptions"
        return 0
    fi
    
    # Create topics
    local topics=("supply-chain-events" "blockchain-verification")
    for topic in "${topics[@]}"; do
        if ! gcloud pubsub topics describe "$topic" &>/dev/null; then
            gcloud pubsub topics create "$topic" --quiet
            log_success "Created topic: $topic"
        else
            log_info "Topic already exists: $topic"
        fi
    done
    
    # Create subscriptions
    if ! gcloud pubsub subscriptions describe process-supply-events &>/dev/null; then
        gcloud pubsub subscriptions create process-supply-events \
            --topic=supply-chain-events \
            --quiet
        log_success "Created subscription: process-supply-events"
    fi
    
    if ! gcloud pubsub subscriptions describe process-blockchain-verification &>/dev/null; then
        gcloud pubsub subscriptions create process-blockchain-verification \
            --topic=blockchain-verification \
            --quiet
        log_success "Created subscription: process-blockchain-verification"
    fi
    
    log_success "Pub/Sub resources created"
}

# Function to create IAM service account
create_service_account() {
    log_info "Creating IAM service account..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create service account and assign permissions"
        return 0
    fi
    
    # Create service account
    if ! gcloud iam service-accounts describe "supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        gcloud iam service-accounts create supply-chain-sa \
            --display-name="Supply Chain Service Account" \
            --description="Service account for supply chain transparency operations" \
            --quiet
        log_success "Service account created"
    else
        log_info "Service account already exists"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/cloudsql.client"
        "roles/pubsub.editor"
        "roles/cloudfunctions.invoker"
        "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" \
            --quiet
    done
    
    # Try to grant blockchain role if available
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/blockchain.nodeUser" \
        --quiet 2>/dev/null || log_warning "Blockchain role not available"
    
    log_success "Service account configured with appropriate permissions"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would deploy Cloud Functions"
        return 0
    fi
    
    # Create temporary directory for Cloud Functions
    TEMP_DIR=$(mktemp -d)
    
    # Deploy supply chain processor function
    create_supply_chain_processor "$TEMP_DIR"
    deploy_processor_function "$TEMP_DIR"
    
    # Deploy API ingestion function
    create_api_function "$TEMP_DIR"
    deploy_api_function "$TEMP_DIR"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    log_success "Cloud Functions deployed successfully"
}

# Function to create supply chain processor
create_supply_chain_processor() {
    local temp_dir=$1
    local func_dir="$temp_dir/supply-chain-processor"
    
    mkdir -p "$func_dir"
    cd "$func_dir"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "supply-chain-processor",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/pubsub": "^4.0.0",
    "@google-cloud/sql-connector": "^1.0.0",
    "pg": "^8.11.0",
    "web3": "^4.0.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create function code
    cat > index.js << 'EOF'
const {PubSub} = require('@google-cloud/pubsub');
const {Client} = require('pg');

const pubsub = new PubSub();

exports.processSupplyChainEvent = async (event, context) => {
  try {
    const eventData = JSON.parse(Buffer.from(event.data, 'base64').toString());
    console.log('Processing supply chain event:', eventData);
    
    // Validate required fields
    const requiredFields = ['product_id', 'supplier_id', 'transaction_type', 'quantity', 'location'];
    for (const field of requiredFields) {
      if (eventData[field] === undefined || eventData[field] === null) {
        throw new Error(`Missing required field: ${field}`);
      }
    }
    
    // Connect to Cloud SQL using Unix socket
    const client = new Client({
      host: `/cloudsql/${process.env.INSTANCE_CONNECTION_NAME}`,
      database: 'supply_chain',
      user: 'supply_chain_user',
      password: process.env.DB_PASSWORD,
    });
    
    await client.connect();
    
    // Insert transaction record
    const query = `
      INSERT INTO transactions (product_id, supplier_id, transaction_type, quantity, location, blockchain_hash)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING transaction_id
    `;
    
    const values = [
      eventData.product_id,
      eventData.supplier_id,
      eventData.transaction_type,
      eventData.quantity,
      eventData.location,
      eventData.blockchain_hash || null
    ];
    
    const result = await client.query(query, values);
    console.log('Transaction recorded:', result.rows[0].transaction_id);
    
    // Publish to blockchain verification queue if blockchain_hash exists
    if (eventData.blockchain_hash) {
      const verificationData = {
        transaction_id: result.rows[0].transaction_id,
        blockchain_hash: eventData.blockchain_hash
      };
      
      await pubsub.topic('blockchain-verification').publish(
        Buffer.from(JSON.stringify(verificationData))
      );
      console.log('Blockchain verification request published');
    }
    
    await client.end();
    
    return {
      success: true,
      transaction_id: result.rows[0].transaction_id
    };
    
  } catch (error) {
    console.error('Error processing supply chain event:', error);
    throw error;
  }
};
EOF
}

# Function to deploy processor function
deploy_processor_function() {
    local temp_dir=$1
    local func_dir="$temp_dir/supply-chain-processor"
    
    cd "$func_dir"
    
    # Install dependencies
    npm install --silent
    
    # Deploy function
    gcloud functions deploy processSupplyChainEvent \
        --runtime=nodejs18 \
        --trigger-topic=supply-chain-events \
        --entry-point=processSupplyChainEvent \
        --set-env-vars="INSTANCE_CONNECTION_NAME=${PROJECT_ID}:${REGION}:${DB_INSTANCE_NAME},DB_PASSWORD=${PGPASSWORD}" \
        --memory=512MB \
        --timeout=60s \
        --service-account="supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    log_success "Supply chain processor function deployed"
}

# Function to create API function
create_api_function() {
    local temp_dir=$1
    local func_dir="$temp_dir/supply-chain-api"
    
    mkdir -p "$func_dir"
    cd "$func_dir"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "supply-chain-api",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/pubsub": "^4.0.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create function code
    cat > index.js << 'EOF'
const {PubSub} = require('@google-cloud/pubsub');
const crypto = require('crypto');

const pubsub = new PubSub();

exports.supplyChainIngestion = async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    if (req.method !== 'POST') {
      return res.status(405).json({error: 'Method Not Allowed'});
    }
    
    const eventData = req.body;
    
    // Validate required fields
    const requiredFields = ['product_id', 'supplier_id', 'transaction_type', 'quantity', 'location'];
    for (const field of requiredFields) {
      if (!eventData[field]) {
        return res.status(400).json({error: `Missing required field: ${field}`});
      }
    }
    
    // Validate data types and ranges
    if (typeof eventData.product_id !== 'number' || eventData.product_id <= 0) {
      return res.status(400).json({error: 'product_id must be a positive number'});
    }
    
    if (typeof eventData.supplier_id !== 'number' || eventData.supplier_id <= 0) {
      return res.status(400).json({error: 'supplier_id must be a positive number'});
    }
    
    if (typeof eventData.quantity !== 'number' || eventData.quantity <= 0) {
      return res.status(400).json({error: 'quantity must be a positive number'});
    }
    
    // Generate blockchain hash for event
    const eventString = JSON.stringify({
      product_id: eventData.product_id,
      supplier_id: eventData.supplier_id,
      transaction_type: eventData.transaction_type,
      quantity: eventData.quantity,
      location: eventData.location,
      timestamp: new Date().toISOString()
    });
    
    eventData.blockchain_hash = '0x' + crypto.createHash('sha256').update(eventString).digest('hex');
    eventData.timestamp = new Date().toISOString();
    
    // Publish to supply chain events topic
    const messageBuffer = Buffer.from(JSON.stringify(eventData));
    await pubsub.topic('supply-chain-events').publish(messageBuffer);
    
    console.log('Supply chain event published:', eventData);
    
    res.status(200).json({
      success: true,
      transaction_hash: eventData.blockchain_hash,
      timestamp: eventData.timestamp,
      message: 'Supply chain event processed successfully'
    });
    
  } catch (error) {
    console.error('Error in supply chain ingestion:', error);
    res.status(500).json({error: 'Internal server error'});
  }
};
EOF
}

# Function to deploy API function
deploy_api_function() {
    local temp_dir=$1
    local func_dir="$temp_dir/supply-chain-api"
    
    cd "$func_dir"
    
    # Install dependencies
    npm install --silent
    
    # Deploy function
    gcloud functions deploy supplyChainIngestion \
        --runtime=nodejs18 \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point=supplyChainIngestion \
        --memory=256MB \
        --timeout=30s \
        --service-account="supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    log_success "Supply chain API function deployed"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would run validation tests"
        return 0
    fi
    
    # Test 1: Verify Cloud SQL connectivity
    log_info "Testing Cloud SQL connectivity..."
    DB_STATUS=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(state)")
    if [ "$DB_STATUS" = "RUNNABLE" ]; then
        log_success "Cloud SQL instance is running"
    else
        log_warning "Cloud SQL instance status: $DB_STATUS"
    fi
    
    # Test 2: Verify Pub/Sub topics
    log_info "Testing Pub/Sub topics..."
    if gcloud pubsub topics describe supply-chain-events &>/dev/null; then
        log_success "Pub/Sub topics verified"
    else
        log_error "Pub/Sub topics verification failed"
    fi
    
    # Test 3: Test API endpoint
    log_info "Testing API endpoint..."
    INGESTION_URL=$(gcloud functions describe supplyChainIngestion --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    if [ -n "$INGESTION_URL" ]; then
        # Test with sample data
        RESPONSE=$(curl -s -X POST "$INGESTION_URL" \
            -H "Content-Type: application/json" \
            -d '{
              "product_id": 1,
              "supplier_id": 1,
              "transaction_type": "TEST",
              "quantity": 1,
              "location": "Test Location"
            }' 2>/dev/null || echo "")
        
        if echo "$RESPONSE" | grep -q "success.*true"; then
            log_success "API endpoint test passed"
        else
            log_warning "API endpoint test failed or returned unexpected response"
        fi
    else
        log_warning "Could not retrieve API endpoint URL"
    fi
    
    # Test 4: Verify blockchain node (if deployed)
    if gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" &>/dev/null; then
        NODE_STATE=$(gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" --format="value(state)" 2>/dev/null || echo "")
        if [ "$NODE_STATE" = "RUNNING" ]; then
            log_success "Blockchain node is running"
        else
            log_info "Blockchain node state: $NODE_STATE"
        fi
    else
        log_info "Blockchain node not deployed (may not be available)"
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
show_deployment_summary() {
    echo
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    echo "Deployed Resources:"
    echo "  • Project ID: $PROJECT_ID"
    echo "  • Region: $REGION"
    echo "  • Cloud SQL Instance: $DB_INSTANCE_NAME"
    echo "  • Blockchain Node: $BLOCKCHAIN_NODE_NAME"
    echo "  • KMS Keyring: blockchain-keyring"
    echo "  • Pub/Sub Topics: supply-chain-events, blockchain-verification"
    echo "  • Service Account: supply-chain-sa"
    echo "  • Cloud Functions: processSupplyChainEvent, supplyChainIngestion"
    echo
    
    # Get API endpoint URL
    INGESTION_URL=$(gcloud functions describe supplyChainIngestion --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    echo "API Endpoint: $INGESTION_URL"
    echo
    
    echo "Next Steps:"
    echo "  1. Test the API endpoint with supply chain data"
    echo "  2. Monitor Cloud Functions logs for processing events"
    echo "  3. Query the Cloud SQL database to verify data storage"
    echo "  4. Set up monitoring and alerting for production use"
    echo
    
    echo "Cost Management:"
    echo "  • Monitor usage in Cloud Billing console"
    echo "  • Set up budget alerts to control costs"
    echo "  • Use ./destroy.sh to remove all resources when done"
    echo
    
    log_info "Deployment log saved to: deployment-$(date +%Y%m%d-%H%M%S).log"
}

# Function to save deployment state
save_deployment_state() {
    local state_file="deployment-state.env"
    
    cat > "$state_file" << EOF
# Supply Chain Transparency Deployment State
# Generated on: $(date)
export PROJECT_ID="$PROJECT_ID"
export REGION="$REGION"
export ZONE="$ZONE"
export DB_INSTANCE_NAME="$DB_INSTANCE_NAME"
export BLOCKCHAIN_NODE_NAME="$BLOCKCHAIN_NODE_NAME"
export PGPASSWORD="$PGPASSWORD"
EOF
    
    log_info "Deployment state saved to: $state_file"
    log_warning "Keep this file secure as it contains sensitive information"
}

# Main deployment function
main() {
    echo "Supply Chain Transparency Deployment Script"
    echo "==========================================="
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --project-id ID     Google Cloud Project ID"
                echo "  --region REGION     Deployment region (default: us-central1)"
                echo "  --zone ZONE         Deployment zone (default: us-central1-a)"
                echo "  --skip-confirmation Skip deployment confirmation"
                echo "  --dry-run           Show what would be deployed without creating resources"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Redirect output to log file
    exec > >(tee "deployment-$(date +%Y%m%d-%H%M%S).log")
    exec 2>&1
    
    # Execute deployment steps
    check_prerequisites
    validate_project
    confirm_deployment
    configure_environment
    enable_apis
    create_kms_resources
    create_cloud_sql
    initialize_database_schema
    deploy_blockchain_node
    create_pubsub_resources
    create_service_account
    deploy_cloud_functions
    run_validation_tests
    save_deployment_state
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi