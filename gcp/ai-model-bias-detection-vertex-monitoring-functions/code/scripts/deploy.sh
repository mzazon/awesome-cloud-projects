#!/bin/bash

# AI Model Bias Detection with Vertex AI Monitoring and Functions - Deployment Script
# This script deploys the complete bias detection infrastructure on Google Cloud Platform

set -euo pipefail

# Color codes for output formatting
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
FUNCTIONS_DIR="$PROJECT_ROOT/bias-functions"

# Default configuration (can be overridden via environment variables)
export PROJECT_ID="${PROJECT_ID:-bias-detection-$(date +%s)}"
export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Resource names
export BUCKET_NAME="${BUCKET_NAME:-bias-detection-reports-${RANDOM_SUFFIX}}"
export FUNCTION_NAME="${FUNCTION_NAME:-bias-detection-processor}"
export ALERT_FUNCTION_NAME="${ALERT_FUNCTION_NAME:-bias-alert-handler}"
export REPORT_FUNCTION_NAME="${REPORT_FUNCTION_NAME:-bias-report-generator}"
export TOPIC_NAME="${TOPIC_NAME:-model-monitoring-alerts}"
export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-bias-audit-scheduler}"
export MODEL_NAME="${MODEL_NAME:-fairness-demo-model}"

# Deployment configuration
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 | grep -q "."; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        log_error "Please install Google Cloud SDK with gsutil"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed or not in PATH"
        log_error "Please install openssl for secure random generation"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to validate and set up project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access"
        log_error "Please create the project or use an existing one"
        exit 1
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" || {
        log_error "Failed to set project to $PROJECT_ID"
        exit 1
    }
    
    gcloud config set compute/region "$REGION" || {
        log_error "Failed to set region to $REGION"
        exit 1
    }
    
    gcloud config set compute/zone "$ZONE" || {
        log_error "Failed to set zone to $ZONE"
        exit 1
    }
    
    log_success "Project configured: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "pubsub.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api"; then
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_success "All required APIs enabled"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log_warning "Bucket $BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create bucket
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        log_error "Failed to create Cloud Storage bucket"
        exit 1
    fi
    
    # Enable versioning
    if ! gsutil versioning set on "gs://$BUCKET_NAME"; then
        log_error "Failed to enable versioning on bucket"
        exit 1
    fi
    
    # Create folder structure
    echo "Bias Detection Reports" | gsutil cp - "gs://$BUCKET_NAME/reports/README.txt"
    echo "Reference Datasets" | gsutil cp - "gs://$BUCKET_NAME/datasets/README.txt"
    echo "Model Artifacts" | gsutil cp - "gs://$BUCKET_NAME/models/README.txt"
    
    log_success "Cloud Storage bucket created and configured"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create topic
    if ! gcloud pubsub topics create "$TOPIC_NAME"; then
        if gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
            log_warning "Topic $TOPIC_NAME already exists, skipping creation"
        else
            log_error "Failed to create Pub/Sub topic"
            exit 1
        fi
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions create bias-detection-sub \
        --topic="$TOPIC_NAME" \
        --ack-deadline=300; then
        if gcloud pubsub subscriptions describe bias-detection-sub &> /dev/null; then
            log_warning "Subscription bias-detection-sub already exists, skipping creation"
        else
            log_error "Failed to create Pub/Sub subscription"
            exit 1
        fi
    fi
    
    log_success "Pub/Sub resources created"
}

# Function to create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    # Create functions directory if it doesn't exist
    mkdir -p "$FUNCTIONS_DIR"
    
    # Create bias detection function
    mkdir -p "$FUNCTIONS_DIR/bias-detector"
    cat > "$FUNCTIONS_DIR/bias-detector/main.py" << 'EOF'
import json
import logging
import os
import time
import pandas as pd
import numpy as np
from google.cloud import logging as cloud_logging
from google.cloud import storage
from google.cloud import aiplatform
import base64
import functions_framework

