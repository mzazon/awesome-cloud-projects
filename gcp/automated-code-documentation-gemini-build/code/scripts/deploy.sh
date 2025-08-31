#!/bin/bash

# Automated Code Documentation with Gemini and Cloud Build - Deployment Script
# This script deploys the complete infrastructure for AI-powered documentation automation

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/gemini-docs-deploy-$(date +%Y%m%d_%H%M%S).log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "${LOG_FILE}" >&2
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}" | tee -a "${LOG_FILE}"
    fi
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    error "Deployment failed with exit code ${exit_code}"
    error "Check log file: ${LOG_FILE}"
    if [[ "${CLEANUP_ON_ERROR:-true}" == "true" ]]; then
        warn "Running cleanup due to deployment failure..."
        cleanup_resources || true
    fi
    exit "${exit_code}"
}

trap cleanup_on_error ERR

# Usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy automated code documentation infrastructure with Gemini AI and Cloud Build.

Options:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -s, --suffix SUFFIX           Resource name suffix (auto-generated if not provided)
    -n, --no-website             Skip optional documentation website deployment
    -d, --debug                   Enable debug logging
    -h, --help                    Show this help message
    --dry-run                     Show what would be deployed without making changes
    --skip-apis                   Skip API enablement (use if APIs are already enabled)
    --cleanup-on-error            Cleanup resources if deployment fails (default: true)

Environment Variables:
    GOOGLE_CLOUD_PROJECT         Google Cloud Project ID
    GOOGLE_CLOUD_REGION          Default region for resources
    DEBUG                        Enable debug mode (true/false)

Examples:
    ${SCRIPT_NAME} --project-id my-project
    ${SCRIPT_NAME} -p my-project -r us-west1 --no-website
    ${SCRIPT_NAME} -p my-project --dry-run

EOF
}

# Default values
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
REGION="${GOOGLE_CLOUD_REGION:-us-central1}"
ZONE="${REGION}-a"
DEPLOY_WEBSITE="true"
DRY_RUN="false"
SKIP_APIS="false"
CLEANUP_ON_ERROR="true"
SUFFIX=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            ZONE="${REGION}-a"
            shift 2
            ;;
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        -n|--no-website)
            DEPLOY_WEBSITE="false"
            shift
            ;;
        -d|--debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --skip-apis)
            SKIP_APIS="true"
            shift
            ;;
        --cleanup-on-error)
            CLEANUP_ON_ERROR="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if openssl is installed (for random suffix generation)
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "${PROJECT_ID}" ]]; then
        error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
        exit 1
    fi
    
    # Check billing
    local billing_account
    billing_account=$(gcloud billing projects describe "${PROJECT_ID}" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "${billing_account}" ]]; then
        warn "Billing is not enabled for project '${PROJECT_ID}'. Some services may not work."
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment
initialize_environment() {
    log "Initializing deployment environment..."
    
    # Generate unique suffix if not provided
    if [[ -z "${SUFFIX}" ]]; then
        SUFFIX=$(openssl rand -hex 3)
        debug "Generated suffix: ${SUFFIX}"
    fi
    
    # Set environment variables
    export PROJECT_ID
    export REGION
    export ZONE
    
    # Set default project and region
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${PROJECT_ID}" --quiet
        gcloud config set compute/region "${REGION}" --quiet
        gcloud config set compute/zone "${ZONE}" --quiet
    fi
    
    # Create unique resource names
    export BUCKET_NAME="code-docs-${SUFFIX}"
    export FUNCTION_NAME="doc-processor-${SUFFIX}"
    export BUILD_TRIGGER_NAME="doc-automation-${SUFFIX}"
    export SERVICE_ACCOUNT_NAME="doc-automation-sa"
    export NOTIFICATION_FUNCTION_NAME="doc-notifier-${SUFFIX}"
    
    log "Environment initialized:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Zone: ${ZONE}"
    log "  Suffix: ${SUFFIX}"
    log "  Bucket Name: ${BUCKET_NAME}"
    log "  Function Name: ${FUNCTION_NAME}"
    log "  Build Trigger Name: ${BUILD_TRIGGER_NAME}"
    log "  Service Account: ${SERVICE_ACCOUNT_NAME}"
}

