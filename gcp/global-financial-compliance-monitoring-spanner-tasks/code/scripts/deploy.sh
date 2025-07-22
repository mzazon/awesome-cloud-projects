#!/bin/bash

# Global Financial Compliance Monitoring with Cloud Spanner and Cloud Tasks
# Deployment Script for GCP
# 
# This script deploys a comprehensive financial compliance monitoring system
# using Cloud Spanner for global consistency and Cloud Tasks for reliable processing.

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

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_NODES=2
DRY_RUN=false
SKIP_CONFIRMATION=false

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
        --spanner-nodes)
            SPANNER_NODES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Deploy financial compliance monitoring system on GCP.

OPTIONS:
    --project-id PROJECT_ID     GCP Project ID (required)
    --region REGION            GCP region (default: $DEFAULT_REGION)
    --spanner-nodes NODES      Number of Spanner nodes (default: $DEFAULT_NODES)
    --dry-run                  Show what would be deployed without executing
    --skip-confirmation        Skip confirmation prompts
    --help                     Show this help message

EXAMPLES:
    $0 --project-id my-compliance-project
    $0 --project-id my-project --region us-east1 --spanner-nodes 3
    $0 --project-id my-project --dry-run

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID:-}" ]]; then
    error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
fi

# Set defaults
REGION=${REGION:-$DEFAULT_REGION}
SPANNER_NODES=${SPANNER_NODES:-$DEFAULT_NODES}
SPANNER_INSTANCE="compliance-monitor"
SPANNER_DATABASE="financial-compliance"
TASK_QUEUE="compliance-checks"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 4)
SERVICE_ACCOUNT="compliance-monitor-sa-${RANDOM_SUFFIX}"

log "Starting deployment of Financial Compliance Monitoring System"
log "Project ID: $PROJECT_ID"
log "Region: $REGION"
log "Spanner Instance: $SPANNER_INSTANCE"
log "Spanner Nodes: $SPANNER_NODES"
log "Service Account: $SERVICE_ACCOUNT"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be created"
fi

# Function to run commands with dry-run support
run_command() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
    else
        echo "  Executing: $cmd"
        eval "$cmd"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Project '$PROJECT_ID' does not exist or is not accessible"
    fi
    
    # Validate region
    if ! gcloud compute regions describe "$REGION" &>/dev/null; then
        error "Invalid region: $REGION"
    fi
    
    # Validate Spanner node count
    if [[ ! "$SPANNER_NODES" =~ ^[1-9][0-9]*$ ]] || [[ "$SPANNER_NODES" -lt 1 ]]; then
        error "Spanner nodes must be a positive integer"
    fi
    
    success "Prerequisites check passed"
}