# Initialize clients
cloud_logging.Client().setup_logging()
storage_client = storage.Client()
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def process_bias_alert(cloud_event):
    """Process model monitoring alerts for bias detection."""
    try:
        # Decode Pub/Sub message
        data = json.loads(base64.b64decode(cloud_event.data['message']['data']))
        
        logger.info(f"Processing bias alert: {data}")
        
        # Extract monitoring information
        model_name = data.get('model_name', 'unknown')
        drift_metric = data.get('drift_metric', 0.0)
        alert_type = data.get('alert_type', 'unknown')
        
        # Calculate bias metrics
        bias_scores = calculate_bias_metrics(data)
        
        # Generate bias report
        report = {
            'timestamp': data.get('timestamp'),
            'model_name': model_name,
            'drift_metric': drift_metric,
            'alert_type': alert_type,
            'bias_scores': bias_scores,
            'fairness_violations': identify_violations(bias_scores),
            'recommendations': generate_recommendations(bias_scores)
        }
        
        # Log bias analysis results
        log_bias_analysis(report)
        
        # Store detailed report in Cloud Storage
        store_bias_report(report)
        
        return {"status": "success", "bias_score": bias_scores.get('demographic_parity', 0.0)}
        
    except Exception as e:
        logger.error(f"Error processing bias alert: {str(e)}")
        return {"status": "error", "message": str(e)}

def calculate_bias_metrics(data):
    """Calculate various bias and fairness metrics."""
    # Simulate bias calculation - in production, use actual prediction data
    np.random.seed(42)
    
    # Mock demographic parity calculation
    demographic_parity = abs(np.random.normal(0.1, 0.05))
    
    # Mock equalized odds calculation
    equalized_odds = abs(np.random.normal(0.08, 0.03))
    
    # Mock calibration metric
    calibration_score = abs(np.random.normal(0.06, 0.02))
    
    return {
        'demographic_parity': round(demographic_parity, 4),
        'equalized_odds': round(equalized_odds, 4),
        'calibration': round(calibration_score, 4),
        'overall_bias_score': round((demographic_parity + equalized_odds + calibration_score) / 3, 4)
    }

def identify_violations(bias_scores):
    """Identify fairness violations based on thresholds."""
    violations = []
    
    if bias_scores['demographic_parity'] > 0.1:
        violations.append('Demographic parity violation detected')
    
    if bias_scores['equalized_odds'] > 0.1:
        violations.append('Equalized odds violation detected')
        
    if bias_scores['calibration'] > 0.05:
        violations.append('Calibration bias detected')
    
    return violations

def generate_recommendations(bias_scores):
    """Generate actionable recommendations for bias mitigation."""
    recommendations = []
    
    if bias_scores['demographic_parity'] > 0.1:
        recommendations.append('Consider rebalancing training data across demographic groups')
    
    if bias_scores['equalized_odds'] > 0.1:
        recommendations.append('Review feature selection for protected attributes')
        
    if bias_scores['overall_bias_score'] > 0.1:
        recommendations.append('Implement bias correction post-processing techniques')
    
    return recommendations

def log_bias_analysis(report):
    """Log bias analysis for compliance and auditing."""
    logger.info(f"BIAS_ANALYSIS: {json.dumps(report)}")

def store_bias_report(report):
    """Store detailed bias report in Cloud Storage."""
    bucket_name = os.environ.get('BUCKET_NAME')
    if bucket_name:
        bucket = storage_client.bucket(bucket_name)
        timestamp = report['timestamp'].replace(':', '-')
        blob_name = f"reports/bias-analysis-{timestamp}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(report, indent=2))
        logger.info(f"Bias report stored: {blob_name}")
EOF

    cat > "$FUNCTIONS_DIR/bias-detector/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-logging==3.10.0
google-cloud-storage==2.13.0
google-cloud-aiplatform==1.42.1
pandas==2.2.0
numpy==1.26.3
EOF

    # Create alert processing function
    mkdir -p "$FUNCTIONS_DIR/alert-processor"
    cat > "$FUNCTIONS_DIR/alert-processor/main.py" << 'EOF'
import json
import logging
import time
from google.cloud import logging as cloud_logging
from google.cloud import pubsub_v1
import functions_framework
import os

