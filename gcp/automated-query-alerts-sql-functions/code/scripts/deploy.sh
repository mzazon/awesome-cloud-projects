#!/bin/bash

#===============================================================================
# Deploy Script for Automated Query Performance Alerts
# Recipe: automated-query-alerts-sql-functions
# Provider: Google Cloud Platform (GCP)
# 
# This script deploys Cloud SQL with Query Insights, Cloud Functions for 
# alert processing, and Cloud Monitoring alert policies for automated 
# database performance monitoring.
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/deploy-query-alerts-$(date +%Y%m%d-%H%M%S).log"
readonly TEMP_DIR="/tmp/query-alerts-deploy-$$"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#===============================================================================
# Logging functions
#===============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

#===============================================================================
# Utility functions
#===============================================================================

cleanup_on_exit() {
    local exit_code=$?
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed. Check logs at: ${LOG_FILE}"
        log_error "Run destroy.sh to clean up any partially created resources"
    fi
    exit ${exit_code}
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check required APIs (we'll enable them later, but verify gcloud works)
    if ! gcloud services list --enabled &> /dev/null; then
        log_error "Unable to access Google Cloud services. Check authentication and permissions."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Please install it for random string generation."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

confirm_deployment() {
    log_warning "This will deploy Cloud SQL, Cloud Functions, and monitoring resources."
    log_warning "Estimated cost: $20-30 for Cloud SQL + minimal charges for other services."
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

#===============================================================================
# Configuration and Environment Setup
#===============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-sql-alerts-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export INSTANCE_NAME="${INSTANCE_NAME:-postgres-db-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-query-alert-handler-${RANDOM_SUFFIX}}"
    export ALERT_POLICY_NAME="${ALERT_POLICY_NAME:-slow-query-alerts-${RANDOM_SUFFIX}}"
    
    # Database configuration
    export DB_PASSWORD="${DB_PASSWORD:-SecurePassword123!}"
    export MONITOR_PASSWORD="${MONITOR_PASSWORD:-MonitorPass456!}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Instance Name: ${INSTANCE_NAME}"
    log_info "Function Name: ${FUNCTION_NAME}"
    
    # Save configuration for cleanup script
    cat > "${TEMP_DIR}/deployment.env" << EOF
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
ZONE="${ZONE}"
INSTANCE_NAME="${INSTANCE_NAME}"
FUNCTION_NAME="${FUNCTION_NAME}"
ALERT_POLICY_NAME="${ALERT_POLICY_NAME}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    # Copy environment file to a persistent location
    mkdir -p ~/.gcp-query-alerts
    cp "${TEMP_DIR}/deployment.env" ~/.gcp-query-alerts/
    
    log_success "Environment setup completed"
}

configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || {
        log_error "Failed to set project. Check if project exists and you have access."
        exit 1
    }
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configuration completed"
}

enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "sqladmin.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || {
            log_error "Failed to enable ${api}"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

#===============================================================================
# Infrastructure Deployment
#===============================================================================

deploy_cloud_sql() {
    log_info "Creating Cloud SQL PostgreSQL instance with Query Insights..."
    
    # Check if instance already exists
    if gcloud sql instances describe "${INSTANCE_NAME}" &> /dev/null; then
        log_warning "Cloud SQL instance ${INSTANCE_NAME} already exists"
        return 0
    fi
    
    # Create Cloud SQL instance
    gcloud sql instances create "${INSTANCE_NAME}" \
        --database-version=POSTGRES_15 \
        --tier=db-custom-2-7680 \
        --region="${REGION}" \
        --edition=ENTERPRISE \
        --insights-config-query-insights-enabled \
        --insights-config-query-string-length=4500 \
        --insights-config-record-application-tags \
        --insights-config-record-client-address \
        --storage-size=20GB \
        --storage-type=SSD \
        --enable-bin-log \
        --maintenance-window-day=SAT \
        --maintenance-window-hour=02 \
        --storage-auto-increase || {
        log_error "Failed to create Cloud SQL instance"
        exit 1
    }
    
    # Wait for instance to be ready
    log_info "Waiting for Cloud SQL instance to be ready..."
    while true; do
        local state=$(gcloud sql instances describe "${INSTANCE_NAME}" --format="value(state)")
        if [[ "${state}" == "RUNNABLE" ]]; then
            break
        fi
        log_info "Instance state: ${state}. Waiting..."
        sleep 30
    done
    
    log_success "Cloud SQL instance created successfully"
}

configure_database() {
    log_info "Configuring database users and sample data..."
    
    # Set root password
    gcloud sql users set-password postgres \
        --instance="${INSTANCE_NAME}" \
        --password="${DB_PASSWORD}" || {
        log_error "Failed to set postgres password"
        exit 1
    }
    
    # Create monitoring user
    gcloud sql users create monitor_user \
        --instance="${INSTANCE_NAME}" \
        --password="${MONITOR_PASSWORD}" || {
        log_error "Failed to create monitor user"
        exit 1
    }
    
    # Get connection name
    CONNECTION_NAME=$(gcloud sql instances describe "${INSTANCE_NAME}" \
        --format="value(connectionName)")
    export CONNECTION_NAME
    
    # Create sample database
    gcloud sql databases create performance_test \
        --instance="${INSTANCE_NAME}" || {
        log_error "Failed to create sample database"
        exit 1
    }
    
    # Create sample data SQL script
    cat > "${TEMP_DIR}/sample_data.sql" << 'EOF'
-- Create sample tables for performance testing
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_name VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email, created_at) 
SELECT 
    'user' || generate_series,
    'user' || generate_series || '@example.com',
    CURRENT_TIMESTAMP - (random() * interval '365 days')
FROM generate_series(1, 10000);

INSERT INTO orders (user_id, product_name, amount, order_date)
SELECT 
    (random() * 9999 + 1)::INTEGER,
    'Product ' || (random() * 100 + 1)::INTEGER,
    (random() * 1000 + 10)::DECIMAL(10,2),
    CURRENT_TIMESTAMP - (random() * interval '90 days')
FROM generate_series(1, 50000);

-- Create intentionally slow query for testing alerts
CREATE OR REPLACE FUNCTION slow_query_test() 
RETURNS TABLE(user_count INTEGER) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(*)::INTEGER 
    FROM users u 
    CROSS JOIN orders o 
    WHERE u.id = o.user_id 
    AND u.created_at > CURRENT_DATE - interval '30 days';
END;
$$ LANGUAGE plpgsql;
EOF
    
    # Create temporary bucket for SQL import
    TEMP_BUCKET="temp-sql-import-${RANDOM_SUFFIX}"
    gsutil mb "gs://${TEMP_BUCKET}" || {
        log_error "Failed to create temporary bucket"
        exit 1
    }
    
    # Upload and import SQL script
    gsutil cp "${TEMP_DIR}/sample_data.sql" "gs://${TEMP_BUCKET}/" || {
        log_error "Failed to upload SQL script"
        exit 1
    }
    
    gcloud sql import sql "${INSTANCE_NAME}" \
        "gs://${TEMP_BUCKET}/sample_data.sql" \
        --database=performance_test || {
        log_error "Failed to import SQL script"
        exit 1
    }
    
    # Clean up temporary bucket
    gsutil rm -r "gs://${TEMP_BUCKET}"
    
    log_success "Database configuration completed"
}

