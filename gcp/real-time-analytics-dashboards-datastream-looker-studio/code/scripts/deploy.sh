#!/bin/bash

# Real-Time Analytics Dashboards with Datastream and Looker Studio
# Deployment script for GCP recipe: real-time-analytics-dashboards-datastream-looker-studio
# Recipe ID: 7a8b9c2d

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RECIPE_NAME="real-time-analytics-dashboards-datastream-looker-studio"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1" | tee -a "${LOG_FILE}"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Running cleanup..."
    if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
        bash "${SCRIPT_DIR}/destroy.sh" --force
    fi
}

# Trap errors and run cleanup
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy real-time analytics dashboards with Datastream and Looker Studio

OPTIONS:
    --project-id PROJECT_ID     Google Cloud project ID (required)
    --region REGION            GCP region (default: us-central1)
    --source-db-host HOST      Source database hostname (required)
    --source-db-port PORT      Source database port (default: 3306)
    --source-db-user USER      Source database username (required)
    --source-db-password PASS  Source database password (required)
    --source-db-name NAME      Source database name (required)
    --dry-run                  Show what would be deployed without executing
    --help                     Show this help message

EXAMPLE:
    $0 --project-id my-analytics-project \\
       --source-db-host 10.0.0.10 \\
       --source-db-user datastream_user \\
       --source-db-password mypassword \\
       --source-db-name ecommerce

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Source database configured for Datastream (binary logging enabled for MySQL)
    - Network connectivity between GCP and source database
    - Required APIs will be enabled automatically

EOF
}

# Default values
REGION="us-central1"
SOURCE_DB_PORT="3306"
DRY_RUN=false

# Parse command line arguments
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
        --source-db-host)
            SOURCE_DB_HOST="$2"
            shift 2
            ;;
        --source-db-port)
            SOURCE_DB_PORT="$2"
            shift 2
            ;;
        --source-db-user)
            SOURCE_DB_USER="$2"
            shift 2
            ;;
        --source-db-password)
            SOURCE_DB_PASSWORD="$2"
            shift 2
            ;;
        --source-db-name)
            SOURCE_DB_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
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

# Validate required parameters
if [[ -z "${PROJECT_ID:-}" ]]; then
    log_error "Project ID is required. Use --project-id option."
    show_help
    exit 1
fi

if [[ -z "${SOURCE_DB_HOST:-}" ]]; then
    log_error "Source database host is required. Use --source-db-host option."
    show_help
    exit 1
fi

if [[ -z "${SOURCE_DB_USER:-}" ]]; then
    log_error "Source database user is required. Use --source-db-user option."
    show_help
    exit 1
fi

if [[ -z "${SOURCE_DB_PASSWORD:-}" ]]; then
    log_error "Source database password is required. Use --source-db-password option."
    show_help
    exit 1
fi

if [[ -z "${SOURCE_DB_NAME:-}" ]]; then
    log_error "Source database name is required. Use --source-db-name option."
    show_help
    exit 1
fi

# Initialize logging
log "Starting deployment of ${RECIPE_NAME}"
log "Project ID: ${PROJECT_ID}"
log "Region: ${REGION}"
log "Source DB Host: ${SOURCE_DB_HOST}"
log "Dry Run: ${DRY_RUN}"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Cannot access project ${PROJECT_ID}. Please check project ID and permissions."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATASET_NAME="ecommerce_analytics"
    export STREAM_NAME="sales-stream"
    export CONNECTION_PROFILE_NAME="source-db-${RANDOM_SUFFIX}"
    export BQ_CONNECTION_PROFILE_NAME="bigquery-${RANDOM_SUFFIX}"
    
    # Store variables in a file for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
DATASET_NAME=${DATASET_NAME}
STREAM_NAME=${STREAM_NAME}
CONNECTION_PROFILE_NAME=${CONNECTION_PROFILE_NAME}
BQ_CONNECTION_PROFILE_NAME=${BQ_CONNECTION_PROFILE_NAME}
SOURCE_DB_HOST=${SOURCE_DB_HOST}
SOURCE_DB_PORT=${SOURCE_DB_PORT}
SOURCE_DB_USER=${SOURCE_DB_USER}
SOURCE_DB_NAME=${SOURCE_DB_NAME}
EOF
    
    log_success "Environment variables configured"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would enable APIs: datastream.googleapis.com, bigquery.googleapis.com, sqladmin.googleapis.com"
        return
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Enable required APIs
    local apis=(
        "datastream.googleapis.com"
        "bigquery.googleapis.com"
        "sqladmin.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset for analytics data..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create BigQuery dataset: ${DATASET_NAME}"
        return
    fi
    
    # Create BigQuery dataset
    if bq mk --dataset \
        --location="${REGION}" \
        --description="Real-time e-commerce analytics dataset" \
        "${PROJECT_ID}:${DATASET_NAME}"; then
        log_success "BigQuery dataset created: ${DATASET_NAME}"
    else
        log_error "Failed to create BigQuery dataset"
        exit 1
    fi
    
    # Set dataset labels for cost tracking and organization
    if bq update --set_label environment:production \
        --set_label purpose:analytics \
        "${PROJECT_ID}:${DATASET_NAME}"; then
        log_success "Dataset labels applied"
    else
        log_warning "Failed to apply dataset labels (non-critical)"
    fi
}

