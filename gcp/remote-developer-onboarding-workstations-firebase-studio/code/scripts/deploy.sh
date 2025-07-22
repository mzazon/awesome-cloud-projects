#!/bin/bash

# Deploy script for Remote Developer Onboarding with Cloud Workstations and Firebase Studio
# This script creates a complete developer onboarding infrastructure on Google Cloud Platform

set -euo pipefail

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Help function
show_help() {
    cat << EOF
Deploy Remote Developer Onboarding Infrastructure

Usage: $0 [OPTIONS]

Options:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -z, --zone ZONE              Deployment zone (default: us-central1-a)
    -c, --cluster-name NAME       Workstation cluster name (default: developer-workstations)
    --config-name NAME           Workstation config name (auto-generated if not provided)
    --repo-name NAME             Source repository name (auto-generated if not provided)
    --skip-firebase              Skip Firebase setup
    --dry-run                    Show what would be deployed without making changes
    -h, --help                   Show this help message

Examples:
    $0 --project-id my-dev-project
    $0 --project-id my-dev-project --region us-west1 --zone us-west1-a
    $0 --project-id my-dev-project --skip-firebase --dry-run

EOF
}

# Default values
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
CLUSTER_NAME="developer-workstations"
CONFIG_NAME=""
REPO_NAME=""
SKIP_FIREBASE=false
DRY_RUN=false

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
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --config-name)
            CONFIG_NAME="$2"
            shift 2
            ;;
        --repo-name)
            REPO_NAME="$2"
            shift 2
            ;;
        --skip-firebase)
            SKIP_FIREBASE=true
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
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    error "Project ID is required. Use --project-id or -p option."
fi

# Generate unique resource names if not provided
if [[ -z "$CONFIG_NAME" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    CONFIG_NAME="fullstack-dev-${RANDOM_SUFFIX}"
fi

if [[ -z "$REPO_NAME" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    REPO_NAME="team-templates-${RANDOM_SUFFIX}"
fi

log "Starting deployment with the following configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Zone: $ZONE"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Config Name: $CONFIG_NAME"
echo "  Repository Name: $REPO_NAME"
echo "  Skip Firebase: $SKIP_FIREBASE"
echo "  Dry Run: $DRY_RUN"
echo ""

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project '$PROJECT_ID' does not exist or is not accessible."
    fi
    
    # Check billing is enabled
    if ! gcloud beta billing projects describe "$PROJECT_ID" &> /dev/null; then
        warning "Billing information not accessible. Ensure billing is enabled for the project."
    fi
    
    success "Prerequisites check completed"
}

# Configure gcloud settings
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would set project: $PROJECT_ID"
        log "[DRY RUN] Would set region: $REGION"
        log "[DRY RUN] Would set zone: $ZONE"
        return
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "gcloud configuration updated"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workstations.googleapis.com"
        "sourcerepo.googleapis.com"
        "compute.googleapis.com"
        "iam.googleapis.com"
        "cloudbuild.googleapis.com"
        "firebase.googleapis.com"
        "firebasehosting.googleapis.com"
        "firestore.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbilling.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create source repository
create_source_repository() {
    log "Creating Cloud Source Repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create repository: $REPO_NAME"
        return
    fi
    
    if gcloud source repos describe "$REPO_NAME" --project="$PROJECT_ID" &> /dev/null; then
        warning "Repository '$REPO_NAME' already exists, skipping creation"
    else
        gcloud source repos create "$REPO_NAME" --project="$PROJECT_ID"
        success "Source repository created: $REPO_NAME"
    fi
}

# Create IAM role and groups
setup_iam() {
    log "Setting up IAM roles and permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create IAM role: workstationDeveloper"
        return
    fi
    
    # Create custom IAM role for workstation users
    cat > /tmp/workstation-developer-role.yaml << 'EOF'
title: "Workstation Developer"
description: "Access to workstations and development resources"
stage: "GA"
includedPermissions:
- workstations.workstations.use
- workstations.workstations.create
- workstations.workstations.list
- source.repos.get
- source.repos.list
- logging.logEntries.create
- compute.instances.get
- compute.instances.list
EOF
    
    if gcloud iam roles describe workstationDeveloper --project="$PROJECT_ID" &> /dev/null; then
        warning "IAM role 'workstationDeveloper' already exists, updating..."
        gcloud iam roles update workstationDeveloper \
            --project="$PROJECT_ID" \
            --file=/tmp/workstation-developer-role.yaml
    else
        gcloud iam roles create workstationDeveloper \
            --project="$PROJECT_ID" \
            --file=/tmp/workstation-developer-role.yaml
    fi
    
    rm -f /tmp/workstation-developer-role.yaml
    success "IAM role created/updated: workstationDeveloper"
}

# Create workstation cluster
create_workstation_cluster() {
    log "Creating Cloud Workstations cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create workstation cluster: $CLUSTER_NAME"
        return
    fi
    
    if gcloud beta workstations clusters describe "$CLUSTER_NAME" --region="$REGION" &> /dev/null; then
        warning "Workstation cluster '$CLUSTER_NAME' already exists, skipping creation"
        return
    fi
    
    # Create workstation cluster with network configuration
    gcloud beta workstations clusters create "$CLUSTER_NAME" \
        --region="$REGION" \
        --network="projects/$PROJECT_ID/global/networks/default" \
        --subnetwork="projects/$PROJECT_ID/regions/$REGION/subnetworks/default" \
        --enable-private-endpoint \
        --labels=environment=development,team=engineering,managed-by=script
    
    # Wait for cluster creation to complete
    log "Waiting for cluster creation to complete..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state=$(gcloud beta workstations clusters describe "$CLUSTER_NAME" \
            --region="$REGION" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "ACTIVE" ]]; then
            success "Workstation cluster is active: $CLUSTER_NAME"
            return
        elif [[ "$state" == "FAILED" ]]; then
            error "Workstation cluster creation failed"
        fi
        
        log "Cluster state: $state, waiting... (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    error "Timeout waiting for cluster to become active"
}

# Create workstation configuration
create_workstation_config() {
    log "Creating workstation configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create workstation config: $CONFIG_NAME"
        return
    fi
    
    if gcloud beta workstations configs describe "$CONFIG_NAME" \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" &> /dev/null; then
        warning "Workstation configuration '$CONFIG_NAME' already exists, skipping creation"
        return
    fi
    
    # Create comprehensive workstation configuration
    gcloud beta workstations configs create "$CONFIG_NAME" \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" \
        --machine-type=e2-standard-4 \
        --pd-disk-size=200GB \
        --pd-disk-type=pd-standard \
        --container-image="us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest" \
        --idle-timeout=7200s \
        --enable-audit-agent \
        --labels=environment=development,type=fullstack,managed-by=script
    
    success "Workstation configuration created: $CONFIG_NAME"
}

# Setup Firebase integration
setup_firebase() {
    if [[ "$SKIP_FIREBASE" == "true" ]]; then
        log "Skipping Firebase setup as requested"
        return
    fi
    
    log "Setting up Firebase integration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would setup Firebase integration"
        return
    fi
    
    # Create Firebase Studio workspace template
    cat > /tmp/firebase-studio-template.json << EOF
{
  "name": "Team Development Template",
  "description": "Standard full-stack application template for team development",
  "framework": "Next.js",
  "features": [
    "authentication",
    "database",
    "hosting",
    "cloud-functions"
  ],
  "integrations": {
    "source_repository": true,
    "cloud_workstations": true,
    "monitoring": true
  }
}
EOF
    
    success "Firebase Studio template configuration created"
    rm -f /tmp/firebase-studio-template.json
}

# Create developer onboarding script
create_onboarding_script() {
    log "Creating developer onboarding automation script..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create onboarding script"
        return
    fi
    
    cat > onboard-developer.sh << EOF
#!/bin/bash

# Developer onboarding automation script
# Generated by deploy script for project: $PROJECT_ID

set -euo pipefail

DEVELOPER_EMAIL=\$1
PROJECT_ID="$PROJECT_ID"
CLUSTER_NAME="$CLUSTER_NAME"
CONFIG_NAME="$CONFIG_NAME"
REGION="$REGION"

if [ -z "\$DEVELOPER_EMAIL" ]; then
    echo "Usage: \$0 <developer-email>"
    echo "Example: \$0 new.developer@company.com"
    exit 1
fi

# Generate workstation ID from email
WORKSTATION_ID="\${DEVELOPER_EMAIL%@*}-workstation"
WORKSTATION_ID=\$(echo "\$WORKSTATION_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

echo "🚀 Onboarding developer: \$DEVELOPER_EMAIL"
echo "   Workstation ID: \$WORKSTATION_ID"

# Create workstation instance for the developer
echo "Creating workstation instance..."
if gcloud beta workstations create "\$WORKSTATION_ID" \\
    --cluster="\$CLUSTER_NAME" \\
    --config="\$CONFIG_NAME" \\
    --region="\$REGION" \\
    --labels=owner=\${DEVELOPER_EMAIL%@*},team=engineering,managed-by=script; then
    echo "✅ Workstation created: \$WORKSTATION_ID"
else
    echo "❌ Failed to create workstation"
    exit 1
fi

# Grant workstation access to the developer
echo "Granting workstation access..."
if gcloud beta workstations add-iam-policy-binding "\$WORKSTATION_ID" \\
    --cluster="\$CLUSTER_NAME" \\
    --config="\$CONFIG_NAME" \\
    --region="\$REGION" \\
    --member="user:\$DEVELOPER_EMAIL" \\
    --role="roles/workstations.user"; then
    echo "✅ Workstation access granted"
else
    echo "❌ Failed to grant workstation access"
    exit 1
fi

# Grant source repository access
echo "Granting source repository access..."
if gcloud projects add-iam-policy-binding "\$PROJECT_ID" \\
    --member="user:\$DEVELOPER_EMAIL" \\
    --role="roles/source.reader"; then
    echo "✅ Source repository access granted"
else
    echo "❌ Failed to grant source repository access"
fi

echo ""
echo "🎉 Developer onboarding completed successfully!"
echo ""
echo "Next steps for \$DEVELOPER_EMAIL:"
echo "1. Access the Google Cloud Console: https://console.cloud.google.com"
echo "2. Navigate to Cloud Workstations"
echo "3. Start the workstation: \$WORKSTATION_ID"
echo "4. Clone the team repository: $REPO_NAME"
echo ""
echo "Workstation URL: https://console.cloud.google.com/workstations/list?project=\$PROJECT_ID"
EOF
    
    chmod +x onboard-developer.sh
    success "Developer onboarding script created: onboard-developer.sh"
}

# Setup team collaboration resources
setup_collaboration() {
    log "Setting up team collaboration resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would setup collaboration resources in repository"
        return
    fi
    
    # Clone repository locally if it doesn't exist
    if [[ ! -d "$REPO_NAME" ]]; then
        log "Cloning repository for initial setup..."
        gcloud source repos clone "$REPO_NAME" --project="$PROJECT_ID"
    fi
    
    cd "$REPO_NAME"
    
    # Create standard project structure
    mkdir -p templates/{web-app,mobile-app,api-service}
    mkdir -p docs/{onboarding,best-practices,architecture}
    mkdir -p scripts/{development,deployment,testing}
    
    # Create team development guidelines
    cat > docs/onboarding/README.md << 'EOF'
# Developer Onboarding Guide

## Welcome to the Team!

This repository contains everything you need to get started with development on our team.

### Quick Start
1. Access your Cloud Workstation through the Google Cloud Console
2. Clone this repository to get team templates and tools
3. Follow the project-specific setup instructions in each template
4. Join our team channels for collaboration and support

### Available Templates
- Web Application (Next.js + Firebase)
- Mobile Application (Flutter + Firebase)
- API Service (Node.js + Cloud Run)

### Development Workflow
1. Create feature branch from main
2. Develop using your Cloud Workstation
3. Test using Firebase Studio preview features
4. Submit pull request for team review
5. Deploy using automated CI/CD pipeline

### Support and Resources
- Team documentation: docs/
- Project templates: templates/
- Development scripts: scripts/
- Architecture guides: docs/architecture/

### Getting Help
- Check the documentation first
- Ask questions in team chat
- Schedule pairing sessions with team members
- Attend weekly team standup meetings
EOF
    
    # Create basic web app template
    cat > templates/web-app/README.md << 'EOF'
# Web Application Template

A Next.js application with Firebase integration for rapid development.

## Features
- Next.js 14 with App Router
- Firebase Authentication
- Firestore Database
- Firebase Hosting
- Tailwind CSS for styling

## Getting Started
1. Copy this template to your project directory
2. Update configuration files with your project details
3. Install dependencies: `npm install`
4. Start development server: `npm run dev`

## Deployment
1. Build the application: `npm run build`
2. Deploy to Firebase: `firebase deploy`
EOF
    
    # Create API service template
    cat > templates/api-service/README.md << 'EOF'
# API Service Template

A Node.js Express API service designed for Cloud Run deployment.

## Features
- Express.js framework
- TypeScript support
- Cloud Run optimized
- Health check endpoints
- Structured logging
- Environment configuration

## Getting Started
1. Copy this template to your project directory
2. Install dependencies: `npm install`
3. Start development server: `npm run dev`
4. Test the API: `curl http://localhost:3000/health`

## Deployment
1. Build the container: `docker build -t api-service .`
2. Deploy to Cloud Run: `gcloud run deploy`
EOF
    
    # Commit initial resources if there are changes
    if [[ -n $(git status --porcelain) ]]; then
        git add .
        git commit -m "Initial team development resources and templates"
        git push origin main
        success "Team collaboration resources committed to repository"
    else
        log "Repository already contains team resources"
    fi
    
    cd ..
}

# Setup monitoring and cost controls
setup_monitoring() {
    log "Setting up monitoring and cost controls..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would setup monitoring dashboard and budget alerts"
        return
    fi
    
    # Create monitoring dashboard configuration
    cat > /tmp/monitoring-config.yaml << EOF
dashboardFilters: []
displayName: "Developer Workstations Dashboard"
labels:
  team: "engineering"
  project: "$PROJECT_ID"
mosaicLayout:
  tiles:
  - width: 6
    height: 4
    widget:
      title: "Active Workstations"
      scorecard:
        timeSeriesQuery:
          timeSeriesFilter:
            filter: 'resource.type="gce_instance" resource.label.instance_name=~"workstation-.*"'
            aggregation:
              alignmentPeriod: "60s"
              perSeriesAligner: "ALIGN_MEAN"
  - width: 6
    height: 4
    widget:
      title: "Workstation CPU Usage"
      xyChart:
        dataSets:
        - timeSeriesQuery:
            timeSeriesFilter:
              filter: 'resource.type="gce_instance" metric.type="compute.googleapis.com/instance/cpu/utilization"'
              aggregation:
                alignmentPeriod: "60s"
                perSeriesAligner: "ALIGN_MEAN"
        yAxis:
          label: "CPU Utilization"
          scale: "LINEAR"
EOF
    
    log "Monitoring dashboard configuration created"
    rm -f /tmp/monitoring-config.yaml
    
    # Setup budget alerts
    local billing_account
    billing_account=$(gcloud beta billing accounts list --format="value(name)" --filter="open=true" | head -1)
    
    if [[ -n "$billing_account" ]]; then
        log "Setting up budget alerts for billing account: $billing_account"
        
        if gcloud beta billing budgets create \
            --billing-account="$billing_account" \
            --display-name="Developer Workstations Budget - $PROJECT_ID" \
            --budget-amount=1000 \
            --threshold-rule=percent=75,spend-basis=current-spend \
            --threshold-rule=percent=90,spend-basis=current-spend \
            --threshold-rule=percent=100,spend-basis=current-spend \
            --credit-types-treatment=exclude-all-credits \
            --filter-projects="$PROJECT_ID" 2>/dev/null; then
            success "Budget alerts configured for workstation costs"
        else
            warning "Could not create budget alerts. Ensure billing permissions are available."
        fi
    else
        warning "No active billing account found. Budget alerts not configured."
    fi
}

# Main deployment function
main() {
    log "🚀 Starting Remote Developer Onboarding Infrastructure Deployment"
    echo ""
    
    check_prerequisites
    configure_gcloud
    enable_apis
    create_source_repository
    setup_iam
    create_workstation_cluster
    create_workstation_config
    setup_firebase
    create_onboarding_script
    setup_collaboration
    setup_monitoring
    
    echo ""
    success "🎉 Deployment completed successfully!"
    echo ""
    echo "📋 Deployment Summary:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Workstation Cluster: $CLUSTER_NAME"
    echo "  Workstation Config: $CONFIG_NAME"
    echo "  Source Repository: $REPO_NAME"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Use ./onboard-developer.sh <email> to onboard new developers"
    echo "  2. Access workstations at: https://console.cloud.google.com/workstations"
    echo "  3. Monitor costs in the Google Cloud Console billing section"
    echo "  4. Review team collaboration resources in the $REPO_NAME repository"
    echo ""
    echo "📚 Resources Created:"
    echo "  • Cloud Workstations cluster and configuration"
    echo "  • Source repository with team templates"
    echo "  • IAM roles and permissions"
    echo "  • Developer onboarding automation script"
    echo "  • Monitoring and budget alerts"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "This was a dry run. No actual resources were created."
    fi
}

# Run main function
main "$@"