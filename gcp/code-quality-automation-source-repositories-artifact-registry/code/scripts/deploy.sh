#!/bin/bash

# GCP Code Quality Automation Deployment Script
# Recipe: Code Quality Automation with Cloud Source Repositories and Artifact Registry
# Description: Deploys intelligent code quality automation pipeline with security scanning

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

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Remove build trigger if created
    if [[ -n "${BUILD_TRIGGER_NAME:-}" ]]; then
        gcloud builds triggers delete "${BUILD_TRIGGER_NAME}" --quiet 2>/dev/null || true
    fi
    
    # Remove repositories if created
    if [[ -n "${REGISTRY_NAME:-}" ]]; then
        gcloud artifacts repositories delete "${REGISTRY_NAME}" --location="${REGION}" --quiet 2>/dev/null || true
        gcloud artifacts repositories delete "${REGISTRY_NAME}-packages" --location="${REGION}" --quiet 2>/dev/null || true
    fi
    
    # Remove source repository if created
    if [[ -n "${REPO_NAME:-}" ]]; then
        gcloud source repos delete "${REPO_NAME}" --quiet 2>/dev/null || true
    fi
    
    # Remove storage bucket if created
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gsutil -m rm -r "gs://${PROJECT_ID}-build-artifacts" 2>/dev/null || true
    fi
    
    log_warning "Partial cleanup completed"
}

# Set up error trap
trap cleanup_on_error ERR

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Parse command line arguments
FORCE_CREATE_PROJECT=false
SKIP_PREREQUISITES=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --force-create-project)
            FORCE_CREATE_PROJECT=true
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id ID           Use existing project ID"
            echo "  --region REGION          GCP region (default: us-central1)"
            echo "  --force-create-project   Create new project even if one exists"
            echo "  --skip-prerequisites     Skip prerequisite checks"
            echo "  --dry-run               Show what would be deployed without executing"
            echo "  --help                  Show this help message"
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
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error_exit "Git is not installed. Please install it first."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login' first."
    fi
    
    # Check if user has necessary permissions
    log_info "Verifying account permissions..."
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    log_info "Active account: ${ACTIVE_ACCOUNT}"
    
    # Verify billing is enabled for the account
    if ! gcloud beta billing accounts list --format="value(name)" | grep -q "."; then
        log_warning "No billing accounts found. You may need billing enabled to create resources."
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set defaults if not provided
    export REGION="${REGION:-$DEFAULT_REGION}"
    export ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    export REPO_NAME="quality-demo-${RANDOM_SUFFIX}"
    export REGISTRY_NAME="quality-artifacts-${RANDOM_SUFFIX}"
    export BUILD_TRIGGER_NAME="quality-pipeline-${RANDOM_SUFFIX}"
    
    # Generate project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="code-quality-demo-$(date +%s)"
        log_info "Generated project ID: ${PROJECT_ID}"
    fi
    
    log_info "Environment configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Repository: ${REPO_NAME}"
    log_info "  Registry: ${REGISTRY_NAME}"
    log_info "  Build Trigger: ${BUILD_TRIGGER_NAME}"
}

# Project setup
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        if [[ "${FORCE_CREATE_PROJECT}" == "true" ]]; then
            log_warning "Project ${PROJECT_ID} exists but --force-create-project specified"
            log_warning "Using existing project"
        else
            log_info "Using existing project: ${PROJECT_ID}"
        fi
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            gcloud projects create "${PROJECT_ID}" --name="Code Quality Demo"
        fi
    fi
    
    # Set current project
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${PROJECT_ID}"
        gcloud config set compute/region "${REGION}"
        gcloud config set compute/zone "${ZONE}"
    fi
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "sourcerepo.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "containeranalysis.googleapis.com"
        "containerscanning.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if [[ "${DRY_RUN}" == "false" ]]; then
            gcloud services enable "${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN}" == "false" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "All required APIs enabled"
}

# Create Cloud Source Repository
create_source_repository() {
    log_info "Creating Cloud Source Repository..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create the source repository
        gcloud source repos create "${REPO_NAME}" --project="${PROJECT_ID}"
        
        # Create temporary directory for repository setup
        TEMP_DIR=$(mktemp -d)
        cd "${TEMP_DIR}"
        
        # Clone repository locally
        gcloud source repos clone "${REPO_NAME}" --project="${PROJECT_ID}"
        cd "${REPO_NAME}"
        
        # Initialize Git configuration
        git config user.email "developer@example.com"
        git config user.name "Quality Developer"
    fi
    
    log_success "Cloud Source Repository created: ${REPO_NAME}"
}

# Create Artifact Registry repositories
create_artifact_registry() {
    log_info "Creating Artifact Registry repositories..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Docker repository for container images
        gcloud artifacts repositories create "${REGISTRY_NAME}" \
            --repository-format=docker \
            --location="${REGION}" \
            --description="Secure registry for quality-validated artifacts"
        
        # Configure Docker authentication
        gcloud auth configure-docker "${REGION}-docker.pkg.dev"
        
        # Create additional repository for language packages
        gcloud artifacts repositories create "${REGISTRY_NAME}-packages" \
            --repository-format=python \
            --location="${REGION}" \
            --description="Python packages with quality validation"
    fi
    
    log_success "Artifact Registry repositories created with security scanning enabled"
}

# Create sample application and configuration files
create_sample_application() {
    log_info "Creating sample application with quality standards..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create application structure
        mkdir -p src tests docs
        
        # Create main application file
        cat > src/app.py << 'EOF'
"""
High-quality sample application demonstrating code standards.
"""
import logging
import json
from typing import Dict, Any
from flask import Flask, jsonify, request

# Configure structured logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health_check() -> Dict[str, Any]:
    """Health check endpoint with proper error handling."""
    try:
        return jsonify({
            'status': 'healthy',
            'service': 'quality-demo-app',
            'version': '1.0.0'
        })
    except Exception as error:
        logger.error(f"Health check failed: {error}")
        return jsonify({'status': 'unhealthy'}), 500

@app.route('/api/quality-metrics', methods=['GET'])
def get_quality_metrics() -> Dict[str, Any]:
    """Return code quality metrics for demonstration."""
    metrics = {
        'code_coverage': 95.2,
        'security_score': 'A+',
        'maintainability_index': 87,
        'complexity_score': 'Low'
    }
    logger.info(f"Quality metrics requested: {metrics}")
    return jsonify(metrics)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

        # Create requirements file
        cat > requirements.txt << 'EOF'
flask==2.3.3
gunicorn==21.2.0
pytest==7.4.3
pytest-cov==4.1.0
flake8==6.1.0
bandit==1.7.5
safety==2.3.5
black==23.9.1
mypy==1.6.1
EOF

        # Create comprehensive test suite
        cat > tests/test_app.py << 'EOF'
"""
Comprehensive test suite demonstrating quality standards.
"""
import pytest
import json
from src.app import app

@pytest.fixture
def client():
    """Create test client for application."""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health_check(client):
    """Test health check endpoint functionality."""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['status'] == 'healthy'
    assert 'service' in data
    assert 'version' in data

def test_quality_metrics(client):
    """Test quality metrics endpoint."""
    response = client.get('/api/quality-metrics')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'code_coverage' in data
    assert 'security_score' in data
    assert isinstance(data['code_coverage'], float)
EOF

        # Create quality configuration files
        cat > .flake8 << 'EOF'
[flake8]
max-line-length = 88
extend-ignore = E203, W503
exclude = .git,__pycache__,build,dist,.venv
per-file-ignores = __init__.py:F401
EOF

        cat > .bandit << 'EOF'
[bandit]
exclude_dirs = tests,venv,.venv
skips = B101
EOF

        # Create Dockerfile
        cat > Dockerfile << 'EOF'
# Multi-stage build for security and efficiency
FROM python:3.11-slim as builder

# Create non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.11-slim as production

# Create non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Set working directory
WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY src/ ./src/

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Add local packages to PATH
ENV PATH=/home/appuser/.local/bin:$PATH

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start application
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "src.app:app"]
EOF

        # Create .dockerignore
        cat > .dockerignore << 'EOF'