# Enable required APIs
enable_apis() {
    if [[ "${SKIP_APIS}" == "true" ]]; then
        log "Skipping API enablement as requested"
        return 0
    fi
    
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "run.googleapis.com"
        "eventarc.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        for api in "${apis[@]}"; do
            log "Enabling ${api}..."
            if gcloud services enable "${api}" --project="${PROJECT_ID}"; then
                debug "Successfully enabled ${api}"
            else
                error "Failed to enable ${api}"
                return 1
            fi
        done
        
        # Wait for APIs to be fully enabled
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    else
        log "DRY RUN: Would enable APIs: ${apis[*]}"
    fi
    
    log "APIs enabled successfully"
}

# Create service account
create_service_account() {
    log "Creating service account for documentation automation..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create service account
        if gcloud iam service-accounts describe "${service_account_email}" &> /dev/null; then
            warn "Service account ${service_account_email} already exists"
        else
            gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
                --display-name="Documentation Automation Service Account" \
                --description="Service account for automated documentation generation" \
                --project="${PROJECT_ID}"
        fi
        
        # Grant necessary permissions
        local roles=(
            "roles/aiplatform.user"
            "roles/storage.objectAdmin"
            "roles/cloudfunctions.invoker"
        )
        
        for role in "${roles[@]}"; do
            log "Granting role ${role} to service account..."
            gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account_email}" \
                --role="${role}" \
                --quiet
        done
    else
        log "DRY RUN: Would create service account ${service_account_email} with roles"
    fi
    
    log "Service account configuration completed"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for documentation storage..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Check if bucket already exists
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            warn "Bucket gs://${BUCKET_NAME} already exists"
        else
            # Create bucket
            gsutil mb -p "${PROJECT_ID}" \
                -c STANDARD \
                -l "${REGION}" \
                "gs://${BUCKET_NAME}"
        fi
        
        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Set up folder structure
        echo "Documentation storage initialized on $(date)" | \
            gsutil cp - "gs://${BUCKET_NAME}/readme.txt"
        
        log "Documentation storage bucket created: ${BUCKET_NAME}"
    else
        log "DRY RUN: Would create bucket gs://${BUCKET_NAME} with versioning enabled"
    fi
}

# Create and deploy documentation processing function
deploy_documentation_function() {
    log "Creating and deploying documentation processing function..."
    
    local function_dir="${SCRIPT_DIR}/../functions/doc-processor"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create function directory
        mkdir -p "${function_dir}"
        
        # Create main.py
        cat > "${function_dir}/main.py" << 'EOF'
import json
import os
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework

vertexai.init(project=os.environ.get('GOOGLE_CLOUD_PROJECT'), location="us-central1")

@functions_framework.http
def generate_docs(request):
    """Generate documentation using Gemini AI"""
    
    try:
        # Parse request data
        request_json = request.get_json()
        repo_path = request_json.get('repo_path', '')
        file_content = request_json.get('file_content', '')
        doc_type = request_json.get('doc_type', 'api')
        
        # Initialize Gemini model
        model = GenerativeModel("gemini-1.5-flash")
        
        # Create documentation prompt based on type
        if doc_type == 'api':
            prompt = f"""
            Analyze the following code and generate comprehensive API documentation in Markdown format.
            Include function descriptions, parameters, return values, and usage examples.
            
            Code:
            {file_content}
            
            Generate clear, professional API documentation:
            """
        elif doc_type == 'readme':
            prompt = f"""
            Analyze the following code repository structure and generate a comprehensive README.md file.
            Include project description, installation instructions, usage examples, and contribution guidelines.
            
            Repository structure and key files:
            {file_content}
            
            Generate a professional README.md:
            """
        else:  # code comments
            prompt = f"""
            Analyze the following code and add comprehensive inline comments explaining the functionality.
            Maintain the original code structure while adding clear, helpful comments.
            
            Code:
            {file_content}
            
            Return the code with added comments:
            """
        
        # Generate documentation with Gemini
        response = model.generate_content(prompt)
        generated_docs = response.text
        
        # Save to Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
        
        # Create filename based on type and timestamp
        import datetime
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{doc_type}/{repo_path}_{timestamp}.md"
        
        blob = bucket.blob(filename)
        blob.upload_from_string(generated_docs)
        
        return {
            'status': 'success',
            'message': f'Documentation generated and stored at {filename}',
            'storage_path': f'gs://{os.environ.get("BUCKET_NAME")}/{filename}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': str(e)
        }, 500
EOF
        
        # Create requirements.txt
        cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.18.0
google-cloud-aiplatform==1.104.0
functions-framework==3.9.1
EOF
        
        # Deploy function
        local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        log "Deploying Cloud Function: ${FUNCTION_NAME}..."
        gcloud functions deploy "${FUNCTION_NAME}" \
            --gen2 \
            --runtime python312 \
            --trigger-http \
            --allow-unauthenticated \
            --source "${function_dir}" \
            --entry-point generate_docs \
            --memory 512MB \
            --timeout 300s \
            --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
            --service-account "${service_account_email}" \
            --region "${REGION}" \
            --project "${PROJECT_ID}" \
            --quiet
        
        # Get function URL
        FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --format="value(serviceConfig.uri)")
        
        export FUNCTION_URL
        log "Function deployed successfully. URL: ${FUNCTION_URL}"
    else
        log "DRY RUN: Would deploy Cloud Function ${FUNCTION_NAME}"
        FUNCTION_URL="https://example-function-url.cloudfunctions.net"
        export FUNCTION_URL
    fi
}

