#!/bin/bash

# Deploy script for Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions
# This script sets up keyless authentication between GitHub Actions and Google Cloud

set -euo pipefail

# ANSI color codes for output formatting
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
handle_error() {
    log_error "An error occurred on line $1. Exiting."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions

OPTIONS:
    -p, --project-id PROJECT_ID      Google Cloud Project ID (required)
    -r, --region REGION              Deployment region (default: us-central1)
    -o, --repo-owner OWNER           GitHub repository owner (required)
    -n, --repo-name NAME             GitHub repository name (required)
    -h, --help                       Show this help message
    --dry-run                        Show what would be deployed without making changes
    --force                          Skip confirmation prompts

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT             Alternative way to set project ID
    GITHUB_REPO_OWNER               Alternative way to set repository owner
    GITHUB_REPO_NAME                Alternative way to set repository name

EXAMPLES:
    $0 --project-id my-project --repo-owner myorg --repo-name myrepo
    $0 -p my-project -o myorg -n myrepo --region us-west1
    $0 --help

EOF
}

# Default values
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
GITHUB_REPO_OWNER=""
GITHUB_REPO_NAME=""
DRY_RUN=false
FORCE=false

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
        -o|--repo-owner)
            GITHUB_REPO_OWNER="$2"
            shift 2
            ;;
        -n|--repo-name)
            GITHUB_REPO_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
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

# Check for environment variables if not provided via CLI
PROJECT_ID=${PROJECT_ID:-$GOOGLE_CLOUD_PROJECT}
GITHUB_REPO_OWNER=${GITHUB_REPO_OWNER:-$GITHUB_REPO_OWNER_ENV}
GITHUB_REPO_NAME=${GITHUB_REPO_NAME:-$GITHUB_REPO_NAME_ENV}

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
    show_help
    exit 1
fi

if [[ -z "$GITHUB_REPO_OWNER" ]]; then
    log_error "GitHub repository owner is required. Use --repo-owner or set GITHUB_REPO_OWNER environment variable."
    show_help
    exit 1
fi

if [[ -z "$GITHUB_REPO_NAME" ]]; then
    log_error "GitHub repository name is required. Use --repo-name or set GITHUB_REPO_NAME environment variable."
    show_help
    exit 1
fi

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
WIF_POOL_ID="github-pool-${RANDOM_SUFFIX}"
WIF_PROVIDER_ID="github-provider-${RANDOM_SUFFIX}"
SERVICE_ACCOUNT_ID="github-actions-sa-${RANDOM_SUFFIX}"
ARTIFACT_REPO_NAME="apps-${RANDOM_SUFFIX}"
CLOUD_RUN_SERVICE="demo-app-${RANDOM_SUFFIX}"
GITHUB_REPO_FULL="${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access to it."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found, using timestamp for random suffix"
    fi
    
    log_success "Prerequisites check completed"
}

# Display deployment plan
show_deployment_plan() {
    cat << EOF

${BLUE}=== DEPLOYMENT PLAN ===${NC}
Project ID:                ${PROJECT_ID}
Region:                    ${REGION}
GitHub Repository:         ${GITHUB_REPO_FULL}

Resources to be created:
• Workload Identity Pool:  ${WIF_POOL_ID}
• OIDC Provider:          ${WIF_PROVIDER_ID}
• Service Account:        ${SERVICE_ACCOUNT_ID}
• Artifact Registry:      ${ARTIFACT_REPO_NAME}
• Sample Application:     ${CLOUD_RUN_SERVICE}

GitHub Actions Configuration:
• Workload Identity Provider will be configured
• Service account will be granted CI/CD permissions
• Repository access will be restricted to: ${GITHUB_REPO_FULL}

EOF
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo -n "Do you want to proceed with the deployment? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log_info "$description"
    eval "$cmd"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "iam.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "sts.googleapis.com"
        "iamcredentials.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            log_info "API $api is already enabled"
        else
            execute_command "gcloud services enable $api --project=$PROJECT_ID" "Enabling $api"
        fi
    done
    
    log_success "Required APIs enabled"
}

# Create Workload Identity Pool
create_workload_identity_pool() {
    log_info "Creating Workload Identity Pool..."
    
    # Check if pool already exists
    if gcloud iam workload-identity-pools describe "$WIF_POOL_ID" \
        --project="$PROJECT_ID" \
        --location="global" &> /dev/null; then
        log_warning "Workload Identity Pool $WIF_POOL_ID already exists"
        return 0
    fi
    
    execute_command \
        "gcloud iam workload-identity-pools create $WIF_POOL_ID \
            --project=$PROJECT_ID \
            --location=global \
            --display-name='GitHub Actions Pool' \
            --description='Pool for GitHub Actions workflows'" \
        "Creating Workload Identity Pool"
    
    log_success "Workload Identity Pool created: $WIF_POOL_ID"
}

# Configure GitHub OIDC Provider
configure_github_provider() {
    log_info "Configuring GitHub OIDC Provider..."
    
    # Check if provider already exists
    if gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_ID" \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$WIF_POOL_ID" &> /dev/null; then
        log_warning "GitHub OIDC Provider $WIF_PROVIDER_ID already exists"
        return 0
    fi
    
    execute_command \
        "gcloud iam workload-identity-pools providers create-oidc $WIF_PROVIDER_ID \
            --project=$PROJECT_ID \
            --location=global \
            --workload-identity-pool=$WIF_POOL_ID \
            --display-name='GitHub OIDC Provider' \
            --attribute-mapping='google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner' \
            --attribute-condition=\"assertion.repository_owner=='$GITHUB_REPO_OWNER'\" \
            --issuer-uri='https://token.actions.githubusercontent.com'" \
        "Creating GitHub OIDC Provider"
    
    log_success "GitHub OIDC Provider configured with repository restriction"
}

# Create Service Account
create_service_account() {
    log_info "Creating Service Account..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="$PROJECT_ID" &> /dev/null; then
        log_warning "Service Account $SERVICE_ACCOUNT_ID already exists"
        return 0
    fi
    
    execute_command \
        "gcloud iam service-accounts create $SERVICE_ACCOUNT_ID \
            --project=$PROJECT_ID \
            --display-name='GitHub Actions Service Account' \
            --description='Service account for GitHub Actions CI/CD workflows'" \
        "Creating Service Account"
    
    # Grant necessary IAM roles
    local service_account_email="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
    local roles=(
        "roles/cloudbuild.builds.builder"
        "roles/artifactregistry.writer"
        "roles/run.developer"
    )
    
    for role in "${roles[@]}"; do
        execute_command \
            "gcloud projects add-iam-policy-binding $PROJECT_ID \
                --member='serviceAccount:$service_account_email' \
                --role='$role'" \
            "Granting role $role to service account"
    done
    
    log_success "Service Account created with CI/CD permissions: $service_account_email"
}

# Configure Workload Identity Federation Binding
configure_wif_binding() {
    log_info "Configuring Workload Identity Federation binding..."
    
    local service_account_email="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
    local wif_pool_name="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"
    
    execute_command \
        "gcloud iam service-accounts add-iam-policy-binding $service_account_email \
            --project=$PROJECT_ID \
            --role='roles/iam.workloadIdentityUser' \
            --member='principalSet://iam.googleapis.com/${wif_pool_name}/attribute.repository/${GITHUB_REPO_FULL}'" \
        "Configuring Workload Identity Federation binding"
    
    log_success "Workload Identity Federation binding configured"
}

# Create Artifact Registry Repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "$ARTIFACT_REPO_NAME" \
        --project="$PROJECT_ID" \
        --location="$REGION" &> /dev/null; then
        log_warning "Artifact Registry repository $ARTIFACT_REPO_NAME already exists"
        return 0
    fi
    
    execute_command \
        "gcloud artifacts repositories create $ARTIFACT_REPO_NAME \
            --project=$PROJECT_ID \
            --repository-format=docker \
            --location=$REGION \
            --description='Repository for CI/CD container images'" \
        "Creating Artifact Registry repository"
    
    execute_command \
        "gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet" \
        "Configuring Docker authentication"
    
    log_success "Artifact Registry repository created: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO_NAME}"
}

