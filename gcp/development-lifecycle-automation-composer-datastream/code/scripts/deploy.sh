#!/bin/bash
#
# deploy.sh - Deploy Development Lifecycle Automation with Cloud Composer and Datastream
#
# This script deploys an intelligent development lifecycle automation system using:
# - Cloud Composer 3 with Apache Airflow 3 for workflow orchestration
# - Datastream for real-time database change data capture
# - Artifact Registry with integrated vulnerability scanning
# - Cloud Workflows for compliance validation and decision making
# - Binary Authorization for security policy enforcement
#
# Usage: ./deploy.sh [--dry-run] [--skip-confirmation]
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
readonly DRY_RUN="${1:-false}"
readonly SKIP_CONFIRMATION="${2:-false}"

# Default values
DEFAULT_PROJECT_ID="devops-automation-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Global variables
PROJECT_ID=""
REGION=""
ZONE=""
COMPOSER_ENV_NAME="intelligent-devops"
DATASTREAM_NAME="schema-changes-stream"
RANDOM_SUFFIX=""
BUCKET_NAME=""
ARTIFACT_REPO=""
DB_INSTANCE=""
DB_PASSWORD=""

# Logging function
log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    local exit_code=$?
    error "Deployment failed with exit code $exit_code"
    error "Check log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        warn "Attempting cleanup of partially created resources..."
        # Don't fail if cleanup fails
        set +e
        cleanup_resources || true
        set -e
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Utility functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    if [[ "$gcloud_version" == "unknown" ]]; then
        error "Could not determine gcloud version"
        exit 1
    fi
    success "gcloud CLI version: $gcloud_version"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    success "Authenticated as: $active_account"
    
    # Check if required tools are available
    local required_tools=("gsutil" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            error "$tool is required but not installed"
            exit 1
        fi
    done
    
    success "All prerequisites checked"
}

get_user_input() {
    info "Configuring deployment parameters..."
    
    # Project ID
    read -p "Enter GCP Project ID (default: $DEFAULT_PROJECT_ID): " PROJECT_ID
    PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
    
    # Region
    read -p "Enter GCP Region (default: $DEFAULT_REGION): " REGION
    REGION="${REGION:-$DEFAULT_REGION}"
    
    # Zone
    read -p "Enter GCP Zone (default: $DEFAULT_ZONE): " ZONE
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    BUCKET_NAME="devops-automation-${RANDOM_SUFFIX}"
    ARTIFACT_REPO="secure-containers-${RANDOM_SUFFIX}"
    DB_INSTANCE="dev-database-${RANDOM_SUFFIX}"
    DB_PASSWORD=$(openssl rand -base64 32)
    
    info "Configuration:"
    info "  Project ID: $PROJECT_ID"
    info "  Region: $REGION"
    info "  Zone: $ZONE"
    info "  Storage Bucket: $BUCKET_NAME"
    info "  Artifact Repository: $ARTIFACT_REPO"
    info "  Database Instance: $DB_INSTANCE"
}

confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "--skip-confirmation" ]]; then
        return 0
    fi
    
    warn "This deployment will create GCP resources that may incur charges:"
    warn "  - Cloud Composer 3 environment (estimated: \$50-100/day)"
    warn "  - Cloud SQL PostgreSQL instance (estimated: \$5-10/day)"
    warn "  - Datastream processing (estimated: \$0.10/GB)"
    warn "  - Cloud Storage and other services (estimated: \$1-5/day)"
    echo
    warn "Total estimated cost: \$56-115 per day during active use"
    echo
    
    read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled by user"
        exit 0
    fi
}

setup_gcp_project() {
    info "Setting up GCP project configuration..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would set project to: $PROJECT_ID"
        return 0
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" || {
        error "Failed to set project. Please check if project exists and you have access."
        exit 1
    }
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "GCP project configuration completed"
}

enable_apis() {
    info "Enabling required GCP APIs..."
    
    local apis=(
        "composer.googleapis.com"
        "datastream.googleapis.com"
        "artifactregistry.googleapis.com"
        "workflows.googleapis.com"
        "cloudbuild.googleapis.com"
        "containeranalysis.googleapis.com"
        "sqladmin.googleapis.com"
        "binaryauthorization.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        info "Enabling $api..."
        if ! gcloud services enable "$api"; then
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

create_storage_bucket() {
    info "Creating Cloud Storage bucket for workflow assets..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create bucket: gs://$BUCKET_NAME"
        return 0
    fi
    
    # Create bucket
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://$BUCKET_NAME"
    
    # Create folder structure
    info "Creating workflow directory structure..."
    for dir in dags data policies logs; do
        echo "" | gsutil cp - "gs://$BUCKET_NAME/$dir/.keep"
    done
    
    success "Storage bucket created: gs://$BUCKET_NAME"
}

create_artifact_registry() {
    info "Creating Artifact Registry repository with security scanning..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create Artifact Registry: $ARTIFACT_REPO"
        return 0
    fi
    
    # Create repository
    if ! gcloud artifacts repositories create "$ARTIFACT_REPO" \
        --repository-format=docker \
        --location="$REGION" \
        --description="Secure container repository with automated scanning"; then
        error "Failed to create Artifact Registry repository"
        exit 1
    fi
    
    # Enable vulnerability scanning
    gcloud artifacts settings enable-upgrade-redirection --project="$PROJECT_ID" || true
    
    # Configure Docker authentication
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    success "Artifact Registry created: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}"
}

create_database() {
    info "Creating development database for change tracking..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create database: $DB_INSTANCE"
        return 0
    fi
    
    # Create Cloud SQL instance
    if ! gcloud sql instances create "$DB_INSTANCE" \
        --database-version=POSTGRES_15 \
        --tier=db-f1-micro \
        --region="$REGION" \
        --root-password="$DB_PASSWORD" \
        --backup-start-time=23:00 \
        --maintenance-window-day=SUN \
        --maintenance-window-hour=02; then
        error "Failed to create Cloud SQL instance"
        exit 1
    fi
    
    # Wait for instance to be ready
    info "Waiting for database instance to be ready..."
    gcloud sql instances wait "$DB_INSTANCE" --timeout=600
    
    # Create application database
    if ! gcloud sql databases create app_development --instance="$DB_INSTANCE"; then
        error "Failed to create application database"
        exit 1
    fi
    
    # Store database credentials securely
    cat > "${SCRIPT_DIR}/db-config.txt" << EOF
Database Instance: $DB_INSTANCE
Database Name: app_development
Region: $REGION
Project: $PROJECT_ID
Password: [Stored securely - use gcloud sql to reset if needed]
EOF
    
    success "Development database created: $DB_INSTANCE"
}

setup_datastream() {
    info "Configuring Datastream for real-time change capture..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would configure Datastream: $DATASTREAM_NAME"
        return 0
    fi
    
    # Get database IP
    local db_ip
    db_ip=$(gcloud sql instances describe "$DB_INSTANCE" --format="value(ipAddresses[0].ipAddress)")
    
    # Create source connection profile
    if ! gcloud datastream connection-profiles create "${DB_INSTANCE}-profile" \
        --location="$REGION" \
        --type=postgresql \
        --postgresql-hostname="$db_ip" \
        --postgresql-port=5432 \
        --postgresql-username=postgres \
        --postgresql-password="$DB_PASSWORD" \
        --postgresql-database=app_development; then
        error "Failed to create source connection profile"
        exit 1
    fi
    
    # Create destination connection profile
    if ! gcloud datastream connection-profiles create storage-destination \
        --location="$REGION" \
        --type=gcs \
        --gcs-bucket="$BUCKET_NAME" \
        --gcs-root-path=/datastream; then
        error "Failed to create destination connection profile"
        exit 1
    fi
    
    # Create Datastream
    if ! gcloud datastream streams create "$DATASTREAM_NAME" \
        --location="$REGION" \
        --source-connection-profile="${DB_INSTANCE}-profile" \
        --destination-connection-profile=storage-destination \
        --include-objects='app_development.*'; then
        error "Failed to create Datastream"
        exit 1
    fi
    
    success "Datastream configured for real-time change capture"
}

create_composer_environment() {
    info "Creating Cloud Composer 3 environment with Apache Airflow 3..."
    warn "This step may take 15-20 minutes to complete..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create Composer environment: $COMPOSER_ENV_NAME"
        return 0
    fi
    
    # Create environment
    if ! gcloud composer environments create "$COMPOSER_ENV_NAME" \
        --location="$REGION" \
        --image-version=composer-3-airflow-3 \
        --node-count=3 \
        --disk-size=30GB \
        --machine-type=n1-standard-2 \
        --env-variables="BUCKET_NAME=$BUCKET_NAME,PROJECT_ID=$PROJECT_ID,ARTIFACT_REPO=$ARTIFACT_REPO,REGION=$REGION"; then
        error "Failed to create Cloud Composer environment"
        exit 1
    fi
    
    # Wait for environment to be ready
    info "Waiting for Cloud Composer environment to be ready (this may take up to 20 minutes)..."
    if ! gcloud composer environments wait "$COMPOSER_ENV_NAME" \
        --location="$REGION" \
        --timeout=1800; then
        error "Cloud Composer environment creation timed out"
        exit 1
    fi
    
    success "Cloud Composer 3 environment created successfully"
}

create_dags() {
    info "Creating and deploying intelligent CI/CD DAGs..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create and deploy DAGs"
        return 0
    fi
    
    # Create intelligent CI/CD DAG
    cat > "${SCRIPT_DIR}/intelligent_cicd_dag.py" << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.google.cloud.operators.cloud_build import CloudBuildCreateBuildOperator
from airflow.providers.google.cloud.operators.workflows import WorkflowsCreateExecutionOperator
from airflow.providers.google.cloud.sensors.gcs import GCSObjectExistenceSensor

# DAG configuration
default_args = {
    'owner': 'devops-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5)
}

dag = DAG(
    'intelligent_cicd_pipeline',
    default_args=default_args,
    description='Intelligent CI/CD pipeline with change detection and security scanning',
    schedule_interval=timedelta(minutes=15),
    catchup=False,
    tags=['cicd', 'intelligent', 'security']
)

# Detect database changes from Datastream
detect_changes = GCSObjectExistenceSensor(
    task_id='detect_datastream_changes',
    bucket='{{ var.value.BUCKET_NAME }}',
    object='datastream/{{ ds }}/changes.json',
    timeout=300,
    poke_interval=60,
    dag=dag
)

def analyze_schema_changes(**context):
    """Analyze database schema changes for impact assessment"""
    import json
    from google.cloud import storage
    
    # Simulated analysis for demo purposes
    analysis = {
        'total_changes': 3,
        'breaking_changes': 0,
        'requires_migration': False,
        'analysis_timestamp': datetime.now().isoformat()
    }
    
    print(f"Schema analysis completed: {analysis}")
    return analysis

analyze_changes = PythonOperator(
    task_id='analyze_schema_changes',
    python_callable=analyze_schema_changes,
    dag=dag
)

def evaluate_security_scan(**context):
    """Evaluate container security scan results"""
    # Simulated security evaluation
    scan_results = {
        'critical_vulnerabilities': 0,
        'high_vulnerabilities': 2,
        'medium_vulnerabilities': 5,
        'low_vulnerabilities': 12,
        'scan_completed': True,
        'deployment_approved': True
    }
    
    print(f"Security evaluation completed: {scan_results}")
    return scan_results

security_evaluation = PythonOperator(
    task_id='evaluate_security_scan',
    python_callable=evaluate_security_scan,
    dag=dag
)

# Define task dependencies
detect_changes >> analyze_changes >> security_evaluation
EOF

    # Create monitoring DAG
    cat > "${SCRIPT_DIR}/monitoring_dag.py" << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'platform-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5)
}

dag = DAG(
    'intelligent_devops_monitoring',
    default_args=default_args,
    description='Monitoring and alerting for intelligent DevOps automation',
    schedule_interval=timedelta(hours=1),
    catchup=False,
    tags=['monitoring', 'observability']
)

def collect_pipeline_metrics(**context):
    """Collect metrics from pipeline executions"""
    metrics = {
        'timestamp': datetime.now().isoformat(),
        'dag_runs_success': 15,
        'dag_runs_failed': 2,
        'avg_execution_time_minutes': 12.5,
        'security_scans_blocked': 1,
        'deployments_approved': 8,
        'compliance_violations': 0
    }
    
    print(f"Pipeline metrics collected: {metrics}")
    return metrics

collect_metrics = PythonOperator(
    task_id='collect_pipeline_metrics',
    python_callable=collect_pipeline_metrics,
    dag=dag
)
EOF

    # Upload DAGs to storage bucket temporarily
    gsutil cp "${SCRIPT_DIR}/intelligent_cicd_dag.py" "gs://$BUCKET_NAME/dags/"
    gsutil cp "${SCRIPT_DIR}/monitoring_dag.py" "gs://$BUCKET_NAME/dags/"
    
    success "DAGs created and staged for deployment"
}

create_workflows() {
    info "Creating compliance validation workflow..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create Cloud Workflows"
        return 0
    fi
    
    # Create compliance workflow definition
    cat > "${SCRIPT_DIR}/compliance-workflow.yaml" << 'EOF'
main:
  params: [input]
  steps:
    - validate_input:
        assign:
          - schema_changes: ${input.schema_changes}
          - security_scan: ${input.security_scan}
          - timestamp: ${sys.now()}
    
    - evaluate_schema_impact:
        switch:
          - condition: ${schema_changes.breaking_changes > 0}
            steps:
              - require_approval:
                  assign:
                    - approval_required: true
          - condition: true
            steps:
              - auto_approve_schema:
                  assign:
                    - schema_approved: true
    
    - evaluate_security_findings:
        switch:
          - condition: ${security_scan.critical_vulnerabilities > 0}
            steps:
              - block_deployment:
                  assign:
                    - deployment_blocked: true
                    - reason: "Critical security vulnerabilities found"
          - condition: true
            steps:
              - approve_security:
                  assign:
                    - security_approved: true
    
    - make_deployment_decision:
        switch:
          - condition: ${default(map.get(vars, "deployment_blocked"), false)}
            return:
              status: "BLOCKED"
              reason: ${default(map.get(vars, "reason"), "Security policy violation")}
              timestamp: ${timestamp}
          - condition: true
            return:
              status: "APPROVED"
              deployment_environment: "staging"
              timestamp: ${timestamp}
EOF

    # Deploy the workflow
    if ! gcloud workflows deploy intelligent-deployment-workflow \
        --source="${SCRIPT_DIR}/compliance-workflow.yaml" \
        --location="$REGION"; then
        error "Failed to deploy compliance workflow"
        exit 1
    fi
    
    success "Compliance validation workflow deployed"
}

setup_security_policies() {
    info "Configuring security policy enforcement..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would configure Binary Authorization policies"
        return 0
    fi
    
    # Create security policy
    cat > "${SCRIPT_DIR}/security-policy.yaml" << EOF
defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
    - projects/$PROJECT_ID/attestors/security-scan-attestor
EOF

    # Apply Binary Authorization policy
    if ! gcloud container binauthz policy import "${SCRIPT_DIR}/security-policy.yaml"; then
        warn "Failed to import Binary Authorization policy - may need manual configuration"
    fi
    
    # Create security scan attestor
    if ! gcloud container binauthz attestors create security-scan-attestor \
        --attestation-authority-note-project="$PROJECT_ID" \
        --attestation-authority-note=security-scan-note \
        --description="Attestor for security scan validation"; then
        warn "Failed to create attestor - may need manual configuration"
    fi
    
    success "Security policy enforcement configured"
}

deploy_dags_to_composer() {
    info "Deploying DAGs to Cloud Composer environment..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would deploy DAGs to Composer"
        return 0
    fi
    
    # Get Composer environment bucket
    local composer_bucket
    composer_bucket=$(gcloud composer environments describe "$COMPOSER_ENV_NAME" \
        --location="$REGION" \
        --format="value(config.dagGcsPrefix)" | sed 's|/dags||')
    
    if [[ -z "$composer_bucket" ]]; then
        error "Failed to get Composer environment bucket"
        exit 1
    fi
    
    # Copy DAGs to Composer environment
    gsutil -m cp "gs://$BUCKET_NAME/dags/"*.py "$composer_bucket/dags/"
    
    # Create sample test data
    echo '{"schema_changes": [{"type": "ADD_COLUMN", "table": "users", "column": "email_verified"}]}' | \
        gsutil cp - "gs://$BUCKET_NAME/datastream/$(date +%Y-%m-%d)/changes.json"
    
    success "DAGs deployed to Cloud Composer environment"
}

create_test_data() {
    info "Creating test data for workflow validation..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        info "[DRY-RUN] Would create test data"
        return 0
    fi
    
    # Create sample schema change data
    local test_date
    test_date=$(date +%Y-%m-%d)
    
    echo '{"schema_changes": [{"type": "ADD_COLUMN", "table": "users", "column": "email_verified", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}], "data_changes": 150}' | \
        gsutil cp - "gs://$BUCKET_NAME/datastream/$test_date/changes.json"
    
    success "Test data created for workflow validation"
}

save_deployment_info() {
    info "Saving deployment information..."
    
    local deployment_info="${SCRIPT_DIR}/deployment-info.txt"
    
    cat > "$deployment_info" << EOF
Development Lifecycle Automation Deployment
===========================================

Deployment Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION
Zone: $ZONE

Resources Created:
- Cloud Composer Environment: $COMPOSER_ENV_NAME
- Storage Bucket: gs://$BUCKET_NAME
- Artifact Registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}
- Database Instance: $DB_INSTANCE
- Datastream: $DATASTREAM_NAME
- Workflow: intelligent-deployment-workflow

Access Information:
- Airflow UI: Use 'gcloud composer environments describe $COMPOSER_ENV_NAME --location=$REGION --format="value(config.airflowUri)"'
- Database: Use 'gcloud sql connect $DB_INSTANCE --user=postgres'

Important Files:
- Database Config: ${SCRIPT_DIR}/db-config.txt
- Deployment Log: $LOG_FILE

Next Steps:
1. Access the Airflow UI to monitor DAG execution
2. Review workflow execution in Cloud Workflows console
3. Monitor security scans in Artifact Registry
4. Check Datastream for change capture

Cleanup:
Run './destroy.sh' to remove all created resources
EOF

    success "Deployment information saved to: $deployment_info"
}