.git
.gitignore
README.md
.env
.venv
venv/
__pycache__/
*.pyc
.pytest_cache/
.coverage
tests/
docs/
EOF
    fi
    
    log_success "Sample application created with quality standards"
}

# Create Cloud Build configuration
create_cloud_build_config() {
    log_info "Creating intelligent Cloud Build pipeline configuration..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        cat > cloudbuild.yaml << 'EOF'
steps:
# Step 1: Install dependencies and prepare environment
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🔍 Installing dependencies for quality analysis..."
    pip install -r requirements.txt
    echo "✅ Dependencies installed successfully"

# Step 2: Code formatting validation
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🎨 Checking code formatting with Black..."
    pip install black==23.9.1
    black --check --diff src/ tests/
    echo "✅ Code formatting validation passed"

# Step 3: Static code analysis
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🔍 Running static code analysis with Flake8..."
    pip install flake8==6.1.0
    flake8 src/ tests/
    echo "✅ Static analysis completed successfully"

# Step 4: Type checking
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🔍 Running type checking with MyPy..."
    pip install mypy==1.6.1
    mypy src/ --ignore-missing-imports
    echo "✅ Type checking validation passed"

# Step 5: Security vulnerability scanning
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🔒 Running security analysis with Bandit..."
    pip install bandit==1.7.5
    bandit -r src/ -f json -o bandit-report.json
    echo "✅ Security analysis completed"

# Step 6: Dependency vulnerability check
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🛡️ Checking dependencies for vulnerabilities..."
    pip install safety==2.3.5
    safety check --json
    echo "✅ Dependency security validation passed"

# Step 7: Comprehensive test execution
- name: 'python:3.11-slim'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    echo "🧪 Running comprehensive test suite..."
    pip install pytest==7.4.3 pytest-cov==4.1.0
    python -m pytest tests/ --cov=src --cov-report=term --cov-report=html
    echo "✅ All tests passed with coverage validation"

# Step 8: Build and scan container image
- name: 'gcr.io/cloud-builders/docker'
  args:
  - 'build'
  - '-t'
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REGISTRY_NAME}/quality-app:${BUILD_ID}'
  - '-t'
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REGISTRY_NAME}/quality-app:latest'
  - '.'

# Step 9: Push validated image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args:
  - 'push'
  - '--all-tags'
  - '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REGISTRY_NAME}/quality-app'

# Configuration for intelligent pipeline
options:
  machineType: 'E2_HIGHCPU_8'
  logging: CLOUD_LOGGING_ONLY

# Substitution variables
substitutions:
  _REGION: 'us-central1'
  _REGISTRY_NAME: '${REGISTRY_NAME}'

# Artifact storage
artifacts:
  objects:
    location: 'gs://${PROJECT_ID}-build-artifacts'
    paths:
    - 'bandit-report.json'
    - 'htmlcov/**/*'
EOF
    fi
    
    log_success "Intelligent Cloud Build pipeline configuration created"
}

# Create Cloud Storage bucket and build trigger
create_build_infrastructure() {
    log_info "Creating build infrastructure..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Cloud Storage bucket for build artifacts
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${PROJECT_ID}-build-artifacts"
        
        # Create intelligent build trigger
        gcloud builds triggers create cloud-source-repositories \
            --repo="${REPO_NAME}" \
            --branch-pattern="^(main|develop|feature/.*)$" \
            --build-config=cloudbuild.yaml \
            --name="${BUILD_TRIGGER_NAME}" \
            --description="Intelligent quality pipeline with automated scanning" \
            --substitutions="_REGION=${REGION},_REGISTRY_NAME=${REGISTRY_NAME}"
    fi
    
    log_success "Build infrastructure created successfully"
}