# Create Cloud Build configuration
create_build_configuration() {
    log "Creating Cloud Build configuration..."
    
    local build_config="${SCRIPT_DIR}/../build/cloudbuild.yaml"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "$(dirname "${build_config}")"
        
        cat > "${build_config}" << EOF
steps:
  # Step 1: Analyze repository structure
  - name: 'gcr.io/cloud-builders/git'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Analyzing repository structure..."
        find . -name "*.py" -o -name "*.js" -o -name "*.go" \\
            -o -name "*.java" | head -10 > files_to_document.txt
        echo "Found files for documentation:"
        cat files_to_document.txt

  # Step 2: Generate API documentation for Python files
  - name: 'gcr.io/cloud-builders/curl'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Generating API documentation..."
        for file in \$\$(grep "\\.py\$\$" files_to_document.txt); do
          if [ -f "\$\$file" ]; then
            echo "Processing \$\$file..."
            content=\$\$(cat "\$\$file" | head -50)
            escaped_content=\$\$(echo "\$\$content" | sed 's/"/\\\\"/g' | tr '\\n' ' ')
            curl -X POST "\${_FUNCTION_URL}" \\
              -H "Content-Type: application/json" \\
              -d "{\\"repo_path\\":\\"\$\$file\\",\\"file_content\\":\\"\$\$escaped_content\\",\\"doc_type\\":\\"api\\"}"
          fi
        done

  # Step 3: Generate README documentation
  - name: 'gcr.io/cloud-builders/curl'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Generating README documentation..."
        repo_structure=\$\$(find . -type f -name "*.py" -o -name "*.js" \\
            -o -name "*.md" | head -20 | xargs ls -la)
        escaped_structure=\$\$(echo "\$\$repo_structure" | sed 's/"/\\\\"/g' | tr '\\n' ' ')
        curl -X POST "\${_FUNCTION_URL}" \\
          -H "Content-Type: application/json" \\
          -d "{\\"repo_path\\":\\"project_root\\",\\"file_content\\":\\"\$\$escaped_structure\\",\\"doc_type\\":\\"readme\\"}"

  # Step 4: Generate code comments for key files
  - name: 'gcr.io/cloud-builders/curl'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Generating enhanced code comments..."
        for file in \$\$(head -3 files_to_document.txt); do
          if [ -f "\$\$file" ]; then
            echo "Adding comments to \$\$file..."
            content=\$\$(cat "\$\$file")
            escaped_content=\$\$(echo "\$\$content" | sed 's/"/\\\\"/g' | tr '\\n' ' ')
            curl -X POST "\${_FUNCTION_URL}" \\
              -H "Content-Type: application/json" \\
              -d "{\\"repo_path\\":\\"\$\$file\\",\\"file_content\\":\\"\$\$escaped_content\\",\\"doc_type\\":\\"comments\\"}"
          fi
        done

  # Step 5: Create documentation index
  - name: 'gcr.io/cloud-builders/gsutil'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Creating documentation index..."
        echo "# Documentation Index" > index.md
        echo "Generated on: \$\$(date)" >> index.md
        echo "" >> index.md
        echo "## Available Documentation" >> index.md
        echo "- API Documentation: gs://\${_BUCKET_NAME}/api/" >> index.md
        echo "- README Files: gs://\${_BUCKET_NAME}/readme/" >> index.md
        echo "- Enhanced Code: gs://\${_BUCKET_NAME}/comments/" >> index.md
        gsutil cp index.md gs://\${_BUCKET_NAME}/

substitutions:
  _FUNCTION_URL: '${FUNCTION_URL}'
  _BUCKET_NAME: '${BUCKET_NAME}'

options:
  logging: CLOUD_LOGGING_ONLY
EOF
        
        log "Cloud Build configuration created at: ${build_config}"
    else
        log "DRY RUN: Would create Cloud Build configuration"
    fi
}

