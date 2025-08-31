#!/bin/bash

# MongoDB to Firestore Migration with API Compatibility - Deployment Script
# This script deploys all infrastructure components for the migration solution

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/mongodb-firestore-migration-deploy-$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Error handling
error_exit() {
    log ERROR "$1"
    log ERROR "Deployment failed. Check log file: $LOG_FILE"
    exit 1
}

# Cleanup on script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Script failed with exit code $exit_code"
        log INFO "To clean up partially deployed resources, run: ./destroy.sh"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Banner
show_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          MongoDB to Firestore Migration Deployment          ║"
    echo "║                    GCP Recipe Solution                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Prerequisites check
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null | head -n1)
    log INFO "Found gcloud CLI version: $gcloud_version"
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error_exit "Not authenticated with gcloud. Run: gcloud auth login"
    fi
    
    # Check for required tools
    local tools=("curl" "python3" "openssl" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is required but not installed"
        fi
    done
    
    # Check Python version
    local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    log INFO "Found Python version: $python_version"
    
    log INFO "✅ All prerequisites check passed"
}

# Project setup
setup_project() {
    log INFO "Setting up GCP project..."
    
    # Generate unique project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="mongo-migration-$(date +%s)"
        log INFO "Generated project ID: $PROJECT_ID"
    fi
    
    # Set environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    log INFO "Configuration:"
    log INFO "  Project ID: $PROJECT_ID"
    log INFO "  Region: $REGION"
    log INFO "  Zone: $ZONE"
    log INFO "  Random Suffix: $RANDOM_SUFFIX"
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would configure gcloud project settings"
        return 0
    fi
    
    # Configure gcloud settings
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
    gcloud config set compute/zone "$ZONE" || error_exit "Failed to set zone"
    
    log INFO "✅ Project setup completed"
}