# Cost estimation
estimate_costs() {
    log "Estimating monthly costs..."
    
    # Spanner costs (approximate)
    local spanner_cost_per_node=731  # USD per node per month (regional config)
    local spanner_cost=$((SPANNER_NODES * spanner_cost_per_node))
    
    # Cloud Functions costs (estimate based on invocations)
    local functions_cost=50  # Estimated monthly cost for compliance processing
    
    # Cloud Tasks costs (minimal for most workloads)
    local tasks_cost=10
    
    # Storage costs (minimal for compliance logs)
    local storage_cost=20
    
    local total_cost=$((spanner_cost + functions_cost + tasks_cost + storage_cost))
    
    echo "Estimated monthly costs:"
    echo "  Cloud Spanner ($SPANNER_NODES nodes): \$${spanner_cost}"
    echo "  Cloud Functions: \$${functions_cost}"
    echo "  Cloud Tasks: \$${tasks_cost}"
    echo "  Storage & Logging: \$${storage_cost}"
    echo "  Total: \$${total_cost}"
    echo ""
    warning "This is an estimate. Actual costs may vary based on usage patterns."
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Set up project configuration
setup_project() {
    log "Setting up project configuration..."
    
    run_command "gcloud config set project $PROJECT_ID" "Setting project"
    run_command "gcloud config set compute/region $REGION" "Setting region"
    
    success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "spanner.googleapis.com"
        "cloudtasks.googleapis.com" 
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        run_command "gcloud services enable $api" "Enabling $api"
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "All required APIs enabled"
}

# Create service account
create_service_account() {
    log "Creating service account for compliance monitoring..."
    
    run_command "gcloud iam service-accounts create $SERVICE_ACCOUNT \
        --display-name='Compliance Monitor Service Account' \
        --description='Service account for financial compliance monitoring'" \
        "Creating service account"
    
    # Grant necessary IAM roles
    local roles=(
        "roles/spanner.databaseUser"
        "roles/cloudtasks.enqueuer"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
        "roles/pubsub.publisher"
        "roles/storage.objectCreator"
    )
    
    for role in "${roles[@]}"; do
        run_command "gcloud projects add-iam-policy-binding $PROJECT_ID \
            --member='serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com' \
            --role='$role'" \
            "Granting role $role"
    done
    
    success "Service account created and configured"
}

# Create Cloud Spanner instance and database
create_spanner_resources() {
    log "Creating Cloud Spanner instance and database..."
    
    run_command "gcloud spanner instances create $SPANNER_INSTANCE \
        --config=regional-$REGION \
        --description='Financial compliance monitoring instance' \
        --nodes=$SPANNER_NODES" \
        "Creating Spanner instance"
    
    run_command "gcloud spanner databases create $SPANNER_DATABASE \
        --instance=$SPANNER_INSTANCE" \
        "Creating Spanner database"
    
    # Create database schema
    log "Creating database schema..."
    
    local transactions_ddl="CREATE TABLE transactions (
        transaction_id STRING(36) NOT NULL,
        account_id STRING(36) NOT NULL,
        amount NUMERIC NOT NULL,
        currency STRING(3) NOT NULL,
        source_country STRING(2) NOT NULL,
        destination_country STRING(2) NOT NULL,
        transaction_type STRING(50) NOT NULL,
        timestamp TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        compliance_status STRING(20) NOT NULL DEFAULT \"PENDING\",
        risk_score NUMERIC,
        kyc_verified BOOL DEFAULT false,
        aml_checked BOOL DEFAULT false,
        regulatory_flags ARRAY<STRING(MAX)>,
        created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        updated_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
    ) PRIMARY KEY (transaction_id)"
    
    local compliance_checks_ddl="CREATE TABLE compliance_checks (
        check_id STRING(36) NOT NULL,
        transaction_id STRING(36) NOT NULL,
        check_type STRING(50) NOT NULL,
        check_status STRING(20) NOT NULL,
        check_result JSON,
        checked_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        checked_by STRING(100) NOT NULL,
        regulatory_requirement STRING(100)
    ) PRIMARY KEY (check_id),
    INTERLEAVE IN PARENT transactions ON DELETE CASCADE"
    
    run_command "gcloud spanner databases ddl update $SPANNER_DATABASE \
        --instance=$SPANNER_INSTANCE \
        --ddl='$transactions_ddl'" \
        "Creating transactions table"
    
    run_command "gcloud spanner databases ddl update $SPANNER_DATABASE \
        --instance=$SPANNER_INSTANCE \
        --ddl='$compliance_checks_ddl'" \
        "Creating compliance_checks table"
    
    success "Spanner resources created successfully"
}

# Create Cloud Tasks queues
create_task_queues() {
    log "Creating Cloud Tasks queues..."
    
    run_command "gcloud tasks queues create $TASK_QUEUE \
        --location=$REGION \
        --max-concurrent-dispatches=10 \
        --max-retry-duration=3600s \
        --max-backoff=300s \
        --min-backoff=10s \
        --max-attempts=5" \
        "Creating main compliance queue"
    
    run_command "gcloud tasks queues create ${TASK_QUEUE}-dlq \
        --location=$REGION \
        --max-concurrent-dispatches=5 \
        --max-retry-duration=86400s" \
        "Creating dead letter queue"
    
    success "Task queues created successfully"
}

# Create Pub/Sub topic for event processing
create_pubsub_resources() {
    log "Creating Pub/Sub resources..."
    
    run_command "gcloud pubsub topics create compliance-events" \
        "Creating compliance events topic"
    
    run_command "gcloud pubsub subscriptions create compliance-events-sub \
        --topic=compliance-events \
        --ack-deadline=600" \
        "Creating compliance events subscription"
    
    success "Pub/Sub resources created successfully"
}

# Deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    # Create temporary directories for function code
    local base_dir="/tmp/compliance-functions-$$"
    mkdir -p "$base_dir"
    
    # Create compliance processor function
    local compliance_dir="$base_dir/compliance-processor"
    mkdir -p "$compliance_dir"
    
    cat > "$compliance_dir/main.py" << 'EOF'
import json
import logging
from datetime import datetime
from google.cloud import spanner
from google.cloud import logging as cloud_logging
from google.cloud import tasks_v2
import functions_framework

# Initialize clients
spanner_client = spanner.Client()
tasks_client = tasks_v2.CloudTasksClient()
logging_client = cloud_logging.Client()