# Initialize logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.http
def process_bias_alerts(request):
    """Process and route bias alerts based on severity."""
    try:
        request_json = request.get_json()
        logger.info(f"Processing alert: {request_json}")
        
        bias_score = request_json.get('bias_score', 0.0)
        violations = request_json.get('fairness_violations', [])
        model_name = request_json.get('model_name', 'unknown')
        
        # Determine alert severity
        severity = determine_severity(bias_score, violations)
        
        # Create structured alert
        alert = {
            'severity': severity,
            'model_name': model_name,
            'bias_score': bias_score,
            'violations': violations,
            'timestamp': request_json.get('timestamp'),
            'alert_id': f"bias-{model_name}-{int(time.time())}"
        }
        
        # Route alert based on severity
        route_alert(alert)
        
        # Log for compliance
        log_compliance_event(alert)
        
        return {"status": "success", "severity": severity, "alert_id": alert['alert_id']}
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return {"status": "error", "message": str(e)}, 500

def determine_severity(bias_score, violations):
    """Determine alert severity based on bias metrics."""
    if bias_score > 0.15 or len(violations) > 2:
        return "CRITICAL"
    elif bias_score > 0.1 or len(violations) > 0:
        return "HIGH"
    elif bias_score > 0.05:
        return "MEDIUM"
    else:
        return "LOW"

def route_alert(alert):
    """Route alerts to appropriate channels based on severity."""
    if alert['severity'] in ['CRITICAL', 'HIGH']:
        send_immediate_notification(alert)
    
    # Always log to structured logging for audit trails
    logger.warning(f"BIAS_ALERT: {json.dumps(alert)}")

def send_immediate_notification(alert):
    """Send immediate notifications for critical bias issues."""
    # In production, integrate with email, Slack, or PagerDuty
    logger.critical(f"IMMEDIATE_ACTION_REQUIRED: {alert['model_name']} has {alert['severity']} bias violations")

def log_compliance_event(alert):
    """Log compliance event for regulatory reporting."""
    compliance_log = {
        'event_type': 'BIAS_DETECTION',
        'severity': alert['severity'],
        'model_name': alert['model_name'],
        'bias_score': alert['bias_score'],
        'violations_count': len(alert['violations']),
        'timestamp': alert['timestamp'],
        'alert_id': alert['alert_id']
    }
    
    logger.info(f"COMPLIANCE_EVENT: {json.dumps(compliance_log)}")
EOF

    cat > "$FUNCTIONS_DIR/alert-processor/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-logging==3.10.0
google-cloud-pubsub==2.19.1
EOF

    # Create audit scheduler function
    mkdir -p "$FUNCTIONS_DIR/audit-scheduler"
    cat > "$FUNCTIONS_DIR/audit-scheduler/main.py" << 'EOF'
import json
import logging
import datetime
import os
from google.cloud import logging as cloud_logging
from google.cloud import storage
from google.cloud import aiplatform
import functions_framework

# Initialize logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)
storage_client = storage.Client()

@functions_framework.http
def generate_bias_audit(request):
    """Generate comprehensive bias audit report."""
    try:
        logger.info("Starting scheduled bias audit")
        
        # Generate audit report
        audit_report = perform_comprehensive_audit()
        
        # Store audit report
        store_audit_report(audit_report)
        
        # Log audit completion
        log_audit_completion(audit_report)
        
        return {
            "status": "success", 
            "audit_id": audit_report['audit_id'],
            "models_audited": len(audit_report['model_results']),
            "violations_found": audit_report['summary']['total_violations']
        }
        
    except Exception as e:
        logger.error(f"Error generating bias audit: {str(e)}")
        return {"status": "error", "message": str(e)}, 500