# Create source database connection profile
create_source_connection_profile() {
    log "Creating source database connection profile..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create connection profile: ${CONNECTION_PROFILE_NAME}"
        return
    fi
    
    # Create connection profile for source database
    if gcloud datastream connection-profiles create "${CONNECTION_PROFILE_NAME}" \
        --location="${REGION}" \
        --type=mysql \
        --mysql-hostname="${SOURCE_DB_HOST}" \
        --mysql-port="${SOURCE_DB_PORT}" \
        --mysql-username="${SOURCE_DB_USER}" \
        --mysql-password-file=<(echo "${SOURCE_DB_PASSWORD}") \
        --display-name="Source Database Connection"; then
        log_success "Source database connection profile created"
    else
        log_error "Failed to create source database connection profile"
        exit 1
    fi
    
    # Verify connection profile creation
    if gcloud datastream connection-profiles describe \
        "${CONNECTION_PROFILE_NAME}" \
        --location="${REGION}" &>/dev/null; then
        log_success "Connection profile verified"
    else
        log_error "Failed to verify connection profile"
        exit 1
    fi
}

# Create BigQuery destination connection profile
create_bigquery_connection_profile() {
    log "Creating BigQuery destination connection profile..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create BigQuery connection profile: ${BQ_CONNECTION_PROFILE_NAME}"
        return
    fi
    
    # Create BigQuery destination connection profile
    if gcloud datastream connection-profiles create "${BQ_CONNECTION_PROFILE_NAME}" \
        --location="${REGION}" \
        --type=bigquery \
        --bigquery-dataset="${DATASET_NAME}" \
        --display-name="BigQuery Analytics Destination"; then
        log_success "BigQuery destination profile configured"
    else
        log_error "Failed to create BigQuery destination profile"
        exit 1
    fi
    
    # Verify BigQuery connection profile
    if gcloud datastream connection-profiles describe \
        "${BQ_CONNECTION_PROFILE_NAME}" \
        --location="${REGION}" &>/dev/null; then
        log_success "BigQuery connection profile verified"
    else
        log_error "Failed to verify BigQuery connection profile"
        exit 1
    fi
}

# Configure and start Datastream
configure_datastream() {
    log "Configuring Datastream for change data capture..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create and start Datastream: ${STREAM_NAME}"
        return
    fi
    
    # Create the Datastream configuration
    local include_objects="${SOURCE_DB_NAME}.sales_orders,${SOURCE_DB_NAME}.customers,${SOURCE_DB_NAME}.products"
    
    if gcloud datastream streams create "${STREAM_NAME}" \
        --location="${REGION}" \
        --source-connection-profile="${CONNECTION_PROFILE_NAME}" \
        --destination-connection-profile="${BQ_CONNECTION_PROFILE_NAME}" \
        --display-name="Real-time Sales Analytics Stream" \
        --include-objects="${include_objects}"; then
        log_success "Datastream configuration created"
    else
        log_error "Failed to create Datastream configuration"
        exit 1
    fi
    
    # Start the stream to begin data replication
    log "Starting Datastream replication..."
    if gcloud datastream streams start "${STREAM_NAME}" \
        --location="${REGION}"; then
        log_success "Datastream started successfully"
    else
        log_error "Failed to start Datastream"
        exit 1
    fi
    
    # Wait for stream to initialize
    log "Waiting for Datastream to initialize..."
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local stream_state
        stream_state=$(gcloud datastream streams describe "${STREAM_NAME}" \
            --location="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${stream_state}" == "RUNNING" ]]; then
            log_success "Datastream is running and replicating data"
            break
        elif [[ "${stream_state}" == "FAILED" ]]; then
            log_error "Datastream failed to start"
            exit 1
        else
            log "Datastream state: ${stream_state}. Waiting... (${attempt}/${max_attempts})"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        log_error "Datastream did not start within expected time"
        exit 1
    fi
}