# Create build trigger
create_build_trigger() {
    log "Creating Cloud Build trigger..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        local trigger_name="${BUILD_TRIGGER_NAME}-manual"
        local build_config="${SCRIPT_DIR}/../build/cloudbuild.yaml"
        
        # Check if trigger already exists
        if gcloud builds triggers describe "${trigger_name}" &> /dev/null; then
            warn "Build trigger ${trigger_name} already exists"
        else
            gcloud builds triggers create manual \
                --name="${trigger_name}" \
                --build-config="${build_config}" \
                --description="Manual documentation generation trigger" \
                --project="${PROJECT_ID}"
        fi
        
        log "Build trigger created: ${trigger_name}"
        log "Note: For GitHub integration, configure repository connection in Cloud Build console"
    else
        log "DRY RUN: Would create build trigger ${BUILD_TRIGGER_NAME}-manual"
    fi
}

# Deploy notification function
deploy_notification_function() {
    log "Deploying notification function..."
    
    local notification_dir="${SCRIPT_DIR}/../functions/notification"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "${notification_dir}"
        
        # Create main.py for notification function
        cat > "${notification_dir}/main.py" << 'EOF'
import json
from google.cloud import storage
import functions_framework

@functions_framework.cloud_event
def notify_team(cloud_event):
    """Send notification when documentation is updated"""
    
    try:
        # Parse the Cloud Storage event
        data = cloud_event.data
        bucket_name = data.get('bucket', '')
        file_name = data.get('name', '')
        
        if 'index.md' in file_name:
            # Documentation update detected
            message = f"""
            📚 Documentation Updated!
            
            New documentation has been generated and is available at:
            gs://{bucket_name}/
            
            Updated files include:
            - API Documentation
            - README Files  
            - Enhanced Code Comments
            
            Access your documentation at: https://console.cloud.google.com/storage/browser/{bucket_name}
            """
            
            print(f"Documentation notification: {message}")
            # Add email/Slack integration here as needed
            
        return {'status': 'notification sent'}
        
    except Exception as e:
        print(f"Notification error: {str(e)}")
        return {'status': 'error', 'message': str(e)}
EOF
        
        # Create requirements.txt for notification function
        cat > "${notification_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.18.0
functions-framework==3.9.1
EOF
        
        # Deploy notification function
        gcloud functions deploy "${NOTIFICATION_FUNCTION_NAME}" \
            --gen2 \
            --runtime python312 \
            --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
            --trigger-event-filters="bucket=${BUCKET_NAME}" \
            --source "${notification_dir}" \
            --entry-point notify_team \
            --memory 256MB \
            --region "${REGION}" \
            --project "${PROJECT_ID}" \
            --quiet
        
        log "Notification function deployed: ${NOTIFICATION_FUNCTION_NAME}"
    else
        log "DRY RUN: Would deploy notification function ${NOTIFICATION_FUNCTION_NAME}"
    fi
}

# Deploy documentation website (optional)
deploy_documentation_website() {
    if [[ "${DEPLOY_WEBSITE}" == "false" ]]; then
        log "Skipping documentation website deployment"
        return 0
    fi
    
    log "Deploying documentation website..."
    
    local website_dir="${SCRIPT_DIR}/../website"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "${website_dir}"
        
        # Create index.html
        cat > "${website_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Project Documentation</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #4285F4; color: white; padding: 20px; border-radius: 8px; }
        .section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 8px; }
        .link { color: #4285F4; text-decoration: none; }
        .link:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📚 Project Documentation</h1>
        <p>Automatically generated documentation powered by Gemini AI</p>
    </div>
    
    <div class="section">
        <h2>📖 API Documentation</h2>
        <p>Comprehensive API documentation with examples and usage patterns.</p>
        <a href="#" class="link">View API Docs →</a>
    </div>
    
    <div class="section">
        <h2>📝 README Files</h2>
        <p>Project overviews, setup instructions, and contribution guidelines.</p>
        <a href="#" class="link">View README Files →</a>
    </div>
    
    <div class="section">
        <h2>💬 Enhanced Code</h2>
        <p>Code files with AI-generated comments and explanations.</p>
        <a href="#" class="link">View Enhanced Code →</a>
    </div>
    
    <div class="section">
        <h2>🔄 Last Updated</h2>
        <p id="lastUpdated">Loading...</p>
    </div>
    
    <script>
        document.getElementById('lastUpdated').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
        
        # Deploy to Cloud Storage
        gsutil cp "${website_dir}/index.html" "gs://${BUCKET_NAME}/website/"
        gsutil web set -m index.html "gs://${BUCKET_NAME}"
        
        log "Documentation website deployed"
        log "Access at: https://storage.googleapis.com/${BUCKET_NAME}/website/index.html"
    else
        log "DRY RUN: Would deploy documentation website"
    fi
}

# Create configuration file for cleanup
create_cleanup_config() {
    local config_file="${SCRIPT_DIR}/.deployment-config"
    
    cat > "${config_file}" << EOF
# Deployment configuration for cleanup
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
BUCKET_NAME="${BUCKET_NAME}"
FUNCTION_NAME="${FUNCTION_NAME}"
BUILD_TRIGGER_NAME="${BUILD_TRIGGER_NAME}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}"
NOTIFICATION_FUNCTION_NAME="${NOTIFICATION_FUNCTION_NAME}"
DEPLOY_WEBSITE="${DEPLOY_WEBSITE}"
DEPLOYMENT_DATE="$(date)"
EOF
    
    log "Deployment configuration saved to: ${config_file}"
}

# Cleanup function for error handling
cleanup_resources() {
    warn "Starting emergency cleanup of partially deployed resources..."
    
    # Note: This is a simplified cleanup. Full cleanup should use destroy.sh
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet &>/dev/null || true
    fi
    
    if [[ -n "${NOTIFICATION_FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${NOTIFICATION_FUNCTION_NAME}" --region="${REGION}" --quiet &>/dev/null || true
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" &>/dev/null || true
    fi
    
    warn "Emergency cleanup completed"
}

# Main deployment function
main() {
    log "Starting deployment of Automated Code Documentation with Gemini and Cloud Build"
    log "Log file: ${LOG_FILE}"
    
    check_prerequisites
    initialize_environment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN MODE - No actual resources will be created"
    fi
    
    enable_apis
    create_service_account
    create_storage_bucket
    deploy_documentation_function
    create_build_configuration
    create_build_trigger
    deploy_notification_function
    deploy_documentation_website
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        create_cleanup_config
    fi
    
    log "Deployment completed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Storage Bucket: gs://${BUCKET_NAME}"
    log "  Documentation Function: ${FUNCTION_NAME}"
    log "  Notification Function: ${NOTIFICATION_FUNCTION_NAME}"
    log "  Build Trigger: ${BUILD_TRIGGER_NAME}-manual"
    if [[ "${DEPLOY_WEBSITE}" == "true" ]]; then
        log "  Website: https://storage.googleapis.com/${BUCKET_NAME}/website/index.html"
    fi
    log ""
    log "🚀 Next Steps:"
    log "  1. Test the documentation function manually"
    log "  2. Trigger the build pipeline to generate sample documentation"
    log "  3. Configure repository connections for automatic triggers"
    log "  4. Customize notification integrations (email/Slack)"
    log ""
    log "📊 Estimated Monthly Cost: \$5-15 for moderate usage"
    log "💡 Use destroy.sh to remove all resources when no longer needed"
    log ""
    log "Log file saved: ${LOG_FILE}"
}

# Run main function
main "$@"