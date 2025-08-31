#!/bin/bash

# Email Signature Generator - Deployment Script
# This script deploys Cloud Functions and Cloud Storage for email signature generation

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Default values
DEFAULT_PROJECT_ID="email-sig-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Script variables
PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-$DEFAULT_ZONE}"
BUCKET_NAME="email-signatures-$(openssl rand -hex 3)"
FUNCTION_NAME="generate-signature"
FUNCTION_SOURCE_DIR="./function-source"

# Check if running in dry-run mode
DRY_RUN="${DRY_RUN:-false}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -p, --project-id PROJECT_ID     GCP Project ID (default: auto-generated)
    -r, --region REGION             GCP region (default: us-central1)
    -z, --zone ZONE                 GCP zone (default: us-central1-a)
    -b, --bucket-name BUCKET_NAME   Cloud Storage bucket name (default: auto-generated)
    -f, --function-name FUNC_NAME   Cloud Function name (default: generate-signature)
    -d, --dry-run                   Show what would be done without executing
    -h, --help                      Show this help message

Environment Variables:
    PROJECT_ID     - GCP Project ID
    REGION         - GCP region
    ZONE           - GCP zone
    DRY_RUN        - Set to 'true' for dry-run mode

Examples:
    $0                                          # Deploy with defaults
    $0 --project-id my-project --region us-east1
    DRY_RUN=true $0                             # Dry run mode
    PROJECT_ID=my-project $0                    # Use environment variable

EOF
}

# Parse command line arguments
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
        -b|--bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -f|--function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        log_info "[DRY-RUN] Would execute: $cmd"
    else
        log_info "$description"
        eval "$cmd"
    fi
}

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud CLI with gsutil."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output formatting will be limited."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to create Cloud Function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create function source directory: $FUNCTION_SOURCE_DIR"
        return 0
    fi
    
    # Create function directory
    mkdir -p "$FUNCTION_SOURCE_DIR"
    cd "$FUNCTION_SOURCE_DIR"
    
    # Create main.py
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime
from google.cloud import storage

def generate_signature(request):
    """HTTP Cloud Function to generate HTML email signatures."""
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        request_args = request.args
        
        # Extract signature parameters with defaults
        name = request_json.get('name') if request_json else request_args.get('name', 'John Doe')
        title = request_json.get('title') if request_json else request_args.get('title', 'Software Engineer')
        company = request_json.get('company') if request_json else request_args.get('company', 'Your Company')
        email = request_json.get('email') if request_json else request_args.get('email', 'john@company.com')
        phone = request_json.get('phone') if request_json else request_args.get('phone', '+1 (555) 123-4567')
        website = request_json.get('website') if request_json else request_args.get('website', 'https://company.com')
        
        # Generate professional HTML signature
        html_signature = f'''
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                .signature-container {{
                    font-family: Arial, Helvetica, sans-serif;
                    font-size: 14px;
                    line-height: 1.4;
                    color: #333333;
                    max-width: 500px;
                }}
                .name {{
                    font-size: 18px;
                    font-weight: bold;
                    color: #2E7EBF;
                    margin-bottom: 5px;
                }}
                .title {{
                    font-size: 14px;
                    color: #666666;
                    margin-bottom: 10px;
                }}
                .company {{
                    font-size: 16px;
                    font-weight: bold;
                    color: #333333;
                    margin-bottom: 10px;
                }}
                .contact-info {{
                    border-top: 2px solid #2E7EBF;
                    padding-top: 10px;
                }}
                .contact-item {{
                    margin-bottom: 5px;
                }}
                .contact-item a {{
                    color: #2E7EBF;
                    text-decoration: none;
                }}
                .contact-item a:hover {{
                    text-decoration: underline;
                }}
            </style>
        </head>
        <body>
            <div class="signature-container">
                <div class="name">{name}</div>
                <div class="title">{title}</div>
                <div class="company">{company}</div>
                <div class="contact-info">
                    <div class="contact-item">Email: <a href="mailto:{email}">{email}</a></div>
                    <div class="contact-item">Phone: <a href="tel:{phone}">{phone}</a></div>
                    <div class="contact-item">Website: <a href="{website}">{website}</a></div>
                </div>
            </div>
        </body>
        </html>
        '''
        
        # Store signature in Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            storage_client = storage.Client()
            bucket = storage_client.bucket(bucket_name)
            
            # Create filename from name and timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            safe_name = name.lower().replace(' ', '_').replace('-', '_')
            filename = f"signatures/{safe_name}_{timestamp}.html"
            
            # Upload HTML signature to bucket
            blob = bucket.blob(filename)
            blob.upload_from_string(html_signature, content_type='text/html')
            
            # Make blob publicly readable
            blob.make_public()
            
            signature_url = f"https://storage.googleapis.com/{bucket_name}/{filename}"
        else:
            signature_url = "Storage not configured"
        
        # Return response with signature and URL
        response_data = {
            'success': True,
            'signature_html': html_signature,
            'storage_url': signature_url,
            'generated_at': datetime.now().isoformat()
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        error_response = {
            'success': False,
            'error': str(e),
            'generated_at': datetime.now().isoformat()
        }
        return (json.dumps(error_response), 500, headers)
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.18.0
EOF
    
    cd ..
    log_success "Cloud Function source code created"
}

