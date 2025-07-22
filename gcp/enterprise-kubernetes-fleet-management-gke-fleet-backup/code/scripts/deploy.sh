#!/bin/bash

# Enterprise Kubernetes Fleet Management with GKE Fleet and Backup for GKE - Deployment Script
# This script automates the deployment of a comprehensive fleet management solution

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_BILLING_ACCOUNT=""

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to print section headers
print_section() {
    echo
    print_status "$BLUE" "=========================================="
    print_status "$BLUE" "$1"
    print_status "$BLUE" "=========================================="
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_status "$RED" "❌ Missing required tools: ${missing_tools[*]}"
        print_status "$YELLOW" "Please install the missing tools and try again."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_status "$RED" "❌ gcloud not authenticated"
        print_status "$YELLOW" "Please run 'gcloud auth login' and try again."
        exit 1
    fi
    
    # Check if gcloud CLI version is recent enough
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "0.0.0")
    log "INFO" "gcloud CLI version: $gcloud_version"
    
    print_status "$GREEN" "✅ All prerequisites met"
}

# Function to get user input with defaults
get_user_input() {
    print_section "Configuration Setup"
    
    # Check if config file exists
    if [[ -f "$CONFIG_FILE" ]]; then
        print_status "$YELLOW" "Found existing configuration file. Loading settings..."
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
    
    # Get billing account
    if [[ -z "${BILLING_ACCOUNT:-}" ]]; then
        print_status "$YELLOW" "Available billing accounts:"
        gcloud billing accounts list
        echo
        read -rp "Enter your billing account ID: " BILLING_ACCOUNT
        if [[ -z "$BILLING_ACCOUNT" ]]; then
            print_status "$RED" "❌ Billing account is required"
            exit 1
        fi
    fi
    
    # Get region
    REGION="${REGION:-$DEFAULT_REGION}"
    read -rp "Enter deployment region [$REGION]: " user_region
    REGION="${user_region:-$REGION}"
    
    # Get zone
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    read -rp "Enter deployment zone [$ZONE]: " user_zone
    ZONE="${user_zone:-$ZONE}"
    
    # Generate unique project IDs
    local timestamp
    timestamp=$(date +%s)
    FLEET_HOST_PROJECT_ID="${FLEET_HOST_PROJECT_ID:-fleet-host-$timestamp}"
    WORKLOAD_PROJECT_1="${WORKLOAD_PROJECT_1:-workload-prod-$timestamp}"
    WORKLOAD_PROJECT_2="${WORKLOAD_PROJECT_2:-workload-staging-$timestamp}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    FLEET_NAME="enterprise-fleet-${RANDOM_SUFFIX}"
    BACKUP_PLAN_NAME="fleet-backup-plan-${RANDOM_SUFFIX}"
    
    # Save configuration
    cat > "$CONFIG_FILE" << EOF
BILLING_ACCOUNT="$BILLING_ACCOUNT"
REGION="$REGION"
ZONE="$ZONE"
FLEET_HOST_PROJECT_ID="$FLEET_HOST_PROJECT_ID"
WORKLOAD_PROJECT_1="$WORKLOAD_PROJECT_1"
WORKLOAD_PROJECT_2="$WORKLOAD_PROJECT_2"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
FLEET_NAME="$FLEET_NAME"
BACKUP_PLAN_NAME="$BACKUP_PLAN_NAME"
EOF
    
    print_status "$GREEN" "✅ Configuration saved"
    log "INFO" "Fleet Host Project: $FLEET_HOST_PROJECT_ID"
    log "INFO" "Production Project: $WORKLOAD_PROJECT_1"
    log "INFO" "Staging Project: $WORKLOAD_PROJECT_2"
    log "INFO" "Region: $REGION"
    log "INFO" "Zone: $ZONE"
}

# Function to create projects
create_projects() {
    print_section "Creating Google Cloud Projects"
    
    local projects=("$FLEET_HOST_PROJECT_ID" "$WORKLOAD_PROJECT_1" "$WORKLOAD_PROJECT_2")
    local project_names=("Fleet Host Project" "Production Workload Project" "Staging Workload Project")
    
    for i in "${!projects[@]}"; do
        local project="${projects[$i]}"
        local name="${project_names[$i]}"
        
        # Check if project already exists
        if gcloud projects describe "$project" &>/dev/null; then
            print_status "$YELLOW" "⚠️  Project $project already exists, skipping creation"
            continue
        fi
        
        print_status "$BLUE" "Creating project: $project ($name)"
        
        if ! gcloud projects create "$project" --name="$name"; then
            print_status "$RED" "❌ Failed to create project: $project"
            exit 1
        fi
        
        # Link billing account
        if ! gcloud billing projects link "$project" --billing-account="$BILLING_ACCOUNT"; then
            print_status "$RED" "❌ Failed to link billing account for project: $project"
            exit 1
        fi
        
        print_status "$GREEN" "✅ Created and configured project: $project"
        
        # Small delay to avoid rate limiting
        sleep 2
    done
}

