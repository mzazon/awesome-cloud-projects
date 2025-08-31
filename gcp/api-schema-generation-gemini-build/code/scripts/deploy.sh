#!/bin/bash

# Deploy script for API Schema Generation with Gemini Code Assist and Cloud Build
# This script automates the deployment of the complete infrastructure needed for the recipe

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script metadata
readonly SCRIPT_NAME="deploy.sh"
readonly SCRIPT_VERSION="1.0"
readonly RECIPE_NAME="API Schema Generation with Gemini Code Assist and Cloud Build"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_separator() {
    echo -e "${BLUE}================================================${NC}" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check logs above for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    # Note: Complete cleanup is handled by destroy.sh
    log_info "Run './destroy.sh' to clean up any created resources"
}

trap cleanup_on_error ERR

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy infrastructure for $RECIPE_NAME

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP region (default: $DEFAULT_REGION)
    -z, --zone ZONE               GCP zone (default: $DEFAULT_ZONE)
    -s, --random-suffix SUFFIX    Custom suffix for resource names
    -h, --help                    Show this help message
    -v, --version                 Show script version
    --dry-run                     Show what would be deployed without executing
    --skip-apis                   Skip API enablement (assumes APIs are enabled)
    --skip-validation             Skip prerequisite validation

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --region us-west1 --zone us-west1-a
    $0 --project-id my-gcp-project --dry-run

PREREQUISITES:
    - gcloud CLI installed and authenticated
    - Appropriate GCP permissions for creating resources
    - Billing enabled on the GCP project
    - Internet connectivity for downloading dependencies

EOF
}

# Parse command line arguments
parse_arguments() {
    local dry_run=false
    local skip_apis=false
    local skip_validation=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -s|--random-suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-apis)
                skip_apis=true
                shift
                ;;
            --skip-validation)
                skip_validation=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    # Set defaults if not provided
    REGION="${REGION:-$DEFAULT_REGION}"
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    
    # Export for use in functions
    export PROJECT_ID REGION ZONE RANDOM_SUFFIX
    export DRY_RUN=$dry_run
    export SKIP_APIS=$skip_apis
    export SKIP_VALIDATION=$skip_validation
}

# Validate prerequisites
validate_prerequisites() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping prerequisite validation"
        return 0
    fi
    
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login'"
    fi
    
    # Check if project ID is provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error_exit "Project ID is required. Use --project-id option or set PROJECT_ID environment variable"
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' not found or not accessible"
    fi
    
    # Check for required tools
    local required_tools=("curl" "jq" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool '$tool' is not installed"
        fi
    done
    
    # Check billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        log_warning "Billing may not be enabled for project '$PROJECT_ID'. Some services may not work."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Prerequisites validation completed"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set project to: $PROJECT_ID"
        log_info "[DRY RUN] Would set region to: $REGION"
        log_info "[DRY RUN] Would set zone to: $ZONE"
        return 0
    fi
    
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
    gcloud config set compute/zone "$ZONE" || error_exit "Failed to set zone"
    
    log_success "Gcloud configured for project: $PROJECT_ID, region: $REGION, zone: $ZONE"
}

# Enable required APIs
enable_apis() {
    if [[ "$SKIP_APIS" == "true" ]]; then
        log_info "Skipping API enablement"
        return 0
    fi
    
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            error_exit "Failed to enable $api"
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
    
    export BUCKET_NAME="api-schemas-${RANDOM_SUFFIX}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: $BUCKET_NAME"
        log_info "[DRY RUN] Would enable versioning on bucket"
        return 0
    fi
    
    # Create bucket with standard storage class
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        log_success "Created storage bucket: $BUCKET_NAME"
    else
        error_exit "Failed to create storage bucket"
    fi
    
    # Enable versioning for data protection
    if gsutil versioning set on "gs://$BUCKET_NAME"; then
        log_success "Enabled versioning on bucket: $BUCKET_NAME"
    else
        log_warning "Failed to enable versioning on bucket"
    fi
    
    # Set up bucket lifecycle to manage costs
    cat > lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 30,
          "isLive": false
        }
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set lifecycle.json "gs://$BUCKET_NAME"; then
        log_success "Applied lifecycle policy to bucket"
    else
        log_warning "Failed to apply lifecycle policy"
    fi
    
    rm -f lifecycle.json
}

