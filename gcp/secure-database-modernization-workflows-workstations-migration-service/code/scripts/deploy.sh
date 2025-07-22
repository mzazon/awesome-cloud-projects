#!/bin/bash

# Deploy script for Secure Database Modernization Workflows with Cloud Workstations and Database Migration Service
# This script sets up the complete infrastructure for secure database migration workflows

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Docker is installed (needed for container image builds)
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it from https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if openssl is available (for random generation)
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-db-modernization-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export WORKSTATION_CLUSTER_NAME="${WORKSTATION_CLUSTER_NAME:-db-migration-cluster}"
    export WORKSTATION_CONFIG_NAME="${WORKSTATION_CONFIG_NAME:-db-migration-config}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DB_MIGRATION_JOB_NAME="${DB_MIGRATION_JOB_NAME:-migration-job-${RANDOM_SUFFIX}}"
    export SECRET_NAME="${SECRET_NAME:-db-credentials-${RANDOM_SUFFIX}}"
    
    # Get project number for service account references
    export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
    
    log "Environment variables set:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  WORKSTATION_CLUSTER_NAME: ${WORKSTATION_CLUSTER_NAME}"
    log "  WORKSTATION_CONFIG_NAME: ${WORKSTATION_CONFIG_NAME}"
    log "  DB_MIGRATION_JOB_NAME: ${DB_MIGRATION_JOB_NAME}"
    log "  SECRET_NAME: ${SECRET_NAME}"
}

# Function to configure gcloud
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workstations.googleapis.com"
        "datamigration.googleapis.com"
        "cloudbuild.googleapis.com"
        "secretmanager.googleapis.com"
        "artifactregistry.googleapis.com"
        "sqladmin.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "compute.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: ${api}"
        gcloud services enable ${api} || {
            error "Failed to enable API: ${api}"
            exit 1
        }
    done
    
    log "All required APIs enabled successfully"
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log "Creating Artifact Registry repository..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe db-migration-images --location=${REGION} &> /dev/null; then
        warn "Artifact Registry repository 'db-migration-images' already exists, skipping creation"
    else
        gcloud artifacts repositories create db-migration-images \
            --repository-format=docker \
            --location=${REGION} \
            --description="Container images for database migration workstations" || {
            error "Failed to create Artifact Registry repository"
            exit 1
        }
        log "Artifact Registry repository created successfully"
    fi
    
    # Configure Docker authentication
    gcloud auth configure-docker ${REGION}-docker.pkg.dev || {
        error "Failed to configure Docker authentication"
        exit 1
    }
    
    log "Docker authentication configured successfully"
}

# Function to create and store database credentials
create_database_credentials() {
    log "Creating database credentials in Secret Manager..."
    
    # Check if secret already exists
    if gcloud secrets describe ${SECRET_NAME} &> /dev/null; then
        warn "Secret '${SECRET_NAME}' already exists, skipping creation"
    else
        # Create secret with sample credentials (replace with actual values)
        echo "host=source-db.example.com,user=migration_user,password=secure_password123,dbname=legacy_db" | \
            gcloud secrets create ${SECRET_NAME} \
            --data-file=- \
            --replication-policy="automatic" || {
            error "Failed to create secret"
            exit 1
        }
        log "Database credentials secret created successfully"
    fi
    
    # Wait for workstation service account to be available
    log "Waiting for workstation service account to be available..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if gcloud iam service-accounts describe "service-${PROJECT_NUMBER}@gcp-sa-workstations.iam.gserviceaccount.com" &> /dev/null; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 10
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warn "Workstation service account not found, will create IAM policy binding anyway"
    fi
    
    # Create IAM policy to allow workstation service account access
    gcloud secrets add-iam-policy-binding ${SECRET_NAME} \
        --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-workstations.iam.gserviceaccount.com" \
        --role="roles/secretmanager.secretAccessor" || {
        warn "Failed to add IAM policy binding for secret access, continuing..."
    }
    
    log "Secret Manager configuration completed"
}

