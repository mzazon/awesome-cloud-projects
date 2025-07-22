#!/bin/bash

# Deploy script for Data Quality Monitoring with Dataform and Cloud Scheduler
# This script creates an automated data quality monitoring system using Dataform for SQL-based data assertions
# and Cloud Scheduler for orchestrating regular quality checks.

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
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Don't exit on cleanup errors
    set +e
    
    # Clean up local files
    rm -f ~/dataform-project/dataform.json 2>/dev/null
    rm -f ~/dataform-project/package.json 2>/dev/null
    rm -f notification-channel.json 2>/dev/null
    rm -f alert-policy.json 2>/dev/null
    rm -f workflow_settings.yaml 2>/dev/null
    
    log_warning "Partial cleanup completed. You may need to manually remove some resources."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set."
        log_info "Please set PROJECT_ID environment variable or use: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Cannot access project $PROJECT_ID. Please check project ID and permissions."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export REGION="${REGION:-us-central1}"
    export DATAFORM_REGION="${DATAFORM_REGION:-us-central1}"
    export REPOSITORY_ID="${REPOSITORY_ID:-data-quality-repo}"
    export WORKSPACE_ID="${WORKSPACE_ID:-quality-workspace}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATASET_ID="sample_ecommerce_${RANDOM_SUFFIX}"
    export SCHEDULER_JOB_ID="dataform-quality-job-${RANDOM_SUFFIX}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Dataset ID: ${DATASET_ID}"
    log_info "Scheduler Job ID: ${SCHEDULER_JOB_ID}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dataform.googleapis.com"
        "cloudscheduler.googleapis.com"
        "monitoring.googleapis.com"
        "bigquery.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Create sample BigQuery dataset and tables
create_sample_data() {
    log_info "Creating sample BigQuery dataset and tables..."
    
    # Create the sample dataset
    if bq mk --dataset --location="${REGION}" "${PROJECT_ID}:${DATASET_ID}" --quiet; then
        log_success "Created dataset: ${DATASET_ID}"
    else
        log_error "Failed to create dataset: ${DATASET_ID}"
        exit 1
    fi
    
    # Create customers table with sample data
    log_info "Creating customers table with sample data..."
    bq query --use_legacy_sql=false --quiet \
    "CREATE OR REPLACE TABLE \`${PROJECT_ID}.${DATASET_ID}.customers\` AS
    SELECT 
      customer_id,
      email,
      first_name,
      last_name,
      registration_date,
      city,
      state
    FROM (
      SELECT 1 as customer_id, 'john@example.com' as email, 'John' as first_name, 'Doe' as last_name, '2024-01-15' as registration_date, 'New York' as city, 'NY' as state
      UNION ALL
      SELECT 2, 'jane@example.com', 'Jane', 'Smith', '2024-02-20', 'Los Angeles', 'CA'
      UNION ALL
      SELECT 3, 'bob@example.com', 'Bob', 'Johnson', '2024-03-10', 'Chicago', 'IL'
      UNION ALL
      SELECT 4, NULL, 'Alice', 'Brown', '2024-04-05', 'Houston', 'TX'
      UNION ALL
      SELECT 5, 'charlie@example.com', NULL, 'Davis', '2024-05-12', 'Phoenix', 'AZ'
    )"
    
    # Create orders table with sample data
    log_info "Creating orders table with sample data..."
    bq query --use_legacy_sql=false --quiet \
    "CREATE OR REPLACE TABLE \`${PROJECT_ID}.${DATASET_ID}.orders\` AS
    SELECT 
      order_id,
      customer_id,
      order_date,
      total_amount,
      status
    FROM (
      SELECT 1 as order_id, 1 as customer_id, '2024-06-01' as order_date, 99.99 as total_amount, 'completed' as status
      UNION ALL
      SELECT 2, 2, '2024-06-02', 149.50, 'completed'
      UNION ALL
      SELECT 3, 3, '2024-06-03', -25.00, 'refunded'
      UNION ALL
      SELECT 4, 999, '2024-06-04', 75.25, 'pending'
      UNION ALL
      SELECT 5, 2, '2024-06-05', NULL, 'completed'
    )"
    
    log_success "Sample BigQuery dataset and tables created with intentional data quality issues"
}