@functions_framework.cloud_event
def process_compliance_check(cloud_event):
    """Process compliance check for financial transaction"""
    
    # Extract transaction data from event
    transaction_data = json.loads(cloud_event.data)
    transaction_id = transaction_data.get('transaction_id')
    
    # Connect to Spanner database
    instance = spanner_client.instance('compliance-monitor')
    database = instance.database('financial-compliance')
    
    # Retrieve transaction details
    with database.snapshot() as snapshot:
        results = snapshot.execute_sql(
            "SELECT * FROM transactions WHERE transaction_id = @transaction_id",
            params={'transaction_id': transaction_id},
            param_types={'transaction_id': spanner.param_types.STRING}
        )
        
        transaction = list(results)[0]
        
        # Perform compliance checks
        compliance_results = perform_compliance_checks(transaction)
        
        # Update transaction with compliance status
        update_compliance_status(database, transaction_id, compliance_results)
        
        # Log compliance check results
        log_compliance_check(transaction_id, compliance_results)
        
        return {'status': 'completed', 'transaction_id': transaction_id}

def perform_compliance_checks(transaction):
    """Perform various compliance checks on transaction"""
    results = {}
    
    # KYC Check
    results['kyc_verified'] = check_kyc_compliance(transaction)
    
    # AML Check
    results['aml_risk_score'] = calculate_aml_risk(transaction)
    
    # Cross-border compliance
    results['cross_border_compliant'] = check_cross_border_rules(transaction)
    
    # Determine overall compliance status
    results['compliance_status'] = determine_compliance_status(results)
    
    return results

def check_kyc_compliance(transaction):
    """Simulate KYC compliance check"""
    return transaction['amount'] < 10000

def calculate_aml_risk(transaction):
    """Calculate AML risk score"""
    risk_score = 0
    
    high_risk_countries = ['XX', 'YY']
    if transaction['source_country'] in high_risk_countries:
        risk_score += 50
    
    if transaction['amount'] > 50000:
        risk_score += 30
    
    return min(risk_score, 100)

def check_cross_border_rules(transaction):
    """Check cross-border compliance rules"""
    source = transaction['source_country']
    destination = transaction['destination_country']
    
    return source != destination and transaction['amount'] < 100000

def determine_compliance_status(results):
    """Determine overall compliance status"""
    if not results['kyc_verified']:
        return 'FAILED'
    if results['aml_risk_score'] > 75:
        return 'HIGH_RISK'
    if not results['cross_border_compliant']:
        return 'BLOCKED'
    return 'APPROVED'

def update_compliance_status(database, transaction_id, results):
    """Update transaction compliance status in Spanner"""
    with database.batch() as batch:
        batch.update(
            table='transactions',
            columns=['transaction_id', 'compliance_status', 'risk_score', 
                    'kyc_verified', 'aml_checked', 'updated_at'],
            values=[(
                transaction_id,
                results['compliance_status'],
                results['aml_risk_score'],
                results['kyc_verified'],
                True,
                spanner.COMMIT_TIMESTAMP
            )]
        )

def log_compliance_check(transaction_id, results):
    """Log compliance check results for audit trail"""
    logging_client.logger('compliance-checks').log_struct({
        'transaction_id': transaction_id,
        'compliance_results': results,
        'timestamp': datetime.utcnow().isoformat(),
        'severity': 'INFO'
    })
EOF

    cat > "$compliance_dir/requirements.txt" << 'EOF'
google-cloud-spanner==3.41.0
google-cloud-logging==3.8.0
google-cloud-tasks==2.14.2
functions-framework==3.4.0
EOF

    # Create transaction processor function
    local transaction_dir="$base_dir/transaction-processor"
    mkdir -p "$transaction_dir"
    
    cat > "$transaction_dir/main.py" << 'EOF'
import json
import uuid
from datetime import datetime
from google.cloud import spanner
from google.cloud import tasks_v2
from google.cloud import pubsub_v1
import functions_framework

# Initialize clients
spanner_client = spanner.Client()
tasks_client = tasks_v2.CloudTasksClient()
publisher = pubsub_v1.PublisherClient()

@functions_framework.http
def process_transaction(request):
    """Process financial transaction and trigger compliance checks"""
    
    # Parse request data
    request_json = request.get_json()
    
    # Generate transaction ID
    transaction_id = str(uuid.uuid4())
    
    # Validate transaction data
    if not validate_transaction_data(request_json):
        return {'error': 'Invalid transaction data'}, 400
    
    # Connect to Spanner database
    instance = spanner_client.instance('compliance-monitor')
    database = instance.database('financial-compliance')
    
    # Insert transaction into database
    with database.batch() as batch:
        batch.insert(
            table='transactions',
            columns=['transaction_id', 'account_id', 'amount', 'currency',
                    'source_country', 'destination_country', 'transaction_type',
                    'timestamp', 'compliance_status', 'created_at', 'updated_at'],
            values=[(
                transaction_id,
                request_json['account_id'],
                request_json['amount'],
                request_json['currency'],
                request_json['source_country'],
                request_json['destination_country'],
                request_json['transaction_type'],
                spanner.COMMIT_TIMESTAMP,
                'PENDING',
                spanner.COMMIT_TIMESTAMP,
                spanner.COMMIT_TIMESTAMP
            )]
        )
    
    # Trigger compliance check
    trigger_compliance_check(transaction_id, request_json)
    
    return {
        'transaction_id': transaction_id,
        'status': 'pending_compliance',
        'message': 'Transaction submitted for compliance processing'
    }