# Function to create Cloud Workstations cluster
create_workstations_cluster() {
    log "Creating Cloud Workstations cluster..."
    
    # Check if cluster already exists
    if gcloud workstations clusters describe ${WORKSTATION_CLUSTER_NAME} --location=${REGION} &> /dev/null; then
        warn "Workstations cluster '${WORKSTATION_CLUSTER_NAME}' already exists, skipping creation"
    else
        gcloud workstations clusters create ${WORKSTATION_CLUSTER_NAME} \
            --location=${REGION} \
            --network="projects/${PROJECT_ID}/global/networks/default" \
            --subnetwork="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default" \
            --enable-private-endpoint \
            --async || {
            error "Failed to create workstations cluster"
            exit 1
        }
        
        log "Workstations cluster creation initiated, waiting for completion..."
        
        # Wait for cluster to be ready
        local max_attempts=60
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            local state=$(gcloud workstations clusters describe ${WORKSTATION_CLUSTER_NAME} \
                --location=${REGION} \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            if [ "$state" = "RUNNING" ]; then
                log "Workstations cluster is running"
                break
            elif [ "$state" = "FAILED" ]; then
                error "Workstations cluster creation failed"
                exit 1
            fi
            
            attempt=$((attempt + 1))
            sleep 30
        done
        
        if [ $attempt -eq $max_attempts ]; then
            error "Timeout waiting for workstations cluster to be ready"
            exit 1
        fi
    fi
    
    log "Cloud Workstations cluster ready"
}

# Function to build and push custom container image
build_container_image() {
    log "Building custom container image for migration workstations..."
    
    # Create temporary directory for build context
    local build_dir=$(mktemp -d)
    
    # Create Dockerfile
    cat > "${build_dir}/Dockerfile" << 'EOF'
FROM us-docker.pkg.dev/google-appengine/workstations-images/code-oss:latest

# Install database migration tools
RUN apt-get update && apt-get install -y \
    mysql-client \
    postgresql-client \
    python3-pip \
    curl \
    wget \
    git \
    && pip3 install sqlalchemy pandas pymysql psycopg2-binary

# Install Google Cloud SDK components
RUN gcloud components install alpha beta --quiet

# Create migration workspace
RUN mkdir -p /home/user/migration-workspace
WORKDIR /home/user/migration-workspace

# Set up sample migration scripts directory
RUN mkdir -p scripts
EOF
    
    # Create sample migration script
    cat > "${build_dir}/migration-script.sql" << 'EOF'
-- Sample migration validation script
SELECT 'Migration environment ready' as status;
EOF
    
    # Create cloudbuild.yaml for the build process
    cat > "${build_dir}/cloudbuild.yaml" << EOF
steps:
# Build custom workstation image with migration tools
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/db-migration-images/migration-workstation:latest', '.']

# Push image to Artifact Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', '${REGION}-docker.pkg.dev/${PROJECT_ID}/db-migration-images/migration-workstation:latest']

options:
  logging: CLOUD_LOGGING_ONLY
EOF
    
    # Submit build
    cd "${build_dir}"
    gcloud builds submit . --config=cloudbuild.yaml || {
        error "Failed to build custom container image"
        rm -rf "${build_dir}"
        exit 1
    }
    
    # Cleanup
    rm -rf "${build_dir}"
    
    log "Custom container image built and pushed successfully"
}

# Function to create workstation configuration
create_workstation_config() {
    log "Creating workstation configuration..."
    
    # Check if configuration already exists
    if gcloud workstations configs describe ${WORKSTATION_CONFIG_NAME} \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER_NAME} &> /dev/null; then
        warn "Workstation configuration '${WORKSTATION_CONFIG_NAME}' already exists, updating..."
        
        # Update configuration with custom image
        gcloud workstations configs update ${WORKSTATION_CONFIG_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER_NAME} \
            --container-image="${REGION}-docker.pkg.dev/${PROJECT_ID}/db-migration-images/migration-workstation:latest" || {
            error "Failed to update workstation configuration"
            exit 1
        }
    else
        gcloud workstations configs create ${WORKSTATION_CONFIG_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER_NAME} \
            --container-image="${REGION}-docker.pkg.dev/${PROJECT_ID}/db-migration-images/migration-workstation:latest" \
            --machine-type="e2-standard-4" \
            --boot-disk-size=50GB \
            --persistent-disk-size=50GB \
            --disable-public-ip-addresses || {
            error "Failed to create workstation configuration"
            exit 1
        }
    fi
    
    log "Workstation configuration created/updated successfully"
}