# Function to enable APIs
enable_apis() {
    print_section "Enabling Required APIs"
    
    # Set fleet host project as active
    gcloud config set project "$FLEET_HOST_PROJECT_ID"
    
    # APIs for fleet host project
    local fleet_apis=(
        "container.googleapis.com"
        "gkehub.googleapis.com"
        "gkebackup.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "krmapihosting.googleapis.com"
        "anthosconfigmanagement.googleapis.com"
        "iam.googleapis.com"
        "cloudbilling.googleapis.com"
    )
    
    print_status "$BLUE" "Enabling APIs for fleet host project..."
    for api in "${fleet_apis[@]}"; do
        print_status "$BLUE" "  Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            print_status "$YELLOW" "⚠️  Warning: Failed to enable $api"
        fi
    done
    
    # APIs for workload projects
    local workload_apis=(
        "container.googleapis.com"
        "gkehub.googleapis.com"
        "gkebackup.googleapis.com"
        "iam.googleapis.com"
    )
    
    for project in "$WORKLOAD_PROJECT_1" "$WORKLOAD_PROJECT_2"; do
        print_status "$BLUE" "Enabling APIs for $project..."
        for api in "${workload_apis[@]}"; do
            print_status "$BLUE" "  Enabling $api..."
            if ! gcloud services enable "$api" --project="$project" --quiet; then
                print_status "$YELLOW" "⚠️  Warning: Failed to enable $api for $project"
            fi
        done
    done
    
    print_status "$GREEN" "✅ APIs enabled across all projects"
    
    # Wait for APIs to be fully enabled
    print_status "$BLUE" "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create GKE clusters
create_gke_clusters() {
    print_section "Creating GKE Clusters"
    
    # Create production cluster
    print_status "$BLUE" "Creating production GKE cluster..."
    local prod_cluster_name="prod-cluster-${RANDOM_SUFFIX}"
    
    if ! gcloud container clusters create "$prod_cluster_name" \
        --project="$WORKLOAD_PROJECT_1" \
        --region="$REGION" \
        --num-nodes=2 \
        --machine-type=e2-standard-4 \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=5 \
        --enable-autorepair \
        --enable-autoupgrade \
        --workload-pool="${WORKLOAD_PROJECT_1}.svc.id.goog" \
        --enable-shielded-nodes \
        --disk-size=50GB \
        --quiet; then
        print_status "$RED" "❌ Failed to create production cluster"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Production cluster created successfully"
    
    # Create staging cluster
    print_status "$BLUE" "Creating staging GKE cluster..."
    local staging_cluster_name="staging-cluster-${RANDOM_SUFFIX}"
    
    if ! gcloud container clusters create "$staging_cluster_name" \
        --project="$WORKLOAD_PROJECT_2" \
        --region="$REGION" \
        --num-nodes=1 \
        --machine-type=e2-standard-2 \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=3 \
        --enable-autorepair \
        --enable-autoupgrade \
        --workload-pool="${WORKLOAD_PROJECT_2}.svc.id.goog" \
        --enable-shielded-nodes \
        --disk-size=50GB \
        --quiet; then
        print_status "$RED" "❌ Failed to create staging cluster"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Staging cluster created successfully"
    
    # Save cluster names to config
    echo "PROD_CLUSTER_NAME=\"$prod_cluster_name\"" >> "$CONFIG_FILE"
    echo "STAGING_CLUSTER_NAME=\"$staging_cluster_name\"" >> "$CONFIG_FILE"
}

# Function to register clusters to fleet
register_clusters_to_fleet() {
    print_section "Registering Clusters to Fleet"
    
    # Load cluster names from config
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Set fleet host project context
    gcloud config set project "$FLEET_HOST_PROJECT_ID"
    
    # Register production cluster
    print_status "$BLUE" "Registering production cluster to fleet..."
    if ! gcloud container fleet memberships register "$PROD_CLUSTER_NAME" \
        --gke-cluster="${WORKLOAD_PROJECT_1}/${REGION}/${PROD_CLUSTER_NAME}" \
        --enable-workload-identity \
        --quiet; then
        print_status "$RED" "❌ Failed to register production cluster to fleet"
        exit 1
    fi
    
    # Register staging cluster
    print_status "$BLUE" "Registering staging cluster to fleet..."
    if ! gcloud container fleet memberships register "$STAGING_CLUSTER_NAME" \
        --gke-cluster="${WORKLOAD_PROJECT_2}/${REGION}/${STAGING_CLUSTER_NAME}" \
        --enable-workload-identity \
        --quiet; then
        print_status "$RED" "❌ Failed to register staging cluster to fleet"
        exit 1
    fi
    
    print_status "$GREEN" "✅ Clusters registered to fleet successfully"
    
    # Verify fleet memberships
    print_status "$BLUE" "Fleet memberships:"
    gcloud container fleet memberships list --format="table(name,gkeCluster.resourceLink,state.code)"
}

# Function to configure Config Connector
configure_config_connector() {
    print_section "Configuring Config Connector for GitOps"
    
    # Load cluster names from config
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Configure Config Connector for production cluster
    print_status "$BLUE" "Configuring Config Connector for production cluster..."
    
    gcloud config set project "$WORKLOAD_PROJECT_1"
    
    # Get cluster credentials
    if ! gcloud container clusters get-credentials "$PROD_CLUSTER_NAME" --region="$REGION"; then
        print_status "$RED" "❌ Failed to get production cluster credentials"
        exit 1
    fi
    
    # Enable Config Connector
    if ! gcloud container fleet config-management enable --quiet; then
        print_status "$YELLOW" "⚠️  Config Management may already be enabled"
    fi
    
    # Create Config Connector namespace
    kubectl create namespace cnrm-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create service account for Config Connector
    local cnrm_sa="cnrm-system@${WORKLOAD_PROJECT_1}.iam.gserviceaccount.com"
    if ! gcloud iam service-accounts describe "$cnrm_sa" &>/dev/null; then
        gcloud iam service-accounts create cnrm-system \
            --display-name="Config Connector Service Account" \
            --quiet
    fi
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding "$WORKLOAD_PROJECT_1" \
        --member="serviceAccount:$cnrm_sa" \
        --role="roles/editor" \
        --quiet
    
    # Create Config Connector configuration
    cat <<EOF | kubectl apply -f -
apiVersion: core.cnrm.cloud.google.com/v1beta1
kind: ConfigConnector
metadata:
  name: configconnector.core.cnrm.cloud.google.com
spec:
  mode: cluster
  googleServiceAccount: "$cnrm_sa"
EOF
    
    print_status "$GREEN" "✅ Config Connector configured for GitOps workflows"
}

# Function to set up backup plans
setup_backup_plans() {
    print_section "Setting Up Backup for GKE with Automated Policies"
    
    # Load cluster names from config
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Switch to fleet host project for centralized backup management
    gcloud config set project "$FLEET_HOST_PROJECT_ID"
    
    # Create backup plan for production cluster
    print_status "$BLUE" "Creating backup plan for production cluster..."
    if ! gcloud backup-dr backup-plans create "${BACKUP_PLAN_NAME}-prod" \
        --location="$REGION" \
        --cluster="projects/${WORKLOAD_PROJECT_1}/locations/${REGION}/clusters/${PROD_CLUSTER_NAME}" \
        --include-volume-data \
        --include-secrets \
        --backup-schedule="0 2 * * *" \
        --backup-retain-days=30 \
        --description="Daily backup for production workloads" \
        --quiet; then
        print_status "$YELLOW" "⚠️  Production backup plan may already exist or creation failed"
    fi
    
    # Create backup plan for staging cluster
    print_status "$BLUE" "Creating backup plan for staging cluster..."
    if ! gcloud backup-dr backup-plans create "${BACKUP_PLAN_NAME}-staging" \
        --location="$REGION" \
        --cluster="projects/${WORKLOAD_PROJECT_2}/locations/${REGION}/clusters/${STAGING_CLUSTER_NAME}" \
        --include-volume-data \
        --include-secrets \
        --backup-schedule="0 3 * * 0" \
        --backup-retain-days=14 \
        --description="Weekly backup for staging workloads" \
        --quiet; then
        print_status "$YELLOW" "⚠️  Staging backup plan may already exist or creation failed"
    fi
    
    # List backup plans to verify creation
    print_status "$BLUE" "Backup plans:"
    gcloud backup-dr backup-plans list --location="$REGION" --format="table(name,cluster,backupSchedule)"
    
    print_status "$GREEN" "✅ Backup plans configured with automated scheduling"
}

# Function to deploy sample applications
deploy_sample_applications() {
    print_section "Deploying Sample Applications with Persistent Storage"
    
    # Load cluster names from config
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Deploy to production cluster
    print_status "$BLUE" "Deploying sample application to production cluster..."
    
    gcloud config set project "$WORKLOAD_PROJECT_1"
    gcloud container clusters get-credentials "$PROD_CLUSTER_NAME" --region="$REGION"
    
    kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web-app
        image: nginx:1.21
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: web-app-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: web-app-pvc
  namespace: production
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
    
    # Deploy to staging cluster
    print_status "$BLUE" "Deploying sample application to staging cluster..."
    
    gcloud config set project "$WORKLOAD_PROJECT_2"
    gcloud container clusters get-credentials "$STAGING_CLUSTER_NAME" --region="$REGION"
    
    kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: staging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test-app
        image: nginx:1.21
        ports:
        - containerPort: 80
EOF
    
    print_status "$GREEN" "✅ Sample applications deployed across fleet clusters"
}

# Function to configure fleet-wide management
configure_fleet_management() {
    print_section "Creating Fleet-Wide Configuration Management"
    
    # Set fleet host project context
    gcloud config set project "$FLEET_HOST_PROJECT_ID"
    
    # Load cluster names from config
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Create temporary config management file
    local config_mgmt_file="/tmp/fleet-config-management.yaml"
    cat > "$config_mgmt_file" <<EOF
apiVersion: configmanagement.gke.io/v1
kind: ConfigManagement
metadata:
  name: config-management
spec:
  enableMultiRepo: true
  policyController:
    enabled: true
    referentialRulesEnabled: true
    logDeniesEnabled: true
    mutationEnabled: true
EOF
    
    # Apply configuration to fleet members
    for cluster_name in "$PROD_CLUSTER_NAME" "$STAGING_CLUSTER_NAME"; do
        print_status "$BLUE" "Applying configuration management to $cluster_name..."
        if ! gcloud container fleet config-management apply \
            --membership="$cluster_name" \
            --config="$config_mgmt_file" \
            --quiet; then
            print_status "$YELLOW" "⚠️  Warning: Failed to apply config management to $cluster_name"
        fi
    done
    
    # Clean up temporary file
    rm -f "$config_mgmt_file"
    
    print_status "$GREEN" "✅ Fleet-wide configuration management enabled"
    
    # Verify configuration status
    print_status "$BLUE" "Configuration management status:"
    gcloud container fleet config-management status --format="table(membershipName,configmanagement.configManagementState.configSync.state)"
}

# Function to set up cross-project IAM
setup_cross_project_iam() {
    print_section "Setting Up Cross-Project IAM for Fleet Operations"
    
    # Create service account for fleet operations
    gcloud config set project "$FLEET_HOST_PROJECT_ID"
    
    local fleet_sa="fleet-manager@${FLEET_HOST_PROJECT_ID}.iam.gserviceaccount.com"
    if ! gcloud iam service-accounts describe "$fleet_sa" &>/dev/null; then
        gcloud iam service-accounts create fleet-manager \
            --display-name="Fleet Manager Service Account" \
            --description="Service account for managing fleet operations" \
            --quiet
    fi
    
    # Grant necessary permissions for cross-project access
    for project in "$WORKLOAD_PROJECT_1" "$WORKLOAD_PROJECT_2"; do
        print_status "$BLUE" "Granting permissions for $project..."
        
        gcloud projects add-iam-policy-binding "$project" \
            --member="serviceAccount:$fleet_sa" \
            --role="roles/container.clusterViewer" \
            --quiet
        
        gcloud projects add-iam-policy-binding "$project" \
            --member="serviceAccount:$fleet_sa" \
            --role="roles/gkebackup.admin" \
            --quiet
    done
    
    print_status "$GREEN" "✅ Cross-project IAM configured for fleet operations"
}

# Function to run validation tests
run_validation() {
    print_section "Running Validation Tests"
    
    # Load configuration
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Verify fleet registration
    print_status "$BLUE" "Verifying fleet registration..."
    gcloud config set project "$FLEET_HOST_PROJECT_ID"
    
    local membership_count
    membership_count=$(gcloud container fleet memberships list --format="value(name)" | wc -l)
    
    if [[ $membership_count -ge 2 ]]; then
        print_status "$GREEN" "✅ Fleet registration verified ($membership_count clusters registered)"
    else
        print_status "$YELLOW" "⚠️  Warning: Expected 2 clusters, found $membership_count"
    fi
    
    # Verify backup plans
    print_status "$BLUE" "Verifying backup plans..."
    local backup_count
    backup_count=$(gcloud backup-dr backup-plans list --location="$REGION" --format="value(name)" | wc -l)
    
    if [[ $backup_count -ge 2 ]]; then
        print_status "$GREEN" "✅ Backup plans verified ($backup_count plans created)"
    else
        print_status "$YELLOW" "⚠️  Warning: Expected 2 backup plans, found $backup_count"
    fi
    
    # Verify sample applications
    print_status "$BLUE" "Verifying sample applications..."
    
    # Check production cluster
    gcloud config set project "$WORKLOAD_PROJECT_1"
    gcloud container clusters get-credentials "$PROD_CLUSTER_NAME" --region="$REGION" --quiet
    
    if kubectl get deployment web-app -n production &>/dev/null; then
        print_status "$GREEN" "✅ Production application deployed"
    else
        print_status "$YELLOW" "⚠️  Warning: Production application not found"
    fi
    
    # Check staging cluster
    gcloud config set project "$WORKLOAD_PROJECT_2"
    gcloud container clusters get-credentials "$STAGING_CLUSTER_NAME" --region="$REGION" --quiet
    
    if kubectl get deployment test-app -n staging &>/dev/null; then
        print_status "$GREEN" "✅ Staging application deployed"
    else
        print_status "$YELLOW" "⚠️  Warning: Staging application not found"
    fi
}

# Function to display deployment summary
display_summary() {
    print_section "Deployment Summary"
    
    # Load configuration
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    cat <<EOF

🎉 Enterprise Kubernetes Fleet Management Deployment Complete!

📋 Deployment Details:
   Fleet Host Project:     $FLEET_HOST_PROJECT_ID
   Production Project:     $WORKLOAD_PROJECT_1
   Staging Project:        $WORKLOAD_PROJECT_2
   Region:                 $REGION
   Zone:                   $ZONE

🚢 Fleet Configuration:
   Fleet Name:             $FLEET_NAME
   Production Cluster:     $PROD_CLUSTER_NAME
   Staging Cluster:        $STAGING_CLUSTER_NAME

💾 Backup Configuration:
   Backup Plan Name:       $BACKUP_PLAN_NAME
   Production Schedule:    Daily at 2:00 AM (30 days retention)
   Staging Schedule:       Weekly on Sunday at 3:00 AM (14 days retention)

🔧 Management Features:
   ✅ GKE Fleet Management
   ✅ Backup for GKE
   ✅ Config Connector (GitOps)
   ✅ Cross-project IAM
   ✅ Fleet-wide Configuration Management
   ✅ Sample Applications

📝 Next Steps:
   1. Access fleet management: gcloud config set project $FLEET_HOST_PROJECT_ID
   2. View fleet status: gcloud container fleet memberships list
   3. Monitor backups: gcloud backup-dr backup-plans list --location=$REGION
   4. Configure GitOps workflows using Config Connector
   5. Implement advanced security policies with Policy Controller

💰 Cost Management:
   Remember to run the cleanup script when done testing to avoid ongoing charges.

📄 Configuration saved to: $CONFIG_FILE
📋 Deployment log: $LOG_FILE

EOF
}

# Main execution function
main() {
    print_status "$GREEN" "🚀 Starting Enterprise Kubernetes Fleet Management Deployment"
    
    log "INFO" "Deployment started by user: $(whoami)"
    log "INFO" "Script location: $SCRIPT_DIR"
    
    # Execute deployment steps
    check_prerequisites
    get_user_input
    create_projects
    enable_apis
    create_gke_clusters
    register_clusters_to_fleet
    configure_config_connector
    setup_backup_plans
    deploy_sample_applications
    configure_fleet_management
    setup_cross_project_iam
    run_validation
    display_summary
    
    print_status "$GREEN" "✅ Deployment completed successfully!"
    log "INFO" "Deployment completed successfully"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_status "$RED" "❌ Deployment failed with exit code $exit_code"
        print_status "$YELLOW" "Check the log file for details: $LOG_FILE"
        print_status "$YELLOW" "Run the cleanup script to remove any partially created resources"
    fi
}

trap cleanup_on_exit EXIT

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi