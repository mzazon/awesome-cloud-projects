#!/bin/bash

# Privacy-Preserving Analytics with Confidential GKE and BigQuery - Deployment Script
# This script deploys the complete privacy-preserving analytics infrastructure
# including Confidential GKE, BigQuery with CMEK, Vertex AI, and Cloud KMS

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
readonly REQUIRED_APIS=(
    "container.googleapis.com"
    "bigquery.googleapis.com"
    "cloudkms.googleapis.com"
    "aiplatform.googleapis.com"
    "compute.googleapis.com"
    "storage.googleapis.com"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_error "Check the log file: ${LOG_FILE}"
    log_warning "Some resources may have been created. Run destroy.sh to clean up."
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy privacy-preserving analytics infrastructure with Confidential GKE and BigQuery.

OPTIONS:
    -p, --project PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION         Google Cloud region (default: us-central1)
    -z, --zone ZONE            Google Cloud zone (default: us-central1-a)
    -s, --suffix SUFFIX        Resource name suffix (default: auto-generated)
    -d, --dry-run              Show what would be deployed without executing
    -v, --verbose              Enable verbose logging
    -h, --help                 Show this help message

EXAMPLES:
    $0 --project my-project-123
    $0 --project my-project-123 --region us-west1 --zone us-west1-b
    $0 --dry-run --project my-project-123

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and authenticated
    - kubectl installed
    - Project billing enabled
    - Required APIs will be enabled automatically
    - Estimated cost: \$75-150 for full deployment

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
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
            -s|--suffix)
                CUSTOM_SUFFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Set default values
set_defaults() {
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    DRY_RUN="${DRY_RUN:-false}"
    VERBOSE="${VERBOSE:-false}"
    
    # Generate unique suffix if not provided
    if [[ -z "${CUSTOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        RANDOM_SUFFIX="${CUSTOM_SUFFIX}"
    fi
    
    # Set resource names
    CLUSTER_NAME="confidential-cluster-${RANDOM_SUFFIX}"
    KEYRING_NAME="analytics-keyring-${RANDOM_SUFFIX}"
    KEY_NAME="analytics-key-${RANDOM_SUFFIX}"
    DATASET_NAME="sensitive_analytics_${RANDOM_SUFFIX}"
    BUCKET_NAME="privacy-analytics-${PROJECT_ID}-${RANDOM_SUFFIX}"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if PROJECT_ID is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project flag or set PROJECT_ID environment variable."
        show_usage
        exit 1
    fi
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        log_error "Install from: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "OpenSSL not found, using date-based random suffix"
    fi
    
    # Validate gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Validate project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project ${PROJECT_ID} or project doesn't exist"
        log_error "Verify project ID and ensure you have appropriate permissions"
        exit 1
    fi
    
    # Check billing account
    local billing_account
    billing_account=$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
    if [[ -z "${billing_account}" ]]; then
        log_error "Project ${PROJECT_ID} does not have billing enabled"
        log_error "Enable billing: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project to ${PROJECT_ID}"
        log_info "[DRY RUN] Would set region to ${REGION}"
        log_info "[DRY RUN] Would set zone to ${ZONE}"
        return 0
    fi
    
    gcloud config set project "${PROJECT_ID}" 2>> "${LOG_FILE}"
    gcloud config set compute/region "${REGION}" 2>> "${LOG_FILE}"
    gcloud config set compute/zone "${ZONE}" 2>> "${LOG_FILE}"
    
    log_success "Gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return 0
    fi
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" 2>> "${LOG_FILE}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create KMS resources
create_kms_resources() {
    log_info "Creating Cloud KMS key ring and encryption keys..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create KMS keyring: ${KEYRING_NAME}"
        log_info "[DRY RUN] Would create KMS key: ${KEY_NAME}"
        return 0
    fi
    
    # Create KMS key ring
    if gcloud kms keyrings create "${KEYRING_NAME}" --location="${REGION}" 2>> "${LOG_FILE}"; then
        log_success "Created KMS keyring: ${KEYRING_NAME}"
    else
        log_error "Failed to create KMS keyring"
        exit 1
    fi
    
    # Create encryption key
    if gcloud kms keys create "${KEY_NAME}" \
        --location="${REGION}" \
        --keyring="${KEYRING_NAME}" \
        --purpose=encryption 2>> "${LOG_FILE}"; then
        log_success "Created KMS key: ${KEY_NAME}"
    else
        log_error "Failed to create KMS key"
        exit 1
    fi
    
    # Store key resource name
    KEY_RESOURCE_NAME="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"
    log_info "Key resource name: ${KEY_RESOURCE_NAME}"
}

# Create Confidential GKE cluster
create_confidential_gke() {
    log_info "Creating Confidential GKE cluster with hardware encryption..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Confidential GKE cluster: ${CLUSTER_NAME}"
        return 0
    fi
    
    # Create Confidential GKE cluster
    if gcloud container clusters create "${CLUSTER_NAME}" \
        --zone="${ZONE}" \
        --machine-type=n2d-standard-4 \
        --num-nodes=2 \
        --enable-confidential-nodes \
        --disk-encryption-key="${KEY_RESOURCE_NAME}" \
        --enable-ip-alias \
        --enable-autorepair \
        --enable-autoupgrade \
        --logging=SYSTEM,WORKLOAD \
        --monitoring=SYSTEM \
        --cluster-version=latest \
        --quiet 2>> "${LOG_FILE}"; then
        log_success "Created Confidential GKE cluster: ${CLUSTER_NAME}"
    else
        log_error "Failed to create Confidential GKE cluster"
        exit 1
    fi
    
    # Get cluster credentials
    if gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone="${ZONE}" 2>> "${LOG_FILE}"; then
        log_success "Retrieved cluster credentials"
    else
        log_error "Failed to get cluster credentials"
        exit 1
    fi
    
    # Verify confidential computing
    log_info "Verifying confidential computing configuration..."
    kubectl get nodes -o wide >> "${LOG_FILE}" 2>&1
}

# Create BigQuery dataset with CMEK
create_bigquery_dataset() {
    log_info "Creating BigQuery dataset with customer-managed encryption..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create BigQuery dataset: ${DATASET_NAME}"
        return 0
    fi
    
    # Create BigQuery dataset with CMEK
    if bq mk --dataset \
        --location="${REGION}" \
        --default_kms_key="${KEY_RESOURCE_NAME}" \
        --description="Privacy-preserving analytics dataset with CMEK" \
        "${PROJECT_ID}:${DATASET_NAME}" 2>> "${LOG_FILE}"; then
        log_success "Created BigQuery dataset: ${DATASET_NAME}"
    else
        log_error "Failed to create BigQuery dataset"
        exit 1
    fi
    
    # Create sample table
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.patient_analytics" \
        patient_id:STRING,age:INTEGER,diagnosis:STRING,treatment_cost:FLOAT,region:STRING,admission_date:DATE 2>> "${LOG_FILE}"; then
        log_success "Created sample table: patient_analytics"
    else
        log_error "Failed to create sample table"
        exit 1
    fi
    
    # Insert sample data
    log_info "Inserting sample healthcare data..."
    if bq query --use_legacy_sql=false \
        --destination_table="${PROJECT_ID}:${DATASET_NAME}.patient_analytics" \
        --replace \
        "SELECT 
           CONCAT('PATIENT_', LPAD(CAST(ROW_NUMBER() OVER() AS STRING), 6, '0')) as patient_id,
           CAST(RAND() * 80 + 20 AS INT64) as age,
           CASE CAST(RAND() * 5 AS INT64)
               WHEN 0 THEN 'Diabetes'
               WHEN 1 THEN 'Hypertension'
               WHEN 2 THEN 'Heart Disease'
               WHEN 3 THEN 'Cancer'
               ELSE 'Respiratory Disease'
           END as diagnosis,
           ROUND(RAND() * 50000 + 5000, 2) as treatment_cost,
           CASE CAST(RAND() * 4 AS INT64)
               WHEN 0 THEN 'North'
               WHEN 1 THEN 'South'
               WHEN 2 THEN 'East'
               ELSE 'West'
           END as region,
           DATE_SUB(CURRENT_DATE(), INTERVAL CAST(RAND() * 365 AS INT64) DAY) as admission_date
       FROM UNNEST(GENERATE_ARRAY(1, 10000)) as num" 2>> "${LOG_FILE}"; then
        log_success "Inserted sample healthcare data"
    else
        log_error "Failed to insert sample data"
        exit 1
    fi
}

# Deploy privacy-preserving analytics application
deploy_analytics_app() {
    log_info "Deploying privacy-preserving analytics application..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy analytics application to Confidential GKE"
        return 0
    fi
    
    # Create application manifest
    cat > "${SCRIPT_DIR}/analytics-app.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: privacy-analytics-app
  labels:
    app: privacy-analytics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: privacy-analytics
  template:
    metadata:
      labels:
        app: privacy-analytics
    spec:
      serviceAccountName: default
      containers:
      - name: analytics-processor
        image: python:3.11-slim
        command: ["/bin/bash"]
        args:
          - -c
          - |
            pip install --no-cache-dir google-cloud-bigquery==3.11.4 google-cloud-kms==2.21.0
            python -c "
            from google.cloud import bigquery
            import os
            import time
            import logging
            
            # Configure logging
            logging.basicConfig(level=logging.INFO)
            logger = logging.getLogger(__name__)
            
            # Initialize BigQuery client
            client = bigquery.Client()
            dataset_id = os.environ['DATASET_NAME']
            
            logger.info(f'Starting privacy-preserving analytics for dataset: {dataset_id}')
            
            while True:
                try:
                    logger.info('Processing encrypted analytics...')
                    
                    # Execute privacy-preserving query with aggregation
                    query = f'''
                    SELECT 
                        diagnosis,
                        region,
                        COUNT(*) as patient_count,
                        AVG(age) as avg_age,
                        AVG(treatment_cost) as avg_cost,
                        STDDEV(treatment_cost) as cost_stddev
                    FROM \\\`{dataset_id}.patient_analytics\\\`
                    WHERE admission_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                    GROUP BY diagnosis, region
                    HAVING COUNT(*) >= 5
                    ORDER BY patient_count DESC
                    '''
                    
                    results = client.query(query)
                    logger.info('Analytics results (encrypted processing):')
                    for row in results:
                        logger.info(f'  {row.diagnosis} in {row.region}: {row.patient_count} patients, '
                                  f'avg age {row.avg_age:.1f}, avg cost \${row.avg_cost:.2f}')
                except Exception as e:
                    logger.error(f'Analytics error: {e}')
                
                time.sleep(60)  # Process every minute
            "
        env:
        - name: DATASET_NAME
          value: "${PROJECT_ID}:${DATASET_NAME}"
        - name: GOOGLE_CLOUD_PROJECT
          value: "${PROJECT_ID}"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 65534
          capabilities:
            drop:
            - ALL
---
apiVersion: v1
kind: Service
metadata:
  name: privacy-analytics-service
spec:
  selector:
    app: privacy-analytics
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF
    
    # Deploy the application
    if kubectl apply -f "${SCRIPT_DIR}/analytics-app.yaml" 2>> "${LOG_FILE}"; then
        log_success "Applied analytics application manifest"
    else
        log_error "Failed to apply analytics application"
        exit 1
    fi
    
    # Wait for deployment
    log_info "Waiting for application deployment..."
    if kubectl wait deployment/privacy-analytics-app \
        --for=condition=Available \
        --timeout=300s 2>> "${LOG_FILE}"; then
        log_success "Analytics application deployed successfully"
    else
        log_error "Analytics application deployment timed out"
        exit 1
    fi
}

# Create privacy-preserving analytics views
create_analytics_views() {
    log_info "Creating privacy-preserving analytics views..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create privacy-preserving BigQuery views"
        return 0
    fi
    
    # Create privacy analytics summary view
    bq query --use_legacy_sql=false << EOF 2>> "${LOG_FILE}"
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.privacy_analytics_summary\` AS
SELECT
  diagnosis,
  region,
  COUNT(*) as patient_count,
  APPROX_QUANTILES(age, 4)[OFFSET(2)] as median_age,
  ROUND(STDDEV(treatment_cost), 2) as cost_variance,
  CASE 
    WHEN COUNT(*) >= 10 THEN ROUND(AVG(treatment_cost), 2)
    ELSE NULL 
  END as avg_treatment_cost,
  DATE_TRUNC(MIN(admission_date), MONTH) as earliest_admission_month
FROM \`${PROJECT_ID}.${DATASET_NAME}.patient_analytics\`
GROUP BY diagnosis, region
HAVING COUNT(*) >= 10
ORDER BY patient_count DESC;
EOF
    
    # Create compliance report view
    bq query --use_legacy_sql=false << EOF 2>> "${LOG_FILE}"
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.compliance_report\` AS
SELECT
  'Healthcare Analytics Report' as report_type,
  CURRENT_DATETIME() as generated_at,
  COUNT(DISTINCT diagnosis) as unique_diagnoses,
  COUNT(DISTINCT region) as regions_covered,
  COUNT(*) as total_encrypted_records,
  AVG(treatment_cost) as overall_avg_cost,
  'CMEK Encrypted with Hardware-level Privacy Protection' as encryption_status
FROM \`${PROJECT_ID}.${DATASET_NAME}.patient_analytics\`;
EOF
    
    log_success "Created privacy-preserving analytics views"
}

# Create Cloud Storage resources for ML
create_storage_resources() {
    log_info "Creating Cloud Storage bucket for ML training..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud Storage bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
        log_success "Created Cloud Storage bucket: ${BUCKET_NAME}"
    else
        log_error "Failed to create Cloud Storage bucket"
        exit 1
    fi
    
    # Enable bucket encryption
    if gsutil kms encryption -k "${KEY_RESOURCE_NAME}" "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
        log_success "Enabled CMEK encryption for bucket"
    else
        log_error "Failed to enable bucket encryption"
        exit 1
    fi
}

# Run validation tests
run_validation() {
    log_info "Running validation tests..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would run validation tests"
        return 0
    fi
    
    # Test BigQuery encryption
    log_info "Validating BigQuery encryption configuration..."
    local encryption_config
    encryption_config=$(bq show --format=prettyjson "${PROJECT_ID}:${DATASET_NAME}" | jq '.defaultEncryptionConfiguration' 2>/dev/null || echo "null")
    if [[ "${encryption_config}" != "null" ]]; then
        log_success "BigQuery CMEK encryption verified"
    else
        log_warning "Could not verify BigQuery encryption configuration"
    fi
    
    # Test Confidential GKE
    log_info "Validating Confidential GKE configuration..."
    if kubectl get nodes -o jsonpath='{.items[*].metadata.labels}' | grep -q 'cloud\.google\.com/gke-confidential-nodes'; then
        log_success "Confidential GKE nodes verified"
    else
        log_warning "Could not verify Confidential GKE configuration"
    fi
    
    # Test analytics application
    log_info "Checking analytics application status..."
    if kubectl get pods -l app=privacy-analytics --field-selector=status.phase=Running | grep -q privacy-analytics; then
        log_success "Analytics application is running"
    else
        log_warning "Analytics application may not be fully ready"
    fi
    
    log_success "Validation completed"
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Resource Suffix: ${RANDOM_SUFFIX}"
    log_info ""
    log_info "Created Resources:"
    log_info "- Confidential GKE Cluster: ${CLUSTER_NAME}"
    log_info "- KMS Key Ring: ${KEYRING_NAME}"
    log_info "- KMS Key: ${KEY_NAME}"
    log_info "- BigQuery Dataset: ${DATASET_NAME}"
    log_info "- Cloud Storage Bucket: ${BUCKET_NAME}"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Monitor analytics application: kubectl logs deployment/privacy-analytics-app -f"
    log_info "2. Query privacy-preserving views: bq query 'SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.privacy_analytics_summary\` LIMIT 5'"
    log_info "3. View compliance report: bq query 'SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.compliance_report\`'"
    log_info ""
    log_info "Cleanup: Run destroy.sh when finished testing"
    log_info "Log file: ${LOG_FILE}"
}

# Main deployment function
main() {
    log_info "Starting Privacy-Preserving Analytics deployment"
    log_info "Log file: ${LOG_FILE}"
    
    # Parse arguments and set defaults
    parse_arguments "$@"
    set_defaults
    
    # Show configuration
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    validate_prerequisites
    configure_gcloud
    enable_apis
    create_kms_resources
    create_confidential_gke
    create_bigquery_dataset
    deploy_analytics_app
    create_analytics_views
    create_storage_resources
    run_validation
    
    # Show summary
    show_deployment_summary
    
    log_success "Privacy-preserving analytics infrastructure deployed successfully!"
    log_info "Total deployment time: $((SECONDS / 60)) minutes"
}

# Run main function with all arguments
main "$@"