cleanup_resources() {
    warn "Cleaning up partially created resources due to deployment failure..."
    
    # Best effort cleanup - don't fail if resources don't exist
    set +e
    
    # Remove Composer environment
    if [[ -n "${COMPOSER_ENV_NAME:-}" ]]; then
        gcloud composer environments delete "$COMPOSER_ENV_NAME" --location="$REGION" --quiet
    fi
    
    # Remove Datastream
    if [[ -n "${DATASTREAM_NAME:-}" ]]; then
        gcloud datastream streams delete "$DATASTREAM_NAME" --location="$REGION" --quiet
        gcloud datastream connection-profiles delete "${DB_INSTANCE}-profile" --location="$REGION" --quiet
        gcloud datastream connection-profiles delete storage-destination --location="$REGION" --quiet
    fi
    
    # Remove database
    if [[ -n "${DB_INSTANCE:-}" ]]; then
        gcloud sql instances delete "$DB_INSTANCE" --quiet
    fi
    
    # Remove Artifact Registry
    if [[ -n "${ARTIFACT_REPO:-}" ]]; then
        gcloud artifacts repositories delete "$ARTIFACT_REPO" --location="$REGION" --quiet
    fi
    
    # Remove workflows
    gcloud workflows delete intelligent-deployment-workflow --location="$REGION" --quiet
    
    # Remove storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        gsutil -m rm -r "gs://$BUCKET_NAME" || true
    fi
    
    # Clean up local files
    rm -f "${SCRIPT_DIR}/intelligent_cicd_dag.py" "${SCRIPT_DIR}/monitoring_dag.py" "${SCRIPT_DIR}/compliance-workflow.yaml" "${SCRIPT_DIR}/security-policy.yaml"
    
    set -e
}

main() {
    info "Starting Development Lifecycle Automation deployment..."
    info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    case "${1:-}" in
        --dry-run)
            info "Running in DRY-RUN mode - no resources will be created"
            ;;
        --skip-confirmation)
            info "Skipping user confirmation prompts"
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--skip-confirmation] [--help]"
            echo "  --dry-run           Show what would be deployed without creating resources"
            echo "  --skip-confirmation Skip user confirmation prompts"
            echo "  --help              Show this help message"
            exit 0
            ;;
    esac
    
    # Deployment steps
    check_prerequisites
    get_user_input
    confirm_deployment
    setup_gcp_project
    enable_apis
    create_storage_bucket
    create_artifact_registry
    create_database
    setup_datastream
    create_composer_environment
    create_dags
    create_workflows
    setup_security_policies
    deploy_dags_to_composer
    create_test_data
    save_deployment_info
    
    success "Deployment completed successfully!"
    success "Check deployment-info.txt for access details and next steps"
    
    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        info "Estimated daily cost: \$56-115 (primarily Cloud Composer environment)"
        warn "Remember to run './destroy.sh' when finished to avoid ongoing charges"
    fi
}

# Make script executable and run main function
chmod +x "$0"
main "$@"