# Function to validate GCP project
validate_project() {
    log_info "Validating GCP project: $PROJECT_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate project: $PROJECT_ID"
        return 0
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        log_info "Please create the project or use an existing one."
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Function to configure gcloud
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    execute_command "gcloud config set project $PROJECT_ID" "Setting project"
    execute_command "gcloud config set compute/region $REGION" "Setting default region"
    execute_command "gcloud config set functions/region $REGION" "Setting functions region"
    
    log_success "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable $api" "Enabling $api"
    done
    
    log_success "Required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME" \
        "Creating Cloud Storage bucket"
    
    execute_command "gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME" \
        "Setting public read access on bucket"
    
    log_success "Cloud Storage bucket created and configured"
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy function from: $FUNCTION_SOURCE_DIR"
        return 0
    fi
    
    cd "$FUNCTION_SOURCE_DIR"
    
    execute_command "gcloud functions deploy $FUNCTION_NAME \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_signature \
        --memory 256Mi \
        --timeout 60s \
        --set-env-vars BUCKET_NAME=$BUCKET_NAME" \
        "Deploying Cloud Function"
    
    cd ..
    log_success "Cloud Function deployed successfully"
}

# Function to get function URL
get_function_url() {
    log_info "Retrieving Cloud Function URL..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would retrieve function URL for: $FUNCTION_NAME"
        return 0
    fi
    
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    log_success "Function URL: $function_url"
    echo "$function_url" > function-url.txt
    log_info "Function URL saved to function-url.txt"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployed function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test the deployed function"
        return 0
    fi
    
    if [[ ! -f "function-url.txt" ]]; then
        log_warning "Function URL not found. Skipping test."
        return 0
    fi
    
    local function_url
    function_url=$(cat function-url.txt)
    
    local test_data='{
        "name": "Test User",
        "title": "DevOps Engineer",
        "company": "Tech Corp",
        "email": "test@techcorp.com",
        "phone": "+1 (555) 123-4567",
        "website": "https://techcorp.com"
    }'
    
    log_info "Sending test request to function..."
    
    if command -v jq &> /dev/null; then
        curl -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d "$test_data" 2>/dev/null | jq .
    else
        curl -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d "$test_data" 2>/dev/null
    fi
    
    log_success "Function test completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Function Name: $FUNCTION_NAME"
    
    if [[ -f "function-url.txt" && "$DRY_RUN" != "true" ]]; then
        echo "Function URL: $(cat function-url.txt)"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Test the function using the URL above"
    echo "2. Check Cloud Storage bucket for generated signatures"
    echo "3. Integrate the API into your applications"
    echo ""
    echo "Cleanup: Run ./destroy.sh to remove all resources"
}

# Main deployment function
main() {
    log_info "Starting Email Signature Generator deployment..."
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Function Name: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no resources will be created"
    fi
    
    echo ""
    
    # Execute deployment steps
    check_prerequisites
    validate_project
    configure_gcloud
    enable_apis
    create_function_source
    create_storage_bucket
    deploy_function
    get_function_url
    test_deployment
    
    echo ""
    log_success "Deployment completed successfully!"
    display_summary
}

# Trap to handle script interruption
trap 'log_error "Script interrupted. You may need to run cleanup manually."; exit 1' INT TERM

# Run main function
main "$@"