# Create Dataform repository and workspace
create_dataform_resources() {
    log_info "Creating Dataform repository and workspace..."
    
    # Create the Dataform repository
    if gcloud dataform repositories create "${REPOSITORY_ID}" \
        --location="${DATAFORM_REGION}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Created Dataform repository: ${REPOSITORY_ID}"
    else
        log_error "Failed to create Dataform repository"
        exit 1
    fi
    
    # Create a development workspace
    if gcloud dataform workspaces create "${WORKSPACE_ID}" \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Created Dataform workspace: ${WORKSPACE_ID}"
    else
        log_error "Failed to create Dataform workspace"
        exit 1
    fi
}

# Initialize Dataform project structure
setup_dataform_project() {
    log_info "Setting up Dataform project structure..."
    
    # Create local directory structure for Dataform project
    mkdir -p ~/dataform-project/definitions/models
    mkdir -p ~/dataform-project/definitions/assertions
    
    # Navigate to project directory
    cd ~/dataform-project
    
    # Create dataform.json configuration file
    cat > dataform.json << EOF
{
  "warehouse": "bigquery",
  "defaultDatabase": "${PROJECT_ID}",
  "defaultSchema": "${DATASET_ID}",
  "assertionSchema": "dataform_assertions_${RANDOM_SUFFIX}",
  "defaultLocation": "${REGION}",
  "vars": {
    "environment": "development"
  }
}
EOF
    
    # Create package.json for dependencies
    cat > package.json << EOF
{
  "dependencies": {
    "@dataform/core": "^3.0.0"
  }
}
EOF
    
    log_success "Dataform project structure initialized"
}

