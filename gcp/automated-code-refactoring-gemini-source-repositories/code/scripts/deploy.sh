#!/bin/bash

# Deployment script for Automated Code Refactoring with Gemini Code Assist and Source Repositories
# This script deploys the complete infrastructure needed for AI-powered code refactoring workflows

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${REPO_NAME:-}" ]] && [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud source repos delete "${REPO_NAME}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
    fi
    if [[ -n "${SERVICE_ACCOUNT_NAME:-}" ]] && [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud iam service-accounts delete "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
    fi
    if [[ -n "${BUILD_TRIGGER_NAME:-}" ]] && [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud builds triggers delete "${BUILD_TRIGGER_NAME}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables
readonly DEFAULT_REGION="us-central1"
readonly REQUIRED_APIS=(
    "sourcerepo.googleapis.com"
    "cloudbuild.googleapis.com"
    "cloudaicompanion.googleapis.com"
)

# Parse command line arguments
DRY_RUN=false
FORCE=false
CUSTOM_PROJECT_ID=""
CUSTOM_REGION="${DEFAULT_REGION}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --project-id)
            CUSTOM_PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --dry-run        Show what would be deployed without making changes"
            echo "  --force          Force deployment even if resources exist"
            echo "  --project-id ID  Use specific project ID instead of generating one"
            echo "  --region REGION  Deploy to specific region (default: us-central1)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Using Google Cloud CLI version: ${gcloud_version}"
    
    log_success "Prerequisites check completed"
}

# Project setup
setup_project() {
    log_info "Setting up project..."
    
    if [[ -n "${CUSTOM_PROJECT_ID}" ]]; then
        export PROJECT_ID="${CUSTOM_PROJECT_ID}"
        log_info "Using provided project ID: ${PROJECT_ID}"
    else
        export PROJECT_ID="refactor-demo-$(date +%s)"
        log_info "Generated project ID: ${PROJECT_ID}"
    fi
    
    export REGION="${CUSTOM_REGION}"
    export REPO_NAME="automated-refactoring-demo"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BUILD_TRIGGER_NAME="refactor-trigger-${random_suffix}"
    export SERVICE_ACCOUNT_NAME="refactor-sa-${random_suffix}"
    
    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Repository: ${REPO_NAME}"
    log_info "  Build Trigger: ${BUILD_TRIGGER_NAME}"
    log_info "  Service Account: ${SERVICE_ACCOUNT_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure project settings"
        return
    fi
    
    # Create project if using generated ID
    if [[ -z "${CUSTOM_PROJECT_ID}" ]]; then
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --quiet; then
            log_error "Failed to create project. You may need billing account access."
            exit 1
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return
    fi
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${PROJECT_ID}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create source repository
create_repository() {
    log_info "Creating source repository..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create repository: ${REPO_NAME}"
        return
    fi
    
    # Check if repository already exists
    if gcloud source repos describe "${REPO_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        if [[ "${FORCE}" == "true" ]]; then
            log_warning "Repository exists, deleting and recreating due to --force flag"
            gcloud source repos delete "${REPO_NAME}" --project="${PROJECT_ID}" --quiet
        else
            log_error "Repository ${REPO_NAME} already exists. Use --force to overwrite."
            exit 1
        fi
    fi
    
    # Create the source repository
    gcloud source repos create "${REPO_NAME}" --project="${PROJECT_ID}"
    
    # Clone the repository locally
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    gcloud source repos clone "${REPO_NAME}" --project="${PROJECT_ID}"
    cd "${REPO_NAME}"
    
    # Create sample application files
    create_sample_application
    
    # Commit and push initial code
    git add .
    git commit -m "Initial commit: Add sample application for refactoring"
    git push origin main
    
    # Store repo path for later cleanup
    export REPO_PATH="${temp_dir}/${REPO_NAME}"
    
    log_success "Source repository created and initialized"
}

# Create sample application with refactoring opportunities
create_sample_application() {
    log_info "Creating sample application..."
    
    # Create main Python application
    cat > main.py << 'EOF'
import json
import requests

def get_user_data(user_id):
    url = "https://api.example.com/users/" + str(user_id)
    response = requests.get(url)
    if response.status_code == 200:
        data = json.loads(response.text)
        return data
    else:
        return None

def get_user_posts(user_id):
    url = "https://api.example.com/users/" + str(user_id) + "/posts"
    response = requests.get(url)
    if response.status_code == 200:
        data = json.loads(response.text)
        return data
    else:
        return None

def process_user_info(user_id):
    user_data = get_user_data(user_id)
    user_posts = get_user_posts(user_id)
    
    if user_data is not None and user_posts is not None:
        result = {}
        result["user"] = user_data
        result["posts"] = user_posts
        return result
    else:
        return None
EOF

    # Create requirements file
    echo "requests>=2.28.0" > requirements.txt
    
    # Create code analysis script
    cat > analyze_and_refactor.py << 'EOF'
#!/usr/bin/env python3
import json
import subprocess
import os

def analyze_code_with_ai():
    """Analyze code and provide refactoring suggestions."""
    print("Starting AI-powered code analysis...")
    
    # Read the current code
    with open('main.py', 'r') as f:
        code_content = f.read()
    
    # In production, this would call the actual Gemini Code Assist API
    # For this demo, we simulate the analysis with predefined suggestions
    print("Analyzing code patterns and best practices...")
    print("Generating refactoring recommendations...")
    
    # Simulated AI analysis results
    analysis_results = {
        "code_quality_score": 6.2,
        "issues_found": [
            "Duplicate code patterns in API request functions",
            "String concatenation should use f-strings",
            "Missing error handling for network requests",
            "Manual JSON parsing instead of using response.json()",
            "Missing type hints for better documentation"
        ],
        "suggestions": [
            "Extract common URL building logic into a helper function",
            "Use f-strings for string formatting instead of concatenation", 
            "Implement proper exception handling for API requests",
            "Use response.json() instead of json.loads(response.text)",
            "Add type hints for better code documentation",
            "Organize code into classes for better structure"
        ],
        "estimated_improvement": "35% reduction in code duplication, improved maintainability"
    }
    
    print("Analysis complete. Refactoring recommendations generated.")
    print(json.dumps(analysis_results, indent=2))
    return analysis_results

if __name__ == "__main__":
    results = analyze_code_with_ai()
    
    # Save analysis results for build pipeline
    with open('refactoring_analysis.json', 'w') as f:
        json.dump(results, f, indent=2)
EOF
    
    chmod +x analyze_and_refactor.py
    
    # Create Cloud Build configuration
    cat > cloudbuild.yaml << 'EOF'
steps:
# Step 1: Setup Git configuration
- name: 'gcr.io/cloud-builders/git'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    git config user.email "refactor-bot@${PROJECT_ID}.iam.gserviceaccount.com"
    git config user.name "Automated Refactor Bot"

# Step 2: Run refactoring analysis
- name: 'gcr.io/cloud-builders/python'
  entrypoint: 'python'
  args: ['analyze_and_refactor.py']

# Step 3: Apply refactoring suggestions
- name: 'gcr.io/cloud-builders/python'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "Applying AI-powered refactoring suggestions..."
    
    # Create improved version of main.py based on analysis
    cat > main_refactored.py << 'PYTHON_EOF'
    import json
    import requests
    from typing import Optional, Dict, Any
    
    class APIClient:
        """API client for handling user data and posts with improved error handling."""
        BASE_URL = "https://api.example.com"
        
        @staticmethod
        def _make_request(endpoint: str) -> Optional[Dict[Any, Any]]:
            """Helper method for API requests with proper error handling."""
            try:
                url = f"{APIClient.BASE_URL}/{endpoint}"
                response = requests.get(url, timeout=10)
                response.raise_for_status()
                return response.json()
            except requests.RequestException as e:
                print(f"API request failed: {e}")
                return None
        
        @staticmethod
        def get_user_data(user_id: int) -> Optional[Dict[Any, Any]]:
            """Fetch user data from the API."""
            return APIClient._make_request(f"users/{user_id}")
        
        @staticmethod
        def get_user_posts(user_id: int) -> Optional[Dict[Any, Any]]:
            """Fetch user posts from the API."""
            return APIClient._make_request(f"users/{user_id}/posts")
        
        @staticmethod
        def process_user_info(user_id: int) -> Optional[Dict[str, Any]]:
            """Process complete user information including posts."""
            user_data = APIClient.get_user_data(user_id)
            user_posts = APIClient.get_user_posts(user_id)
            
            if user_data and user_posts:
                return {
                    "user": user_data,
                    "posts": user_posts
                }
            return None
    PYTHON_EOF
    
    # Replace original file with refactored version
    mv main_refactored.py main.py
    
    echo "✅ Refactoring applied successfully"

# Step 4: Create pull request with improvements
- name: 'gcr.io/cloud-builders/git'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    BRANCH_NAME="refactor/ai-improvements-$(date +%s)"
    
    # Create and switch to new branch
    git checkout -b "$BRANCH_NAME"
    
    # Add refactored files
    git add main.py refactoring_analysis.json
    
    # Commit changes with detailed message
    git commit -m "🤖 AI-powered code refactoring
    
    Applied the following improvements:
    - Extracted common API request logic into helper method
    - Added proper error handling with try/catch blocks
    - Implemented type hints for better code documentation
    - Used f-strings for improved string formatting
    - Added timeout for API requests to prevent hanging
    - Organized code into a class structure for better maintainability
    - Used response.json() instead of manual JSON parsing
    
    Generated by automated refactoring workflow with AI assistance."
    
    # Push the branch
    git push origin "$BRANCH_NAME"
    
    echo "✅ Pull request branch created: $BRANCH_NAME"
    echo "Navigate to Source Repositories console to create pull request"

options:
  logging: CLOUD_LOGGING_ONLY
substitutions:
  _PROJECT_ID: '${PROJECT_ID}'
EOF
    
    log_success "Sample application created"
}

# Create service account
create_service_account() {
    log_info "Creating service account..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create service account: ${SERVICE_ACCOUNT_NAME}"
        return
    fi
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" &>/dev/null; then
        if [[ "${FORCE}" == "true" ]]; then
            log_warning "Service account exists, deleting and recreating due to --force flag"
            gcloud iam service-accounts delete "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet
        else
            log_error "Service account ${SERVICE_ACCOUNT_NAME} already exists. Use --force to overwrite."
            exit 1
        fi
    fi
    
    # Create service account
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Automated Refactoring Service Account" \
        --description="Service account for AI-powered code refactoring workflows" \
        --project="${PROJECT_ID}"
    
    # Grant necessary permissions
    local roles=(
        "roles/source.writer"
        "roles/cloudaicompanion.user"
        "roles/cloudbuild.builds.editor"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role: ${role}"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}"
    done
    
    log_success "Service account created with appropriate permissions"
}

# Create build trigger
create_build_trigger() {
    log_info "Creating Cloud Build trigger..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create build trigger: ${BUILD_TRIGGER_NAME}"
        return
    fi
    
    # Check if trigger already exists
    if gcloud builds triggers describe "${BUILD_TRIGGER_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        if [[ "${FORCE}" == "true" ]]; then
            log_warning "Build trigger exists, deleting and recreating due to --force flag"
            gcloud builds triggers delete "${BUILD_TRIGGER_NAME}" --project="${PROJECT_ID}" --quiet
        else
            log_error "Build trigger ${BUILD_TRIGGER_NAME} already exists. Use --force to overwrite."
            exit 1
        fi
    fi
    
    # Create build trigger
    gcloud builds triggers create cloud-source-repositories \
        --repo="${REPO_NAME}" \
        --branch-pattern="^main$" \
        --build-config=cloudbuild.yaml \
        --name="${BUILD_TRIGGER_NAME}" \
        --description="Automated code refactoring with AI assistance" \
        --service-account="projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="${PROJECT_ID}"
    
    log_success "Build trigger created: ${BUILD_TRIGGER_NAME}"
}

# Validation
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi
    
    # Check repository
    if gcloud source repos describe "${REPO_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        log_success "✓ Source repository is accessible"
    else
        log_error "✗ Source repository validation failed"
        exit 1
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" &>/dev/null; then
        log_success "✓ Service account is configured"
    else
        log_error "✗ Service account validation failed"
        exit 1
    fi
    
    # Check build trigger
    if gcloud builds triggers describe "${BUILD_TRIGGER_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        log_success "✓ Build trigger is active"
    else
        log_error "✗ Build trigger validation failed"
        exit 1
    fi
    
    # Test manual build
    log_info "Testing manual build trigger..."
    cd "${REPO_PATH}"
    local build_id
    build_id=$(gcloud builds submit --config=cloudbuild.yaml --source=. --project="${PROJECT_ID}" --format="value(id)")
    
    if [[ -n "${build_id}" ]]; then
        log_success "✓ Manual build submitted successfully (ID: ${build_id})"
        log_info "Monitor build progress: gcloud builds log --stream ${build_id} --project=${PROJECT_ID}"
    else
        log_warning "Manual build submission failed, but infrastructure is deployed"
    fi
    
    log_success "Deployment validation completed"
}

# Generate deployment summary
print_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Repository: ${REPO_NAME}"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "Build Trigger: ${BUILD_TRIGGER_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Navigate to the Google Cloud Console > Source Repositories"
    echo "2. View your repository: https://source.cloud.google.com/repos"
    echo "3. Monitor builds: https://console.cloud.google.com/cloud-build/builds"
    echo "4. Make code changes and push to trigger automated refactoring"
    echo ""
    echo "Cleanup command:"
    echo "./destroy.sh --project-id ${PROJECT_ID}"
}

# Main deployment function
main() {
    log_info "Starting deployment of Automated Code Refactoring solution..."
    
    check_prerequisites
    setup_project
    enable_apis
    create_repository
    create_service_account
    create_build_trigger
    validate_deployment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Deployment simulation completed successfully"
    else
        log_success "🎉 Deployment completed successfully!"
        print_summary
    fi
}

# Run main function
main "$@"