#!/bin/bash

# Deploy script for Cloud-Native Development Environments with Firebase Studio and Gemini Code Assist
# This script automates the deployment of a complete cloud-native development environment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Firebase CLI is installed
    if ! command_exists firebase; then
        log_error "Firebase CLI is not installed. Installing..."
        if command_exists npm; then
            npm install -g firebase-tools
        else
            log_error "npm is not installed. Please install Node.js and npm first."
            exit 1
        fi
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command_exists git; then
        log_error "git is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-firebase-studio-dev-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export FIREBASE_PROJECT_NAME="${FIREBASE_PROJECT_NAME:-my-ai-app}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export REPO_NAME="${REPO_NAME:-ai-app-repo-${RANDOM_SUFFIX}}"
    export REGISTRY_NAME="${REGISTRY_NAME:-ai-app-registry-${RANDOM_SUFFIX}}"
    export REGISTRY_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}"
    
    log_success "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  FIREBASE_PROJECT_NAME: ${FIREBASE_PROJECT_NAME}"
    log "  REPO_NAME: ${REPO_NAME}"
    log "  REGISTRY_NAME: ${REGISTRY_NAME}"
}

# Function to create GCP project
create_project() {
    log "Creating GCP project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Project ${PROJECT_ID} already exists. Skipping creation."
    else
        gcloud projects create "${PROJECT_ID}" \
            --name="Firebase Studio Development Environment" \
            --set-as-default
        
        log_success "Project created: ${PROJECT_ID}"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Project configuration set"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "firebase.googleapis.com"
        "sourcerepo.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "aiplatform.googleapis.com"
        "generativelanguage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    log_success "All required APIs enabled"
}

# Function to initialize Firebase project
initialize_firebase() {
    log "Initializing Firebase project..."
    
    # Login to Firebase if not already logged in
    if ! firebase projects:list >/dev/null 2>&1; then
        log_warning "Not authenticated with Firebase. Please run 'firebase login' if the automatic login fails."
    fi
    
    # Check if Firebase project exists
    if firebase projects:list | grep -q "${PROJECT_ID}"; then
        log_warning "Firebase project ${PROJECT_ID} already exists. Skipping creation."
    else
        # Create Firebase project
        firebase projects:create "${PROJECT_ID}" \
            --display-name "AI Development Environment" || {
            log_warning "Firebase project creation failed or project already exists"
        }
    fi
    
    # Set the project as default
    firebase use "${PROJECT_ID}" --quiet
    
    log_success "Firebase project initialized: ${PROJECT_ID}"
}

# Function to create Cloud Source Repository
create_source_repository() {
    log "Creating Cloud Source Repository..."
    
    # Check if repository already exists
    if gcloud source repos describe "${REPO_NAME}" >/dev/null 2>&1; then
        log_warning "Repository ${REPO_NAME} already exists. Skipping creation."
    else
        gcloud source repos create "${REPO_NAME}" \
            --project="${PROJECT_ID}"
        
        log_success "Cloud Source Repository created: ${REPO_NAME}"
    fi
    
    # Get repository clone URL
    REPO_URL=$(gcloud source repos describe "${REPO_NAME}" \
        --format="value(url)")
    
    # Configure Git credentials helper
    git config --global credential.helper gcloud.sh
    
    log_success "Repository URL: ${REPO_URL}"
    export REPO_URL
}

# Function to create Artifact Registry
create_artifact_registry() {
    log "Creating Artifact Registry..."
    
    # Check if registry already exists
    if gcloud artifacts repositories describe "${REGISTRY_NAME}" \
        --location="${REGION}" >/dev/null 2>&1; then
        log_warning "Registry ${REGISTRY_NAME} already exists. Skipping creation."
    else
        gcloud artifacts repositories create "${REGISTRY_NAME}" \
            --repository-format=docker \
            --location="${REGION}" \
            --description="Container registry for AI applications"
        
        log_success "Artifact Registry created: ${REGISTRY_NAME}"
    fi
    
    # Configure Docker authentication
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    log_success "Registry URL: ${REGISTRY_URL}"
}

