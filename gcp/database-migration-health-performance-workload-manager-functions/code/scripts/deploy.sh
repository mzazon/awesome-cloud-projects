#!/bin/bash

# Database Migration Health and Performance Monitoring - Deployment Script
# This script deploys Cloud Workload Manager, Cloud Functions, and monitoring infrastructure
# for comprehensive database migration monitoring and alerting

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Function to run commands with dry-run support
run_command() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: $1"
    else
        eval "$1"
    fi
}

log "Starting Database Migration Health Monitoring deployment..."

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            error "PROJECT_ID environment variable not set and no default project configured. Please set PROJECT_ID or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    # Check if required APIs are enabled
    info "Checking required APIs..."
    local required_apis=(
        "workloadmanager.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "datamigration.googleapis.com"
        "sqladmin.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            warn "API $api is not enabled. It will be enabled during deployment."
        fi
    done
    
    log "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 7))
    fi
    
    export MIGRATION_NAME=${MIGRATION_NAME:-"migration-monitor-${RANDOM_SUFFIX}"}
    export WORKLOAD_NAME=${WORKLOAD_NAME:-"workload-monitor-${RANDOM_SUFFIX}"}
    export BUCKET_NAME=${BUCKET_NAME:-"${PROJECT_ID}-migration-monitoring-${RANDOM_SUFFIX}"}
    
    # Set gcloud defaults
    run_command "gcloud config set project ${PROJECT_ID}"
    run_command "gcloud config set compute/region ${REGION}"
    run_command "gcloud config set compute/zone ${ZONE}"
    
    log "Environment configured:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  ZONE: ${ZONE}"
    info "  MIGRATION_NAME: ${MIGRATION_NAME}"
    info "  WORKLOAD_NAME: ${WORKLOAD_NAME}"
    info "  BUCKET_NAME: ${BUCKET_NAME}"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workloadmanager.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "datamigration.googleapis.com"
        "sqladmin.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling $api..."
        run_command "gcloud services enable $api --quiet"
    done
    
    log "APIs enabled successfully"
    
    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
}

# Create storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        warn "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    run_command "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}"
    run_command "gsutil versioning set on gs://${BUCKET_NAME}"
    
    log "Storage bucket created: gs://${BUCKET_NAME}"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topics and subscriptions..."
    
    local topics=("migration-events" "validation-results" "alert-notifications")
    local subscriptions=("migration-monitor-sub" "validation-processor-sub" "alert-manager-sub")
    
    # Create topics
    for topic in "${topics[@]}"; do
        info "Creating topic: $topic"
        run_command "gcloud pubsub topics create $topic --quiet || true"
    done
    
    # Create subscriptions
    info "Creating subscription: migration-monitor-sub"
    run_command "gcloud pubsub subscriptions create migration-monitor-sub --topic=migration-events --quiet || true"
    
    info "Creating subscription: validation-processor-sub"
    run_command "gcloud pubsub subscriptions create validation-processor-sub --topic=validation-results --quiet || true"
    
    info "Creating subscription: alert-manager-sub"
    run_command "gcloud pubsub subscriptions create alert-manager-sub --topic=alert-notifications --quiet || true"
    
    log "Pub/Sub resources created successfully"
}