# Function to create database migration profiles
create_migration_profiles() {
    log "Creating database migration connection profiles..."
    
    # Create Cloud SQL instance for target database
    if gcloud sql instances describe target-mysql-instance &> /dev/null; then
        warn "Cloud SQL instance 'target-mysql-instance' already exists, skipping creation"
    else
        log "Creating Cloud SQL instance for target database..."
        gcloud sql instances create target-mysql-instance \
            --database-version=MYSQL_8_0 \
            --tier=db-custom-2-7680 \
            --region=${REGION} \
            --storage-type=SSD \
            --storage-size=100GB \
            --backup-start-time=03:00 \
            --enable-bin-log \
            --retained-backups-count=7 \
            --async || {
            error "Failed to create Cloud SQL instance"
            exit 1
        }
        
        log "Waiting for Cloud SQL instance to be ready..."
        
        # Wait for Cloud SQL instance to be ready
        local max_attempts=60
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            local state=$(gcloud sql instances describe target-mysql-instance \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            if [ "$state" = "RUNNABLE" ]; then
                log "Cloud SQL instance is running"
                break
            elif [ "$state" = "FAILED" ]; then
                error "Cloud SQL instance creation failed"
                exit 1
            fi
            
            attempt=$((attempt + 1))
            sleep 30
        done
        
        if [ $attempt -eq $max_attempts ]; then
            error "Timeout waiting for Cloud SQL instance to be ready"
            exit 1
        fi
    fi
    
    # Create connection profile for source database
    if gcloud database-migration connection-profiles describe source-db-profile --location=${REGION} &> /dev/null; then
        warn "Source database connection profile already exists, skipping creation"
    else
        gcloud database-migration connection-profiles create mysql source-db-profile \
            --location=${REGION} \
            --host="source-db.example.com" \
            --port=3306 \
            --username="migration_user" \
            --password-secret="projects/${PROJECT_ID}/secrets/${SECRET_NAME}/versions/latest" || {
            warn "Failed to create source database connection profile (expected if source database is not accessible)"
        }
    fi
    
    # Create connection profile for target Cloud SQL instance
    if gcloud database-migration connection-profiles describe target-db-profile --location=${REGION} &> /dev/null; then
        warn "Target database connection profile already exists, skipping creation"
    else
        gcloud database-migration connection-profiles create cloudsql target-db-profile \
            --location=${REGION} \
            --cloudsql-instance="projects/${PROJECT_ID}/instances/target-mysql-instance" || {
            error "Failed to create target database connection profile"
            exit 1
        }
    fi
    
    log "Database migration connection profiles created successfully"
}

# Function to create custom IAM roles
create_custom_iam_roles() {
    log "Creating custom IAM roles for database migration team..."
    
    # Create temporary file for role definition
    local role_file=$(mktemp)
    
    cat > "${role_file}" << EOF
title: "Database Migration Developer"
description: "Custom role for database migration team members"
stage: "GA"
includedPermissions:
- workstations.workstations.use
- workstations.workstations.create
- datamigration.migrationjobs.create
- datamigration.migrationjobs.get
- datamigration.migrationjobs.list
- secretmanager.versions.access
- cloudsql.instances.connect
- logging.logEntries.create
- cloudbuild.builds.create
- cloudbuild.builds.get
- cloudbuild.builds.list
EOF
    
    # Create or update custom IAM role
    if gcloud iam roles describe databaseMigrationDeveloper --project=${PROJECT_ID} &> /dev/null; then
        warn "Custom IAM role already exists, updating..."
        gcloud iam roles update databaseMigrationDeveloper \
            --project=${PROJECT_ID} \
            --file="${role_file}" || {
            error "Failed to update custom IAM role"
            rm -f "${role_file}"
            exit 1
        }
    else
        gcloud iam roles create databaseMigrationDeveloper \
            --project=${PROJECT_ID} \
            --file="${role_file}" || {
            error "Failed to create custom IAM role"
            rm -f "${role_file}"
            exit 1
        }
    fi
    
    rm -f "${role_file}"
    
    log "Custom IAM roles created successfully"
}

# Function to create sample workstation instance
create_sample_workstation() {
    log "Creating sample workstation instance..."
    
    # Check if workstation instance already exists
    if gcloud workstations describe migration-dev-workspace \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER_NAME} \
        --config=${WORKSTATION_CONFIG_NAME} &> /dev/null; then
        warn "Workstation instance 'migration-dev-workspace' already exists, skipping creation"
    else
        gcloud workstations create migration-dev-workspace \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER_NAME} \
            --config=${WORKSTATION_CONFIG_NAME} || {
            error "Failed to create workstation instance"
            exit 1
        }
        
        log "Starting workstation instance..."
        gcloud workstations start migration-dev-workspace \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER_NAME} \
            --config=${WORKSTATION_CONFIG_NAME} || {
            error "Failed to start workstation instance"
            exit 1
        }
    fi
    
    log "Sample workstation instance created and started successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo
    echo -e "${BLUE}=== Deployment Summary ===${NC}"
    echo -e "${BLUE}Project ID:${NC} ${PROJECT_ID}"
    echo -e "${BLUE}Region:${NC} ${REGION}"
    echo -e "${BLUE}Workstation Cluster:${NC} ${WORKSTATION_CLUSTER_NAME}"
    echo -e "${BLUE}Workstation Config:${NC} ${WORKSTATION_CONFIG_NAME}"
    echo -e "${BLUE}Secret Name:${NC} ${SECRET_NAME}"
    echo
    echo -e "${BLUE}=== Next Steps ===${NC}"
    echo "1. Access your workstation through the Google Cloud Console:"
    echo "   https://console.cloud.google.com/workstations/workstations?project=${PROJECT_ID}"
    echo
    echo "2. Update the database credentials in Secret Manager:"
    echo "   gcloud secrets versions add ${SECRET_NAME} --data-file=credentials.txt"
    echo
    echo "3. Configure source database connection profile with actual database details"
    echo
    echo "4. Create migration team members and assign them the custom IAM role:"
    echo "   gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
    echo "     --member=\"user:developer@company.com\" \\"
    echo "     --role=\"projects/${PROJECT_ID}/roles/databaseMigrationDeveloper\""
    echo
    echo -e "${GREEN}Deployment completed successfully!${NC}"
}

# Main deployment function
main() {
    log "Starting deployment of Secure Database Modernization Workflows..."
    
    check_prerequisites
    set_environment_variables
    configure_gcloud
    enable_apis
    create_artifact_registry
    create_database_credentials
    create_workstations_cluster
    build_container_image
    create_workstation_config
    create_migration_profiles
    create_custom_iam_roles
    create_sample_workstation
    display_summary
    
    log "Deployment completed successfully!"
}

# Run main function
main "$@"