# Enable APIs
enable_apis() {
    log INFO "Enabling required Google Cloud APIs..."
    
    local apis=(
        "firestore.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "secretmanager.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log INFO "Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            error_exit "Failed to enable API: $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log INFO "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log INFO "✅ APIs enabled successfully"
}

# Create Firestore database
create_firestore_database() {
    log INFO "Creating Firestore database..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would create Firestore database in Native mode"
        return 0
    fi
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --database="(default)" --quiet &> /dev/null; then
        log WARN "Firestore database already exists, skipping creation"
        return 0
    fi
    
    # Create Firestore database in Native mode
    if ! gcloud firestore databases create --region="$REGION" --quiet; then
        error_exit "Failed to create Firestore database"
    fi
    
    log INFO "✅ Firestore database created in Native mode"
}

# Create MongoDB connection secret
create_mongodb_secret() {
    log INFO "Creating MongoDB connection secret..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would create MongoDB connection secret"
        return 0
    fi
    
    # Check if secret already exists
    if gcloud secrets describe mongodb-connection-string --quiet &> /dev/null; then
        log WARN "MongoDB connection secret already exists, skipping creation"
    else
        # Create placeholder secret (to be updated with real credentials)
        local placeholder_connection="mongodb://username:password@host:port/database"
        echo "$placeholder_connection" | gcloud secrets create mongodb-connection-string \
            --data-file=- || error_exit "Failed to create MongoDB connection secret"
        
        log WARN "⚠️  Created placeholder MongoDB connection string"
        log WARN "⚠️  Update with real credentials: gcloud secrets versions add mongodb-connection-string --data-file=connection_string.txt"
    fi
    
    # Grant Cloud Functions access to the secret
    local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
    if ! gcloud secrets add-iam-policy-binding mongodb-connection-string \
        --member="serviceAccount:$service_account" \
        --role="roles/secretmanager.secretAccessor" --quiet; then
        error_exit "Failed to grant secret access to Cloud Functions"
    fi
    
    log INFO "✅ MongoDB connection secret configured"
}

# Deploy migration function
deploy_migration_function() {
    log INFO "Deploying MongoDB to Firestore migration function..."
    
    local function_dir="/tmp/migration-function-$$"
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would deploy migration function"
        return 0
    fi
    
    # Create temporary function directory
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
google-cloud-firestore==2.18.1
pymongo==4.6.2
google-cloud-secret-manager==2.20.2
functions-framework==3.8.1
EOF
    
    # Create main.py
    cat > "$function_dir/main.py" << 'EOF'
import os
import json
from google.cloud import firestore
from google.cloud import secretmanager
import pymongo
import functions_framework

def get_mongodb_connection():
    """Retrieve MongoDB connection string from Secret Manager"""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{os.environ['GCP_PROJECT']}/secrets/mongodb-connection-string/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def migrate_collection(request):
    """HTTP function to migrate a MongoDB collection to Firestore"""
    try:
        # Parse request parameters
        request_json = request.get_json(silent=True)
        collection_name = request_json.get('collection', 'users')
        batch_size = int(request_json.get('batch_size', 100))
        
        # Initialize clients
        mongo_client = pymongo.MongoClient(get_mongodb_connection())
        firestore_client = firestore.Client()
        
        # Get source collection
        db_name = mongo_client.list_database_names()[0]  # Use first database
        mongo_collection = mongo_client[db_name][collection_name]
        
        # Migrate documents in batches
        batch = firestore_client.batch()
        count = 0
        
        for doc in mongo_collection.find():
            # Convert MongoDB ObjectId to string for Firestore compatibility
            doc_id = str(doc.pop('_id'))
            
            # Create Firestore document reference
            doc_ref = firestore_client.collection(collection_name).document(doc_id)
            batch.set(doc_ref, doc)
            count += 1
            
            # Commit batch when size limit reached
            if count % batch_size == 0:
                batch.commit()
                batch = firestore_client.batch()
                print(f"Migrated {count} documents...")
        
        # Commit remaining documents
        if count % batch_size != 0:
            batch.commit()
        
        return json.dumps({
            'status': 'success',
            'collection': collection_name,
            'documents_migrated': count
        })
        
    except Exception as e:
        return json.dumps({
            'status': 'error',
            'message': str(e)
        }), 500
EOF
    
    # Deploy the migration function
    log INFO "Deploying migration function from $function_dir..."
    if ! gcloud functions deploy migrate-mongodb-collection \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source "$function_dir" \
        --entry-point migrate_collection \
        --memory 512Mi \
        --timeout 540s \
        --set-env-vars "GCP_PROJECT=$PROJECT_ID" \
        --quiet; then
        error_exit "Failed to deploy migration function"
    fi
    
    # Clean up temporary directory
    rm -rf "$function_dir"
    
    log INFO "✅ Migration function deployed successfully"
}

# Deploy compatibility API
deploy_compatibility_api() {
    log INFO "Deploying MongoDB compatibility API..."
    
    local api_dir="/tmp/compatibility-api-$$"
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would deploy compatibility API"
        return 0
    fi
    
    # Create temporary API directory
    mkdir -p "$api_dir"
    
    # Create requirements.txt
    cat > "$api_dir/requirements.txt" << 'EOF'
google-cloud-firestore==2.18.1
functions-framework==3.8.1
flask==3.0.3
EOF
    
    # Create main.py
    cat > "$api_dir/main.py" << 'EOF'
import json
from google.cloud import firestore
import functions_framework
from flask import Request

# Initialize Firestore client
db = firestore.Client()

@functions_framework.http
def mongo_api_compatibility(request: Request):
    """MongoDB-compatible API endpoints for Firestore"""
    
    if request.method == 'POST':
        return handle_post_request(request)
    elif request.method == 'GET':
        return handle_get_request(request)
    elif request.method == 'PUT':
        return handle_put_request(request)
    elif request.method == 'DELETE':
        return handle_delete_request(request)
    else:
        return {'error': 'Method not allowed'}, 405

def handle_post_request(request):
    """Handle document creation (insertOne/insertMany)"""
    try:
        data = request.get_json()
        collection_name = data.get('collection')
        documents = data.get('documents', [])
        
        if not isinstance(documents, list):
            documents = [documents]
        
        results = []
        for doc in documents:
            doc_ref = db.collection(collection_name).add(doc)
            results.append({'_id': doc_ref[1].id, 'acknowledged': True})
        
        return {
            'acknowledged': True,
            'insertedIds': [r['_id'] for r in results],
            'insertedCount': len(results)
        }
        
    except Exception as e:
        return {'error': str(e)}, 500

def handle_get_request(request):
    """Handle document queries (find)"""
    try:
        collection_name = request.args.get('collection')
        limit = int(request.args.get('limit', 20))
        
        # Simple query - extend for complex MongoDB query compatibility
        docs = db.collection(collection_name).limit(limit).stream()
        
        results = []
        for doc in docs:
            doc_data = doc.to_dict()
            doc_data['_id'] = doc.id
            results.append(doc_data)
        
        return {
            'documents': results,
            'count': len(results)
        }
        
    except Exception as e:
        return {'error': str(e)}, 500

def handle_put_request(request):
    """Handle document updates (updateOne/updateMany)"""
    try:
        data = request.get_json()
        collection_name = data.get('collection')
        document_id = data.get('_id')
        update_data = data.get('update', {})
        
        doc_ref = db.collection(collection_name).document(document_id)
        doc_ref.update(update_data)
        
        return {
            'acknowledged': True,
            'modifiedCount': 1,
            'matchedCount': 1
        }
        
    except Exception as e:
        return {'error': str(e)}, 500

def handle_delete_request(request):
    """Handle document deletion (deleteOne/deleteMany)"""
    try:
        collection_name = request.args.get('collection')
        document_id = request.args.get('_id')
        
        db.collection(collection_name).document(document_id).delete()
        
        return {
            'acknowledged': True,
            'deletedCount': 1
        }
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Deploy the compatibility API
    log INFO "Deploying compatibility API from $api_dir..."
    if ! gcloud functions deploy mongo-compatibility-api \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source "$api_dir" \
        --entry-point mongo_api_compatibility \
        --memory 256Mi \
        --timeout 60s \
        --quiet; then
        error_exit "Failed to deploy compatibility API"
    fi
    
    # Clean up temporary directory
    rm -rf "$api_dir"
    
    # Get the API endpoint URL
    local api_url
    api_url=$(gcloud functions describe mongo-compatibility-api \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "")
    
    if [ -n "$api_url" ]; then
        log INFO "✅ MongoDB compatibility API deployed at: $api_url"
        echo "$api_url" > /tmp/mongo-api-url.txt
    else
        log WARN "Could not retrieve API URL"
    fi
    
    log INFO "✅ Compatibility API deployed successfully"
}

# Create Cloud Build pipeline
create_build_pipeline() {
    log INFO "Creating Cloud Build migration pipeline..."
    
    local build_config="/tmp/cloudbuild-$$.yaml"
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would create Cloud Build pipeline"
        return 0
    fi
    
    # Create Cloud Build configuration
    cat > "$build_config" << EOF
steps:
# Validate source MongoDB connection
- name: 'python:3.12'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install pymongo google-cloud-secret-manager
    python -c "
    from google.cloud import secretmanager
    import pymongo
    import os
    
    client = secretmanager.SecretManagerServiceClient()
    name = f'projects/\$PROJECT_ID/secrets/mongodb-connection-string/versions/latest'
    response = client.access_secret_version(request={'name': name})
    connection_string = response.payload.data.decode('UTF-8')
    
    # Only validate connection format for placeholder
    if 'username:password@host:port' in connection_string:
        print('⚠️  Using placeholder connection string')
        print('   Update with real credentials before running migration')
    else:
        mongo_client = pymongo.MongoClient(connection_string)
        databases = mongo_client.list_database_names()
        print(f'✅ MongoDB connection validated. Databases found: {databases}')
    "

# Execute migration for each collection
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk:latest'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    # Get migration function URL
    MIGRATION_URL=\$(gcloud functions describe migrate-mongodb-collection \
        --format="value(serviceConfig.uri)")
    
    # Migrate common collections (customize based on your schema)
    for collection in users products orders; do
      echo "Migrating collection: \$collection"
      if curl -X POST "\$MIGRATION_URL" \
        -H "Content-Type: application/json" \
        -d "{\\"collection\\": \\"\$collection\\", \\"batch_size\\": 100}" \
        --fail --silent --show-error; then
        echo "✅ Collection \$collection migration completed"
      else
        echo "⚠️  Collection \$collection migration failed or no data found"
      fi
    done

# Validate migrated data in Firestore
- name: 'python:3.12'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install google-cloud-firestore
    python -c "
    from google.cloud import firestore
    
    db = firestore.Client()
    collections = ['users', 'products', 'orders']
    
    for collection_name in collections:
        try:
            docs = list(db.collection(collection_name).limit(5).stream())
            count = len(docs)
            print(f'✅ Validation: {collection_name} has {count} documents in Firestore')
        except Exception as e:
            print(f'⚠️  Collection {collection_name}: {e}')
    "

substitutions:
  _REGION: '$REGION'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'
EOF
    
    log INFO "Cloud Build configuration created at $build_config"
    log INFO "To execute migration pipeline, run:"
    log INFO "  gcloud builds submit --config $build_config --substitutions _REGION=$REGION"
    
    # Save build config for later use
    cp "$build_config" "/tmp/migration-cloudbuild.yaml"
    
    log INFO "✅ Cloud Build pipeline configuration ready"
}

# Create application integration example
create_integration_example() {
    log INFO "Creating application integration example..."
    
    local integration_file="/tmp/application-integration.py"
    
    cat > "$integration_file" << 'EOF'
"""
Sample application code showing MongoDB to Firestore compatibility integration
"""
import requests
import json

class FirestoreMongoClient:
    """MongoDB-compatible client for Firestore"""
    
    def __init__(self, api_url):
        self.api_url = api_url.rstrip('/')
    
    def collection(self, name):
        return FirestoreCollection(self.api_url, name)

class FirestoreCollection:
    """MongoDB-compatible collection interface"""
    
    def __init__(self, api_url, collection_name):
        self.api_url = api_url
        self.collection_name = collection_name
    
    def insert_one(self, document):
        """Insert a single document"""
        response = requests.post(self.api_url, json={
            'collection': self.collection_name,
            'documents': document
        })
        return response.json()
    
    def find(self, query=None, limit=20):
        """Find documents (simplified query support)"""
        params = {
            'collection': self.collection_name,
            'limit': limit
        }
        response = requests.get(self.api_url, params=params)
        result = response.json()
        return result.get('documents', [])
    
    def update_one(self, filter_doc, update_doc):
        """Update a single document"""
        document_id = filter_doc.get('_id')
        response = requests.put(self.api_url, json={
            'collection': self.collection_name,
            '_id': document_id,
            'update': update_doc
        })
        return response.json()
    
    def delete_one(self, filter_doc):
        """Delete a single document"""
        document_id = filter_doc.get('_id')
        params = {
            'collection': self.collection_name,
            '_id': document_id
        }
        response = requests.delete(self.api_url, params=params)
        return response.json()

# Example usage showing minimal code changes
def example_usage():
    # Original MongoDB client (commented out)
    # client = pymongo.MongoClient("mongodb://localhost:27017/")
    # db = client['myapp']
    
    # New Firestore-compatible client
    API_URL = "REPLACE_WITH_YOUR_API_URL"
    client = FirestoreMongoClient(API_URL)
    
    # Collection operations remain the same
    users = client.collection('users')
    
    # Insert operation
    result = users.insert_one({
        'name': 'John Doe',
        'email': 'john@example.com',
        'age': 30
    })
    print(f"Inserted user: {result}")
    
    # Find operation
    all_users = users.find(limit=10)
    print(f"Found {len(all_users)} users")
    
    # Update operation
    if all_users:
        user_id = all_users[0]['_id']
        users.update_one(
            {'_id': user_id},
            {'age': 31}
        )
        print(f"Updated user {user_id}")

if __name__ == '__main__':
    example_usage()
EOF
    
    log INFO "✅ Application integration example created at $integration_file"
}

# Validate deployment
validate_deployment() {
    log INFO "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Check Firestore database
    if gcloud firestore databases describe --database="(default)" --quiet &> /dev/null; then
        log INFO "✅ Firestore database is accessible"
    else
        log WARN "⚠️  Firestore database validation failed"
    fi
    
    # Check migration function
    if gcloud functions describe migrate-mongodb-collection --quiet &> /dev/null; then
        log INFO "✅ Migration function is deployed"
    else
        log WARN "⚠️  Migration function validation failed"
    fi
    
    # Check compatibility API
    if gcloud functions describe mongo-compatibility-api --quiet &> /dev/null; then
        log INFO "✅ Compatibility API is deployed"
    else
        log WARN "⚠️  Compatibility API validation failed"
    fi
    
    # Check secret
    if gcloud secrets describe mongodb-connection-string --quiet &> /dev/null; then
        log INFO "✅ MongoDB connection secret exists"
    else
        log WARN "⚠️  MongoDB connection secret validation failed"
    fi
    
    log INFO "✅ Deployment validation completed"
}

# Display deployment summary
show_summary() {
    local api_url=""
    if [ -f "/tmp/mongo-api-url.txt" ]; then
        api_url=$(cat /tmp/mongo-api-url.txt)
    fi
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Deployment Summary                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    log INFO "Deployment completed successfully!"
    log INFO ""
    log INFO "📋 Deployed Resources:"
    log INFO "  • Firestore database (Native mode)"
    log INFO "  • Migration Cloud Function: migrate-mongodb-collection"
    log INFO "  • Compatibility API Function: mongo-compatibility-api"
    log INFO "  • MongoDB connection secret: mongodb-connection-string"
    log INFO "  • Cloud Build pipeline configuration"
    log INFO ""
    
    if [ -n "$api_url" ]; then
        log INFO "🔗 API Endpoints:"
        log INFO "  • Compatibility API: $api_url"
        log INFO ""
    fi
    
    log INFO "📝 Next Steps:"
    log INFO "  1. Update MongoDB connection string:"
    log INFO "     echo 'mongodb://real-host:port/db' | gcloud secrets versions add mongodb-connection-string --data-file=-"
    log INFO ""
    log INFO "  2. Run migration pipeline:"
    log INFO "     gcloud builds submit --config /tmp/migration-cloudbuild.yaml --substitutions _REGION=$REGION"
    log INFO ""
    log INFO "  3. Test compatibility API with sample application code:"
    log INFO "     python3 /tmp/application-integration.py"
    log INFO ""
    log INFO "  4. Monitor resources:"
    log INFO "     • Firestore: https://console.cloud.google.com/firestore"
    log INFO "     • Cloud Functions: https://console.cloud.google.com/functions"
    log INFO "     • Cloud Build: https://console.cloud.google.com/cloud-build"
    log INFO ""
    log INFO "📊 Log file: $LOG_FILE"
    
    if [ "$DRY_RUN" = "true" ]; then
        log WARN "This was a DRY RUN - no resources were actually created"
    fi
}

# Main execution
main() {
    show_banner
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --dry-run         Validate configuration without deploying"
                echo "  --project-id ID   Specify GCP project ID"
                echo "  --region REGION   Specify GCP region (default: us-central1)"
                echo "  --help            Show this help message"
                exit 0
                ;;
            *)
                log WARN "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    log INFO "Starting deployment process..."
    log INFO "Log file: $LOG_FILE"
    
    check_prerequisites
    setup_project
    enable_apis
    create_firestore_database
    create_mongodb_secret
    deploy_migration_function
    deploy_compatibility_api
    create_build_pipeline
    create_integration_example
    validate_deployment
    show_summary
    
    log INFO "🎉 MongoDB to Firestore migration infrastructure deployed successfully!"
}

# Execute main function
main "$@"