# Create Cloud SQL instance
create_cloudsql_instance() {
    log "Creating Cloud SQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe ${MIGRATION_NAME}-target --quiet &>/dev/null; then
        warn "Cloud SQL instance ${MIGRATION_NAME}-target already exists, skipping creation"
        return 0
    fi
    
    info "Creating Cloud SQL MySQL instance..."
    run_command "gcloud sql instances create ${MIGRATION_NAME}-target \
        --database-version=MYSQL_8_0 \
        --tier=db-g1-small \
        --region=${REGION} \
        --storage-size=20GB \
        --storage-type=SSD \
        --backup-start-time=03:00 \
        --enable-bin-log \
        --labels=purpose=migration-target,environment=monitoring \
        --quiet"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Waiting for Cloud SQL instance to be ready..."
        gcloud sql instances patch ${MIGRATION_NAME}-target --quiet &>/dev/null || true
        sleep 60
    fi
    
    info "Setting root password..."
    run_command "gcloud sql users set-password root \
        --host=% \
        --instance=${MIGRATION_NAME}-target \
        --password=SecurePassword123! \
        --quiet"
    
    info "Creating sample database..."
    run_command "gcloud sql databases create sample_db \
        --instance=${MIGRATION_NAME}-target \
        --quiet"
    
    log "Cloud SQL instance created successfully"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log "Deploying Cloud Functions..."
    
    # Create function directories
    run_command "mkdir -p migration-functions/migration-monitor"
    run_command "mkdir -p migration-functions/data-validator"
    run_command "mkdir -p migration-functions/alert-manager"
    
    # Deploy Migration Monitor Function
    info "Deploying migration monitor function..."
    cat > migration-functions/migration-monitor/main.py << 'EOF'
import json
import logging
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1
from google.cloud import datamigration_v1
import functions_framework
from datetime import datetime, timezone

# Initialize clients
monitoring_client = monitoring_v3.MetricServiceClient()
publisher = pubsub_v1.PublisherClient()
migration_client = datamigration_v1.DataMigrationServiceClient()

@functions_framework.http
def monitor_migration(request):
    """Monitor database migration progress and performance"""
    
    try:
        # Get project and migration job details
        project_id = request.json.get('project_id')
        migration_job_id = request.json.get('migration_job_id')
        location = request.json.get('location', 'us-central1')
        
        if not all([project_id, migration_job_id]):
            return {'error': 'Missing required parameters'}, 400
        
        # Get migration job status
        migration_job_name = f"projects/{project_id}/locations/{location}/migrationJobs/{migration_job_id}"
        
        try:
            migration_job = migration_client.get_migration_job(name=migration_job_name)
            
            # Extract key metrics
            metrics = {
                'migration_job_id': migration_job_id,
                'state': migration_job.state.name,
                'phase': migration_job.phase.name,
                'type': migration_job.type_.name,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'duration_seconds': 0
            }
            
            # Calculate duration if job has started
            if migration_job.create_time:
                start_time = migration_job.create_time
                current_time = datetime.now(timezone.utc)
                duration = current_time - start_time.replace(tzinfo=timezone.utc)
                metrics['duration_seconds'] = duration.total_seconds()
            
            # Add error information if present
            if migration_job.error:
                metrics['error_code'] = migration_job.error.code
                metrics['error_message'] = migration_job.error.message
            
            # Publish metrics to Pub/Sub for further processing
            topic_path = publisher.topic_path(project_id, 'migration-events')
            message_data = json.dumps(metrics).encode('utf-8')
            publisher.publish(topic_path, message_data)
            
            # Create custom metrics in Cloud Monitoring
            create_custom_metrics(project_id, metrics)
            
            logging.info(f"Migration monitoring completed for job: {migration_job_id}")
            return {'status': 'success', 'metrics': metrics}
            
        except Exception as e:
            logging.error(f"Error monitoring migration job: {str(e)}")
            return {'error': f'Migration job monitoring failed: {str(e)}'}, 500
            
    except Exception as e:
        logging.error(f"Function execution error: {str(e)}")
        return {'error': f'Function failed: {str(e)}'}, 500

def create_custom_metrics(project_id, metrics):
    """Create custom metrics in Cloud Monitoring"""
    
    project_name = f"projects/{project_id}"
    
    # Create metric for migration duration
    series = monitoring_v3.TimeSeries()
    series.metric.type = "custom.googleapis.com/migration/duration_seconds"
    series.resource.type = "global"
    
    point = monitoring_v3.Point()
    point.value.double_value = metrics['duration_seconds']
    point.interval.end_time.seconds = int(datetime.now().timestamp())
    series.points = [point]
    
    try:
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
    except Exception as e:
        logging.warning(f"Failed to create custom metric: {str(e)}")
EOF
    
    cat > migration-functions/migration-monitor/requirements.txt << 'EOF'
google-cloud-monitoring==2.15.1
google-cloud-pubsub==2.18.1
google-cloud-dms==1.7.0
functions-framework==3.4.0
EOF
    
    run_command "cd migration-functions/migration-monitor && gcloud functions deploy migration-monitor \
        --runtime=python311 \
        --trigger=http \
        --entry-point=monitor_migration \
        --memory=256MB \
        --timeout=60s \
        --allow-unauthenticated \
        --set-env-vars=PROJECT_ID=${PROJECT_ID} \
        --quiet"
    
    # Deploy Data Validator Function
    info "Deploying data validator function..."
    cat > migration-functions/data-validator/main.py << 'EOF'
import json
import logging
import pymysql
from google.cloud import pubsub_v1
from google.cloud import monitoring_v3
import functions_framework
from datetime import datetime
import hashlib

# Initialize clients
publisher = pubsub_v1.PublisherClient()
monitoring_client = monitoring_v3.MetricServiceClient()

@functions_framework.cloud_event
def validate_migration_data(cloud_event):
    """Validate data consistency between source and target databases"""
    
    try:
        # Parse Pub/Sub message
        data = json.loads(cloud_event.data['message']['data'])
        project_id = data.get('project_id')
        source_config = data.get('source_database')
        target_config = data.get('target_database')
        validation_queries = data.get('validation_queries', [])
        
        if not all([project_id, source_config, target_config]):
            logging.error("Missing required database configuration")
            return
        
        validation_results = {
            'timestamp': datetime.now().isoformat(),
            'validation_id': hashlib.md5(f"{project_id}-{datetime.now()}".encode()).hexdigest()[:8],
            'project_id': project_id,
            'total_checks': len(validation_queries),
            'passed_checks': 0,
            'failed_checks': 0,
            'errors': [],
            'data_consistency': True
        }
        
        # Perform data validation checks
        for query_config in validation_queries:
            try:
                result = execute_validation_query(source_config, target_config, query_config)
                if result['passed']:
                    validation_results['passed_checks'] += 1
                else:
                    validation_results['failed_checks'] += 1
                    validation_results['data_consistency'] = False
                    validation_results['errors'].append(result['error'])
                    
            except Exception as e:
                validation_results['failed_checks'] += 1
                validation_results['data_consistency'] = False
                validation_results['errors'].append(f"Query validation error: {str(e)}")
        
        # Calculate validation score
        if validation_results['total_checks'] > 0:
            validation_results['validation_score'] = (
                validation_results['passed_checks'] / validation_results['total_checks']
            ) * 100
        else:
            validation_results['validation_score'] = 0
        
        # Publish results for alerting
        topic_path = publisher.topic_path(project_id, 'validation-results')
        message_data = json.dumps(validation_results).encode('utf-8')
        publisher.publish(topic_path, message_data)
        
        # Create validation metrics
        create_validation_metrics(project_id, validation_results)
        
        logging.info(f"Data validation completed: {validation_results['validation_score']}% passed")
        
    except Exception as e:
        logging.error(f"Validation function error: {str(e)}")

def execute_validation_query(source_config, target_config, query_config):
    """Execute validation query against source and target databases"""
    
    try:
        # This is a placeholder implementation for the example
        # In production, implement actual database connection logic
        return {'passed': True, 'error': None}
        
    except Exception as e:
        return {'passed': False, 'error': f"Query execution failed: {str(e)}"}

def create_validation_metrics(project_id, results):
    """Create validation metrics in Cloud Monitoring"""
    
    project_name = f"projects/{project_id}"
    
    # Create validation score metric
    series = monitoring_v3.TimeSeries()
    series.metric.type = "custom.googleapis.com/migration/validation_score"
    series.resource.type = "global"
    
    point = monitoring_v3.Point()
    point.value.double_value = results['validation_score']
    point.interval.end_time.seconds = int(datetime.now().timestamp())
    series.points = [point]
    
    try:
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
    except Exception as e:
        logging.warning(f"Failed to create validation metric: {str(e)}")
EOF
    
    cat > migration-functions/data-validator/requirements.txt << 'EOF'
google-cloud-pubsub==2.18.1
google-cloud-monitoring==2.15.1
PyMySQL==1.1.0
functions-framework==3.4.0
EOF
    
    run_command "cd migration-functions/data-validator && gcloud functions deploy data-validator \
        --runtime=python311 \
        --trigger=topic=validation-results \
        --entry-point=validate_migration_data \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars=PROJECT_ID=${PROJECT_ID} \
        --quiet"
    
    # Deploy Alert Manager Function
    info "Deploying alert manager function..."
    cat > migration-functions/alert-manager/main.py << 'EOF'
import json
import logging
import smtplib
import requests
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from google.cloud import pubsub_v1
import functions_framework
from datetime import datetime

# Initialize clients
publisher = pubsub_v1.PublisherClient()

@functions_framework.cloud_event
def manage_alerts(cloud_event):
    """Process migration alerts and send notifications"""
    
    try:
        # Parse incoming alert data
        data = json.loads(cloud_event.data['message']['data'])
        alert_type = data.get('alert_type', 'info')
        severity = data.get('severity', 'low')
        message = data.get('message', 'Migration alert')
        project_id = data.get('project_id')
        migration_details = data.get('migration_details', {})
        
        # Create alert payload
        alert_payload = {
            'timestamp': datetime.now().isoformat(),
            'alert_id': f"alert-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
            'project_id': project_id,
            'alert_type': alert_type,
            'severity': severity,
            'message': message,
            'migration_details': migration_details
        }
        
        # Route alerts based on severity
        if severity in ['high', 'critical']:
            send_immediate_alerts(alert_payload)
        elif severity == 'medium':
            send_standard_alerts(alert_payload)
        else:
            log_low_priority_alert(alert_payload)
        
        logging.info(f"Alert processed: {alert_payload['alert_id']}")
        
    except Exception as e:
        logging.error(f"Alert management error: {str(e)}")

def send_immediate_alerts(alert_payload):
    """Send high-priority alerts through multiple channels"""
    
    # Email notification
    try:
        send_email_alert(alert_payload)
    except Exception as e:
        logging.error(f"Email alert failed: {str(e)}")
    
    # Slack notification (if webhook configured)
    try:
        send_slack_alert(alert_payload)
    except Exception as e:
        logging.error(f"Slack alert failed: {str(e)}")

def send_standard_alerts(alert_payload):
    """Send medium-priority alerts via email"""
    
    try:
        send_email_alert(alert_payload)
    except Exception as e:
        logging.error(f"Standard alert failed: {str(e)}")

def log_low_priority_alert(alert_payload):
    """Log low-priority alerts for batch review"""
    
    logging.info(f"Low priority alert: {json.dumps(alert_payload)}")

def send_email_alert(alert_payload):
    """Send email notification (placeholder - configure SMTP as needed)"""
    
    # This is a placeholder implementation
    # In production, configure with your SMTP server details
    logging.info(f"EMAIL ALERT: {alert_payload['message']}")

def send_slack_alert(alert_payload):
    """Send Slack notification (placeholder - configure webhook as needed)"""
    
    # This is a placeholder implementation
    # In production, configure with your Slack webhook URL
    logging.info(f"SLACK ALERT: {alert_payload['message']}")
EOF
    
    cat > migration-functions/alert-manager/requirements.txt << 'EOF'
google-cloud-pubsub==2.18.1
requests==2.31.0
functions-framework==3.4.0
EOF
    
    run_command "cd migration-functions/alert-manager && gcloud functions deploy alert-manager \
        --runtime=python311 \
        --trigger=topic=alert-notifications \
        --entry-point=manage_alerts \
        --memory=256MB \
        --timeout=60s \
        --set-env-vars=PROJECT_ID=${PROJECT_ID} \
        --quiet"
    
    run_command "cd ../.."
    
    log "Cloud Functions deployed successfully"
}