# Verify data replication
verify_data_replication() {
    log "Verifying data replication in BigQuery..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would verify data replication in BigQuery"
        return
    fi
    
    # Wait for initial data to be replicated
    log "Waiting for initial data replication..."
    sleep 60
    
    # Check for replicated tables in BigQuery
    log "Checking for replicated tables..."
    if bq ls "${DATASET_NAME}" &>/dev/null; then
        local table_count
        table_count=$(bq ls "${DATASET_NAME}" | grep -c "TABLE" || echo "0")
        log_success "Found ${table_count} tables in BigQuery dataset"
    else
        log_warning "No tables found yet in BigQuery dataset (this may be normal for initial replication)"
    fi
    
    # Check stream status
    local stream_status
    stream_status=$(gcloud datastream streams describe "${STREAM_NAME}" \
        --location="${REGION}" \
        --format="table(state,backfillAll.completed)" 2>/dev/null || echo "UNKNOWN")
    
    log "Datastream status: ${stream_status}"
}

# Create analytics views
create_analytics_views() {
    log "Creating analytics views for business intelligence..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create analytics views in BigQuery"
        return
    fi
    
    # Wait for tables to be available
    log "Waiting for source tables to be available..."
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if bq ls "${DATASET_NAME}" | grep -q "sales_orders"; then
            log_success "Source tables are available"
            break
        else
            log "Waiting for source tables... (${attempt}/${max_attempts})"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        log_warning "Source tables not available yet. Views will be created but may fail initially."
    fi
    
    # Create sales performance view
    log "Creating sales performance view..."
    if bq query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.sales_performance\` AS
    SELECT 
        DATE(o.order_date) as order_date,
        o.customer_id,
        COALESCE(c.customer_name, 'Unknown') as customer_name,
        o.product_id,
        COALESCE(p.product_name, 'Unknown') as product_name,
        o.quantity,
        o.unit_price,
        o.quantity * o.unit_price as total_amount,
        o._metadata_timestamp as last_updated
    FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_orders\` o
    LEFT JOIN \`${PROJECT_ID}.${DATASET_NAME}.customers\` c 
        ON o.customer_id = c.customer_id
    LEFT JOIN \`${PROJECT_ID}.${DATASET_NAME}.products\` p 
        ON o.product_id = p.product_id
    WHERE COALESCE(o._metadata_deleted, false) = false"; then
        log_success "Sales performance view created"
    else
        log_warning "Failed to create sales performance view (may succeed after data replication completes)"
    fi
    
    # Create daily sales summary view
    log "Creating daily sales summary view..."
    if bq query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.daily_sales_summary\` AS
    SELECT 
        DATE(order_date) as sales_date,
        COUNT(*) as total_orders,
        SUM(total_amount) as total_revenue,
        AVG(total_amount) as avg_order_value,
        COUNT(DISTINCT customer_id) as unique_customers
    FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_performance\`
    GROUP BY DATE(order_date)
    ORDER BY sales_date DESC"; then
        log_success "Daily sales summary view created"
    else
        log_warning "Failed to create daily sales summary view (may succeed after data replication completes)"
    fi
}

# Display connection information for Looker Studio
display_looker_studio_info() {
    log "Preparing Looker Studio connection information..."
    
    cat << EOF

🎉 Deployment completed successfully!

==================================================
LOOKER STUDIO CONNECTION INFORMATION
==================================================

To create your real-time analytics dashboard:

1. Open Looker Studio: https://lookerstudio.google.com/
2. Click 'Create' > 'Report'
3. Select 'BigQuery' as data source
4. Use these connection details:

   Project ID: ${PROJECT_ID}
   Dataset: ${DATASET_NAME}
   
   Available Tables/Views:
   - sales_orders (raw data from Datastream)
   - customers (raw data from Datastream)  
   - products (raw data from Datastream)
   - sales_performance (business view)
   - daily_sales_summary (aggregated view)

5. Recommended starting view: daily_sales_summary

Sample Query for Looker Studio:
SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.daily_sales_summary\`
ORDER BY sales_date DESC LIMIT 30

==================================================
NEXT STEPS
==================================================

1. Verify data is flowing: Check BigQuery dataset for new data
2. Create Looker Studio dashboard using the connection info above
3. Monitor Datastream status in the Google Cloud Console
4. Set up alerts for data freshness and stream health

==================================================
MONITORING COMMANDS
==================================================

Check Datastream status:
gcloud datastream streams describe ${STREAM_NAME} --location=${REGION}

Check data freshness in BigQuery:
bq query --use_legacy_sql=false "SELECT MAX(_metadata_timestamp) as latest_update FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_orders\`"

List replicated tables:
bq ls ${DATASET_NAME}

==================================================

EOF
}

# Main deployment function
main() {
    log "=== Starting Real-Time Analytics Dashboard Deployment ==="
    
    check_prerequisites
    setup_environment
    enable_apis
    create_bigquery_dataset
    create_source_connection_profile
    create_bigquery_connection_profile
    configure_datastream
    verify_data_replication
    create_analytics_views
    display_looker_studio_info
    
    log_success "=== Deployment completed successfully! ==="
    log "Log file: ${LOG_FILE}"
    log "Environment file: ${SCRIPT_DIR}/.env"
}

# Run main function
main "$@"