def validate_transaction_data(data):
    """Validate required transaction fields"""
    required_fields = ['account_id', 'amount', 'currency', 'source_country',
                      'destination_country', 'transaction_type']
    
    for field in required_fields:
        if field not in data:
            return False
    
    return True

def trigger_compliance_check(transaction_id, transaction_data):
    """Trigger compliance check via Pub/Sub"""
    project_id = spanner_client.project
    topic_path = publisher.topic_path(project_id, 'compliance-events')
    
    message_data = {
        'transaction_id': transaction_id,
        'transaction_data': transaction_data,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    # Publish message to trigger compliance processing
    publisher.publish(topic_path, json.dumps(message_data).encode('utf-8'))
EOF

    cat > "$transaction_dir/requirements.txt" << 'EOF'
google-cloud-spanner==3.41.0
google-cloud-tasks==2.14.2
google-cloud-pubsub==2.18.4
functions-framework==3.4.0
EOF

    # Deploy functions
    run_command "gcloud functions deploy compliance-processor \
        --gen2 \
        --runtime=python311 \
        --source=$compliance_dir \
        --entry-point=process_compliance_check \
        --trigger-topic=compliance-events \
        --service-account=${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com \
        --region=$REGION \
        --memory=512Mi \
        --timeout=540s" \
        "Deploying compliance processor function"
    
    run_command "gcloud functions deploy transaction-processor \
        --gen2 \
        --runtime=python311 \
        --source=$transaction_dir \
        --entry-point=process_transaction \
        --trigger-http \
        --service-account=${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com \
        --region=$REGION \
        --memory=512Mi \
        --timeout=60s \
        --allow-unauthenticated" \
        "Deploying transaction processor function"
    
    # Clean up temporary files
    rm -rf "$base_dir"
    
    success "Cloud Functions deployed successfully"
}

# Configure monitoring and logging
setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    # Create log sink for compliance events
    run_command "gcloud logging sinks create compliance-audit-sink \
        storage.googleapis.com/compliance-audit-logs-$RANDOM_SUFFIX \
        --log-filter='resource.type=\"cloud_function\" AND 
                     (resource.labels.function_name=\"compliance-processor\" OR 
                      resource.labels.function_name=\"transaction-processor\")'" \
        "Creating audit log sink"
    
    success "Monitoring and logging configured"
}

# Display deployment summary
deployment_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Spanner Instance: $SPANNER_INSTANCE"
    echo "Spanner Database: $SPANNER_DATABASE"
    echo "Service Account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "Task Queue: $TASK_QUEUE"
    echo ""
    echo "Deployed Functions:"
    echo "  - transaction-processor (HTTP trigger)"
    echo "  - compliance-processor (Pub/Sub trigger)"
    echo ""
    echo "Next Steps:"
    echo "1. Test the transaction processor API endpoint"
    echo "2. Monitor compliance processing in Cloud Logging"
    echo "3. Review Spanner database for transaction records"
    echo "4. Set up additional monitoring alerts as needed"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get function URLs
        local transaction_url
        transaction_url=$(gcloud functions describe transaction-processor \
            --region="$REGION" \
            --format="value(serviceConfig.uri)" 2>/dev/null || echo "URL not available")
        
        echo "Transaction Processor URL: $transaction_url"
        echo ""
        echo "Test command:"
        echo "curl -X POST $transaction_url \\"
        echo "  -H 'Content-Type: application/json' \\"
        echo "  -d '{\"account_id\":\"test-001\",\"amount\":5000,\"currency\":\"USD\",\"source_country\":\"US\",\"destination_country\":\"CA\",\"transaction_type\":\"wire_transfer\"}'"
    fi
}

# Main deployment flow
main() {
    check_prerequisites
    estimate_costs
    confirm_deployment
    
    setup_project
    enable_apis
    create_service_account
    create_spanner_resources
    create_task_queues
    create_pubsub_resources
    deploy_functions
    setup_monitoring
    
    success "Financial Compliance Monitoring System deployed successfully!"
    deployment_summary
}

# Error handling
trap 'error "Deployment failed. Check the logs above for details."' ERR

# Run main deployment
main "$@"