def perform_comprehensive_audit():
    """Perform comprehensive bias audit across all models."""
    timestamp = datetime.datetime.utcnow().isoformat()
    audit_id = f"audit-{timestamp.replace(':', '-').split('.')[0]}"
    
    # Mock audit results - in production, query actual model predictions
    model_results = [
        {
            'model_name': 'credit-scoring-model',
            'bias_metrics': {
                'demographic_parity': 0.08,
                'equalized_odds': 0.12,
                'calibration': 0.04
            },
            'violations': ['Equalized odds violation detected'],
            'data_drift': 0.15,
            'prediction_count': 10000
        },
        {
            'model_name': 'hiring-recommendation-model',
            'bias_metrics': {
                'demographic_parity': 0.06,
                'equalized_odds': 0.07,
                'calibration': 0.03
            },
            'violations': [],
            'data_drift': 0.08,
            'prediction_count': 5000
        }
    ]
    
    # Calculate summary statistics
    total_violations = sum(len(result['violations']) for result in model_results)
    avg_bias_score = sum(
        sum(result['bias_metrics'].values()) / len(result['bias_metrics']) 
        for result in model_results
    ) / len(model_results)
    
    audit_report = {
        'audit_id': audit_id,
        'timestamp': timestamp,
        'audit_type': 'SCHEDULED_COMPREHENSIVE',
        'model_results': model_results,
        'summary': {
            'total_models': len(model_results),
            'total_violations': total_violations,
            'average_bias_score': round(avg_bias_score, 4),
            'models_with_violations': len([r for r in model_results if r['violations']])
        },
        'recommendations': generate_audit_recommendations(model_results)
    }
    
    return audit_report

def generate_audit_recommendations(model_results):
    """Generate actionable recommendations from audit results."""
    recommendations = []
    
    high_bias_models = [r for r in model_results if 
                       sum(r['bias_metrics'].values()) / len(r['bias_metrics']) > 0.1]
    
    if high_bias_models:
        recommendations.append({
            'priority': 'HIGH',
            'action': 'Immediate bias remediation required',
            'models': [m['model_name'] for m in high_bias_models],
            'timeline': '1-2 weeks'
        })
    
    drift_models = [r for r in model_results if r['data_drift'] > 0.1]
    if drift_models:
        recommendations.append({
            'priority': 'MEDIUM',
            'action': 'Model retraining recommended due to data drift',
            'models': [m['model_name'] for m in drift_models],
            'timeline': '2-4 weeks'
        })
    
    return recommendations

def store_audit_report(audit_report):
    """Store audit report in Cloud Storage."""
    bucket_name = os.environ.get('BUCKET_NAME')
    if bucket_name:
        bucket = storage_client.bucket(bucket_name)
        blob_name = f"reports/audit-{audit_report['audit_id']}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(audit_report, indent=2))
        logger.info(f"Audit report stored: {blob_name}")

def log_audit_completion(audit_report):
    """Log audit completion for compliance tracking."""
    logger.info(f"AUDIT_COMPLETED: {json.dumps(audit_report['summary'])}")
EOF

    cat > "$FUNCTIONS_DIR/audit-scheduler/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-logging==3.10.0
google-cloud-storage==2.13.0
google-cloud-aiplatform==1.42.1
EOF

    log_success "Function source code created"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Deploy bias detection function
    log_info "Deploying bias detection function..."
    cd "$FUNCTIONS_DIR/bias-detector"
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime python311 \
        --trigger-topic "$TOPIC_NAME" \
        --source . \
        --entry-point process_bias_alert \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars BUCKET_NAME="$BUCKET_NAME" \
        --region="$REGION"; then
        log_error "Failed to deploy bias detection function"
        exit 1
    fi
    
    # Deploy alert processing function
    log_info "Deploying alert processing function..."
    cd "../alert-processor"
    if ! gcloud functions deploy "$ALERT_FUNCTION_NAME" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --source . \
        --entry-point process_bias_alerts \
        --memory 256MB \
        --timeout 120s \
        --allow-unauthenticated \
        --region="$REGION"; then
        log_error "Failed to deploy alert processing function"
        exit 1
    fi
    
    # Deploy audit function
    log_info "Deploying audit function..."
    cd "../audit-scheduler"
    if ! gcloud functions deploy "$REPORT_FUNCTION_NAME" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --source . \
        --entry-point generate_bias_audit \
        --memory 512MB \
        --timeout 600s \
        --set-env-vars BUCKET_NAME="$BUCKET_NAME" \
        --allow-unauthenticated \
        --region="$REGION"; then
        log_error "Failed to deploy audit function"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    
    log_success "All Cloud Functions deployed successfully"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job..."
    
    # Get the audit function URL
    local audit_function_url
    audit_function_url=$(gcloud functions describe "$REPORT_FUNCTION_NAME" \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    if [[ -z "$audit_function_url" ]]; then
        log_error "Failed to get audit function URL"
        exit 1
    fi
    
    # Create Cloud Scheduler job
    if ! gcloud scheduler jobs create http "$SCHEDULER_JOB_NAME" \
        --location="$REGION" \
        --schedule="0 9 * * 1" \
        --uri="$audit_function_url" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"audit_type": "scheduled", "trigger": "weekly"}' \
        --time-zone="America/New_York"; then
        if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$REGION" &> /dev/null; then
            log_warning "Scheduler job $SCHEDULER_JOB_NAME already exists, skipping creation"
        else
            log_error "Failed to create Cloud Scheduler job"
            exit 1
        fi
    fi
    
    log_success "Cloud Scheduler job created for weekly bias audits"
}