deploy_cloud_function() {
    log_info "Creating Cloud Function for alert processing..."
    
    # Create directory for Cloud Function code
    mkdir -p "${TEMP_DIR}/query-alert-function"
    cd "${TEMP_DIR}/query-alert-function"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-monitoring==2.20.0
google-cloud-sql==3.8.0
google-cloud-logging==3.8.0
google-auth==2.23.4
requests==2.31.0
functions-framework==3.5.0
EOF
    
    # Create main.py
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timezone
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging
import functions_framework

# Configure logging
cloud_logging.Client().setup_logging()

@functions_framework.http
def process_query_alert(request):
    """Process Cloud Monitoring alert for slow queries"""
    try:
        # Parse alert payload
        alert_data = request.get_json()
        if not alert_data:
            return "No alert data received", 400
        
        # Extract alert details
        incident = alert_data.get('incident', {})
        condition_name = incident.get('condition_name', 'Unknown')
        policy_name = incident.get('policy_name', 'Unknown')
        state = incident.get('state', 'UNKNOWN')
        
        # Log alert processing
        logging.info(f"Processing alert: {condition_name}, State: {state}")
        
        # Create enriched alert message
        alert_message = create_enriched_alert(incident, alert_data)
        
        # Send notifications
        send_alert_notification(alert_message, state)
        
        return f"Alert processed successfully: {condition_name}", 200
        
    except Exception as e:
        logging.error(f"Error processing alert: {str(e)}")
        return f"Error processing alert: {str(e)}", 500

def create_enriched_alert(incident, alert_data):
    """Create enriched alert message with query insights"""
    timestamp = datetime.now(timezone.utc).isoformat()
    
    message = {
        "timestamp": timestamp,
        "alert_type": "Database Query Performance",
        "severity": determine_severity(incident),
        "condition": incident.get('condition_name', 'Unknown'),
        "state": incident.get('state', 'UNKNOWN'),
        "summary": incident.get('summary', 'Query performance threshold exceeded'),
        "recommendations": generate_recommendations(incident),
        "resource_name": incident.get('resource_name', 'Unknown'),
        "documentation": "https://cloud.google.com/sql/docs/postgres/using-query-insights"
    }
    
    return message

def determine_severity(incident):
    """Determine alert severity based on incident data"""
    condition_name = incident.get('condition_name', '').lower()
    
    if 'critical' in condition_name or 'error' in condition_name:
        return 'CRITICAL'
    elif 'warning' in condition_name:
        return 'WARNING'
    else:
        return 'INFO'

def generate_recommendations(incident):
    """Generate actionable recommendations for query performance"""
    recommendations = [
        "Review Query Insights dashboard for slow query patterns",
        "Check for missing indexes on frequently queried columns", 
        "Analyze query execution plans for optimization opportunities",
        "Consider connection pooling if high connection counts detected",
        "Monitor for lock contention and blocking queries"
    ]
    
    return recommendations

def send_alert_notification(message, state):
    """Send alert notification via multiple channels"""
    try:
        # Log structured alert message
        logging.info(f"QUERY_PERFORMANCE_ALERT: {json.dumps(message)}")
        
        if state == 'OPEN':
            logging.warning(f"🚨 ALERT OPENED: {message['summary']}")
        elif state == 'CLOSED':
            logging.info(f"✅ ALERT RESOLVED: {message['summary']}")
        
    except Exception as e:
        logging.error(f"Error sending notification: {str(e)}")
EOF
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point process_query_alert \
        --memory 256MB \
        --timeout 60s \
        --region "${REGION}" || {
        log_error "Failed to deploy Cloud Function"
        exit 1
    }
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    export FUNCTION_URL
    
    # Save function URL to environment file
    echo "FUNCTION_URL=\"${FUNCTION_URL}\"" >> ~/.gcp-query-alerts/deployment.env
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}"
}

