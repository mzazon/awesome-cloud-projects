#!/bin/bash

set -euo pipefail

# Simple File Sharing with Cloud Storage and Functions - Deployment Script
# This script deploys a serverless file sharing portal using Cloud Storage and Cloud Functions

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_ZONE="us-central1-a"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warn() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_warn "You may need to manually clean up partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a serverless file sharing portal using Google Cloud Storage and Functions.

OPTIONS:
    -p, --project       Google Cloud project ID (required)
    -r, --region        Deployment region (default: ${DEFAULT_REGION})
    -z, --zone          Deployment zone (default: ${DEFAULT_ZONE})
    -n, --name          Resource name suffix (optional, generates random if not provided)
    -h, --help          Show this help message
    --dry-run           Show what would be deployed without actually deploying

EXAMPLES:
    $0 --project my-project-123
    $0 --project my-project-123 --region us-west1 --name prod
    $0 --project my-project-123 --dry-run

REQUIREMENTS:
    - gcloud CLI installed and authenticated
    - Billing enabled on the project
    - Required APIs will be enabled automatically

EOF
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available (for random generation)
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Please install it for random string generation."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
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
            -n|--name)
                NAME_SUFFIX="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project flag."
        show_help
        exit 1
    fi
    
    # Set defaults
    REGION="${REGION:-$DEFAULT_REGION}"
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate random suffix if not provided
    if [[ -z "${NAME_SUFFIX:-}" ]]; then
        NAME_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set resource names
    BUCKET_NAME="file-share-bucket-${NAME_SUFFIX}"
    UPLOAD_FUNCTION_NAME="upload-file-${NAME_SUFFIX}"
    LINK_FUNCTION_NAME="generate-link-${NAME_SUFFIX}"
}

# Validate project and setup
validate_project() {
    log_info "Validating project: ${PROJECT_ID}"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' not found or no access"
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" | grep -q "True"; then
        log_error "Billing is not enabled for project '${PROJECT_ID}'"
        log_info "Enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would enable API: ${api}"
        else
            log_info "Enabling API: ${api}"
            gcloud services enable "${api}" --project="${PROJECT_ID}"
        fi
    done
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_info "Waiting for APIs to be ready..."
        sleep 10
    fi
    
    log_success "APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        log_info "[DRY RUN] Would set uniform bucket-level access"
        log_info "[DRY RUN] Would configure CORS policy"
        return
    fi
    
    # Check if bucket already exists
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warn "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
    else
        # Create bucket
        gcloud storage buckets create "gs://${BUCKET_NAME}" \
            --location="${REGION}" \
            --storage-class=STANDARD \
            --project="${PROJECT_ID}"
        
        log_success "Bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Enable uniform bucket-level access
    gcloud storage buckets update "gs://${BUCKET_NAME}" \
        --uniform-bucket-level-access
    
    # Create and apply CORS policy
    local cors_file="${SCRIPT_DIR}/cors.json"
    cat > "${cors_file}" << 'EOF'
[{
    "origin":["*"],
    "method":["GET","POST","PUT"],
    "responseHeader":["Content-Type"],
    "maxAgeSeconds":3600
}]
EOF
    
    gcloud storage buckets update "gs://${BUCKET_NAME}" \
        --cors-file="${cors_file}"
    
    # Clean up CORS file
    rm -f "${cors_file}"
    
    log_success "Cloud Storage bucket configured with CORS policy"
}

# Create function source code
create_function_code() {
    log_info "Creating function source code..."
    
    local upload_dir="${SCRIPT_DIR}/../upload-function"
    local link_dir="${SCRIPT_DIR}/../link-function"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create function source code in:"
        log_info "[DRY RUN]   - ${upload_dir}"
        log_info "[DRY RUN]   - ${link_dir}"
        return
    fi
    
    # Create upload function directory and code
    mkdir -p "${upload_dir}"
    cat > "${upload_dir}/main.py" << 'EOF'
import functions_framework
from google.cloud import storage
import tempfile
import os
from werkzeug.utils import secure_filename
import logging

# Initialize Cloud Storage client
storage_client = storage.Client()
bucket_name = os.environ.get('BUCKET_NAME')

@functions_framework.http
def upload_file(request):
    """HTTP Cloud Function for file uploads."""
    # Enable CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    if request.method != 'POST':
        return ('Method not allowed', 405, headers)
    
    try:
        # Get uploaded file
        uploaded_file = request.files.get('file')
        if not uploaded_file:
            return ('No file provided', 400, headers)
        
        # Secure the filename
        filename = secure_filename(uploaded_file.filename)
        if not filename:
            return ('Invalid filename', 400, headers)
        
        # Upload to Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(filename)
        blob.upload_from_file(uploaded_file)
        
        logging.info(f'File {filename} uploaded successfully')
        return ({'message': f'File {filename} uploaded successfully', 'filename': filename}, 200, headers)
        
    except Exception as e:
        logging.error(f'Upload error: {str(e)}')
        return ('Upload failed', 500, headers)
EOF
    
    cat > "${upload_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
Werkzeug==3.*
EOF
    
    # Create link generation function directory and code
    mkdir -p "${link_dir}"
    cat > "${link_dir}/main.py" << 'EOF'
import functions_framework
from google.cloud import storage
from datetime import datetime, timedelta
import json
import os
import logging

# Initialize Cloud Storage client
storage_client = storage.Client()
bucket_name = os.environ.get('BUCKET_NAME')

@functions_framework.http
def generate_link(request):
    """HTTP Cloud Function for generating shareable links."""
    # Enable CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get filename from request
        if request.method == 'POST':
            data = request.get_json()
            filename = data.get('filename') if data else None
        else:
            filename = request.args.get('filename')
        
        if not filename:
            return ('Filename required', 400, headers)
        
        # Generate signed URL (valid for 1 hour)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(filename)
        
        # Check if file exists
        if not blob.exists():
            return ('File not found', 404, headers)
        
        # Generate signed URL with 1 hour expiration
        url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.utcnow() + timedelta(hours=1),
            method="GET"
        )
        
        logging.info(f'Generated signed URL for {filename}')
        return ({
            'filename': filename,
            'download_url': url,
            'expires_in': '1 hour'
        }, 200, headers)
        
    except Exception as e:
        logging.error(f'Link generation error: {str(e)}')
        return ('Link generation failed', 500, headers)
EOF
    
    cat > "${link_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
EOF
    
    log_success "Function source code created"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    local upload_dir="${SCRIPT_DIR}/../upload-function"
    local link_dir="${SCRIPT_DIR}/../link-function"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy upload function: ${UPLOAD_FUNCTION_NAME}"
        log_info "[DRY RUN] Would deploy link function: ${LINK_FUNCTION_NAME}"
        return
    fi
    
    # Deploy upload function
    log_info "Deploying upload function: ${UPLOAD_FUNCTION_NAME}"
    gcloud functions deploy "${UPLOAD_FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-http \
        --source "${upload_dir}" \
        --entry-point upload_file \
        --memory 256MB \
        --timeout 60s \
        --allow-unauthenticated \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
        --region "${REGION}" \
        --project "${PROJECT_ID}"
    
    # Deploy link generation function
    log_info "Deploying link generation function: ${LINK_FUNCTION_NAME}"
    gcloud functions deploy "${LINK_FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-http \
        --source "${link_dir}" \
        --entry-point generate_link \
        --memory 256MB \
        --timeout 30s \
        --allow-unauthenticated \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
        --region "${REGION}" \
        --project "${PROJECT_ID}"
    
    log_success "Cloud Functions deployed successfully"
}

# Get function URLs
get_function_urls() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would retrieve function URLs"
        return
    fi
    
    log_info "Retrieving function URLs..."
    
    UPLOAD_URL=$(gcloud functions describe "${UPLOAD_FUNCTION_NAME}" \
        --region "${REGION}" \
        --project "${PROJECT_ID}" \
        --format="value(httpsTrigger.url)")
    
    LINK_URL=$(gcloud functions describe "${LINK_FUNCTION_NAME}" \
        --region "${REGION}" \
        --project="${PROJECT_ID}" \
        --format="value(httpsTrigger.url)")
    
    log_success "Function URLs retrieved"
}

# Create web interface
create_web_interface() {
    log_info "Creating web interface..."
    
    local interface_file="${SCRIPT_DIR}/../file-share-interface.html"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create web interface: ${interface_file}"
        return
    fi
    
    cat > "${interface_file}" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Simple File Sharing Portal</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }
        .section { margin: 30px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
        button { background: #4285F4; color: white; padding: 10px 20px; border: none; border-radius: 3px; cursor: pointer; }
        button:hover { background: #3367D6; }
        .result { margin-top: 10px; padding: 10px; background: #f0f0f0; border-radius: 3px; }
        .loading { display: none; color: #666; }
    </style>
</head>
<body>
    <h1>Simple File Sharing Portal</h1>
    
    <div class="section">
        <h2>Upload File</h2>
        <input type="file" id="fileInput" accept="*/*">
        <button onclick="uploadFile()">Upload</button>
        <div class="loading" id="uploadLoading">Uploading...</div>
        <div id="uploadResult" class="result" style="display:none;"></div>
    </div>
    
    <div class="section">
        <h2>Generate Share Link</h2>
        <input type="text" id="filenameInput" placeholder="Enter filename">
        <button onclick="generateLink()">Generate Link</button>
        <div class="loading" id="linkLoading">Generating link...</div>
        <div id="linkResult" class="result" style="display:none;"></div>
    </div>
    
    <script>
        const uploadUrl = '${UPLOAD_URL:-PLACEHOLDER_UPLOAD_URL}';
        const linkUrl = '${LINK_URL:-PLACEHOLDER_LINK_URL}';
        
        async function uploadFile() {
            const fileInput = document.getElementById('fileInput');
            const resultDiv = document.getElementById('uploadResult');
            const loadingDiv = document.getElementById('uploadLoading');
            
            if (!fileInput.files[0]) {
                alert('Please select a file');
                return;
            }
            
            const formData = new FormData();
            formData.append('file', fileInput.files[0]);
            
            loadingDiv.style.display = 'block';
            resultDiv.style.display = 'none';
            
            try {
                const response = await fetch(uploadUrl, {
                    method: 'POST',
                    body: formData
                });
                
                const result = await response.json();
                loadingDiv.style.display = 'none';
                resultDiv.innerHTML = response.ok ? 
                    \`<strong>✅ Success:</strong> \${result.message}\` : 
                    \`<strong>❌ Error:</strong> Upload failed\`;
                resultDiv.style.display = 'block';
                
                if (response.ok) {
                    document.getElementById('filenameInput').value = result.filename;
                }
            } catch (error) {
                loadingDiv.style.display = 'none';
                resultDiv.innerHTML = \`<strong>❌ Error:</strong> \${error.message}\`;
                resultDiv.style.display = 'block';
            }
        }
        
        async function generateLink() {
            const filename = document.getElementById('filenameInput').value;
            const resultDiv = document.getElementById('linkResult');
            const loadingDiv = document.getElementById('linkLoading');
            
            if (!filename) {
                alert('Please enter a filename');
                return;
            }
            
            loadingDiv.style.display = 'block';
            resultDiv.style.display = 'none';
            
            try {
                const response = await fetch(linkUrl, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({filename: filename})
                });
                
                const result = await response.json();
                loadingDiv.style.display = 'none';
                
                if (response.ok) {
                    resultDiv.innerHTML = \`
                        <strong>✅ Shareable Link Generated:</strong><br>
                        <a href="\${result.download_url}" target="_blank" style="word-break: break-all;">\${result.download_url}</a><br>
                        <small>🕒 Expires in: \${result.expires_in}</small>
                    \`;
                } else {
                    resultDiv.innerHTML = \`<strong>❌ Error:</strong> \${result.message || 'Link generation failed'}\`;
                }
                resultDiv.style.display = 'block';
            } catch (error) {
                loadingDiv.style.display = 'none';
                resultDiv.innerHTML = \`<strong>❌ Error:</strong> \${error.message}\`;
                resultDiv.style.display = 'block';
            }
        }
    </script>
</body>
</html>
EOF
    
    log_success "Web interface created: ${interface_file}"
}

# Save deployment information
save_deployment_info() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would save deployment information"
        return
    fi
    
    local info_file="${SCRIPT_DIR}/deployment-info.json"
    
    cat > "${info_file}" << EOF
{
    "project_id": "${PROJECT_ID}",
    "region": "${REGION}",
    "zone": "${ZONE}",
    "name_suffix": "${NAME_SUFFIX}",
    "bucket_name": "${BUCKET_NAME}",
    "upload_function_name": "${UPLOAD_FUNCTION_NAME}",
    "link_function_name": "${LINK_FUNCTION_NAME}",
    "upload_url": "${UPLOAD_URL:-}",
    "link_url": "${LINK_URL:-}",
    "deployed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    log_success "Deployment information saved to: ${info_file}"
}

# Print deployment summary
print_summary() {
    log_success "Deployment completed successfully!"
    echo
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Bucket: gs://${BUCKET_NAME}"
    log_info "Upload Function: ${UPLOAD_FUNCTION_NAME}"
    log_info "Link Function: ${LINK_FUNCTION_NAME}"
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_info "Upload URL: ${UPLOAD_URL}"
        log_info "Link URL: ${LINK_URL}"
        log_info "Web Interface: ${SCRIPT_DIR}/../file-share-interface.html"
    fi
    
    echo
    log_info "=== NEXT STEPS ==="
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "1. Run this script without --dry-run to deploy"
    else
        log_info "1. Open the web interface in a browser to test"
        log_info "2. Upload files and generate shareable links"
        log_info "3. Monitor usage in Google Cloud Console"
    fi
    log_info "4. Run destroy.sh when you want to clean up resources"
    
    echo
    log_info "=== ESTIMATED COSTS ==="
    log_info "Cloud Storage: ~\$0.02/GB/month"
    log_info "Cloud Functions: Free tier covers 2M invocations/month"
    log_info "Data Transfer: \$0.12/GB egress (first 1GB free per month)"
    
    echo
    log_warn "Remember to clean up resources when no longer needed to avoid charges!"
}

# Main deployment function
main() {
    log_info "Starting deployment of Simple File Sharing Portal"
    log_info "Log file: ${LOG_FILE}"
    
    parse_arguments "$@"
    check_prerequisites
    validate_project
    enable_apis
    create_storage_bucket
    create_function_code
    deploy_functions
    get_function_urls
    create_web_interface
    save_deployment_info
    print_summary
    
    log_success "Deployment script completed successfully!"
}

# Run main function with all arguments
main "$@"