# Create Workload Manager evaluation
create_workload_manager() {
    log "Creating Cloud Workload Manager evaluation..."
    
    # Check if evaluation already exists
    if gcloud workload-manager evaluations describe ${WORKLOAD_NAME} --location=${REGION} --quiet &>/dev/null; then
        warn "Workload Manager evaluation ${WORKLOAD_NAME} already exists, skipping creation"
        return 0
    fi
    
    info "Creating workload evaluation..."
    run_command "gcloud workload-manager evaluations create ${WORKLOAD_NAME} \
        --location=${REGION} \
        --workload-type=DATABASE \
        --workload-uri=\"projects/${PROJECT_ID}/locations/${REGION}/instances/${MIGRATION_NAME}-target\" \
        --labels=environment=migration,purpose=health-monitoring \
        --quiet"
    
    log "Cloud Workload Manager evaluation created successfully"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating custom monitoring dashboard..."
    
    cat > dashboard-config.json << 'EOF'
{
  "displayName": "Database Migration Monitoring",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Migration Progress",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"custom.googleapis.com/migration/duration_seconds\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Data Validation Score",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"custom.googleapis.com/migration/validation_score\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_BAR"
            }
          }
        }
      },
      {
        "width": 12,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Cloud SQL Performance",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "CPU Utilization",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    run_command "gcloud monitoring dashboards create --config-from-file=dashboard-config.json --quiet"
    
    log "Custom monitoring dashboard created successfully"
}

# Main deployment function
main() {
    log "Starting Database Migration Health Monitoring deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    create_cloudsql_instance
    deploy_cloud_functions
    create_workload_manager
    create_monitoring_dashboard
    
    log "Deployment completed successfully!"
    
    # Display important information
    echo ""
    echo "========================================"
    echo "DEPLOYMENT SUMMARY"
    echo "========================================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Migration Name: ${MIGRATION_NAME}"
    echo "Workload Name: ${WORKLOAD_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "Cloud Functions:"
    echo "  - migration-monitor"
    echo "  - data-validator"
    echo "  - alert-manager"
    echo ""
    echo "Cloud SQL Instance: ${MIGRATION_NAME}-target"
    echo "Workload Manager Evaluation: ${WORKLOAD_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. View monitoring dashboard in Cloud Console"
    echo "2. Configure alert notifications (email/Slack)"
    echo "3. Set up source database for migration"
    echo "4. Test the monitoring system with sample data"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "========================================"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Some resources may have been created."
        info "Run './destroy.sh' to clean up any created resources"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"