create_monitoring_alert() {
    log_info "Creating Cloud Monitoring alert policy..."
    
    # Create notification channel configuration
    cat > "${TEMP_DIR}/notification_channel.json" << EOF
{
  "type": "webhook_tokenauth",
  "displayName": "Query Alert Webhook",
  "description": "Webhook for query performance alerts",
  "labels": {
    "url": "${FUNCTION_URL}"
  },
  "enabled": true
}
EOF
    
    # Create notification channel
    log_info "Creating notification channel..."
    NOTIFICATION_CHANNEL=$(gcloud alpha monitoring channels create \
        --channel-content-from-file="${TEMP_DIR}/notification_channel.json" \
        --format="value(name)") || {
        log_error "Failed to create notification channel"
        exit 1
    }
    export NOTIFICATION_CHANNEL
    
    # Save notification channel to environment file
    echo "NOTIFICATION_CHANNEL=\"${NOTIFICATION_CHANNEL}\"" >> ~/.gcp-query-alerts/deployment.env
    
    # Create alert policy configuration
    cat > "${TEMP_DIR}/alert_policy.json" << EOF
{
  "displayName": "${ALERT_POLICY_NAME}",
  "documentation": {
    "content": "Alert triggered when database queries exceed performance thresholds. Review Query Insights dashboard for detailed analysis.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Query execution time > 5 seconds",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/query_insights/execution_time\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5.0,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN",
            "crossSeriesReducer": "REDUCE_MEAN",
            "groupByFields": ["resource.label.database_id"]
          }
        ]
      }
    }
  ],
  "notificationChannels": ["${NOTIFICATION_CHANNEL}"],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    # Create alert policy
    log_info "Creating alert policy..."
    gcloud alpha monitoring policies create \
        --policy-from-file="${TEMP_DIR}/alert_policy.json" || {
        log_error "Failed to create alert policy"
        exit 1
    }
    
    log_success "Cloud Monitoring alert policy created"
}

#===============================================================================
# Main deployment function
#===============================================================================

main() {
    trap cleanup_on_exit EXIT
    
    log_info "Starting deployment of Automated Query Performance Alerts"
    log_info "Log file: ${LOG_FILE}"
    
    # Pre-deployment checks
    check_prerequisites
    confirm_deployment
    
    # Environment setup
    setup_environment
    configure_gcloud
    enable_apis
    
    # Infrastructure deployment
    deploy_cloud_sql
    configure_database
    deploy_cloud_function
    create_monitoring_alert
    
    # Success message
    log_success "Deployment completed successfully!"
    echo
    log_info "==== Deployment Summary ===="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Cloud SQL Instance: ${INSTANCE_NAME}"
    log_info "Cloud Function: ${FUNCTION_NAME}"
    log_info "Alert Policy: ${ALERT_POLICY_NAME}"
    log_info "Function URL: ${FUNCTION_URL}"
    echo
    log_info "==== Next Steps ===="
    log_info "1. Access Query Insights dashboard:"
    log_info "   https://console.cloud.google.com/sql/instances/${INSTANCE_NAME}/insights?project=${PROJECT_ID}"
    echo
    log_info "2. View Cloud Monitoring dashboard:"
    log_info "   https://console.cloud.google.com/monitoring/alerting/policies?project=${PROJECT_ID}"
    echo
    log_info "3. Test the alert system by executing slow queries against the database"
    log_info "4. Monitor Cloud Functions logs for alert processing"
    echo
    log_warning "Remember to run destroy.sh when you're done to avoid ongoing charges"
    log_info "Deployment configuration saved to: ~/.gcp-query-alerts/deployment.env"
}

# Run main function
main "$@"