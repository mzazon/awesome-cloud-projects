#!/bin/bash

# Legacy Database Applications with Database Migration Service and Application Design Center - Deployment Script
# This script deploys the complete infrastructure for modernizing legacy SQL Server applications to PostgreSQL
# Recipe: legacy-database-applications-database-migration-service-application-design-center

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables for cleanup tracking
CREATED_RESOURCES=()

# Logging functions
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    "${SCRIPT_DIR}/destroy.sh" --partial-cleanup 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Track created resources for cleanup
track_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_location="${3:-}"
    CREATED_RESOURCES+=("${resource_type}:${resource_name}:${resource_location}")
    echo "${CREATED_RESOURCES[@]}" > "${SCRIPT_DIR}/.created_resources"
}

# Prerequisites validation
check_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        log_error "No project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Check for required tools
    local required_tools=("openssl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites validation completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core project configuration
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique identifiers
    local random_suffix=$(openssl rand -hex 3)
    export MIGRATION_JOB_NAME="legacy-modernization-${random_suffix}"
    export CLOUD_SQL_INSTANCE="modernized-postgres-${random_suffix}"
    export CONNECTION_PROFILE_SOURCE="sqlserver-source-${random_suffix}"
    export CONNECTION_PROFILE_DEST="postgres-dest-${random_suffix}"
    
    # SQL Server connection details (user configurable)
    export SQLSERVER_HOST="${SQLSERVER_HOST:-}"
    export SQLSERVER_PORT="${SQLSERVER_PORT:-1433}"
    export SQLSERVER_USERNAME="${SQLSERVER_USERNAME:-migration_user}"
    export SQLSERVER_PASSWORD="${SQLSERVER_PASSWORD:-}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Environment setup completed"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Migration Job: ${MIGRATION_JOB_NAME}"
    log_info "Cloud SQL Instance: ${CLOUD_SQL_INSTANCE}"
}