# Function to configure Gemini Code Assist
configure_gemini_assist() {
    log "Configuring Gemini Code Assist..."
    
    # Create service account for Gemini Code Assist
    local service_account="gemini-code-assist"
    
    if gcloud iam service-accounts describe "${service_account}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
        log_warning "Service account ${service_account} already exists. Skipping creation."
    else
        gcloud iam service-accounts create "${service_account}" \
            --display-name="Gemini Code Assist Service Account" \
            --description="Service account for AI-powered development assistance"
        
        log_success "Service account created: ${service_account}"
    fi
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/aiplatform.user" \
        --quiet
    
    log_success "Gemini Code Assist integration configured"
}

# Function to create application configuration
create_app_config() {
    log "Creating application configuration..."
    
    # Create temporary workspace directory
    local workspace_dir="firebase-studio-workspace"
    mkdir -p "${workspace_dir}"
    cd "${workspace_dir}"
    
    # Create application configuration file
    cat > app-config.json << EOF
{
  "name": "intelligent-task-manager",
  "description": "AI-powered task management application with natural language processing",
  "features": [
    "Natural language task creation",
    "AI-powered priority suggestions",
    "Smart deadline recommendations",
    "Automated task categorization"
  ],
  "tech_stack": {
    "frontend": "Next.js with TypeScript",
    "backend": "Firebase Functions",
    "database": "Firestore",
    "ai": "Gemini API"
  }
}
EOF
    
    # Create initial project structure
    mkdir -p src/{components,pages,lib,types}
    mkdir -p functions/src
    
    log_success "Application configuration created"
    cd ..
}

# Function to set up Cloud Build
setup_cloud_build() {
    log "Setting up Cloud Build..."
    
    # Create Cloud Build configuration
    cat > cloudbuild.yaml << EOF
steps:
# Install dependencies
- name: 'node:18'
  entrypoint: 'npm'
  args: ['install']

# Run tests
- name: 'node:18'
  entrypoint: 'npm'
  args: ['test']

# Build application
- name: 'node:18'
  entrypoint: 'npm'
  args: ['run', 'build']

# Build Docker image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGISTRY_URL}/ai-app:latest', '.']

# Push image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGISTRY_URL}/ai-app:latest']

# Deploy to Cloud Run
- name: 'gcr.io/cloud-builders/gcloud'
  args: ['run', 'deploy', 'ai-app', 
         '--image', '${REGISTRY_URL}/ai-app:latest',
         '--region', '${REGION}',
         '--platform', 'managed',
         '--allow-unauthenticated']

options:
  logging: CLOUD_LOGGING_ONLY
EOF
    
    # Create build trigger
    if ! gcloud builds triggers list --format="value(name)" | grep -q "firebase-studio-trigger"; then
        gcloud builds triggers create cloud-source-repositories \
            --repo="${REPO_NAME}" \
            --branch-pattern="main" \
            --build-config=cloudbuild.yaml \
            --description="Automated build and deployment trigger" \
            --name="firebase-studio-trigger"
        
        log_success "Cloud Build trigger created"
    else
        log_warning "Cloud Build trigger already exists. Skipping creation."
    fi
    
    log_success "Cloud Build configuration completed"
}

# Function to initialize Git repository
initialize_git_repository() {
    log "Initializing Git repository..."
    
    # Create temporary directory for repository setup
    local temp_dir="temp-repo-setup"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"
    
    # Clone repository
    git clone "${REPO_URL}" . || {
        log_warning "Repository clone failed or empty repository"
        git init
        git remote add origin "${REPO_URL}"
    }
    
    # Create initial project files
    echo "# AI Development Environment" > README.md
    echo "This project was created using Firebase Studio and Gemini Code Assist" >> README.md
    echo "" >> README.md
    echo "## Getting Started" >> README.md
    echo "1. Open Firebase Studio at https://studio.firebase.google.com" >> README.md
    echo "2. Import this repository" >> README.md
    echo "3. Start developing with AI assistance" >> README.md
    
    # Create .gitignore
    cat > .gitignore << EOF
node_modules/
*.env
.DS_Store
dist/
build/
*.log
.cache/
.firebase/
EOF
    
    # Copy configuration files
    cp ../cloudbuild.yaml . 2>/dev/null || true
    cp ../firebase-studio-workspace/app-config.json . 2>/dev/null || true
    
    # Create package.json for Node.js project
    cat > package.json << EOF
{
  "name": "intelligent-task-manager",
  "version": "1.0.0",
  "description": "AI-powered task management application",
  "main": "index.js",
  "scripts": {
    "start": "next start",
    "build": "next build",
    "dev": "next dev",
    "test": "jest"
  },
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0",
    "firebase": "^10.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/react": "^18.0.0",
    "typescript": "^5.0.0",
    "jest": "^29.0.0"
  }
}
EOF
    
    # Initial commit
    git add .
    git commit -m "Initial project setup with Firebase Studio configuration" || true
    
    # Push to remote repository
    git push origin main || git push -u origin main || {
        log_warning "Git push failed. Repository may be empty or have conflicts."
    }
    
    cd ..
    rm -rf "${temp_dir}"
    
    log_success "Git repository initialized with project configuration"
}