# Create sample application
create_sample_application() {
    log_info "Creating sample application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create sample application files"
        return 0
    fi
    
    # Create application directory structure
    mkdir -p sample-app
    
    # Create Flask application
    cat > sample-app/app.py << 'EOF'
from flask import Flask, jsonify
import os
import datetime

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({
        "message": "Hello from Cloud Run!",
        "timestamp": datetime.datetime.now().isoformat(),
        "version": os.getenv('APP_VERSION', '1.0.0'),
        "environment": os.getenv('ENVIRONMENT', 'production')
    })

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 8080)))
EOF
    
    # Create requirements file
    cat > sample-app/requirements.txt << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > sample-app/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
EOF
    
    log_success "Sample application created"
}

# Generate GitHub Actions workflow
generate_github_workflow() {
    log_info "Generating GitHub Actions workflow..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create GitHub Actions workflow file"
        return 0
    fi
    
    # Create GitHub Actions workflow directory
    mkdir -p .github/workflows
    
    local wif_provider_name="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
    local service_account_email="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create the CI/CD workflow file
    cat > .github/workflows/deploy.yml << EOF
name: Build and Deploy to Cloud Run

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  PROJECT_ID: ${PROJECT_ID}
  REGION: ${REGION}
  ARTIFACT_REPO: ${ARTIFACT_REPO_NAME}
  SERVICE_NAME: ${CLOUD_RUN_SERVICE}

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    permissions:
      contents: read
      id-token: write
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: '${wif_provider_name}'
        service_account: '${service_account_email}'
    
    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2
    
    - name: Configure Docker for Artifact Registry
      run: gcloud auth configure-docker ${REGION}-docker.pkg.dev
    
    - name: Build and push Docker image
      run: |
        IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO_NAME}/demo-app"
        IMAGE_TAG="\${IMAGE_NAME}:\${GITHUB_SHA}"
        
        docker build -t \${IMAGE_TAG} ./sample-app
        docker push \${IMAGE_TAG}
        
        echo "IMAGE_TAG=\${IMAGE_TAG}" >> \$GITHUB_ENV
    
    - name: Deploy to Cloud Run
      run: |
        gcloud run deploy \${SERVICE_NAME} \\
          --image \${IMAGE_TAG} \\
          --region \${REGION} \\
          --platform managed \\
          --allow-unauthenticated \\
          --port 8080 \\
          --memory 512Mi \\
          --cpu 1 \\
          --min-instances 0 \\
          --max-instances 10 \\
          --set-env-vars="APP_VERSION=\${GITHUB_SHA:0:8},ENVIRONMENT=production"
    
    - name: Get service URL
      run: |
        SERVICE_URL=\$(gcloud run services describe \${SERVICE_NAME} \\
          --region=\${REGION} \\
          --format='value(status.url)')
        echo "Service deployed at: \${SERVICE_URL}"
EOF
    
    log_success "GitHub Actions workflow created at .github/workflows/deploy.yml"
}

# Display configuration summary
display_summary() {
    local wif_provider_name="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
    local service_account_email="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    cat << EOF

${GREEN}=== DEPLOYMENT COMPLETE ===${NC}

Configuration Summary:
• Project ID: ${PROJECT_ID}
• Region: ${REGION}
• GitHub Repository: ${GITHUB_REPO_FULL}

Workload Identity Federation:
• Pool ID: ${WIF_POOL_ID}
• Provider ID: ${WIF_PROVIDER_ID}
• Provider Name: ${wif_provider_name}

Service Account:
• ID: ${SERVICE_ACCOUNT_ID}
• Email: ${service_account_email}

Resources Created:
• Artifact Registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO_NAME}
• Sample Application: ./sample-app/
• GitHub Workflow: ./.github/workflows/deploy.yml

Next Steps:
1. Push the generated files to your GitHub repository
2. Ensure your repository has Actions enabled
3. Push to the main branch to trigger the workflow
4. Monitor the GitHub Actions workflow execution

For cleanup, run: ./destroy.sh --project-id ${PROJECT_ID}

EOF
}

# Main execution function
main() {
    log_info "Starting deployment of Secure CI/CD Authentication with Workload Identity Federation"
    
    check_prerequisites
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &> /dev/null
    
    show_deployment_plan
    confirm_deployment
    
    # Execute deployment steps
    enable_apis
    create_workload_identity_pool
    configure_github_provider
    create_service_account
    configure_wif_binding
    create_artifact_registry
    create_sample_application
    generate_github_workflow
    
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"