# Create data quality assertions
create_assertions() {
    log_info "Creating data quality assertions..."
    
    # Create customer data quality assertions
    cat > definitions/assertions/customer_quality_checks.sqlx << 'EOF'
config {
  type: "assertion",
  name: "customers_have_valid_emails"
}

-- Check for customers with missing or invalid email addresses
SELECT 
  customer_id,
  email,
  first_name,
  last_name,
  'Missing or invalid email address' as quality_issue
FROM ${ref("customers")}
WHERE email IS NULL 
   OR email = ''
   OR NOT REGEXP_CONTAINS(email, r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
EOF
    
    # Create assertion for customer name completeness
    cat > definitions/assertions/customer_name_completeness.sqlx << 'EOF'
config {
  type: "assertion",
  name: "customers_have_complete_names"
}

-- Check for customers with missing first or last names
SELECT 
  customer_id,
  first_name,
  last_name,
  email,
  'Incomplete customer name information' as quality_issue
FROM ${ref("customers")}
WHERE first_name IS NULL 
   OR last_name IS NULL
   OR TRIM(first_name) = ''
   OR TRIM(last_name) = ''
EOF
    
    # Create order data quality assertions
    cat > definitions/assertions/order_quality_checks.sqlx << 'EOF'
config {
  type: "assertion",
  name: "orders_have_valid_amounts"
}

-- Check for orders with invalid or missing amounts
SELECT 
  order_id,
  customer_id,
  total_amount,
  status,
  'Invalid order amount detected' as quality_issue
FROM ${ref("orders")}
WHERE total_amount IS NULL 
   OR total_amount < 0
   OR (status IN ('completed', 'pending') AND total_amount <= 0)
EOF
    
    # Create referential integrity assertion
    cat > definitions/assertions/order_referential_integrity.sqlx << 'EOF'
config {
  type: "assertion",
  name: "orders_reference_valid_customers"
}

-- Check for orders referencing non-existent customers
SELECT 
  o.order_id,
  o.customer_id,
  o.order_date,
  o.total_amount,
  'Order references non-existent customer' as quality_issue
FROM ${ref("orders")} o
LEFT JOIN ${ref("customers")} c
  ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
EOF
    
    log_success "Data quality assertions created"
}

# Create data quality summary view
create_summary_view() {
    log_info "Creating data quality summary view..."
    
    cat > definitions/models/data_quality_summary.sqlx << 'EOF'
config {
  type: "view",
  name: "data_quality_summary",
  description: "Centralized view of data quality metrics across all tables"
}

WITH assertion_results AS (
  SELECT 
    'customers_have_valid_emails' as assertion_name,
    'customers' as table_name,
    COUNT(*) as failed_records,
    CURRENT_TIMESTAMP() as check_timestamp
  FROM ${ref("customers_have_valid_emails")}
  
  UNION ALL
  
  SELECT 
    'customers_have_complete_names' as assertion_name,
    'customers' as table_name,
    COUNT(*) as failed_records,
    CURRENT_TIMESTAMP() as check_timestamp
  FROM ${ref("customers_have_complete_names")}
  
  UNION ALL
  
  SELECT 
    'orders_have_valid_amounts' as assertion_name,
    'orders' as table_name,
    COUNT(*) as failed_records,
    CURRENT_TIMESTAMP() as check_timestamp
  FROM ${ref("orders_have_valid_amounts")}
  
  UNION ALL
  
  SELECT 
    'orders_reference_valid_customers' as assertion_name,
    'orders' as table_name,
    COUNT(*) as failed_records,
    CURRENT_TIMESTAMP() as check_timestamp
  FROM ${ref("orders_reference_valid_customers")}
),

quality_metrics AS (
  SELECT 
    table_name,
    COUNT(*) as total_assertions,
    SUM(CASE WHEN failed_records > 0 THEN 1 ELSE 0 END) as failed_assertions,
    SUM(failed_records) as total_failed_records,
    MAX(check_timestamp) as last_check_timestamp
  FROM assertion_results
  GROUP BY table_name
)

SELECT 
  table_name,
  total_assertions,
  failed_assertions,
  total_failed_records,
  ROUND(
    ((total_assertions - failed_assertions) / total_assertions) * 100, 2
  ) as quality_score_percent,
  CASE 
    WHEN failed_assertions = 0 THEN 'EXCELLENT'
    WHEN failed_assertions <= 1 THEN 'GOOD'
    WHEN failed_assertions <= 2 THEN 'FAIR'
    ELSE 'POOR'
  END as quality_status,
  last_check_timestamp
FROM quality_metrics
ORDER BY quality_score_percent DESC
EOF
    
    log_success "Data quality summary view created"
}

# Create release configuration
create_release_config() {
    log_info "Creating Dataform release configuration..."
    
    # Create workflow configuration
    cat > workflow_settings.yaml << EOF
defaultProject: ${PROJECT_ID}
defaultDataset: ${DATASET_ID}
defaultLocation: ${REGION}
assertionDataset: dataform_assertions_${RANDOM_SUFFIX}
EOF
    
    # Create the release configuration
    if gcloud dataform release-configs create quality-monitoring-release \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --git-commitish=main \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Release configuration created"
    else
        log_error "Failed to create release configuration"
        exit 1
    fi
    
    # Create compilation result to validate the project
    log_info "Creating compilation result to validate project..."
    if gcloud dataform compilation-results create \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --workspace="${WORKSPACE_ID}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Project validation completed"
    else
        log_warning "Project validation failed - this may be expected for initial setup"
    fi
}

# Create service account and scheduler job
create_scheduler() {
    log_info "Creating Cloud Scheduler service account and job..."
    
    # Create service account for Cloud Scheduler
    if gcloud iam service-accounts create dataform-scheduler-sa \
        --display-name="Dataform Scheduler Service Account" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Created service account: dataform-scheduler-sa"
    else
        log_warning "Service account may already exist"
    fi
    
    # Grant necessary permissions to the service account
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:dataform-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/dataform.editor" \
        --quiet
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:dataform-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/bigquery.admin" \
        --quiet
    
    # Create the Cloud Scheduler job to run every 6 hours
    if gcloud scheduler jobs create http "${SCHEDULER_JOB_ID}" \
        --location="${REGION}" \
        --schedule="0 */6 * * *" \
        --uri="https://dataform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${DATAFORM_REGION}/repositories/${REPOSITORY_ID}/workflowInvocations" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body="{\"compilationResult\":\"projects/${PROJECT_ID}/locations/${DATAFORM_REGION}/repositories/${REPOSITORY_ID}/compilationResults/latest\"}" \
        --oidc-service-account-email="dataform-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --oidc-token-audience="https://dataform.googleapis.com/" \
        --quiet; then
        log_success "Cloud Scheduler job created: ${SCHEDULER_JOB_ID}"
    else
        log_error "Failed to create Cloud Scheduler job"
        exit 1
    fi
}

# Configure monitoring and alerting
setup_monitoring() {
    log_info "Setting up Cloud Monitoring and alerting..."
    
    # Create log-based metric for data quality failures
    if gcloud logging metrics create data_quality_failures \
        --description="Metric tracking data quality assertion failures" \
        --log-filter='resource.type="bigquery_dataset" AND (textPayload:"assertion" OR textPayload:"quality")' \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Created log-based metric: data_quality_failures"
    else
        log_warning "Log-based metric may already exist"
    fi
    
    # Create notification channel for email alerts
    cat > notification-channel.json << EOF
{
  "type": "email",
  "displayName": "Data Quality Alerts",
  "description": "Email notifications for data quality issues",
  "labels": {
    "email_address": "admin@example.com"
  },
  "enabled": true
}
EOF
    
    # Create the notification channel
    if gcloud alpha monitoring channels create --channel-content-from-file=notification-channel.json --quiet; then
        log_success "Created notification channel for alerts"
    else
        log_warning "Notification channel creation failed - please configure manually"
    fi
    
    # Get the notification channel ID for alert policy
    NOTIFICATION_CHANNEL=$(gcloud alpha monitoring channels list \
        --filter="displayName:'Data Quality Alerts'" \
        --format="value(name)" --quiet || echo "")
    
    # Create alert policy if notification channel exists
    if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
        cat > alert-policy.json << EOF
{
  "displayName": "Data Quality Alert Policy",
  "documentation": {
    "content": "Alert when data quality assertions fail or quality scores drop below acceptable thresholds"
  },
  "conditions": [
    {
      "displayName": "High Data Quality Failure Rate",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/data_quality_failures\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
    "${NOTIFICATION_CHANNEL}"
  ]
}
EOF
        
        if gcloud alpha monitoring policies create --policy-from-file=alert-policy.json --quiet; then
            log_success "Created alert policy for data quality monitoring"
        else
            log_warning "Alert policy creation failed"
        fi
    else
        log_warning "Skipping alert policy creation - no notification channel available"
    fi
}

# Validation function
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Dataform repository
    if gcloud dataform repositories describe "${REPOSITORY_ID}" \
        --location="${DATAFORM_REGION}" \
        --project="${PROJECT_ID}" \
        --format="value(name)" --quiet >/dev/null 2>&1; then
        log_success "Dataform repository is accessible"
    else
        log_error "Dataform repository validation failed"
        return 1
    fi
    
    # Check BigQuery dataset
    if bq show "${PROJECT_ID}:${DATASET_ID}" >/dev/null 2>&1; then
        log_success "BigQuery dataset is accessible"
    else
        log_error "BigQuery dataset validation failed"
        return 1
    fi
    
    # Check Cloud Scheduler job
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_ID}" \
        --location="${REGION}" \
        --format="value(name)" --quiet >/dev/null 2>&1; then
        log_success "Cloud Scheduler job is configured"
    else
        log_error "Cloud Scheduler job validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Main deployment function
main() {
    log_info "Starting deployment of Data Quality Monitoring with Dataform and Cloud Scheduler"
    
    check_prerequisites
    setup_environment
    enable_apis
    create_sample_data
    create_dataform_resources
    setup_dataform_project
    create_assertions
    create_summary_view
    create_release_config
    create_scheduler
    setup_monitoring
    validate_deployment
    
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "📋 Deployment Summary:"
    echo "   • Project ID: ${PROJECT_ID}"
    echo "   • Region: ${REGION}"
    echo "   • Dataset ID: ${DATASET_ID}"
    echo "   • Dataform Repository: ${REPOSITORY_ID}"
    echo "   • Scheduler Job: ${SCHEDULER_JOB_ID}"
    echo
    log_info "🔍 Next Steps:"
    echo "   1. Update notification email in Cloud Monitoring console"
    echo "   2. Test manual workflow execution with:"
    echo "      gcloud dataform workflow-invocations create \\"
    echo "        --location=${DATAFORM_REGION} \\"
    echo "        --repository=${REPOSITORY_ID} \\"
    echo "        --compilation-result=projects/${PROJECT_ID}/locations/${DATAFORM_REGION}/repositories/${REPOSITORY_ID}/compilationResults/latest"
    echo "   3. Monitor data quality results in BigQuery dataset: ${DATASET_ID}"
    echo "   4. View scheduler job status: gcloud scheduler jobs describe ${SCHEDULER_JOB_ID} --location=${REGION}"
    echo
    log_warning "⚠️  Remember to run ./destroy.sh when you're done to avoid ongoing charges"
}

# Run main function
main "$@"