# Validate SQL Server connection parameters
validate_source_database_config() {
    log_info "Validating source database configuration..."
    
    if [[ -z "${SQLSERVER_HOST}" ]]; then
        log_warning "SQLSERVER_HOST not set. You'll need to configure this manually."
        log_info "Set environment variable: export SQLSERVER_HOST='your-sqlserver-host'"
    fi
    
    if [[ -z "${SQLSERVER_PASSWORD}" ]]; then
        log_warning "SQLSERVER_PASSWORD not set. You'll need to configure this manually."
        log_info "Set environment variable: export SQLSERVER_PASSWORD='your-password'"
    fi
    
    if [[ -n "${SQLSERVER_HOST}" && -n "${SQLSERVER_PASSWORD}" ]]; then
        log_success "Source database configuration provided"
    else
        log_warning "Source database configuration incomplete. Manual configuration will be required."
    fi
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "datamigration.googleapis.com"
        "sqladmin.googleapis.com"
        "compute.googleapis.com"
        "servicenetworking.googleapis.com"
        "cloudaicompanion.googleapis.com"
        "applicationdesigncenter.googleapis.com"
        "aiplatform.googleapis.com"
        "sourcerepo.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
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

# Create Cloud SQL PostgreSQL instance
create_cloud_sql_instance() {
    log_info "Creating Cloud SQL PostgreSQL instance: ${CLOUD_SQL_INSTANCE}..."
    
    if gcloud sql instances describe "${CLOUD_SQL_INSTANCE}" --quiet &>/dev/null; then
        log_warning "Cloud SQL instance ${CLOUD_SQL_INSTANCE} already exists"
        return 0
    fi
    
    # Generate a secure password for the migration user
    local migration_password=$(openssl rand -base64 16)
    
    # Create the Cloud SQL instance
    if gcloud sql instances create "${CLOUD_SQL_INSTANCE}" \
        --database-version=POSTGRES_15 \
        --tier=db-standard-2 \
        --region="${REGION}" \
        --storage-type=SSD \
        --storage-size=100GB \
        --storage-auto-increase \
        --backup-start-time=02:00 \
        --maintenance-window-day=SUN \
        --maintenance-window-hour=03 \
        --deletion-protection \
        --quiet; then
        
        track_resource "cloudsql" "${CLOUD_SQL_INSTANCE}" "${REGION}"
        log_success "Cloud SQL instance created: ${CLOUD_SQL_INSTANCE}"
        
        # Wait for instance to be ready
        log_info "Waiting for Cloud SQL instance to be ready..."
        local max_attempts=30
        local attempt=1
        while [[ ${attempt} -le ${max_attempts} ]]; do
            if gcloud sql instances describe "${CLOUD_SQL_INSTANCE}" \
                --format="value(state)" | grep -q "RUNNABLE"; then
                break
            fi
            log_info "Attempt ${attempt}/${max_attempts}: Waiting for instance to be ready..."
            sleep 30
            ((attempt++))
        done
        
        if [[ ${attempt} -gt ${max_attempts} ]]; then
            log_error "Cloud SQL instance failed to become ready within expected time"
            exit 1
        fi
        
        # Create migration user
        log_info "Creating migration user..."
        if gcloud sql users create migration-user \
            --instance="${CLOUD_SQL_INSTANCE}" \
            --password="${migration_password}" \
            --quiet; then
            log_success "Migration user created"
            log_info "Migration user password: ${migration_password}"
            echo "MIGRATION_PASSWORD=${migration_password}" >> "${SCRIPT_DIR}/.env"
        else
            log_error "Failed to create migration user"
            exit 1
        fi
        
    else
        log_error "Failed to create Cloud SQL instance"
        exit 1
    fi
}

# Create source database connection profile
create_source_connection_profile() {
    log_info "Creating source database connection profile: ${CONNECTION_PROFILE_SOURCE}..."
    
    if gcloud datamigration connection-profiles describe "${CONNECTION_PROFILE_SOURCE}" \
        --region="${REGION}" --quiet &>/dev/null; then
        log_warning "Source connection profile ${CONNECTION_PROFILE_SOURCE} already exists"
        return 0
    fi
    
    if [[ -z "${SQLSERVER_HOST}" || -z "${SQLSERVER_PASSWORD}" ]]; then
        log_warning "Creating placeholder connection profile. Manual configuration required."
        log_info "After deployment, update with: gcloud datamigration connection-profiles create sql-server"
        log_info "Required parameters: --host, --port, --username, --password"
        
        # Create a placeholder profile that will need manual configuration
        cat > "${SCRIPT_DIR}/source-profile-config.yaml" << EOF
# SQL Server Connection Profile Configuration
# Update these values with your actual SQL Server details

connection_profile_name: ${CONNECTION_PROFILE_SOURCE}
region: ${REGION}
host: "YOUR_SQLSERVER_HOST"
port: ${SQLSERVER_PORT}
username: "${SQLSERVER_USERNAME}"
password: "YOUR_SQLSERVER_PASSWORD"
ssl_enabled: false

# Command to create the connection profile:
# gcloud datamigration connection-profiles create sql-server \\
#     ${CONNECTION_PROFILE_SOURCE} \\
#     --region=${REGION} \\
#     --host="YOUR_SQLSERVER_HOST" \\
#     --port=${SQLSERVER_PORT} \\
#     --username="${SQLSERVER_USERNAME}" \\
#     --password="YOUR_SQLSERVER_PASSWORD" \\
#     --no-ssl
EOF
        log_info "Source profile configuration saved to: ${SCRIPT_DIR}/source-profile-config.yaml"
        return 0
    fi
    
    # Create the actual connection profile
    if gcloud datamigration connection-profiles create sql-server \
        "${CONNECTION_PROFILE_SOURCE}" \
        --region="${REGION}" \
        --host="${SQLSERVER_HOST}" \
        --port="${SQLSERVER_PORT}" \
        --username="${SQLSERVER_USERNAME}" \
        --password="${SQLSERVER_PASSWORD}" \
        --no-ssl \
        --quiet; then
        
        track_resource "connection-profile" "${CONNECTION_PROFILE_SOURCE}" "${REGION}"
        log_success "Source connection profile created: ${CONNECTION_PROFILE_SOURCE}"
    else
        log_error "Failed to create source connection profile"
        exit 1
    fi
}

# Create destination connection profile
create_destination_connection_profile() {
    log_info "Creating destination connection profile: ${CONNECTION_PROFILE_DEST}..."
    
    if gcloud datamigration connection-profiles describe "${CONNECTION_PROFILE_DEST}" \
        --region="${REGION}" --quiet &>/dev/null; then
        log_warning "Destination connection profile ${CONNECTION_PROFILE_DEST} already exists"
        return 0
    fi
    
    if gcloud datamigration connection-profiles create cloudsql-postgres \
        "${CONNECTION_PROFILE_DEST}" \
        --region="${REGION}" \
        --cloudsql-instance="${CLOUD_SQL_INSTANCE}" \
        --quiet; then
        
        track_resource "connection-profile" "${CONNECTION_PROFILE_DEST}" "${REGION}"
        log_success "Destination connection profile created: ${CONNECTION_PROFILE_DEST}"
    else
        log_error "Failed to create destination connection profile"
        exit 1
    fi
}

# Create migration job
create_migration_job() {
    log_info "Creating migration job: ${MIGRATION_JOB_NAME}..."
    
    if gcloud datamigration migration-jobs describe "${MIGRATION_JOB_NAME}" \
        --region="${REGION}" --quiet &>/dev/null; then
        log_warning "Migration job ${MIGRATION_JOB_NAME} already exists"
        return 0
    fi
    
    # Check if source connection profile exists
    if ! gcloud datamigration connection-profiles describe "${CONNECTION_PROFILE_SOURCE}" \
        --region="${REGION}" --quiet &>/dev/null; then
        log_warning "Source connection profile not found. Creating migration job configuration file."
        
        cat > "${SCRIPT_DIR}/migration-job-config.yaml" << EOF
# Migration Job Configuration
# Create this job after configuring the source connection profile

migration_job_name: ${MIGRATION_JOB_NAME}
region: ${REGION}
type: CONTINUOUS
source: ${CONNECTION_PROFILE_SOURCE}
destination: ${CONNECTION_PROFILE_DEST}
peer_vpc: "projects/${PROJECT_ID}/global/networks/default"

# Command to create the migration job:
# gcloud datamigration migration-jobs create \\
#     ${MIGRATION_JOB_NAME} \\
#     --region=${REGION} \\
#     --type=CONTINUOUS \\
#     --source=${CONNECTION_PROFILE_SOURCE} \\
#     --destination=${CONNECTION_PROFILE_DEST} \\
#     --peer-vpc="projects/${PROJECT_ID}/global/networks/default"

# Command to start the migration:
# gcloud datamigration migration-jobs start \\
#     ${MIGRATION_JOB_NAME} \\
#     --region=${REGION}
EOF
        log_info "Migration job configuration saved to: ${SCRIPT_DIR}/migration-job-config.yaml"
        return 0
    fi
    
    if gcloud datamigration migration-jobs create \
        "${MIGRATION_JOB_NAME}" \
        --region="${REGION}" \
        --type=CONTINUOUS \
        --source="${CONNECTION_PROFILE_SOURCE}" \
        --destination="${CONNECTION_PROFILE_DEST}" \
        --peer-vpc="projects/${PROJECT_ID}/global/networks/default" \
        --quiet; then
        
        track_resource "migration-job" "${MIGRATION_JOB_NAME}" "${REGION}"
        log_success "Migration job created: ${MIGRATION_JOB_NAME}"
        
        # Start the migration job
        log_info "Starting migration job..."
        if gcloud datamigration migration-jobs start \
            "${MIGRATION_JOB_NAME}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Migration job started successfully"
        else
            log_warning "Migration job created but failed to start. Start manually when ready."
        fi
    else
        log_error "Failed to create migration job"
        exit 1
    fi
}

# Setup Application Design Center
setup_application_design_center() {
    log_info "Setting up Application Design Center..."
    
    # Create workspace
    local workspace_name="legacy-modernization-workspace"
    if gcloud alpha application-design-center workspaces create \
        "${workspace_name}" \
        --region="${REGION}" \
        --description="Legacy database application modernization project" \
        --quiet 2>/dev/null; then
        
        track_resource "adc-workspace" "${workspace_name}" "${REGION}"
        log_success "Application Design Center workspace created: ${workspace_name}"
    else
        log_warning "Application Design Center workspace may already exist or API not available"
    fi
    
    # Create project
    local project_name="modernization-project"
    if gcloud alpha application-design-center projects create \
        "${project_name}" \
        --workspace="${workspace_name}" \
        --region="${REGION}" \
        --quiet 2>/dev/null; then
        
        track_resource "adc-project" "${project_name}" "${REGION}"
        log_success "Application Design Center project created: ${project_name}"
    else
        log_warning "Application Design Center project may already exist or API not available"
    fi
}

# Setup Gemini Code Assist
setup_gemini_code_assist() {
    log_info "Setting up Gemini Code Assist..."
    
    # Create source repository for code analysis
    local repo_name="legacy-app-modernization"
    if gcloud source repos create "${repo_name}" --quiet 2>/dev/null; then
        track_resource "source-repo" "${repo_name}" ""
        log_success "Source repository created: ${repo_name}"
        
        # Clone repository
        if gcloud source repos clone "${repo_name}" \
            --project="${PROJECT_ID}" "${SCRIPT_DIR}/${repo_name}" --quiet; then
            log_success "Repository cloned to: ${SCRIPT_DIR}/${repo_name}"
            
            # Create analysis configuration
            cat > "${SCRIPT_DIR}/${repo_name}/app-analysis-config.yaml" << 'EOF'
analysis_scope:
  - database_layer: true
  - business_logic: true
  - data_access_patterns: true
modernization_targets:
  - postgresql_optimization: true
  - cloud_native_patterns: true
  - microservices_ready: true
frameworks:
  - target: "spring-boot"
  - orm: "hibernate"
  - connection_pool: "hikari"
EOF
            
            # Create PostgreSQL configuration template
            cat > "${SCRIPT_DIR}/${repo_name}/postgres-config.yaml" << EOF
database:
  host: ${CLOUD_SQL_INSTANCE}
  port: 5432
  database: postgres
  username: migration-user
  connection_pool:
    initial_size: 5
    max_size: 20
    timeout: 30s
features:
  postgresql_optimizations: true
  cloud_native_monitoring: true
EOF
            
            log_success "Analysis configuration files created"
        else
            log_warning "Failed to clone repository"
        fi
    else
        log_warning "Source repository may already exist"
    fi
}

# Create monitoring and logging setup
setup_monitoring() {
    log_info "Setting up monitoring and logging..."
    
    # Create log sink for migration monitoring
    local sink_name="migration-logs-${CLOUD_SQL_INSTANCE}"
    if gcloud logging sinks create "${sink_name}" \
        bigquery.googleapis.com/projects/"${PROJECT_ID}"/datasets/migration_logs \
        --log-filter="resource.type=gce_instance AND logName=projects/${PROJECT_ID}/logs/datamigration" \
        --quiet 2>/dev/null; then
        track_resource "log-sink" "${sink_name}" ""
        log_success "Log sink created for migration monitoring"
    else
        log_warning "Log sink may already exist or BigQuery dataset not available"
    fi
}

# Generate deployment summary
generate_deployment_summary() {
    log_info "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment-summary.md" << EOF
# Deployment Summary

## Infrastructure Created

### Core Resources
- **Cloud SQL Instance**: \`${CLOUD_SQL_INSTANCE}\`
- **Migration Job**: \`${MIGRATION_JOB_NAME}\`
- **Source Connection Profile**: \`${CONNECTION_PROFILE_SOURCE}\`
- **Destination Connection Profile**: \`${CONNECTION_PROFILE_DEST}\`

### Application Modernization
- **Application Design Center Workspace**: \`legacy-modernization-workspace\`
- **Source Repository**: \`legacy-app-modernization\`

## Next Steps

### 1. Configure Source Database Connection
If you haven't provided SQL Server connection details, update the connection profile:

\`\`\`bash
gcloud datamigration connection-profiles create sql-server \\
    ${CONNECTION_PROFILE_SOURCE} \\
    --region=${REGION} \\
    --host="YOUR_SQLSERVER_HOST" \\
    --port=${SQLSERVER_PORT} \\
    --username="${SQLSERVER_USERNAME}" \\
    --password="YOUR_SQLSERVER_PASSWORD" \\
    --no-ssl
\`\`\`

### 2. Start Migration Job
\`\`\`bash
gcloud datamigration migration-jobs start \\
    ${MIGRATION_JOB_NAME} \\
    --region=${REGION}
\`\`\`

### 3. Monitor Migration Progress
\`\`\`bash
gcloud datamigration migration-jobs describe \\
    ${MIGRATION_JOB_NAME} \\
    --region=${REGION}
\`\`\`

### 4. Access Application Code Repository
\`\`\`bash
cd ${SCRIPT_DIR}/legacy-app-modernization
# Add your application code for analysis
\`\`\`

## Costs

Estimated monthly costs:
- Cloud SQL (db-standard-2): ~\$200-300
- Database Migration Service: Based on data volume
- Application Design Center: Minimal usage costs

## Support

- Deployment log: \`${LOG_FILE}\`
- Created resources: \`${SCRIPT_DIR}/.created_resources\`
- Configuration files: \`${SCRIPT_DIR}/\`

## Cleanup

To remove all resources:
\`\`\`bash
./destroy.sh
\`\`\`
EOF
    
    log_success "Deployment summary created: ${SCRIPT_DIR}/deployment-summary.md"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_failed=false
    
    # Check Cloud SQL instance
    if gcloud sql instances describe "${CLOUD_SQL_INSTANCE}" --quiet &>/dev/null; then
        local instance_state=$(gcloud sql instances describe "${CLOUD_SQL_INSTANCE}" \
            --format="value(state)")
        if [[ "${instance_state}" == "RUNNABLE" ]]; then
            log_success "Cloud SQL instance is running"
        else
            log_warning "Cloud SQL instance state: ${instance_state}"
        fi
    else
        log_error "Cloud SQL instance not found"
        validation_failed=true
    fi
    
    # Check connection profiles
    if gcloud datamigration connection-profiles describe "${CONNECTION_PROFILE_DEST}" \
        --region="${REGION}" --quiet &>/dev/null; then
        log_success "Destination connection profile exists"
    else
        log_error "Destination connection profile not found"
        validation_failed=true
    fi
    
    if [[ "${validation_failed}" == "true" ]]; then
        log_error "Deployment validation failed"
        exit 1
    else
        log_success "Deployment validation completed successfully"
    fi
}

# Main deployment function
main() {
    log_info "Starting deployment of Legacy Database Applications modernization solution..."
    log_info "Deployment log: ${LOG_FILE}"
    
    check_prerequisites
    setup_environment
    validate_source_database_config
    enable_apis
    create_cloud_sql_instance
    create_destination_connection_profile
    create_source_connection_profile
    create_migration_job
    setup_application_design_center
    setup_gemini_code_assist
    setup_monitoring
    validate_deployment
    generate_deployment_summary
    
    log_success "Deployment completed successfully!"
    log_info "Next steps:"
    log_info "1. Review deployment summary: ${SCRIPT_DIR}/deployment-summary.md"
    log_info "2. Configure source database connection if needed"
    log_info "3. Monitor migration progress"
    log_info "4. Begin application modernization with provided tools"
    
    echo
    log_success "🎉 Legacy Database Applications modernization infrastructure is ready!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi