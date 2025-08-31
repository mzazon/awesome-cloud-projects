#!/bin/bash

# Smart Product Catalog Management with Vertex AI Search and Cloud Run - Deployment Script
# This script deploys the complete infrastructure for an AI-powered product catalog solution

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Configuration variables with defaults
PROJECT_ID_PREFIX="smart-catalog"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique identifiers
TIMESTAMP=$(date +%s)
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Resource names
PROJECT_ID="${PROJECT_ID_PREFIX}-${TIMESTAMP}"
APP_NAME="product-catalog-${RANDOM_SUFFIX}"
SEARCH_APP_ID="catalog-search-${RANDOM_SUFFIX}"
DATASTORE_ID="products-${RANDOM_SUFFIX}"
BUCKET_NAME="${PROJECT_ID}-product-data"

# Print banner
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}   Smart Product Catalog Management with Vertex AI Search and Cloud Run - Deployment Script${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Display configuration
log "Deployment Configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  App Name: ${APP_NAME}"
echo "  Search App ID: ${SEARCH_APP_ID}"
echo "  Datastore ID: ${DATASTORE_ID}"
echo "  Bucket Name: ${BUCKET_NAME}"
echo "  Dry Run: ${DRY_RUN}"
echo ""

# Confirmation prompt unless dry run
if [[ "${DRY_RUN}" != "true" ]]; then
    read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if required tools are available
    for tool in openssl curl python3; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
    
    success "Prerequisites check completed"
}

# Create GCP project
create_project() {
    log "Creating GCP project..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create project: ${PROJECT_ID}"
        return
    fi
    
    # Create project
    if ! gcloud projects create "${PROJECT_ID}" --name="Smart Product Catalog" 2>/dev/null; then
        warning "Project creation failed or project already exists"
    else
        success "Project created: ${PROJECT_ID}"
    fi
    
    # Set as current project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Project configuration set"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would enable APIs: run, cloudbuild, firestore, discoveryengine, artifactregistry"
        return
    fi
    
    local apis=(
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "firestore.googleapis.com"
        "discoveryengine.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create Firestore database
create_firestore() {
    log "Creating Firestore database..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Firestore database in region: ${REGION}"
        return
    fi
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --region="${REGION}" &>/dev/null; then
        warning "Firestore database already exists"
    else
        if gcloud firestore databases create --region="${REGION}" --type=firestore-native --quiet; then
            success "Firestore database created"
        else
            error "Failed to create Firestore database"
        fi
    fi
}

# Create Cloud Storage bucket
create_storage() {
    log "Creating Cloud Storage bucket..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create bucket: ${BUCKET_NAME}"
        return
    fi
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        success "Cloud Storage bucket created: ${BUCKET_NAME}"
    else
        error "Failed to create Cloud Storage bucket"
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        success "Versioning enabled on bucket"
    else
        warning "Failed to enable versioning"
    fi
}

# Create and upload sample product data
create_sample_data() {
    log "Creating and uploading sample product data..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create and upload sample product data"
        return
    fi
    
    # Create sample product data
    cat > products.jsonl << 'EOF'
{"id": "prod-001", "content": "Wireless Bluetooth Headphones - Premium noise-cancelling over-ear headphones with 30-hour battery life. Perfect for music lovers and professionals.", "category": "Electronics", "brand": "AudioTech", "price": 199.99, "rating": 4.5, "tags": ["wireless", "bluetooth", "noise-cancelling", "headphones"]}
{"id": "prod-002", "content": "Organic Cotton T-Shirt - Soft, comfortable, and sustainably made t-shirt available in multiple colors. Made from 100% organic cotton.", "category": "Clothing", "brand": "EcoWear", "price": 29.99, "rating": 4.3, "tags": ["organic", "cotton", "sustainable", "t-shirt"]}
{"id": "prod-003", "content": "Smart Fitness Tracker - Advanced health monitoring with heart rate, sleep tracking, and GPS. Water-resistant with 7-day battery life.", "category": "Fitness", "brand": "HealthTech", "price": 149.99, "rating": 4.7, "tags": ["fitness", "tracker", "health", "gps", "waterproof"]}
{"id": "prod-004", "content": "Professional Coffee Maker - Programmable drip coffee maker with thermal carafe and built-in grinder. Makes perfect coffee every time.", "category": "Kitchen", "brand": "BrewMaster", "price": 299.99, "rating": 4.4, "tags": ["coffee", "maker", "programmable", "grinder"]}
{"id": "prod-005", "content": "Wireless Gaming Mouse - High-precision gaming mouse with customizable RGB lighting and ergonomic design. Perfect for competitive gaming.", "category": "Electronics", "brand": "GameGear", "price": 79.99, "rating": 4.6, "tags": ["gaming", "mouse", "wireless", "rgb", "ergonomic"]}
EOF
    
    # Upload to Cloud Storage
    if gsutil cp products.jsonl "gs://${BUCKET_NAME}/"; then
        success "Sample product data uploaded"
    else
        error "Failed to upload sample product data"
    fi
    
    # Clean up local file
    rm -f products.jsonl
}

# Create Vertex AI Search data store
create_datastore() {
    log "Creating Vertex AI Search data store..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create data store: ${DATASTORE_ID}"
        return
    fi
    
    # Create data store
    if gcloud alpha discovery-engine data-stores create \
        --data-store-id="${DATASTORE_ID}" \
        --display-name="Product Catalog Data Store" \
        --industry-vertical=GENERIC \
        --solution-types=SOLUTION_TYPE_SEARCH \
        --content-config=CONTENT_REQUIRED \
        --location=global; then
        success "Vertex AI Search data store created: ${DATASTORE_ID}"
    else
        error "Failed to create Vertex AI Search data store"
    fi
}

# Import data into search engine
import_search_data() {
    log "Importing product data into Vertex AI Search..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would import data from gs://${BUCKET_NAME}/products.jsonl"
        return
    fi
    
    # Import product data
    if gcloud alpha discovery-engine documents import \
        --data-store="${DATASTORE_ID}" \
        --location=global \
        --gcs-uri="gs://${BUCKET_NAME}/products.jsonl" \
        --reconciliation-mode=INCREMENTAL; then
        success "Product data import initiated"
        log "Note: Data indexing may take 5-10 minutes to complete"
    else
        error "Failed to import product data"
    fi
}

# Create search application
create_search_app() {
    log "Creating Vertex AI Search application..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create search app: ${SEARCH_APP_ID}"
        return
    fi
    
    # Wait a bit for data store to be ready
    sleep 10
    
    # Create search application
    if gcloud alpha discovery-engine engines create \
        --engine-id="${SEARCH_APP_ID}" \
        --display-name="Product Catalog Search" \
        --data-store-ids="${DATASTORE_ID}" \
        --industry-vertical=GENERIC \
        --solution-type=SOLUTION_TYPE_SEARCH \
        --location=global; then
        success "Vertex AI Search application created: ${SEARCH_APP_ID}"
    else
        error "Failed to create Vertex AI Search application"
    fi
}

# Create Cloud Run application
create_app_code() {
    log "Creating Cloud Run application code..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create application code in app/ directory"
        return
    fi
    
    # Create application directory
    mkdir -p app
    cd app
    
    # Create Python application
    cat > main.py << 'EOF'
import os
from flask import Flask, request, jsonify
from google.cloud import discoveryengine
from google.cloud import firestore
import json
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize clients
search_client = discoveryengine.SearchServiceClient()
db = firestore.Client()

PROJECT_ID = os.environ.get('PROJECT_ID')
SEARCH_APP_ID = os.environ.get('SEARCH_APP_ID')
DATASTORE_ID = os.environ.get('DATASTORE_ID')

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy", "service": "product-catalog"})

@app.route('/search')
def search_products():
    query = request.args.get('q', '')
    page_size = int(request.args.get('page_size', 10))
    
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400
    
    try:
        # Configure search request
        serving_config = f"projects/{PROJECT_ID}/locations/global/collections/default_collection/engines/{SEARCH_APP_ID}/servingConfigs/default_config"
        
        search_request = discoveryengine.SearchRequest(
            serving_config=serving_config,
            query=query,
            page_size=page_size,
            content_search_spec=discoveryengine.SearchRequest.ContentSearchSpec(
                snippet_spec=discoveryengine.SearchRequest.ContentSearchSpec.SnippetSpec(
                    return_snippet=True
                ),
                summary_spec=discoveryengine.SearchRequest.ContentSearchSpec.SummarySpec(
                    summary_result_count=3
                )
            )
        )
        
        # Execute search
        response = search_client.search(search_request)
        
        # Process results
        results = []
        for result in response.results:
            doc_data = {}
            if hasattr(result.document, 'derived_struct_data'):
                doc_data = dict(result.document.derived_struct_data)
            
            results.append({
                "id": result.document.id,
                "content": doc_data.get('content', ''),
                "category": doc_data.get('category', ''),
                "brand": doc_data.get('brand', ''),
                "price": doc_data.get('price', 0),
                "rating": doc_data.get('rating', 0),
                "snippet": getattr(result.document, 'snippet', {}).get('snippet', '')
            })
        
        logger.info(f"Search query: {query}, Results: {len(results)}")
        
        return jsonify({
            "query": query,
            "results": results,
            "total_results": len(results)
        })
        
    except Exception as e:
        logger.error(f"Search error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/recommend')
def get_recommendations():
    product_id = request.args.get('product_id', '')
    page_size = int(request.args.get('page_size', 5))
    
    if not product_id:
        return jsonify({"error": "Parameter 'product_id' is required"}), 400
    
    try:
        # Simple recommendation based on category similarity
        product_ref = db.collection('products').document(product_id)
        product_doc = product_ref.get()
        
        if not product_doc.exists:
            return jsonify({"error": "Product not found"}), 404
        
        product_data = product_doc.to_dict()
        category = product_data.get('category', '')
        
        # Find similar products in the same category
        similar_products = db.collection('products').where('category', '==', category).limit(page_size + 1).stream()
        
        recommendations = []
        for doc in similar_products:
            if doc.id != product_id:  # Exclude the current product
                recommendations.append({
                    "id": doc.id,
                    **doc.to_dict()
                })
        
        logger.info(f"Recommendations for product: {product_id}, Count: {len(recommendations[:page_size])}")
        
        return jsonify({
            "product_id": product_id,
            "recommendations": recommendations[:page_size]
        })
        
    except Exception as e:
        logger.error(f"Recommendation error: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==3.0.3
google-cloud-discoveryengine==0.13.10
google-cloud-firestore==2.19.0
gunicorn==22.0.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF
    
    success "Cloud Run application code created"
}

# Deploy Cloud Run service
deploy_cloud_run() {
    log "Deploying Cloud Run service..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would deploy Cloud Run service: ${APP_NAME}"
        return
    fi
    
    # Build and deploy to Cloud Run
    if gcloud run deploy "${APP_NAME}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},SEARCH_APP_ID=${SEARCH_APP_ID},DATASTORE_ID=${DATASTORE_ID}" \
        --memory 1Gi \
        --cpu 1 \
        --timeout 300; then
        
        # Get the service URL
        SERVICE_URL=$(gcloud run services describe "${APP_NAME}" \
            --region="${REGION}" \
            --format="value(status.url)")
        
        success "Cloud Run service deployed at: ${SERVICE_URL}"
        echo "SERVICE_URL=${SERVICE_URL}" >> ../deployment_info.txt
    else
        error "Failed to deploy Cloud Run service"
    fi
    
    cd ..
}

# Add sample products to Firestore
add_firestore_products() {
    log "Adding sample products to Firestore..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would add sample products to Firestore"
        return
    fi
    
    # Create Python script to add products
    cat > add_products.py << 'EOF'
import json
from google.cloud import firestore

# Initialize Firestore client
db = firestore.Client()

# Sample product data
products = [
    {"id": "prod-001", "content": "Wireless Bluetooth Headphones", "category": "Electronics", "brand": "AudioTech", "price": 199.99, "rating": 4.5},
    {"id": "prod-002", "content": "Organic Cotton T-Shirt", "category": "Clothing", "brand": "EcoWear", "price": 29.99, "rating": 4.3},
    {"id": "prod-003", "content": "Smart Fitness Tracker", "category": "Fitness", "brand": "HealthTech", "price": 149.99, "rating": 4.7},
    {"id": "prod-004", "content": "Professional Coffee Maker", "category": "Kitchen", "brand": "BrewMaster", "price": 299.99, "rating": 4.4},
    {"id": "prod-005", "content": "Wireless Gaming Mouse", "category": "Electronics", "brand": "GameGear", "price": 79.99, "rating": 4.6}
]

# Add products to Firestore
for product in products:
    doc_ref = db.collection('products').document(product['id'])
    doc_ref.set(product)
    print(f"Added product: {product['id']}")

print("✅ All products added to Firestore")
EOF
    
    # Install required Python packages and run the script
    if python3 -m pip install google-cloud-firestore --quiet && python3 add_products.py; then
        success "Sample products added to Firestore"
    else
        error "Failed to add products to Firestore"
    fi
    
    # Clean up
    rm -f add_products.py
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment_info.txt << EOF
# Smart Product Catalog Deployment Information
# Generated on: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
APP_NAME=${APP_NAME}
SEARCH_APP_ID=${SEARCH_APP_ID}
DATASTORE_ID=${DATASTORE_ID}
BUCKET_NAME=${BUCKET_NAME}

# To clean up resources, run:
# ./destroy.sh

# Access URLs:
# Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}
# Firestore: https://console.cloud.google.com/firestore/data?project=${PROJECT_ID}
# Cloud Run: https://console.cloud.google.com/run?project=${PROJECT_ID}
# Vertex AI Search: https://console.cloud.google.com/gen-app-builder/engines?project=${PROJECT_ID}
EOF
    
    success "Deployment information saved to deployment_info.txt"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would validate deployment"
        return
    fi
    
    # Check if Cloud Run service is running
    if gcloud run services describe "${APP_NAME}" --region="${REGION}" --format="value(status.conditions[0].status)" | grep -q "True"; then
        success "Cloud Run service is running"
    else
        warning "Cloud Run service validation failed"
    fi
    
    # Check if Vertex AI Search engine exists
    if gcloud alpha discovery-engine engines describe "${SEARCH_APP_ID}" --location=global &>/dev/null; then
        success "Vertex AI Search engine is active"
    else
        warning "Vertex AI Search engine validation failed"
    fi
    
    # Test health endpoint if service URL is available
    if [[ -f "deployment_info.txt" ]]; then
        SERVICE_URL=$(grep "SERVICE_URL=" deployment_info.txt | cut -d'=' -f2)
        if [[ -n "${SERVICE_URL}" ]]; then
            if curl -s "${SERVICE_URL}/health" | grep -q "healthy"; then
                success "Health endpoint is responding"
            else
                warning "Health endpoint validation failed"
            fi
        fi
    fi
}

# Main deployment function
main() {
    log "Starting Smart Product Catalog deployment..."
    
    check_prerequisites
    create_project
    enable_apis
    create_firestore
    create_storage
    create_sample_data
    create_datastore
    import_search_data
    create_search_app
    create_app_code
    deploy_cloud_run
    add_firestore_products
    save_deployment_info
    validate_deployment
    
    echo ""
    echo -e "${GREEN}================================================================================================${NC}"
    echo -e "${GREEN}   🎉 Smart Product Catalog deployment completed successfully!${NC}"
    echo -e "${GREEN}================================================================================================${NC}"
    echo ""
    echo "Deployment Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  App Name: ${APP_NAME}"
    echo ""
    echo "Next Steps:"
    echo "  1. Check deployment_info.txt for detailed information"
    echo "  2. Access the Cloud Console to monitor resources"
    echo "  3. Test the API endpoints when data indexing completes (5-10 minutes)"
    echo "  4. Run ./destroy.sh to clean up resources when done"
    echo ""
    echo "Estimated Monthly Cost: $15-25 (depending on usage)"
    echo ""
}

# Handle script interruption
trap 'echo -e "\n${RED}Deployment interrupted. Run ./destroy.sh to clean up any created resources.${NC}"; exit 1' INT

# Run main function
main "$@"