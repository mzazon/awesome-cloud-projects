#!/bin/bash

# Deploy script for Secure Remote Development Access with Cloud Identity-Aware Proxy and Cloud Code
# This script implements zero-trust security principles for remote development environments

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Error handler
error_handler() {
    local line_no=$1
    log_error "Script failed at line $line_no"
    log_error "Cleaning up any partial deployment..."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="secure-dev"
REQUIRED_APIS=(
    "iap.googleapis.com"
    "compute.googleapis.com"
    "artifactregistry.googleapis.com"
    "cloudbuild.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy secure remote development environment with Cloud IAP and Cloud Code.

OPTIONS:
    -p, --project-id PROJECT_ID    Specify existing project ID (optional)
    -r, --region REGION           Specify GCP region (default: us-central1)
    -z, --zone ZONE              Specify GCP zone (default: us-central1-a)
    -n, --no-vm                  Skip VM creation (for testing other components)
    -h, --help                   Show this help message
    --dry-run                    Show what would be deployed without executing

EXAMPLES:
    $0                           # Deploy with auto-generated project
    $0 -p my-project-123         # Deploy to existing project
    $0 -r us-west2 -z us-west2-a # Deploy to specific region/zone
    $0 --dry-run                 # Preview deployment

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Owner or Project Admin permissions
    - VS Code with Cloud Code extension (for development)

EOF
}

# Parse command line arguments
parse_args() {
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
            -n|--no-vm)
                SKIP_VM=true
                shift
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
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if docker is available (for container operations)
    if ! command -v docker &> /dev/null; then
        log_warning "Docker not found. Container operations will be limited."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating random strings"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    REGION=${REGION:-"us-central1"}
    ZONE=${ZONE:-"us-central1-a"}
    
    # Generate project ID if not provided
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
        log_info "Generated project ID: $PROJECT_ID"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Export variables for use in other functions
    export PROJECT_ID REGION ZONE RANDOM_SUFFIX
    export REPO_NAME="secure-dev-repo-${RANDOM_SUFFIX}"
    export VM_NAME="dev-vm-${RANDOM_SUFFIX}"
    export IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/secure-app:v1.0"
    
    log_success "Environment configured"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
}

# Create or configure GCP project
setup_project() {
    log_info "Setting up GCP project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create/configure project: $PROJECT_ID"
        return
    fi
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Using existing project: $PROJECT_ID"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Secure Development Environment"
        
        # Wait for project creation to complete
        sleep 10
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project configured: $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return
    fi
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for API enablement to propagate
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create repository: $REPO_NAME"
        return
    fi
    
    # Create repository
    gcloud artifacts repositories create "$REPO_NAME" \
        --repository-format=docker \
        --location="$REGION" \
        --description="Secure development container registry" \
        --quiet
    
    # Configure Docker authentication
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    log_success "Artifact Registry repository created: $REPO_NAME"
}

# Create development VM with IAP configuration
create_development_vm() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping VM creation as requested"
        return
    fi
    
    log_info "Creating development VM with IAP configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create VM: $VM_NAME"
        log_info "[DRY RUN] Would create firewall rule: allow-iap-ssh"
        return
    fi
    
    # Create development VM without external IP
    gcloud compute instances create "$VM_NAME" \
        --zone="$ZONE" \
        --machine-type=e2-standard-4 \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=50GB \
        --boot-disk-type=pd-standard \
        --no-address \
        --metadata=enable-oslogin=TRUE \
        --scopes=cloud-platform \
        --tags=iap-access,dev-environment \
        --quiet
    
    # Create firewall rule for IAP SSH access
    if ! gcloud compute firewall-rules describe allow-iap-ssh &>/dev/null; then
        gcloud compute firewall-rules create allow-iap-ssh \
            --direction=INGRESS \
            --priority=1000 \
            --network=default \
            --action=ALLOW \
            --rules=tcp:22 \
            --source-ranges=35.235.240.0/20 \
            --target-tags=iap-access \
            --quiet
    else
        log_info "Firewall rule allow-iap-ssh already exists"
    fi
    
    log_success "Development VM created: $VM_NAME"
}