# Function to create monitoring configuration
create_monitoring_config() {
    log_info "Creating model monitoring configuration..."
    
    cat > "$PROJECT_ROOT/monitoring-config.json" << EOF
{
  "display_name": "Bias Detection Monitor",
  "monitoring_objectives": [
    {
      "display_name": "Input Drift Detection",
      "type": "INPUT_FEATURE_DRIFT",
      "categorical_metrics": ["L_INFINITY", "JENSEN_SHANNON_DIVERGENCE"],
      "numerical_metrics": ["JENSEN_SHANNON_DIVERGENCE"],
      "alert_thresholds": {
        "categorical": 0.1,
        "numerical": 0.15
      }
    },
    {
      "display_name": "Output Drift Detection", 
      "type": "OUTPUT_INFERENCE_DRIFT",
      "categorical_metrics": ["L_INFINITY"],
      "numerical_metrics": ["JENSEN_SHANNON_DIVERGENCE"],
      "alert_thresholds": {
        "categorical": 0.08,
        "numerical": 0.12
      }
    }
  ],
  "notification_channels": [
    {
      "type": "PUBSUB",
      "topic": "projects/$PROJECT_ID/topics/$TOPIC_NAME"
    }
  ],
  "schedule": {
    "cron": "0 */6 * * *"
  }
}
EOF
    
    log_success "Model monitoring configuration created"
}

# Function to display deployment summary
display_summary() {
    log_success "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "Functions Deployed:"
    echo "  - Bias Detection: $FUNCTION_NAME"
    echo "  - Alert Processing: $ALERT_FUNCTION_NAME"
    echo "  - Audit Reports: $REPORT_FUNCTION_NAME"
    echo "Scheduler Job: $SCHEDULER_JOB_NAME"
    echo ""
    echo "Next steps:"
    echo "1. Test the deployment using the validation commands in the recipe"
    echo "2. Configure actual model monitoring for your ML models"
    echo "3. Customize bias thresholds based on your requirements"
    echo "4. Set up additional alerting channels (email, Slack, etc.)"
}

# Function to confirm deployment
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will create the following resources:"
    echo "- Cloud Storage bucket: $BUCKET_NAME"
    echo "- Pub/Sub topic: $TOPIC_NAME"
    echo "- Cloud Functions: $FUNCTION_NAME, $ALERT_FUNCTION_NAME, $REPORT_FUNCTION_NAME"
    echo "- Cloud Scheduler job: $SCHEDULER_JOB_NAME"
    echo ""
    echo "Estimated cost: $10-25 for resources created during this deployment"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    log_info "Starting AI Model Bias Detection deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    check_prerequisites
    setup_project
    confirm_deployment
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    create_function_code
    deploy_cloud_functions
    create_scheduler_job
    create_monitoring_config
    display_summary
    
    log_success "AI Model Bias Detection deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Deploy AI Model Bias Detection infrastructure on Google Cloud"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --dry-run          Show what would be deployed without creating resources"
        echo "  --skip-confirmation Skip deployment confirmation prompt"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID         Google Cloud project ID (default: auto-generated)"
        echo "  REGION             Deployment region (default: us-central1)"
        echo "  BUCKET_NAME        Storage bucket name (default: auto-generated)"
        echo "  SKIP_CONFIRMATION  Skip confirmation prompt (default: false)"
        echo ""
        exit 0
        ;;
    --dry-run)
        DRY_RUN="true"
        ;;
    --skip-confirmation)
        SKIP_CONFIRMATION="true"
        ;;
esac

# Run main function
main "$@"