# Function to provide Firebase Studio instructions
provide_firebase_studio_instructions() {
    log "🌐 Firebase Studio Setup Instructions"
    echo ""
    echo "===================================================================================="
    echo "                    FIREBASE STUDIO WORKSPACE SETUP"
    echo "===================================================================================="
    echo ""
    echo "1. Open Firebase Studio: https://studio.firebase.google.com"
    echo "2. Sign in with your Google account"
    echo "3. Select project: ${PROJECT_ID}"
    echo "4. Click 'Create new workspace'"
    echo "5. Choose 'Full-stack AI app' template"
    echo "6. Name your workspace: 'ai-development-environment'"
    echo "7. Import your Git repository: ${REPO_URL}"
    echo ""
    echo "🤖 Gemini Code Assist is automatically integrated and ready to use!"
    echo ""
    echo "===================================================================================="
    echo "                         NEXT STEPS"
    echo "===================================================================================="
    echo ""
    echo "• Start coding with AI assistance in Firebase Studio"
    echo "• Use the App Prototyping Agent to generate application scaffolding"
    echo "• Leverage Gemini Code Assist for intelligent code completion"
    echo "• Deploy automatically through Cloud Build on Git commits"
    echo ""
    echo "===================================================================================="
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check Firebase project
    if firebase projects:list | grep -q "${PROJECT_ID}"; then
        log_success "Firebase project validation passed"
    else
        log_warning "Firebase project validation failed"
    fi
    
    # Check Cloud Source Repository
    if gcloud source repos describe "${REPO_NAME}" >/dev/null 2>&1; then
        log_success "Cloud Source Repository validation passed"
    else
        log_warning "Cloud Source Repository validation failed"
    fi
    
    # Check Artifact Registry
    if gcloud artifacts repositories describe "${REGISTRY_NAME}" \
        --location="${REGION}" >/dev/null 2>&1; then
        log_success "Artifact Registry validation passed"
    else
        log_warning "Artifact Registry validation failed"
    fi
    
    # Check API enablement
    local enabled_apis=$(gcloud services list --enabled --format="value(name)" | grep -E "(firebase|sourcerepo|artifactregistry|cloudbuild|run|aiplatform|generativelanguage)")
    if [[ -n "${enabled_apis}" ]]; then
        log_success "Required APIs validation passed"
    else
        log_warning "Some required APIs may not be enabled"
    fi
    
    log_success "Deployment validation completed"
}

# Function to save deployment summary
save_deployment_summary() {
    log "Saving deployment summary..."
    
    cat > deployment-summary.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "firebase_project_name": "${FIREBASE_PROJECT_NAME}",
  "repository_name": "${REPO_NAME}",
  "repository_url": "${REPO_URL}",
  "registry_name": "${REGISTRY_NAME}",
  "registry_url": "${REGISTRY_URL}",
  "firebase_studio_url": "https://studio.firebase.google.com",
  "next_steps": [
    "Access Firebase Studio at https://studio.firebase.google.com",
    "Create new workspace and import repository",
    "Start developing with AI assistance",
    "Use App Prototyping Agent for rapid development"
  ]
}
EOF
    
    log_success "Deployment summary saved to deployment-summary.json"
}

# Main deployment function
main() {
    log "Starting Firebase Studio and Gemini Code Assist deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_project
    enable_apis
    initialize_firebase
    create_source_repository
    create_artifact_registry
    configure_gemini_assist
    create_app_config
    setup_cloud_build
    initialize_git_repository
    validate_deployment
    save_deployment_summary
    
    log_success "🎉 Deployment completed successfully!"
    echo ""
    provide_firebase_studio_instructions
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"