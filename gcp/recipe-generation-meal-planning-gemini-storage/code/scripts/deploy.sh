#!/bin/bash

# Recipe Generation and Meal Planning with Gemini and Storage - Deployment Script
# This script deploys a complete AI-powered recipe generation system using
# Vertex AI Gemini, Cloud Functions, and Cloud Storage

set -euo pipefail

# Color codes for output
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
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check for required tools
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    if ! command_exists gsutil; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    if ! command_exists curl; then
        error_exit "curl is not installed. Please install curl."
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Google Cloud SDK version: ${gcloud_version}"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Check if project ID is provided as argument or environment variable
    if [[ "${1:-}" ]]; then
        export PROJECT_ID="$1"
    elif [[ "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${PROJECT_ID}"
    else
        export PROJECT_ID="recipe-ai-$(date +%s)"
        log_warning "No PROJECT_ID provided, using generated ID: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffix
    export BUCKET_NAME="recipe-storage-${RANDOM_SUFFIX}"
    export FUNCTION_NAME_GEN="recipe-generator"
    export FUNCTION_NAME_GET="recipe-retriever"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    log_success "Environment variables configured"
}

# Create or verify project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --name="Recipe AI Platform"; then
            error_exit "Failed to create project ${PROJECT_ID}"
        fi
        log_success "Project ${PROJECT_ID} created successfully"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Check if billing is enabled
    log_info "Checking billing status..."
    if ! gcloud beta billing projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Billing is not enabled for project ${PROJECT_ID}"
        log_warning "Please enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        read -p "Press Enter after enabling billing to continue..."
    fi
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}"; then
            log_success "Enabled ${api}"
        else
            error_exit "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        # Create bucket
        if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
            log_success "Created bucket: gs://${BUCKET_NAME}"
        else
            error_exit "Failed to create bucket: gs://${BUCKET_NAME}"
        fi
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    log_success "Enabled versioning on bucket"
    
    # Create initial data structure
    echo '{"recipes": [], "preferences": {}}' | gsutil cp - "gs://${BUCKET_NAME}/data/recipes.json"
    echo '{"users": {}}' | gsutil cp - "gs://${BUCKET_NAME}/data/preferences.json"
    
    log_success "Cloud Storage bucket setup completed"
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create generator function
    mkdir -p "${temp_dir}/generator"
    
    cat > "${temp_dir}/generator/requirements.txt" << 'EOF'
google-cloud-aiplatform>=1.38.0
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF
    
    cat > "${temp_dir}/generator/main.py" << 'EOF'
import json
import os
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
from datetime import datetime

# Initialize Vertex AI with project from environment
aiplatform.init(project=os.environ.get('GCP_PROJECT'))

@functions_framework.http
def generate_recipe(request):
    """Generate personalized recipes using Gemini AI"""
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Invalid JSON'}, 400
        
        ingredients = request_json.get('ingredients', [])
        dietary_restrictions = request_json.get('dietary_restrictions', [])
        skill_level = request_json.get('skill_level', 'beginner')
        cuisine_type = request_json.get('cuisine_type', 'any')
        
        if not ingredients:
            return {'error': 'Ingredients list required'}, 400
        
        # Create comprehensive Gemini prompt for recipe generation
        prompt = f"""
        Create a detailed recipe using these ingredients: {', '.join(ingredients)}
        
        Requirements:
        - Dietary restrictions: {', '.join(dietary_restrictions) if dietary_restrictions else 'None'}
        - Cooking skill level: {skill_level}
        - Cuisine preference: {cuisine_type}
        
        Please provide:
        1. Recipe title
        2. Preparation time and cooking time
        3. Ingredient list with quantities
        4. Step-by-step instructions
        5. Nutritional highlights
        6. Serving suggestions
        
        Format as JSON with fields: title, prep_time, cook_time, ingredients_with_quantities, instructions, nutrition_info, serving_suggestions
        """
        
        # Generate content using Gemini 1.5 Flash model
        model = aiplatform.generative_models.GenerativeModel('gemini-1.5-flash')
        response = model.generate_content(prompt)
        
        # Parse and store recipe with metadata
        recipe_data = {
            'id': f"recipe-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            'generated_at': datetime.now().isoformat(),
            'input_ingredients': ingredients,
            'dietary_restrictions': dietary_restrictions,
            'skill_level': skill_level,
            'cuisine_type': cuisine_type,
            'ai_response': response.text
        }
        
        # Store in Cloud Storage with structured path
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
        blob = bucket.blob(f"recipes/{recipe_data['id']}.json")
        blob.upload_from_string(json.dumps(recipe_data, indent=2))
        
        return {
            'success': True,
            'recipe_id': recipe_data['id'],
            'recipe': recipe_data
        }
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Create retriever function
    mkdir -p "${temp_dir}/retriever"
    
    cat > "${temp_dir}/retriever/requirements.txt" << 'EOF'
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF
    
    cat > "${temp_dir}/retriever/main.py" << 'EOF'
