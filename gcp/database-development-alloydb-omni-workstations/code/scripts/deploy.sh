#!/bin/bash

# Database Development Workflows with AlloyDB Omni and Cloud Workstations - Deployment Script
# This script deploys the complete infrastructure for database development workflows
# using AlloyDB Omni and Cloud Workstations on Google Cloud Platform

set -euo pipefail

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

# Error handling
handle_error() {
    log_error "Deployment failed at line $1. Check the logs above for details."
    log_info "You can run the destroy.sh script to clean up any partially created resources."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_PROJECT_ID="db-dev-workflows-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Database Development Workflows with AlloyDB Omni and Cloud Workstations

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (default: ${DEFAULT_PROJECT_ID})
    -r, --region REGION             GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE                 GCP zone (default: ${DEFAULT_ZONE})
    -s, --skip-apis                 Skip API enablement (useful for existing projects)
    -d, --dry-run                   Show what would be deployed without making changes
    -h, --help                      Show this help message

EXAMPLES:
    $0                              # Deploy with default settings
    $0 -p my-project -r us-west1    # Deploy to specific project and region
    $0 --dry-run                    # Preview deployment without making changes

EOF
}

# Parse command line arguments
PROJECT_ID="${DEFAULT_PROJECT_ID}"
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
SKIP_APIS=false
DRY_RUN=false

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
        -s|--skip-apis)
            SKIP_APIS=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
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

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
CLUSTER_NAME="workstation-cluster-${RANDOM_SUFFIX}"
CONFIG_NAME="db-dev-config-${RANDOM_SUFFIX}"
REPO_NAME="database-development-${RANDOM_SUFFIX}"
WORKSTATION_NAME="db-dev-workstation-${RANDOM_SUFFIX}"
NETWORK_NAME="db-dev-network"
SUBNET_NAME="db-dev-subnet"

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No resources will be created"
    log_info "Would deploy the following resources:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Network: ${NETWORK_NAME}"
    log_info "  Subnet: ${SUBNET_NAME}"
    log_info "  Workstation Cluster: ${CLUSTER_NAME}"
    log_info "  Workstation Config: ${CONFIG_NAME}"
    log_info "  Source Repository: ${REPO_NAME}"
    log_info "  Workstation: ${WORKSTATION_NAME}"
    exit 0
fi

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if docker is available for AlloyDB Omni configuration
    if ! command -v docker &> /dev/null; then
        log_warning "Docker not found. AlloyDB Omni container setup will be created but requires Docker to run."
    fi
    
    # Check if git is available for repository operations
    if ! command -v git &> /dev/null; then
        log_warning "Git not found. Source repository setup may be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Project setup
setup_project() {
    log_info "Setting up Google Cloud project configuration..."
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration set: ${PROJECT_ID} in ${REGION}"
}

# Enable required APIs
enable_apis() {
    if [[ "$SKIP_APIS" == "true" ]]; then
        log_info "Skipping API enablement as requested"
        return
    fi
    
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workstations.googleapis.com"
        "compute.googleapis.com"
        "sourcerepo.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    log_success "All required APIs enabled"
}

# Create VPC network
create_network() {
    log_info "Creating VPC network for secure development environment..."
    
    # Create VPC network
    gcloud compute networks create "${NETWORK_NAME}" \
        --subnet-mode=regional \
        --description="Network for database development workstations"
    
    # Create subnet
    gcloud compute networks subnets create "${SUBNET_NAME}" \
        --network="${NETWORK_NAME}" \
        --range=10.0.0.0/24 \
        --region="${REGION}"
    
    # Create firewall rule for internal communication
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-internal" \
        --network="${NETWORK_NAME}" \
        --allow=tcp,udp,icmp \
        --source-ranges=10.0.0.0/24 \
        --description="Allow internal communication within development network"
    
    log_success "VPC network and subnet created successfully"
}

# Create Cloud Workstations cluster
create_workstations_cluster() {
    log_info "Creating Cloud Workstations cluster..."
    
    gcloud workstations clusters create "${CLUSTER_NAME}" \
        --region="${REGION}" \
        --network="projects/${PROJECT_ID}/global/networks/${NETWORK_NAME}" \
        --subnetwork="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/${SUBNET_NAME}" \
        --labels=environment=development,team=database
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local state=$(gcloud workstations clusters describe "${CLUSTER_NAME}" \
            --region="${REGION}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "ACTIVE" ]]; then
            break
        fi
        
        log_info "Cluster state: ${state}. Waiting... (attempt $((attempt + 1))/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Cluster creation timed out. Please check the Google Cloud Console for status."
        exit 1
    fi
    
    log_success "Cloud Workstations cluster created: ${CLUSTER_NAME}"
}

# Create workstation configuration
create_workstation_config() {
    log_info "Creating workstation configuration for database development..."
    
    # Create temporary configuration file
    local config_file="${SCRIPT_DIR}/workstation-config.yaml"
    cat > "${config_file}" << EOF
displayName: "Database Development Environment"
machineType: "e2-standard-4"
bootDiskSizeGb: 100
container:
  image: "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
  env:
    DEBIAN_FRONTEND: noninteractive
runAsUser: 1000
persistentDirectories:
  - mountPath: "/home/user"
    gcePersistentDisk:
      sizeGb: 200
      diskType: "pd-standard"
labels:
  environment: "development"
  purpose: "database-development"
EOF
    
    # Create the configuration
    gcloud workstations configs create "${CONFIG_NAME}" \
        --region="${REGION}" \
        --cluster="${CLUSTER_NAME}" \
        --from-file="${config_file}"
    
    # Clean up temporary file
    rm -f "${config_file}"
    
    log_success "Workstation configuration created: ${CONFIG_NAME}"
}

# Create source repository
create_source_repository() {
    log_info "Setting up Cloud Source Repository for database projects..."
    
    # Create Cloud Source Repository
    gcloud source repos create "${REPO_NAME}" \
        --description="Repository for database development projects"
    
    # Get repository clone URL
    local repo_url
    repo_url=$(gcloud source repos describe "${REPO_NAME}" --format="value(url)")
    
    # Create initial repository structure
    local temp_repo_dir="${SCRIPT_DIR}/temp-repo"
    mkdir -p "${temp_repo_dir}"
    cd "${temp_repo_dir}"
    
    git init
    git config user.email "developer@${PROJECT_ID}.iam.gserviceaccount.com"
    git config user.name "Database Development Team"
    
    # Create directory structure
    mkdir -p schemas migrations functions tests docker
    
    # Create README
    cat > README.md << EOF
# Database Development Project

This repository contains database schemas, migrations, functions, and tests
for our database development workflow using AlloyDB Omni.

## Structure
- \`schemas/\` - Database schema definitions
- \`migrations/\` - Database migration scripts
- \`functions/\` - Stored procedures and functions
- \`tests/\` - Database tests and validation scripts
- \`docker/\` - AlloyDB Omni container configurations

## Getting Started
1. Access your Cloud Workstation through the Google Cloud Console
2. Clone this repository in your workstation
3. Start AlloyDB Omni using the Docker configuration in the docker/ directory

## Connection Information
- Host: localhost (when running in workstation)
- Port: 5432
- Database: development_db
- Username: dev_user
- Password: dev_password_123
EOF
    
    git add .
    git commit -m "Initial repository setup for database development"
    git remote add origin "${repo_url}"
    git push origin main
    
    cd "${SCRIPT_DIR}"
    rm -rf "${temp_repo_dir}"
    
    log_success "Source repository created: ${REPO_NAME}"
    log_info "Repository URL: ${repo_url}"
}

# Create AlloyDB Omni configuration
create_alloydb_config() {
    log_info "Creating AlloyDB Omni container configuration..."
    
    local alloydb_dir="${PROJECT_DIR}/alloydb-config"
    mkdir -p "${alloydb_dir}/init-scripts"
    
    # Create docker-compose file
    cat > "${alloydb_dir}/docker-compose.yml" << EOF
version: '3.8'
services:
  alloydb-omni:
    image: google/alloydbomni:latest
    container_name: alloydb-dev
    environment:
      - POSTGRES_DB=development_db
      - POSTGRES_USER=dev_user
      - POSTGRES_PASSWORD=dev_password_123
      - ALLOYDB_COLUMNAR_ENGINE=on
    ports:
      - "5432:5432"
    volumes:
      - alloydb_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d
    networks:
      - db-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev_user -d development_db"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  alloydb_data:

networks:
  db-network:
    driver: bridge
EOF
    
    # Create initialization script
    cat > "${alloydb_dir}/init-scripts/01-create-extensions.sql" << EOF
-- Enable required extensions for AlloyDB development
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS google_columnar_engine;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create development schema
CREATE SCHEMA IF NOT EXISTS app_development;
GRANT ALL PRIVILEGES ON SCHEMA app_development TO dev_user;
EOF
    
    # Create setup script
    cat > "${alloydb_dir}/setup-dev-db.sh" << 'EOF'
#!/bin/bash
echo "Setting up AlloyDB Omni development environment..."

# Start AlloyDB Omni container
docker-compose up -d

# Wait for database to be ready
echo "Waiting for database to be ready..."
until docker exec alloydb-dev pg_isready -U dev_user -d development_db; do
  echo "Database is starting up..."
  sleep 2
done

echo "✅ AlloyDB Omni development environment is ready"
echo "Connection string: postgresql://dev_user:dev_password_123@localhost:5432/development_db"
EOF
    
    chmod +x "${alloydb_dir}/setup-dev-db.sh"
    
    log_success "AlloyDB Omni container configuration created in ${alloydb_dir}"
}

# Create development workstation
create_workstation() {
    log_info "Creating development workstation..."
    
    gcloud workstations create "${WORKSTATION_NAME}" \
        --region="${REGION}" \
        --cluster="${CLUSTER_NAME}" \
        --config="${CONFIG_NAME}" \
        --labels=developer=primary,project=database-development
    
    # Wait for workstation to be ready
    log_info "Waiting for workstation to be ready..."
    local max_attempts=20
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local state=$(gcloud workstations describe "${WORKSTATION_NAME}" \
            --region="${REGION}" \
            --cluster="${CLUSTER_NAME}" \
            --config="${CONFIG_NAME}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "ACTIVE" ]]; then
            break
        fi
        
        log_info "Workstation state: ${state}. Waiting... (attempt $((attempt + 1))/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Workstation creation timed out. Please check the Google Cloud Console for status."
        exit 1
    fi
    
    log_success "Development workstation created: ${WORKSTATION_NAME}"
}

# Create Cloud Build configuration
create_build_config() {
    log_info "Creating Cloud Build configuration for automated database testing..."
    
    # Create Cloud Build configuration file
    cat > "${PROJECT_DIR}/cloudbuild.yaml" << EOF
steps:
  # Start AlloyDB Omni for testing
  - name: 'docker/compose:1.29.2'
    args: ['-f', 'alloydb-config/docker-compose.yml', 'up', '-d']
    env:
      - 'COMPOSE_PROJECT_NAME=test-db'

  # Wait for database to be ready
  - name: 'postgres:15'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        apt-get update && apt-get install -y postgresql-client
        until pg_isready -h alloydb-dev -p 5432 -U dev_user; do
          echo "Waiting for database..."
          sleep 5
        done
        echo "Database is ready"

  # Run database migrations
  - name: 'postgres:15'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        apt-get update && apt-get install -y postgresql-client
        for file in migrations/*.sql; do
          if [ -f "\$file" ]; then
            echo "Running migration: \$file"
            PGPASSWORD=dev_password_123 psql -h alloydb-dev -U dev_user -d development_db -f "\$file"
          fi
        done

  # Run database tests
  - name: 'postgres:15'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        apt-get update && apt-get install -y postgresql-client
        for file in tests/*.sql; do
          if [ -f "\$file" ]; then
            echo "Running test: \$file"
            PGPASSWORD=dev_password_123 psql -h alloydb-dev -U dev_user -d development_db -f "\$file"
          fi
        done

  # Cleanup
  - name: 'docker/compose:1.29.2'
    args: ['-f', 'alloydb-config/docker-compose.yml', 'down', '-v']
    env:
      - 'COMPOSE_PROJECT_NAME=test-db'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'
timeout: 1800s
EOF
    
    # Create build trigger
    gcloud builds triggers create cloud-source-repositories \
        --repo="${REPO_NAME}" \
        --branch-pattern="^main$" \
        --build-config=cloudbuild.yaml \
        --description="Automated database testing on main branch"
    
    log_success "Cloud Build trigger created for automated database testing"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${PROJECT_DIR}/deployment-info.txt"
    cat > "${info_file}" << EOF
Database Development Workflows Deployment Information
====================================================

Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}

Resources Created:
------------------
Network: ${NETWORK_NAME}
Subnet: ${SUBNET_NAME}
Firewall Rule: ${NETWORK_NAME}-allow-internal
Workstation Cluster: ${CLUSTER_NAME}
Workstation Config: ${CONFIG_NAME}
Workstation: ${WORKSTATION_NAME}
Source Repository: ${REPO_NAME}

Access Information:
-------------------
Start Workstation:
  gcloud workstations start ${WORKSTATION_NAME} \\
    --region=${REGION} \\
    --cluster=${CLUSTER_NAME} \\
    --config=${CONFIG_NAME}

Clone Repository (from workstation):
  gcloud source repos clone ${REPO_NAME}

AlloyDB Omni Setup:
  cd alloydb-config && ./setup-dev-db.sh

Connection String:
  postgresql://dev_user:dev_password_123@localhost:5432/development_db

Cost Estimation:
----------------
Estimated monthly cost: \$50-75 (varies by usage)
- Cloud Workstations: ~\$30-50/month
- Compute Engine (cluster): ~\$15-20/month
- Storage and networking: ~\$5-10/month

Next Steps:
-----------
1. Access your workstation through the Google Cloud Console
2. Clone the source repository
3. Set up AlloyDB Omni using the provided Docker configuration
4. Start developing your database applications

For cleanup, run: ./scripts/destroy.sh
EOF
    
    log_success "Deployment information saved to ${info_file}"
}

# Main deployment function
main() {
    log_info "Starting Database Development Workflows deployment..."
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "This deployment will take approximately 10-15 minutes."
    
    check_prerequisites
    setup_project
    enable_apis
    create_network
    create_workstations_cluster
    create_workstation_config
    create_source_repository
    create_alloydb_config
    create_workstation
    create_build_config
    save_deployment_info
    
    log_success "Deployment completed successfully!"
    log_success "Your database development environment is ready to use."
    
    echo
    log_info "Quick Start:"
    log_info "1. Start your workstation:"
    echo "   gcloud workstations start ${WORKSTATION_NAME} \\"
    echo "     --region=${REGION} \\"
    echo "     --cluster=${CLUSTER_NAME} \\"
    echo "     --config=${CONFIG_NAME}"
    echo
    log_info "2. Access workstation through Google Cloud Console or:"
    echo "   gcloud workstations ssh ${WORKSTATION_NAME} \\"
    echo "     --region=${REGION} \\"
    echo "     --cluster=${CLUSTER_NAME} \\"
    echo "     --config=${CONFIG_NAME}"
    echo
    log_info "3. In your workstation, clone the repository:"
    echo "   gcloud source repos clone ${REPO_NAME}"
    echo
    log_info "4. Set up AlloyDB Omni:"
    echo "   cd ${REPO_NAME}/alloydb-config && ./setup-dev-db.sh"
    echo
    log_info "View deployment details in: ${PROJECT_DIR}/deployment-info.txt"
    log_warning "Remember to run ./scripts/destroy.sh when done to avoid ongoing charges."
}

# Run main function
main "$@"