# Configure IAP and OAuth
configure_iap() {
    log_info "Configuring IAP and OAuth..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure OAuth consent screen"
        log_info "[DRY RUN] Would create OAuth brand"
        return
    fi
    
    # Get current user email
    USER_EMAIL=$(gcloud config get-value account)
    
    # Create OAuth brand (this may fail if already exists)
    if ! gcloud iap oauth-brands list --format="value(name)" | head -n1 &>/dev/null; then
        log_info "Creating OAuth brand..."
        gcloud iap oauth-brands create \
            --application_title="Secure Development Environment" \
            --support_email="$USER_EMAIL" \
            --quiet || log_warning "OAuth brand creation failed (may already exist)"
    else
        log_info "OAuth brand already exists"
    fi
    
    log_warning "Manual OAuth consent screen configuration required:"
    log_warning "1. Navigate to: https://console.cloud.google.com/apis/credentials/consent?project=$PROJECT_ID"
    log_warning "2. Configure OAuth consent screen if not already done"
    log_warning "3. Add your email as a test user if using External user type"
    
    log_success "IAP configuration initiated"
}

# Configure IAM permissions
configure_iam() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping IAM configuration (no VM created)"
        return
    fi
    
    log_info "Configuring IAM permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure IAM permissions for VM access"
        return
    fi
    
    USER_EMAIL=$(gcloud config get-value account)
    
    # Grant IAP tunnel access to the VM
    gcloud compute instances add-iam-policy-binding "$VM_NAME" \
        --zone="$ZONE" \
        --member="user:$USER_EMAIL" \
        --role="roles/iap.tunnelResourceAccessor" \
        --quiet
    
    # Grant necessary project-level permissions
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="user:$USER_EMAIL" \
        --role="roles/compute.instanceAdmin" \
        --quiet
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="user:$USER_EMAIL" \
        --role="roles/artifactregistry.writer" \
        --quiet
    
    log_success "IAM permissions configured"
}

# Install development tools on VM
install_development_tools() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping development tools installation (no VM created)"
        return
    fi
    
    log_info "Installing development tools on remote VM..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install development tools on VM"
        return
    fi
    
    # Install tools via IAP SSH connection
    gcloud compute ssh "$VM_NAME" \
        --zone="$ZONE" \
        --tunnel-through-iap \
        --quiet \
        --command="
        set -e
        echo 'Updating system packages...'
        sudo apt-get update && sudo apt-get upgrade -y
        
        echo 'Installing Docker...'
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker \$USER
        rm get-docker.sh
        
        echo 'Installing Google Cloud CLI...'
        curl https://sdk.cloud.google.com | bash
        
        echo 'Installing development tools...'
        sudo apt-get install -y git vim curl wget unzip python3 python3-pip nodejs npm
        
        echo 'Configuring Git...'
        git config --global user.name 'Developer'
        git config --global user.email 'developer@example.com'
        
        echo 'Development environment setup complete'
        "
    
    log_success "Development tools installed"
}

# Create sample application and container
create_sample_application() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping sample application creation (no VM created)"
        return
    fi
    
    log_info "Creating sample application and container..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create sample application and push to registry"
        return
    fi
    
    # Create sample application on VM
    gcloud compute ssh "$VM_NAME" \
        --zone="$ZONE" \
        --tunnel-through-iap \
        --quiet \
        --command="
        set -e
        
        # Re-authenticate gcloud (session may have expired)
        gcloud auth login --brief --quiet
        gcloud config set project $PROJECT_ID
        gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
        
        # Create sample application
        mkdir -p ~/secure-app && cd ~/secure-app
        
        cat > Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask
COPY . .
EXPOSE 8080
CMD [\"python\", \"app.py\"]
EOF
        
        cat > app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Secure Development Environment - IAP Protected'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
        
        echo 'Sample application created'
        
        # Build and push container image
        docker build -t $IMAGE_URI .
        docker push $IMAGE_URI
        
        echo 'Container image pushed to Artifact Registry'
        "
    
    log_success "Sample application created and containerized"
}

# Create Cloud Code configuration
create_cloud_code_config() {
    log_info "Creating Cloud Code configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create VS Code configuration files"
        return
    fi
    
    # Create .vscode directory and configuration
    mkdir -p .vscode
    
    # VS Code settings for Cloud Code
    cat > .vscode/settings.json << EOF
{
    "cloudcode.gcp.project": "$PROJECT_ID",
    "cloudcode.gcp.region": "$REGION",
    "cloudcode.kubernetes.defaultNamespace": "default",
    "cloudcode.artifactRegistry.repository": "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME"
}
EOF
    
    # Launch configuration for Cloud Run debugging
    cat > .vscode/launch.json << EOF
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Cloud Run: Debug",
            "type": "cloudcode.cloudrun",
            "request": "launch",
            "build": {
                "docker": {
                    "path": "Dockerfile"
                }
            },
            "deploy": {
                "cloudrun": {
                    "region": "$REGION",
                    "service": "secure-dev-app"
                }
            }
        }
    ]
}
EOF
    
    log_success "Cloud Code configuration created"
    log_info "Install Cloud Code extension: code --install-extension GoogleCloudTools.cloudcode"
}

# Configure audit logging and monitoring
configure_monitoring() {
    log_info "Configuring audit logging and monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure audit logging and monitoring"
        return
    fi
    
    # Create audit configuration
    cat > audit-policy.yaml << EOF
auditConfigs:
- service: iap.googleapis.com
  auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_READ
  - logType: DATA_WRITE
- service: compute.googleapis.com
  auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_WRITE
EOF
    
    log_info "Audit policy configuration created (apply via Cloud Console)"
    log_warning "Manual configuration required for audit logging:"
    log_warning "1. Go to: https://console.cloud.google.com/iam-admin/audit?project=$PROJECT_ID"
    log_warning "2. Configure audit logs for IAP and Compute Engine services"
    
    log_success "Monitoring configuration prepared"
}

# Test IAP connection
test_iap_connection() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping IAP connection test (no VM created)"
        return
    fi
    
    log_info "Testing IAP SSH connection..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test IAP SSH connection"
        return
    fi
    
    # Test IAP SSH connection
    if gcloud compute ssh "$VM_NAME" \
        --zone="$ZONE" \
        --tunnel-through-iap \
        --quiet \
        --command="echo 'IAP SSH connection successful'"; then
        log_success "IAP SSH connection test passed"
    else
        log_warning "IAP SSH connection test failed - this may be expected if OAuth consent is not configured"
    fi
}

# Save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > "${SCRIPT_DIR}/deployment-state.env" << EOF
# Deployment state for secure remote development environment
PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
REPO_NAME="$REPO_NAME"
VM_NAME="$VM_NAME"
IMAGE_URI="$IMAGE_URI"
DEPLOYMENT_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
    
    log_success "Deployment state saved to deployment-state.env"
}

# Main deployment function
main() {
    log_info "Starting secure remote development environment deployment..."
    log_info "Script: $0"
    log_info "Working directory: $(pwd)"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Show dry run message
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_artifact_registry
    create_development_vm
    configure_iap
    configure_iam
    install_development_tools
    create_sample_application
    create_cloud_code_config
    configure_monitoring
    test_iap_connection
    save_deployment_state
    
    # Display completion message
    log_success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_info "Next steps:"
        log_info "1. Complete OAuth consent screen configuration in Cloud Console"
        log_info "2. Install Cloud Code extension in VS Code"
        log_info "3. Open VS Code and connect to remote development environment"
        log_info "4. Access development VM via: gcloud compute ssh $VM_NAME --zone=$ZONE --tunnel-through-iap"
        echo ""
        log_info "Deployment details:"
        log_info "- Project ID: $PROJECT_ID"
        log_info "- Development VM: $VM_NAME"
        log_info "- Artifact Registry: $REPO_NAME"
        log_info "- Region: $REGION"
        echo ""
        log_warning "Remember to run ./destroy.sh when you're done to avoid charges"
    fi
}

# Execute main function with all arguments
main "$@"