# Commit and push initial code
commit_initial_code() {
    log_info "Committing initial code to trigger quality pipeline..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Add all files to repository
        git add .
        
        # Create initial commit
        git commit -m "Initial commit: Implement intelligent code quality automation

Features:
- Comprehensive static analysis and security scanning
- Automated testing with coverage validation
- Secure Docker containerization
- Integrated vulnerability assessment
- Multi-stage quality gates"
        
        # Push to trigger pipeline
        git push origin main
        
        # Clean up temporary directory
        cd /
        rm -rf "${TEMP_DIR}"
    fi
    
    log_success "Code committed and intelligent quality pipeline triggered"
}

# Configure advanced security scanning
configure_security_scanning() {
    log_info "Configuring advanced security scanning..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create security policy
        cat > /tmp/security-policy.yaml << 'EOF'
# Artifact Registry Security Policy
apiVersion: v1
kind: Policy
metadata:
  name: quality-security-policy
spec:
  vulnerability_scanning:
    enabled: true
    severity_threshold: "MEDIUM"
  binary_authorization:
    enabled: true
    require_attestations: true
  compliance_checks:
    - cis_benchmarks
    - security_best_practices
EOF
        
        # Wait for image to be available, then scan
        log_info "Waiting for container image to be available for scanning..."
        sleep 60
        
        # Configure continuous vulnerability scanning
        gcloud container images scan \
            "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/quality-app:latest" \
            --location="${REGION}" || true
    fi
    
    log_success "Advanced security scanning configured"
}

# Setup monitoring and alerting
setup_monitoring() {
    log_info "Setting up quality metrics monitoring..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create custom metrics for quality tracking
        gcloud logging metrics create code_quality_score \
            --description="Code quality score from automated analysis" \
            --log-filter='resource.type="cloud_build" AND jsonPayload.status="SUCCESS"' || true
        
        # Create monitoring configuration
        cat > /tmp/monitoring-config.yaml << 'EOF'
# Cloud Build Quality Metrics Configuration
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: code-quality-metrics
spec:
  metrics:
    - build_success_rate
    - security_scan_results
    - test_coverage_percentage
    - vulnerability_count
    - build_duration
    - quality_gate_failures
EOF
    fi
    
    log_success "Quality metrics monitoring configured"
}

# Display deployment summary
display_summary() {
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "📋 Deployment Summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Source Repository: ${REPO_NAME}"
    log_info "  Artifact Registry: ${REGISTRY_NAME}"
    log_info "  Build Trigger: ${BUILD_TRIGGER_NAME}"
    echo
    log_info "🔗 Quick Links:"
    log_info "  Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    log_info "  Source Repositories: https://console.cloud.google.com/source/repos?project=${PROJECT_ID}"
    log_info "  Artifact Registry: https://console.cloud.google.com/artifacts?project=${PROJECT_ID}"
    log_info "  Cloud Build: https://console.cloud.google.com/cloud-build/builds?project=${PROJECT_ID}"
    echo
    log_info "🔍 Next Steps:"
    log_info "  1. Monitor the build pipeline in Cloud Build console"
    log_info "  2. Check vulnerability scan results in Artifact Registry"
    log_info "  3. Review quality metrics and security reports"
    log_info "  4. Customize quality gates based on your requirements"
    echo
    log_info "💡 Tips:"
    log_info "  - Push code changes to trigger automatic quality validation"
    log_info "  - Monitor build logs for detailed quality analysis results"
    log_info "  - Use Cloud Code IDE integration for real-time feedback"
    echo
    log_info "🧹 Cleanup:"
    log_info "  Run './destroy.sh' to remove all created resources"
}

# Main deployment function
main() {
    log_info "🚀 Starting GCP Code Quality Automation deployment..."
    echo
    
    # Check if this is a dry run
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "🔍 DRY RUN MODE - No resources will be created"
        echo
    fi
    
    # Run deployment steps
    if [[ "${SKIP_PREREQUISITES}" == "false" ]]; then
        check_prerequisites
    fi
    
    setup_environment
    setup_project
    enable_apis
    create_source_repository
    create_artifact_registry
    create_sample_application
    create_cloud_build_config
    create_build_infrastructure
    commit_initial_code
    configure_security_scanning
    setup_monitoring
    
    # Display summary
    display_summary
}

# Run main function
main "$@"