import json
import os
from google.cloud import storage
import functions_framework

@functions_framework.http
def retrieve_recipes(request):
    """Retrieve and search stored recipes with filtering capabilities"""
    try:
        # Parse query parameters for flexible search
        args = request.args
        recipe_id = args.get('recipe_id')
        ingredient_filter = args.get('ingredient')
        cuisine_filter = args.get('cuisine')
        limit = int(args.get('limit', 10))
        
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
        
        # If specific recipe requested, return it directly
        if recipe_id:
            blob = bucket.blob(f"recipes/{recipe_id}.json")
            if blob.exists():
                recipe_data = json.loads(blob.download_as_text())
                return {'recipe': recipe_data}
            else:
                return {'error': 'Recipe not found'}, 404
        
        # List all recipes with filtering capabilities
        recipes = []
        blobs = bucket.list_blobs(prefix="recipes/")
        
        for blob in blobs:
            if blob.name.endswith('.json'):
                try:
                    recipe_data = json.loads(blob.download_as_text())
                    
                    # Apply filters based on request parameters
                    include_recipe = True
                    
                    if ingredient_filter:
                        ingredients_text = ' '.join(recipe_data.get('input_ingredients', []))
                        if ingredient_filter.lower() not in ingredients_text.lower():
                            include_recipe = False
                    
                    if cuisine_filter:
                        if cuisine_filter.lower() != recipe_data.get('cuisine_type', '').lower():
                            include_recipe = False
                    
                    if include_recipe:
                        recipes.append({
                            'id': recipe_data.get('id'),
                            'generated_at': recipe_data.get('generated_at'),
                            'ingredients': recipe_data.get('input_ingredients'),
                            'cuisine_type': recipe_data.get('cuisine_type'),
                            'skill_level': recipe_data.get('skill_level')
                        })
                        
                        if len(recipes) >= limit:
                            break
                
                except Exception as e:
                    continue  # Skip malformed recipes gracefully
        
        return {
            'recipes': recipes,
            'total_found': len(recipes)
        }
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Store the temp directory path for later use
    FUNCTION_CODE_DIR="${temp_dir}"
    log_success "Function source code created"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Deploy recipe generation function
    log_info "Deploying recipe generation function..."
    if gcloud functions deploy "${FUNCTION_NAME_GEN}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source "${FUNCTION_CODE_DIR}/generator" \
        --entry-point generate_recipe \
        --memory 512MB \
        --timeout 60s \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME},GCP_PROJECT=${PROJECT_ID}"; then
        log_success "Recipe generation function deployed"
    else
        error_exit "Failed to deploy recipe generation function"
    fi
    
    # Deploy recipe retrieval function
    log_info "Deploying recipe retrieval function..."
    if gcloud functions deploy "${FUNCTION_NAME_GET}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source "${FUNCTION_CODE_DIR}/retriever" \
        --entry-point retrieve_recipes \
        --memory 256MB \
        --timeout 30s \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}"; then
        log_success "Recipe retrieval function deployed"
    else
        error_exit "Failed to deploy recipe retrieval function"
    fi
    
    # Get function URLs
    GENERATOR_URL=$(gcloud functions describe "${FUNCTION_NAME_GEN}" --format="value(httpsTrigger.url)")
    RETRIEVER_URL=$(gcloud functions describe "${FUNCTION_NAME_GET}" --format="value(httpsTrigger.url)")
    
    log_success "Cloud Functions deployed successfully"
    log_info "Generator URL: ${GENERATOR_URL}"
    log_info "Retriever URL: ${RETRIEVER_URL}"
}