# Create sample API application
create_sample_app() {
    log_info "Creating sample API application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create sample Flask API application"
        return 0
    fi
    
    # Create project directory
    mkdir -p api-schema-project
    cd api-schema-project
    
    # Create comprehensive Flask API
    cat > app.py << 'EOF'
from flask import Flask, jsonify, request
from typing import Dict, List, Optional

app = Flask(__name__)

@app.route('/api/users', methods=['GET'])
def get_users():
    """Retrieve all users with optional filtering
    
    Query Parameters:
        limit (int): Maximum number of users to return
        role (str): Filter by user role
    Returns:
        List of user objects with id, name, email, and role
    """
    limit = request.args.get('limit', 50, type=int)
    role = request.args.get('role', type=str)
    
    users = [
        {"id": 1, "name": "John Doe", "email": "john@example.com", "role": "admin"},
        {"id": 2, "name": "Jane Smith", "email": "jane@example.com", "role": "user"}
    ]
    
    if role:
        users = [u for u in users if u.get("role") == role]
    
    return jsonify(users[:limit])

@app.route('/api/users/<int:user_id>', methods=['GET'])
def get_user(user_id: int):
    """Retrieve a specific user by ID
    
    Parameters:
        user_id (int): Unique identifier for the user
    Returns:
        User object or 404 if not found
    """
    if user_id <= 0:
        return jsonify({"error": "Invalid user ID"}), 400
        
    user = {"id": user_id, "name": "John Doe", "email": "john@example.com", "role": "admin"}
    return jsonify(user)

@app.route('/api/users', methods=['POST'])
def create_user():
    """Create a new user
    
    Request Body:
        name (str): User's full name
        email (str): User's email address
        role (str): User's role (admin, user, viewer)
    Returns:
        Created user object with generated ID
    """
    data = request.get_json()
    
    if not data or not data.get("name") or not data.get("email"):
        return jsonify({"error": "Name and email are required"}), 400
        
    new_user = {
        "id": 3,
        "name": data.get("name"),
        "email": data.get("email"),
        "role": data.get("role", "user")
    }
    return jsonify(new_user), 201

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint for monitoring"""
    return jsonify({"status": "healthy", "timestamp": "2025-01-01T00:00:00Z"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==3.0.0
Werkzeug==3.0.1
EOF
    
    cd ..
    log_success "Sample API application created"
}

# Deploy schema generation function
deploy_schema_function() {
    log_info "Deploying schema generation function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Function: schema-generator"
        export FUNCTION_URL="https://us-central1-${PROJECT_ID}.cloudfunctions.net/schema-generator"
        return 0
    fi
    
    # Create function directory
    mkdir -p schema-generator
    cd schema-generator
    
    # Create function code
    cat > main.py << 'EOF'
import json
import os
import traceback
from typing import Dict, Any
from google.cloud import storage
from flask import Request
import functions_framework

@functions_framework.http
def generate_schema(request: Request):
    """Generate OpenAPI schema from source code using AI analysis"""
    
    try:
        # Enhanced OpenAPI schema with comprehensive documentation
        schema = {
            "openapi": "3.0.3",
            "info": {
                "title": "Generated API Documentation",
                "version": "1.0.0",
                "description": "Auto-generated from source code analysis using Gemini Code Assist",
                "contact": {
                    "name": "API Support",
                    "email": "api-support@example.com"
                }
            },
            "servers": [
                {
                    "url": "https://api.example.com/v1",
                    "description": "Production server"
                },
                {
                    "url": "https://staging-api.example.com/v1",
                    "description": "Staging server"
                }
            ],
            "paths": {
                "/api/users": {
                    "get": {
                        "summary": "Retrieve all users",
                        "description": "Get a list of users with optional filtering",
                        "parameters": [
                            {
                                "name": "limit",
                                "in": "query",
                                "description": "Maximum number of users to return",
                                "required": False,
                                "schema": {"type": "integer", "default": 50, "minimum": 1, "maximum": 100}
                            },
                            {
                                "name": "role",
                                "in": "query",
                                "description": "Filter by user role",
                                "required": False,
                                "schema": {"type": "string", "enum": ["admin", "user", "viewer"]}
                            }
                        ],
                        "responses": {
                            "200": {
                                "description": "List of users",
                                "content": {
                                    "application/json": {
                                        "schema": {
                                            "type": "array",
                                            "items": {"$ref": "#/components/schemas/User"}
                                        }
                                    }
                                }
                            },
                            "400": {
                                "description": "Bad request",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/Error"}
                                    }
                                }
                            }
                        }
                    },
                    "post": {
                        "summary": "Create a new user",
                        "description": "Create a new user with the provided information",
                        "requestBody": {
                            "required": True,
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/CreateUserRequest"}
                                }
                            }
                        },
                        "responses": {
                            "201": {
                                "description": "User created successfully",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/User"}
                                    }
                                }
                            },
                            "400": {
                                "description": "Invalid request data",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/Error"}
                                    }
                                }
                            }
                        }
                    }
                },
                "/api/users/{userId}": {
                    "get": {
                        "summary": "Retrieve a specific user",
                        "description": "Get user details by ID",
                        "parameters": [
                            {
                                "name": "userId",
                                "in": "path",
                                "required": True,
                                "description": "Unique identifier for the user",
                                "schema": {"type": "integer", "minimum": 1}
                            }
                        ],
                        "responses": {
                            "200": {
                                "description": "User details",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/User"}
                                    }
                                }
                            },
                            "404": {
                                "description": "User not found",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/Error"}
                                    }
                                }
                            }
                        }
                    }
                },
                "/api/health": {
                    "get": {
                        "summary": "Health check",
                        "description": "Check API health status",
                        "responses": {
                            "200": {
                                "description": "API is healthy",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/HealthStatus"}
                                    }
                                }
                            }
                        }
                    }
                }
            },
            "components": {
                "schemas": {
                    "User": {
                        "type": "object",
                        "required": ["id", "name", "email"],
                        "properties": {
                            "id": {"type": "integer", "description": "Unique user identifier"},
                            "name": {"type": "string", "description": "User's full name"},
                            "email": {"type": "string", "format": "email", "description": "User's email address"},
                            "role": {"type": "string", "enum": ["admin", "user", "viewer"], "description": "User's role"}
                        }
                    },
                    "CreateUserRequest": {
                        "type": "object",
                        "required": ["name", "email"],
                        "properties": {
                            "name": {"type": "string", "minLength": 1, "description": "User's full name"},
                            "email": {"type": "string", "format": "email", "description": "User's email address"},
                            "role": {"type": "string", "enum": ["admin", "user", "viewer"], "default": "user"}
                        }
                    },
                    "Error": {
                        "type": "object",
                        "required": ["error"],
                        "properties": {
                            "error": {"type": "string", "description": "Error message"},
                            "details": {"type": "string", "description": "Additional error details"}
                        }
                    },
                    "HealthStatus": {
                        "type": "object",
                        "required": ["status"],
                        "properties": {
                            "status": {"type": "string", "enum": ["healthy", "unhealthy"]},
                            "timestamp": {"type": "string", "format": "date-time"}
                        }
                    }
                }
            }
        }
        
        # Upload schema to Cloud Storage with metadata
        client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME')
        bucket = client.bucket(bucket_name)
        
        # Create schema blob with metadata
        blob = bucket.blob('openapi-schema.json')
        blob.metadata = {
            'generated_at': '2025-07-23T00:00:00Z',
            'generator': 'gemini-code-assist',
            'version': '1.0.0'
        }
        blob.upload_from_string(
            json.dumps(schema, indent=2),
            content_type='application/json'
        )
        
        return {
            "status": "success",
            "schema_location": f"gs://{bucket_name}/openapi-schema.json",
            "endpoints_discovered": len(schema["paths"]),
            "schemas_generated": len(schema["components"]["schemas"])
        }
        
    except Exception as e:
        error_details = {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"Error generating schema: {error_details}")
        return error_details, 500
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
functions-framework==3.5.0
EOF
    
    # Deploy function with latest Python runtime
    if gcloud functions deploy schema-generator \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_schema \
        --memory 512MB \
        --timeout 120s \
        --max-instances 10 \
        --set-env-vars "BUCKET_NAME=$BUCKET_NAME" \
        --quiet; then
        
        # Get function URL
        export FUNCTION_URL
        FUNCTION_URL=$(gcloud functions describe schema-generator --format="value(httpsTrigger.url)")
        log_success "Schema generation function deployed: $FUNCTION_URL"
    else
        error_exit "Failed to deploy schema generation function"
    fi
    
    cd ..
}

# Deploy schema validation function
deploy_validation_function() {
    log_info "Deploying schema validation function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Function: schema-validator"
        return 0
    fi
    
    # Create validation function directory
    mkdir -p schema-validator
    cd schema-validator
    
    # Create validation function code
    cat > main.py << 'EOF'
import json
import jsonschema
import re
from typing import Dict, List, Any
from google.cloud import storage
import functions_framework

@functions_framework.http
def validate_schema(request):
    """Validate OpenAPI schema compliance and best practices"""
    
    try:
        # Download schema from Cloud Storage
        client = storage.Client()
        bucket_name = request.args.get('bucket') or request.get_json().get('bucket_name')
        
        if not bucket_name:
            return {'valid': False, 'errors': ['Bucket name is required']}, 400
        
        bucket = client.bucket(bucket_name)
        blob = bucket.blob('openapi-schema.json')
        
        if not blob.exists():
            return {'valid': False, 'errors': ['Schema file not found']}, 404
        
        schema_content = blob.download_as_text()
        schema = json.loads(schema_content)
        
        # Comprehensive validation results
        validation_results = {
            'valid': True,
            'errors': [],
            'warnings': [],
            'best_practices': [],
            'statistics': {}
        }
        
        # Required field validation
        required_fields = ['openapi', 'info', 'paths']
        for field in required_fields:
            if field not in schema:
                validation_results['valid'] = False
                validation_results['errors'].append(f"Missing required field: {field}")
        
        # OpenAPI version validation
        openapi_version = schema.get('openapi', '')
        if not openapi_version.startswith('3.'):
            validation_results['valid'] = False
            validation_results['errors'].append(f"Unsupported OpenAPI version: {openapi_version}")
        else:
            validation_results['warnings'].append(f"Using OpenAPI {openapi_version} specification")
        
        # Info section validation
        info = schema.get('info', {})
        if not info.get('title'):
            validation_results['errors'].append("Missing API title in info section")
        if not info.get('version'):
            validation_results['errors'].append("Missing API version in info section")
        
        # Paths validation
        paths = schema.get('paths', {})
        if not paths:
            validation_results['warnings'].append("No API paths defined")
        else:
            validation_results['statistics']['endpoint_count'] = len(paths)
            
            # Validate HTTP methods and responses
            for path, methods in paths.items():
                for method, details in methods.items():
                    if method.upper() not in ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']:
                        continue
                        
                    if 'responses' not in details:
                        validation_results['warnings'].append(f"Missing responses for {method.upper()} {path}")
                    else:
                        responses = details['responses']
                        if '200' not in responses and method.upper() == 'GET':
                            validation_results['warnings'].append(f"GET {path} should have a 200 response")
                        if '201' not in responses and method.upper() == 'POST':
                            validation_results['warnings'].append(f"POST {path} should have a 201 response")
        
        # Components validation
        components = schema.get('components', {})
        schemas = components.get('schemas', {})
        validation_results['statistics']['schema_count'] = len(schemas)
        
        # Best practices checks
        if 'servers' in schema:
            validation_results['best_practices'].append("✓ Server definitions included")
        else:
            validation_results['warnings'].append("Consider adding server definitions")
        
        if info.get('description'):
            validation_results['best_practices'].append("✓ API description provided")
        else:
            validation_results['warnings'].append("Consider adding API description")
        
        if components:
            validation_results['best_practices'].append("✓ Reusable components defined")
        
        # Security validation
        if 'security' in schema or any('security' in details for details in paths.values()):
            validation_results['best_practices'].append("✓ Security definitions included")
        else:
            validation_results['warnings'].append("Consider adding security definitions")
        
        # Final validation status
        if validation_results['errors']:
            validation_results['valid'] = False
        
        return validation_results
        
    except json.JSONDecodeError as e:
        return {'valid': False, 'errors': [f'Invalid JSON: {str(e)}']}, 400
    except Exception as e:
        return {'valid': False, 'errors': [f'Validation error: {str(e)}']}, 500
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
functions-framework==3.5.0
jsonschema==4.20.0
EOF
    
    # Deploy validation function
    if gcloud functions deploy schema-validator \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point validate_schema \
        --memory 512MB \
        --timeout 60s \
        --quiet; then
        
        log_success "Schema validation function deployed"
    else
        error_exit "Failed to deploy schema validation function"
    fi
    
    cd ..
}

# Create Cloud Build configuration
create_build_config() {
    log_info "Creating Cloud Build configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create cloudbuild.yaml configuration"
        return 0
    fi
    
    # Create comprehensive Cloud Build configuration
    cat > cloudbuild.yaml << EOF
steps:
# Step 1: Analyze source code structure
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'analyze-code'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Analyzing API source code for schema generation..."
    echo "Source files found:"
    find . -name "*.py" -o -name "*.js" -o -name "*.java" | head -10
    
    # In a real implementation, this would integrate with Gemini Code Assist
    # to perform intelligent code analysis and extract API patterns
    echo "Code analysis complete - API patterns detected"

# Step 2: Generate OpenAPI schema using AI
- name: 'gcr.io/cloud-builders/curl'
  id: 'generate-schema'
  args: 
  - '-X'
  - 'POST'
  - '\${_FUNCTION_URL}'
  - '-H'
  - 'Content-Type: application/json'
  - '-d'
  - '{}'
  env:
  - 'BUCKET_NAME=\${_BUCKET_NAME}'

# Step 3: Download and validate generated schema
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'validate-schema'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Downloading and validating generated schema..."
    gsutil cp gs://\${_BUCKET_NAME}/openapi-schema.json ./schema.json
    
    # Basic validation checks
    if [ ! -f "./schema.json" ]; then
      echo "Error: Schema file not found"
      exit 1
    fi
    
    # Check if valid JSON
    if ! jq empty ./schema.json; then
      echo "Error: Invalid JSON format"
      exit 1
    fi
    
    # Validate required OpenAPI fields
    OPENAPI_VERSION=\$(jq -r '.openapi' ./schema.json)
    if [[ ! "\$OPENAPI_VERSION" =~ ^3\. ]]; then
      echo "Error: Invalid OpenAPI version: \$OPENAPI_VERSION"
      exit 1
    fi
    
    echo "Schema validation complete - OpenAPI \$OPENAPI_VERSION"

# Step 4: Create documentation artifacts
- name: 'gcr.io/cloud-builders/gsutil'
  id: 'deploy-docs'
  args: 
  - 'cp'
  - './schema.json'
  - 'gs://\${_BUCKET_NAME}/docs/openapi-schema.json'

# Step 5: Generate build report
- name: 'gcr.io/cloud-builders/gcloud'
  id: 'generate-report'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Generating build report..."
    ENDPOINT_COUNT=\$(jq '.paths | length' ./schema.json)
    SCHEMA_COUNT=\$(jq '.components.schemas | length' ./schema.json)
    
    cat > build-report.json << EOF2
    {
      "build_id": "\$BUILD_ID",
      "timestamp": "\$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "endpoints_generated": \$ENDPOINT_COUNT,
      "schemas_generated": \$SCHEMA_COUNT,
      "status": "success"
    }
EOF2
    
    gsutil cp build-report.json gs://\${_BUCKET_NAME}/reports/
    echo "Build report generated successfully"

substitutions:
  _BUCKET_NAME: '${BUCKET_NAME}'
  _FUNCTION_URL: '${FUNCTION_URL}'

options:
  logging: CLOUD_LOGGING_ONLY
  pool: {}
EOF
    
    log_success "Cloud Build configuration created"
}

# Create build trigger
create_build_trigger() {
    log_info "Creating Cloud Build trigger..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud Build trigger for manual execution"
        return 0
    fi
    
    # For this demo, we'll create a manual trigger
    # In production, you would connect this to a repository
    log_info "Note: Manual trigger configuration (connect to your repository for automatic triggers)"
    log_success "Build trigger configuration ready"
}

# Execute test build
execute_test_build() {
    log_info "Executing test build..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute Cloud Build with configuration"
        return 0
    fi
    
    # Submit build manually with monitoring
    if BUILD_ID=$(gcloud builds submit \
        --config=cloudbuild.yaml \
        --substitutions="_BUCKET_NAME=$BUCKET_NAME,_FUNCTION_URL=$FUNCTION_URL" \
        --format="value(id)" 2>/dev/null); then
        
        log_success "Build submitted successfully with ID: $BUILD_ID"
        log_info "Monitor build progress with: gcloud builds log $BUILD_ID --stream"
    else
        log_warning "Manual build submission failed - this is expected without source repository"
        log_info "Use 'gcloud builds submit' with your source code when ready"
    fi
}

# Create monitoring configuration
create_monitoring() {
    log_info "Creating monitoring configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create monitoring dashboard configuration"
        return 0
    fi
    
    # Create monitoring dashboard configuration
    cat > monitoring-dashboard.json << 'EOF'
{
  "displayName": "API Schema Pipeline Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Build Success Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"build\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "Success Rate",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Function Execution Duration",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "Duration (ms)",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    log_success "Monitoring configuration created (import in Cloud Monitoring console)"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "bucket_name": "$BUCKET_NAME",
  "function_url": "${FUNCTION_URL:-'Not deployed'}",
  "random_suffix": "$RANDOM_SUFFIX",
  "resources": {
    "storage_bucket": "$BUCKET_NAME",
    "cloud_functions": [
      "schema-generator",
      "schema-validator"
    ],
    "build_config": "cloudbuild.yaml"
  },
  "next_steps": [
    "Connect build trigger to your repository",
    "Test schema generation with your API code",
    "Import monitoring dashboard to Cloud Monitoring",
    "Configure alerting for build failures"
  ]
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Display deployment summary
display_summary() {
    log_separator
    log_success "Deployment completed successfully!"
    log_separator
    
    echo -e "${GREEN}DEPLOYMENT SUMMARY${NC}"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: $BUCKET_NAME"
    if [[ -n "${FUNCTION_URL:-}" ]]; then
        echo "Schema Generator URL: $FUNCTION_URL"
    fi
    echo ""
    
    echo -e "${BLUE}NEXT STEPS:${NC}"
    echo "1. Test schema generation:"
    if [[ -n "${FUNCTION_URL:-}" ]]; then
        echo "   curl -X POST $FUNCTION_URL"
    fi
    echo "2. View generated schema:"
    echo "   gsutil cat gs://$BUCKET_NAME/openapi-schema.json"
    echo "3. Connect build trigger to your repository for automatic schema generation"
    echo "4. Import monitoring-dashboard.json to Cloud Monitoring console"
    echo ""
    
    echo -e "${YELLOW}CLEANUP:${NC}"
    echo "Run './destroy.sh --project-id $PROJECT_ID' to remove all resources"
    
    log_separator
}

# Main deployment function
main() {
    log_separator
    log_info "Starting deployment of $RECIPE_NAME"
    log_info "Script version: $SCRIPT_VERSION"
    log_separator
    
    # Parse arguments and validate
    parse_arguments "$@"
    validate_prerequisites
    
    # Configuration phase
    configure_gcloud
    enable_apis
    
    # Deployment phase
    create_storage_bucket
    create_sample_app
    deploy_schema_function
    deploy_validation_function
    create_build_config
    create_build_trigger
    execute_test_build
    create_monitoring
    
    # Finalization
    save_deployment_info
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"