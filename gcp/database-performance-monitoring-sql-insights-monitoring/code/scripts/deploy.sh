#!/bin/bash

# Deploy script for Database Performance Monitoring with Cloud SQL Insights and Cloud Monitoring
# This script automates the complete deployment of the monitoring infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Use destroy.sh to clean up any partially created resources"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo "=========================================================="
echo "Database Performance Monitoring Deployment"
echo "Cloud SQL Insights + Cloud Monitoring + Cloud Functions"
echo "=========================================================="

# Check prerequisites
log_info "Checking prerequisites..."

# Check if gcloud CLI is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed"
    log_error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    log_error "Not authenticated with Google Cloud"
    log_error "Please run: gcloud auth login"
    exit 1
fi

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
    log_error "gsutil is not available"
    log_error "Please ensure Google Cloud SDK is properly installed"
    exit 1
fi

log_success "Prerequisites check completed"

# Configuration section
log_info "Setting up configuration..."

# Set environment variables with user input or defaults
read -p "Enter project ID (or press Enter for auto-generated): " input_project_id
if [ -z "$input_project_id" ]; then
    export PROJECT_ID="db-monitoring-$(date +%s)"
    log_info "Using auto-generated project ID: ${PROJECT_ID}"
else
    export PROJECT_ID="$input_project_id"
fi

read -p "Enter region [us-central1]: " input_region
export REGION="${input_region:-us-central1}"

read -p "Enter zone [us-central1-a]: " input_zone
export ZONE="${input_zone:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Resource names
export DB_INSTANCE_NAME="performance-db-${RANDOM_SUFFIX}"
export FUNCTION_NAME="db-alert-handler-${RANDOM_SUFFIX}"
export TOPIC_NAME="db-alerts-${RANDOM_SUFFIX}"
export BUCKET_NAME="db-reports-${RANDOM_SUFFIX}"

log_info "Configuration completed:"
log_info "  Project ID: ${PROJECT_ID}"
log_info "  Region: ${REGION}"
log_info "  Zone: ${ZONE}"
log_info "  DB Instance: ${DB_INSTANCE_NAME}"
log_info "  Function: ${FUNCTION_NAME}"
log_info "  Topic: ${TOPIC_NAME}"
log_info "  Bucket: ${BUCKET_NAME}"

# Confirmation prompt
read -p "Continue with deployment? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

# Create or set project
log_info "Setting up Google Cloud project..."
if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
    log_info "Using existing project: ${PROJECT_ID}"
else
    log_info "Creating new project: ${PROJECT_ID}"
    gcloud projects create "${PROJECT_ID}" --name="Database Monitoring Project"
    
    # Enable billing (user must have a billing account)
    log_warning "Please ensure billing is enabled for project ${PROJECT_ID}"
    log_warning "Visit: https://console.cloud.google.com/billing/projects"
    read -p "Press Enter after enabling billing..."
fi

# Set default project and region
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"

# Enable required APIs
log_info "Enabling required Google Cloud APIs..."
apis=(
    "sqladmin.googleapis.com"
    "monitoring.googleapis.com"
    "cloudfunctions.googleapis.com"
    "pubsub.googleapis.com"
    "storage.googleapis.com"
    "logging.googleapis.com"
    "cloudbuild.googleapis.com"
)

for api in "${apis[@]}"; do
    log_info "Enabling ${api}..."
    gcloud services enable "${api}"
done

# Wait for APIs to be fully enabled
log_info "Waiting for APIs to be fully enabled..."
sleep 30

log_success "Required APIs enabled successfully"

# Create foundational resources
log_info "Creating foundational resources..."

# Create Pub/Sub topic
log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
gcloud pubsub topics create "${TOPIC_NAME}"

# Create Cloud Storage bucket
log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
gsutil mb -p "${PROJECT_ID}" \
    -c STANDARD \
    -l "${REGION}" \
    "gs://${BUCKET_NAME}"

# Enable bucket versioning for report retention
gsutil versioning set on "gs://${BUCKET_NAME}"

log_success "Foundational resources created successfully"

# Create Cloud SQL instance
log_info "Creating Cloud SQL PostgreSQL instance with Enterprise Plus edition..."
log_warning "This may take 10-15 minutes..."

# Set database password
export DB_PASSWORD="SecurePass123!$(openssl rand -hex 4)"
log_info "Generated secure database password"

# Create the instance
gcloud sql instances create "${DB_INSTANCE_NAME}" \
    --database-version=POSTGRES_15 \
    --tier=db-perf-optimized-N-2 \
    --region="${REGION}" \
    --edition=ENTERPRISE_PLUS \
    --enable-bin-log \
    --storage-type=SSD \
    --storage-size=100GB \
    --storage-auto-increase \
    --maintenance-window-day=SUN \
    --maintenance-window-hour=04 \
    --backup-start-time=02:00 \
    --deletion-protection

log_success "Cloud SQL instance created: ${DB_INSTANCE_NAME}"

# Enable Query Insights
log_info "Enabling Query Insights with advanced configuration..."
gcloud sql instances patch "${DB_INSTANCE_NAME}" \
    --insights-config-query-insights-enabled \
    --insights-config-query-string-length=1024 \
    --insights-config-record-application-tags \
    --insights-config-record-client-address

# Wait for configuration to apply
log_info "Waiting for Query Insights configuration to apply..."
sleep 60

log_success "Query Insights enabled with comprehensive data collection"

# Set database password and create test database
log_info "Configuring database access and creating test database..."
gcloud sql users set-password postgres \
    --instance="${DB_INSTANCE_NAME}" \
    --password="${DB_PASSWORD}"

gcloud sql databases create performance_test \
    --instance="${DB_INSTANCE_NAME}"

# Get connection name
export CONNECTION_NAME=$(gcloud sql instances describe "${DB_INSTANCE_NAME}" \
    --format="value(connectionName)")

log_success "Database configured with connection name: ${CONNECTION_NAME}"

# Create monitoring dashboard
log_info "Creating custom monitoring dashboard..."
cat > /tmp/dashboard-config.json << 'EOF'
{
  "displayName": "Cloud SQL Performance Monitoring Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Database Connections",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloudsql_database\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Query Insights Top Queries",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/insights/aggregate/execution_time\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=/tmp/dashboard-config.json
rm /tmp/dashboard-config.json

log_success "Custom monitoring dashboard created"

# Create alerting policies
log_info "Creating intelligent alerting policies..."

# CPU alerting policy
cat > /tmp/cpu-alert-policy.json << EOF
{
  "displayName": "Cloud SQL High CPU Usage",
  "conditions": [
    {
      "displayName": "CPU utilization is high",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${PROJECT_ID}:${DB_INSTANCE_NAME}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF

gcloud alpha monitoring policies create --policy-from-file=/tmp/cpu-alert-policy.json
rm /tmp/cpu-alert-policy.json

# Slow query alerting policy
cat > /tmp/slow-query-alert-policy.json << EOF
{
  "displayName": "Cloud SQL Slow Query Detection",
  "conditions": [
    {
      "displayName": "Query execution time is high",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${PROJECT_ID}:${DB_INSTANCE_NAME}\" AND metric.type=\"cloudsql.googleapis.com/insights/aggregate/execution_time\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5000,
        "duration": "180s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF

gcloud alpha monitoring policies create --policy-from-file=/tmp/slow-query-alert-policy.json
rm /tmp/slow-query-alert-policy.json

log_success "Alerting policies created for proactive monitoring"

# Deploy Cloud Function
log_info "Deploying Cloud Function for automated alert processing..."

# Create function directory
mkdir -p /tmp/db-alert-function
cd /tmp/db-alert-function

# Create main function file
cat > main.py << 'EOF'
import json
import base64
import os
from google.cloud import storage
from google.cloud import monitoring_v3
from datetime import datetime, timezone
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_db_alert(event, context):
    """Process database performance alerts and generate actionable insights."""
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message = base64.b64decode(event['data']).decode('utf-8')
            alert_data = json.loads(message)
        else:
            alert_data = event
        
        logger.info(f"Processing alert: {alert_data}")
        
        # Extract alert information
        alert_type = alert_data.get('incident', {}).get('condition_name', 'Unknown')
        resource_name = alert_data.get('incident', {}).get('resource_display_name', 'Unknown')
        state = alert_data.get('incident', {}).get('state', 'UNKNOWN')
        
        # Generate performance report
        report = generate_performance_report(alert_type, resource_name, state)
        
        # Store report in Cloud Storage
        store_report(report)
        
        # Log processed alert
        logger.info(f"Successfully processed {alert_type} alert for {resource_name}")
        
        return {"status": "success", "alert_type": alert_type}
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return {"status": "error", "message": str(e)}

def generate_performance_report(alert_type, resource_name, state):
    """Generate detailed performance analysis report."""
    timestamp = datetime.now(timezone.utc).isoformat()
    
    report = {
        "timestamp": timestamp,
        "alert_type": alert_type,
        "resource_name": resource_name,
        "state": state,
        "recommendations": get_performance_recommendations(alert_type),
        "analysis": f"Performance alert triggered for {resource_name} at {timestamp}"
    }
    
    return report

def get_performance_recommendations(alert_type):
    """Provide intelligent recommendations based on alert type."""
    recommendations = {
        "CPU utilization is high": [
            "Consider upgrading to a higher CPU tier",
            "Review Query Insights for expensive queries",
            "Implement query optimization strategies",
            "Consider read replicas for read-heavy workloads"
        ],
        "Query execution time is high": [
            "Analyze query execution plans in Query Insights",
            "Review and optimize table indexes",
            "Consider query rewriting for better performance",
            "Check for table lock contention"
        ]
    }
    
    return recommendations.get(alert_type, ["Review database performance metrics"])

def store_report(report):
    """Store performance report in Cloud Storage."""
    try:
        client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME', 'default-bucket')
        bucket = client.bucket(bucket_name)
        
        filename = f"performance-reports/{report['timestamp']}-{report['alert_type'].replace(' ', '-')}.json"
        blob = bucket.blob(filename)
        blob.upload_from_string(json.dumps(report, indent=2))
        
        logger.info(f"Report stored: gs://{bucket_name}/{filename}")
        
    except Exception as e:
        logger.warning(f"Failed to store report: {str(e)}")
EOF

# Create requirements file
cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
google-cloud-monitoring==2.15.1
functions-framework==3.4.0
EOF

# Deploy the Cloud Function
log_info "Deploying Cloud Function with intelligent alert processing..."
gcloud functions deploy "${FUNCTION_NAME}" \
    --runtime python39 \
    --trigger-topic "${TOPIC_NAME}" \
    --source . \
    --entry-point process_db_alert \
    --memory 256MB \
    --timeout 60s \
    --set-env-vars "BUCKET_NAME=${BUCKET_NAME}"

cd - > /dev/null
rm -rf /tmp/db-alert-function

log_success "Cloud Function deployed successfully"

# Configure notification channels
log_info "Configuring notification channels for alert integration..."

# Create Pub/Sub notification channel
NOTIFICATION_CHANNEL=$(gcloud alpha monitoring channels create \
    --display-name="Database Alert Processing" \
    --type=pubsub \
    --channel-labels="topic=projects/${PROJECT_ID}/topics/${TOPIC_NAME}" \
    --format="value(name)")

# Update alerting policies with notification channel
POLICIES=$(gcloud alpha monitoring policies list \
    --filter="displayName:('Cloud SQL High CPU Usage' OR 'Cloud SQL Slow Query Detection')" \
    --format="value(name)")

for policy in $POLICIES; do
    gcloud alpha monitoring policies update "$policy" \
        --add-notification-channels="$NOTIFICATION_CHANNEL"
done

log_success "Notification channels configured for automated alert processing"

# Generate test data
log_info "Creating test database schema and sample data..."
cat > /tmp/test_data.sql << 'EOF'
-- Create test table with indexes
CREATE TABLE performance_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data TEXT
);

-- Create index for testing
CREATE INDEX idx_performance_test_name ON performance_test(name);
CREATE INDEX idx_performance_test_created_at ON performance_test(created_at);

-- Insert test data
INSERT INTO performance_test (name, data) 
SELECT 'Test User ' || generate_series(1, 1000), 
       'Sample data for performance testing';

-- Create some query load for monitoring validation
SELECT COUNT(*) FROM performance_test WHERE name LIKE '%User 5%';
SELECT * FROM performance_test ORDER BY created_at DESC LIMIT 100;
EOF

# Apply test data (requires Cloud SQL Proxy or authorized networks)
log_warning "Test data script created at /tmp/test_data.sql"
log_warning "To load test data, connect to your database and run the SQL script"

# Save deployment information
log_info "Saving deployment information..."
cat > /tmp/deployment-info.txt << EOF
Database Performance Monitoring Deployment Information
======================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}

Resources Created:
- Cloud SQL Instance: ${DB_INSTANCE_NAME}
- Cloud Function: ${FUNCTION_NAME}
- Pub/Sub Topic: ${TOPIC_NAME}
- Storage Bucket: ${BUCKET_NAME}
- Connection Name: ${CONNECTION_NAME}

Database Access:
- Database Password: ${DB_PASSWORD}
- Test Database: performance_test

Important URLs:
- Cloud SQL Console: https://console.cloud.google.com/sql/instances/${DB_INSTANCE_NAME}/overview?project=${PROJECT_ID}
- Monitoring Dashboard: https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}
- Cloud Functions: https://console.cloud.google.com/functions/details/${REGION}/${FUNCTION_NAME}?project=${PROJECT_ID}

Next Steps:
1. Connect to the database using Cloud SQL Proxy or authorized networks
2. Run the test data script: /tmp/test_data.sql
3. Monitor Query Insights in the Cloud SQL console
4. Review the custom monitoring dashboard
5. Test alerting by generating database load

Cost Management:
- Remember to run destroy.sh when testing is complete
- Monitor costs in the billing console
- Consider scaling down the instance for long-term use

Security Notes:
- Database password is stored in this file - keep secure
- Consider using IAM database authentication for production
- Review firewall rules and authorized networks
EOF

log_success "Deployment information saved to /tmp/deployment-info.txt"

# Final success message
echo ""
echo "=========================================================="
log_success "Database Performance Monitoring Deployment Complete!"
echo "=========================================================="
echo ""
log_info "Key resources created:"
log_info "  ✅ Cloud SQL Enterprise Plus instance with Query Insights"
log_info "  ✅ Custom monitoring dashboard and alerting policies"
log_info "  ✅ Cloud Function for intelligent alert processing"
log_info "  ✅ Pub/Sub topic and Cloud Storage bucket"
echo ""
log_warning "Important: Save the deployment information from /tmp/deployment-info.txt"
log_warning "Database password: ${DB_PASSWORD}"
echo ""
log_info "Next steps:"
log_info "1. Connect to your database and load test data"
log_info "2. Generate some database activity to see Query Insights in action"
log_info "3. Monitor performance metrics in the custom dashboard"
log_info "4. Test alerting by creating database load"
echo ""
log_warning "Remember to run destroy.sh when testing is complete to avoid charges"
echo ""

# Copy deployment info to user directory if possible
if [ -w "$HOME" ]; then
    cp /tmp/deployment-info.txt "$HOME/db-monitoring-deployment-info.txt"
    log_info "Deployment info also saved to: $HOME/db-monitoring-deployment-info.txt"
fi

exit 0