# Configure IAM permissions
setup_iam() {
    log_info "Setting up IAM permissions..."
    
    # Get the default Cloud Functions service account
    local project_number
    project_number=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    local functions_sa="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    # Grant Vertex AI User role
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${functions_sa}" \
        --role="roles/aiplatform.user"; then
        log_success "Granted Vertex AI User role"
    else
        log_warning "Failed to grant Vertex AI User role (may already exist)"
    fi
    
    # Grant Storage Object Admin role
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${functions_sa}" \
        --role="roles/storage.objectAdmin"; then
        log_success "Granted Storage Object Admin role"
    else
        log_warning "Failed to grant Storage Object Admin role (may already exist)"
    fi
    
    log_success "IAM permissions configured"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test recipe generation
    log_info "Testing recipe generation API..."
    local test_response
    test_response=$(curl -s -X POST "${GENERATOR_URL}" \
        -H "Content-Type: application/json" \
        -d '{
            "ingredients": ["chicken", "rice", "vegetables"],
            "dietary_restrictions": [],
            "skill_level": "beginner",
            "cuisine_type": "any"
        }' || echo "")
    
    if [[ -n "${test_response}" && "${test_response}" == *"success"* ]]; then
        log_success "Recipe generation API test passed"
    else
        log_warning "Recipe generation API test failed or returned unexpected response"
        log_info "Response: ${test_response}"
    fi
    
    # Test recipe retrieval
    log_info "Testing recipe retrieval API..."
    local retrieval_response
    retrieval_response=$(curl -s "${RETRIEVER_URL}?limit=1" || echo "")
    
    if [[ -n "${retrieval_response}" && "${retrieval_response}" == *"recipes"* ]]; then
        log_success "Recipe retrieval API test passed"
    else
        log_warning "Recipe retrieval API test failed or returned unexpected response"
        log_info "Response: ${retrieval_response}"
    fi
}

# Cleanup temporary files
cleanup_temp() {
    if [[ -n "${FUNCTION_CODE_DIR:-}" && -d "${FUNCTION_CODE_DIR}" ]]; then
        rm -rf "${FUNCTION_CODE_DIR}"
        log_info "Cleaned up temporary function code directory"
    fi
}

# Display deployment summary
show_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Project Information:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Bucket: gs://${BUCKET_NAME}"
    echo
    log_info "Cloud Functions:"
    echo "  Recipe Generator: ${GENERATOR_URL}"
    echo "  Recipe Retriever: ${RETRIEVER_URL}"
    echo
    log_info "API Examples:"
    echo "  Generate Recipe:"
    echo "    curl -X POST ${GENERATOR_URL} \\"
    echo "      -H 'Content-Type: application/json' \\"
    echo "      -d '{\"ingredients\": [\"chicken\", \"rice\"], \"skill_level\": \"beginner\"}'"
    echo
    echo "  Retrieve Recipes:"
    echo "    curl \"${RETRIEVER_URL}?ingredient=chicken&limit=5\""
    echo
    log_info "Next Steps:"
    echo "  1. Test the APIs using the examples above"
    echo "  2. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME_GEN}"
    echo "  3. Check storage: gsutil ls gs://${BUCKET_NAME}/recipes/"
    echo "  4. Monitor costs in the Google Cloud Console"
    echo
    log_warning "Remember to run destroy.sh when you're done to avoid ongoing charges!"
}

# Main deployment function
main() {
    log_info "Starting Recipe Generation and Meal Planning deployment..."
    
    # Set trap for cleanup on exit
    trap cleanup_temp EXIT
    
    validate_prerequisites
    setup_environment "$@"
    setup_project
    enable_apis
    create_storage_bucket
    create_function_code
    deploy_functions
    setup_iam
    test_deployment
    show_summary
    
    log_success "Deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi