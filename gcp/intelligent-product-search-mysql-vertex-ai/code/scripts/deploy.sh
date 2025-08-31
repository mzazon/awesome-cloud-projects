#!/bin/bash

# Intelligent Product Search with Cloud SQL and Vertex AI - Deployment Script
# This script deploys the complete infrastructure for semantic product search
# Recipe: intelligent-product-search-mysql-vertex-ai

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed (usually comes with gcloud)
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Use provided project ID or create a new one
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="product-search-$(date +%s)"
        log "Generated PROJECT_ID: $PROJECT_ID"
    else
        log "Using provided PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default values if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export INSTANCE_NAME="${INSTANCE_NAME:-product-db-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-products}"
    export FUNCTION_NAME="${FUNCTION_NAME:-product-search-${RANDOM_SUFFIX}}"
    
    log_success "Environment variables configured"
    echo "  PROJECT_ID: $PROJECT_ID"
    echo "  REGION: $REGION"
    echo "  ZONE: $ZONE"
    echo "  INSTANCE_NAME: $INSTANCE_NAME"
    echo "  BUCKET_NAME: $BUCKET_NAME"
    echo "  FUNCTION_NAME: $FUNCTION_NAME"
}

# Function to create or verify project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "Project $PROJECT_ID already exists"
    else
        log "Creating new project: $PROJECT_ID"
        if [[ "$DRY_RUN" != "true" ]]; then
            if ! gcloud projects create "$PROJECT_ID"; then
                log_error "Failed to create project. You may need billing permissions or the project ID may be taken."
                exit 1
            fi
        fi
    fi
    
    # Set default project and region
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_cmd "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_cmd "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "sqladmin.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable $api" "Enabling $api"
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        execute_cmd "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}" \
                   "Creating storage bucket"
    fi
    
    log_success "Storage bucket ready: gs://${BUCKET_NAME}"
}

# Function to create Cloud SQL instance
create_sql_instance() {
    log "Creating Cloud SQL MySQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe "$INSTANCE_NAME" &> /dev/null; then
        log_warning "Cloud SQL instance $INSTANCE_NAME already exists"
    else
        execute_cmd "gcloud sql instances create ${INSTANCE_NAME} \
            --database-version=MYSQL_8_0 \
            --tier=db-n1-standard-2 \
            --region=${REGION} \
            --storage-size=20GB \
            --storage-type=SSD \
            --backup-start-time=03:00 \
            --enable-bin-log \
            --maintenance-window-day=SUN \
            --maintenance-window-hour=04" \
            "Creating Cloud SQL instance"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log "Waiting for Cloud SQL instance to be ready..."
            sleep 60
        fi
    fi
    
    # Set root password
    export DB_PASSWORD="${DB_PASSWORD:-SecurePass$(openssl rand -hex 4)}"
    execute_cmd "gcloud sql users set-password root \
        --host=% \
        --instance=${INSTANCE_NAME} \
        --password=${DB_PASSWORD}" \
        "Setting database root password"
    
    log_success "Cloud SQL instance created with vector capabilities"
    echo "  Instance: $INSTANCE_NAME"
    echo "  Password: $DB_PASSWORD (store this securely!)"
}

# Function to create database and schema
setup_database() {
    log "Setting up database schema..."
    
    # Create database
    execute_cmd "gcloud sql databases create products --instance=${INSTANCE_NAME}" \
               "Creating products database"
    
    # Create schema file
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > schema.sql << 'EOF'
CREATE TABLE product_catalog (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(100),
    price DECIMAL(10,2),
    image_url VARCHAR(500),
    embedding JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_price (price)
);

CREATE TABLE search_queries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    query_text TEXT NOT NULL,
    query_embedding JSON,
    results_count INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    fi
    
    # Execute schema creation
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Executing database schema creation..."
        echo "Use the following command to apply schema:"
        echo "gcloud sql connect ${INSTANCE_NAME} --user=root --database=products < schema.sql"
        
        # Note: Interactive connection required for schema creation
        log_warning "Schema file created. Please run the connection command manually."
    fi
    
    log_success "Database schema prepared"
}

# Function to create Cloud Function code
create_function_code() {
    log "Creating Cloud Function code..."
    
    # Create function directory
    mkdir -p product-search-function
    cd product-search-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-aiplatform==1.56.0
google-cloud-sql-connector==1.0.0
PyMySQL==1.1.0
functions-framework==3.5.0
numpy==1.24.3
vertexai==1.56.0
EOF
    
    # Create main function file
    cat > main.py << 'EOF'
import json
import os
import numpy as np
from google.cloud import aiplatform
from google.cloud.sql.connector import Connector
import pymysql
import functions_framework
import vertexai
from vertexai.language_models import TextEmbeddingModel

# Initialize Vertex AI
PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION')
vertexai.init(project=PROJECT_ID, location=REGION)

def get_embedding(text):
    """Generate embedding using Vertex AI text-embedding-005 model."""
    model = TextEmbeddingModel.from_pretrained("text-embedding-005")
    embeddings = model.get_embeddings([text])
    return embeddings[0].values

def get_db_connection():
    """Create database connection using Cloud SQL Connector."""
    connector = Connector()
    
    def getconn():
        conn = connector.connect(
            f"{PROJECT_ID}:{os.environ.get('REGION')}:{os.environ.get('INSTANCE_NAME')}",
            "pymysql",
            user="root",
            password=os.environ.get('DB_PASSWORD'),
            db="products"
        )
        return conn
    
    return getconn()

@functions_framework.http
def search_products(request):
    """Handle product search requests."""
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        return ('', 204, headers)
    
    try:
        request_json = request.get_json()
        query = request_json.get('query', '')
        limit = request_json.get('limit', 10)
        
        # Generate embedding for search query
        query_embedding = get_embedding(query)
        
        # Connect to database
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Store search query for analytics
        cursor.execute(
            "INSERT INTO search_queries (query_text, query_embedding) VALUES (%s, %s)",
            (query, json.dumps(query_embedding))
        )
        
        # Get all products with embeddings for similarity calculation
        cursor.execute("""
            SELECT id, name, description, category, price, image_url, embedding
            FROM product_catalog 
            WHERE embedding IS NOT NULL
        """)
        
        products = cursor.fetchall()
        results = []
        
        for product in products:
            product_embedding = json.loads(product[6])
            
            # Calculate cosine similarity
            similarity = np.dot(query_embedding, product_embedding) / (
                np.linalg.norm(query_embedding) * np.linalg.norm(product_embedding)
            )
            
            results.append({
                'id': product[0],
                'name': product[1],
                'description': product[2],
                'category': product[3],
                'price': float(product[4]) if product[4] else None,
                'image_url': product[5],
                'similarity': float(similarity)
            })
        
        # Sort by similarity and limit results
        results.sort(key=lambda x: x['similarity'], reverse=True)
        results = results[:limit]
        
        # Update results count
        cursor.execute(
            "UPDATE search_queries SET results_count = %s WHERE id = LAST_INSERT_ID()",
            (len(results),)
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return (json.dumps({'results': results}), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': str(e)}), 500, {'Access-Control-Allow-Origin': '*'})

@functions_framework.http
def add_product(request):
    """Add new product with embedding generation."""
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        return ('', 204, headers)
    
    try:
        request_json = request.get_json()
        
        # Generate embedding for product description
        description = request_json.get('description', '')
        embedding = get_embedding(description)
        
        # Connect to database
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Insert product with embedding
        cursor.execute("""
            INSERT INTO product_catalog (name, description, category, price, image_url, embedding)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (
            request_json.get('name'),
            description,
            request_json.get('category'),
            request_json.get('price'),
            request_json.get('image_url'),
            json.dumps(embedding)
        ))
        
        product_id = cursor.lastrowid
        conn.commit()
        cursor.close()
        conn.close()
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return (json.dumps({'id': product_id, 'status': 'success'}), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': str(e)}), 500, {'Access-Control-Allow-Origin': '*'})
EOF
    
    cd ..
    log_success "Cloud Function code created"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    cd product-search-function
    
    # Deploy search function
    execute_cmd "gcloud functions deploy ${FUNCTION_NAME} \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --source . \
        --entry-point search_products \
        --memory 512MB \
        --timeout 60s \
        --region ${REGION} \
        --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION},INSTANCE_NAME=${INSTANCE_NAME},DB_PASSWORD=${DB_PASSWORD} \
        --allow-unauthenticated" \
        "Deploying search function"
    
    # Deploy product addition function
    execute_cmd "gcloud functions deploy ${FUNCTION_NAME}-add \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --source . \
        --entry-point add_product \
        --memory 512MB \
        --timeout 60s \
        --region ${REGION} \
        --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION},INSTANCE_NAME=${INSTANCE_NAME},DB_PASSWORD=${DB_PASSWORD} \
        --allow-unauthenticated" \
        "Deploying product addition function"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get function URLs
        export SEARCH_URL=$(gcloud functions describe ${FUNCTION_NAME} \
            --region=${REGION} \
            --format="value(serviceConfig.uri)")
        export ADD_URL=$(gcloud functions describe "${FUNCTION_NAME}-add" \
            --region=${REGION} \
            --format="value(serviceConfig.uri)")
        
        echo "  Search URL: ${SEARCH_URL}"
        echo "  Add Product URL: ${ADD_URL}"
    fi
    
    cd ..
    log_success "Cloud Functions deployed successfully"
}

# Function to load sample data
load_sample_data() {
    log "Loading sample product data..."
    
    # Create sample product data
    cat > sample_products.json << 'EOF'
[
  {
    "name": "UltraComfort Running Shoes",
    "description": "Lightweight athletic footwear with advanced cushioning technology and breathable mesh upper for long-distance running comfort",
    "category": "footwear",
    "price": 129.99,
    "image_url": "https://example.com/shoes1.jpg"
  },
  {
    "name": "Professional Chef Knife Set",
    "description": "High-carbon stainless steel culinary knives with ergonomic handles for precision cutting and food preparation",
    "category": "kitchen",
    "price": 89.99,
    "image_url": "https://example.com/knives1.jpg"
  },
  {
    "name": "Wireless Noise-Canceling Headphones",
    "description": "Premium audio device with active noise cancellation and wireless bluetooth connectivity for immersive music experience",
    "category": "electronics",
    "price": 199.99,
    "image_url": "https://example.com/headphones1.jpg"
  },
  {
    "name": "Ergonomic Office Chair",
    "description": "Adjustable desk chair with lumbar support and memory foam cushioning for comfortable workspace seating",
    "category": "furniture",
    "price": 299.99,
    "image_url": "https://example.com/chair1.jpg"
  },
  {
    "name": "Organic Green Tea Collection",
    "description": "Premium loose leaf tea blend with natural antioxidants and calming herbal ingredients for wellness and relaxation",
    "category": "beverages",
    "price": 24.99,
    "image_url": "https://example.com/tea1.jpg"
  }
]
EOF
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Loading products via API..."
        # Note: This requires the functions to be deployed and database schema applied
        log_warning "Sample data file created. Load manually after schema is applied:"
        echo "for product in \$(cat sample_products.json | jq -c '.[]'); do"
        echo "  curl -X POST \"\${ADD_URL}\" -H \"Content-Type: application/json\" -d \"\$product\""
        echo "  sleep 2"
        echo "done"
    fi
    
    log_success "Sample product data prepared"
}

# Function to create test script
create_test_script() {
    log "Creating search test script..."
    
    cat > test_search.sh << 'EOF'
#!/bin/bash

SEARCH_URL="$1"
QUERY="$2"

if [ -z "$SEARCH_URL" ] || [ -z "$QUERY" ]; then
    echo "Usage: $0 <search_url> <query>"
    echo "Example: $0 https://... 'comfortable shoes for running'"
    exit 1
fi

echo "Searching for: $QUERY"
echo "================================"

curl -X POST "$SEARCH_URL" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$QUERY\", \"limit\": 5}" \
    | jq -r '.results[] | "\(.name) (Similarity: \(.similarity | . * 100 | floor)%)\n  \(.description)\n  Price: $\(.price)\n"'
EOF
    
    chmod +x test_search.sh
    log_success "Search test script created"
}

# Function to save deployment configuration
save_config() {
    log "Saving deployment configuration..."
    
    cat > deployment_config.env << EOF
# Deployment Configuration - Generated $(date)
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
INSTANCE_NAME=${INSTANCE_NAME}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
DB_PASSWORD=${DB_PASSWORD}
EOF

    if [[ "$DRY_RUN" != "true" && -n "${SEARCH_URL:-}" ]]; then
        cat >> deployment_config.env << EOF
SEARCH_URL=${SEARCH_URL}
ADD_URL=${ADD_URL}
EOF
    fi
    
    log_success "Configuration saved to deployment_config.env"
    log_warning "Keep deployment_config.env secure - it contains sensitive information!"
}

# Main deployment function
main() {
    echo "================================================================"
    echo "Intelligent Product Search with Cloud SQL and Vertex AI"
    echo "Deployment Script"
    echo "================================================================"
    echo
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_sql_instance
    setup_database
    create_function_code
    deploy_functions
    load_sample_data
    create_test_script
    save_config
    
    echo
    echo "================================================================"
    log_success "Deployment completed successfully!"
    echo "================================================================"
    echo
    echo "Next steps:"
    echo "1. Apply database schema manually:"
    echo "   gcloud sql connect ${INSTANCE_NAME} --user=root --database=products < schema.sql"
    echo
    echo "2. Load sample data:"
    echo "   source deployment_config.env"
    echo "   ./load_sample_data.sh"
    echo
    echo "3. Test semantic search:"
    echo "   ./test_search.sh \"\${SEARCH_URL}\" \"comfortable shoes for running\""
    echo
    echo "Configuration saved in: deployment_config.env"
    echo "Keep this file secure!"
    echo
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT

# Run main function
main "$@"