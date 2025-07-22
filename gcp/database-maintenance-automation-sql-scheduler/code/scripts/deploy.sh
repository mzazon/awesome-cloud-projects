#!/bin/bash

# Database Maintenance Automation with Cloud SQL and Cloud Scheduler - Deployment Script
# This script deploys the complete database maintenance automation solution on Google Cloud Platform

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        error "No default project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get current project configuration
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DB_INSTANCE_NAME="maintenance-db-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="db-maintenance-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB_NAME="db-scheduler-${RANDOM_SUFFIX}"
    export BUCKET_NAME="db-maintenance-logs-${PROJECT_ID}-${RANDOM_SUFFIX}"
    
    # Database configuration
    export DB_USER="${DB_USER:-maintenance_user}"
    export DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 12)!Aa1}"
    export DB_NAME="${DB_NAME:-maintenance_app}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Environment configured - Project: ${PROJECT_ID}, Region: ${REGION}"
    log "Database Instance: ${DB_INSTANCE_NAME}"
    log "Function Name: ${FUNCTION_NAME}"
    log "Storage Bucket: ${BUCKET_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "sqladmin.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log "Waiting for APIs to be fully available..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for maintenance logs..."
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
    
    # Create lifecycle policy
    cat > /tmp/lifecycle.json << EOF
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
EOF
    
    if gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"; then
        success "Lifecycle policy applied to storage bucket"
    else
        warning "Failed to apply lifecycle policy to storage bucket"
    fi
    
    rm -f /tmp/lifecycle.json
}

# Function to create Cloud SQL instance
create_sql_instance() {
    log "Creating Cloud SQL instance..."
    
    local create_cmd="gcloud sql instances create ${DB_INSTANCE_NAME} \
        --database-version=MYSQL_8_0 \
        --tier=db-f1-micro \
        --region=${REGION} \
        --backup-start-time=02:00 \
        --maintenance-window-day=SUN \
        --maintenance-window-hour=03 \
        --enable-bin-log \
        --storage-auto-increase \
        --storage-type=SSD \
        --database-flags=slow_query_log=on,long_query_time=2 \
        --quiet"
    
    if eval "${create_cmd}"; then
        success "Cloud SQL instance created: ${DB_INSTANCE_NAME}"
    else
        error "Failed to create Cloud SQL instance"
        exit 1
    fi
    
    # Wait for instance to be ready
    log "Waiting for Cloud SQL instance to be ready..."
    local timeout=300
    local counter=0
    
    while [ $counter -lt $timeout ]; do
        local status=$(gcloud sql instances describe "${DB_INSTANCE_NAME}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        if [ "$status" = "RUNNABLE" ]; then
            success "Cloud SQL instance is ready"
            break
        fi
        sleep 10
        counter=$((counter + 10))
        log "Waiting... (${counter}s/${timeout}s)"
    done
    
    if [ $counter -ge $timeout ]; then
        error "Timeout waiting for Cloud SQL instance to be ready"
        exit 1
    fi
    
    # Create database
    if gcloud sql databases create "${DB_NAME}" --instance="${DB_INSTANCE_NAME}"; then
        success "Database created: ${DB_NAME}"
    else
        error "Failed to create database"
        exit 1
    fi
    
    # Create database user
    if gcloud sql users create "${DB_USER}" --instance="${DB_INSTANCE_NAME}" --password="${DB_PASSWORD}"; then
        success "Database user created: ${DB_USER}"
        log "Database password: ${DB_PASSWORD}"
    else
        error "Failed to create database user"
        exit 1
    fi
}

# Function to deploy Cloud Function
deploy_function() {
    log "Deploying Cloud Function for database maintenance..."
    
    # Create temporary directory for function code
    local func_dir="/tmp/maintenance-function-$$"
    mkdir -p "${func_dir}"
    
    # Create main.py
    cat > "${func_dir}/main.py" << 'EOF'
import functions_framework
import pymysql
import json
import logging
from google.cloud import monitoring_v3
from google.cloud import storage
from google.cloud import sql_v1
from datetime import datetime, timedelta
import os

def get_db_connection():
    """Establish connection to Cloud SQL instance"""
    connection = pymysql.connect(
        host='127.0.0.1',
        user=os.environ['DB_USER'],
        password=os.environ['DB_PASSWORD'],
        database=os.environ['DB_NAME'],
        unix_socket=f'/cloudsql/{os.environ["CONNECTION_NAME"]}'
    )
    return connection

def analyze_slow_queries(connection):
    """Analyze and log slow queries for optimization"""
    cursor = connection.cursor()
    cursor.execute("""
        SELECT sql_text, exec_count, avg_timer_wait/1000000000 as avg_time_seconds
        FROM performance_schema.events_statements_summary_by_digest 
        WHERE avg_timer_wait > 2000000000
        ORDER BY avg_timer_wait DESC LIMIT 10
    """)
    
    slow_queries = cursor.fetchall()
    cursor.close()
    
    return [{"query": q[0][:100], "count": q[1], "avg_time": float(q[2])} 
            for q in slow_queries]

def optimize_tables(connection):
    """Perform table optimization and maintenance"""
    cursor = connection.cursor()
    cursor.execute("SHOW TABLES")
    tables = cursor.fetchall()
    
    optimized_tables = []
    for table in tables:
        table_name = table[0]
        try:
            cursor.execute(f"OPTIMIZE TABLE {table_name}")
            optimized_tables.append(table_name)
        except Exception as e:
            logging.warning(f"Failed to optimize {table_name}: {e}")
    
    cursor.close()
    return optimized_tables

def collect_performance_metrics(connection):
    """Collect database performance metrics"""
    cursor = connection.cursor()
    
    # Get connection stats
    cursor.execute("SHOW STATUS LIKE 'Threads_connected'")
    connections = cursor.fetchone()[1]
    
    # Get query cache stats
    cursor.execute("SHOW STATUS LIKE 'Qcache_hits'")
    cache_hits = cursor.fetchone()[1]
    
    cursor.execute("SHOW STATUS LIKE 'Questions'")
    total_queries = cursor.fetchone()[1]
    
    cursor.close()
    
    return {
        "connections": int(connections),
        "cache_hits": int(cache_hits),
        "total_queries": int(total_queries),
        "timestamp": datetime.now().isoformat()
    }

def save_maintenance_report(report_data, bucket_name):
    """Save maintenance report to Cloud Storage"""
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    blob_name = f"maintenance-reports/report_{timestamp}.json"
    
    blob = bucket.blob(blob_name)
    blob.upload_from_string(json.dumps(report_data, indent=2))
    
    return blob_name

@functions_framework.http
def database_maintenance(request):
    """Main maintenance function triggered by Cloud Scheduler"""
    try:
        connection = get_db_connection()
        
        # Perform maintenance tasks
        slow_queries = analyze_slow_queries(connection)
        optimized_tables = optimize_tables(connection)
        performance_metrics = collect_performance_metrics(connection)
        
        # Create maintenance report
        report = {
            "maintenance_date": datetime.now().isoformat(),
            "slow_queries": slow_queries,
            "optimized_tables": optimized_tables,
            "performance_metrics": performance_metrics,
            "status": "completed"
        }
        
        # Save report to storage
        report_path = save_maintenance_report(report, os.environ['BUCKET_NAME'])
        
        connection.close()
        
        return {
            "status": "success",
            "report_path": report_path,
            "optimized_tables_count": len(optimized_tables),
            "slow_queries_found": len(slow_queries)
        }
        
    except Exception as e:
        logging.error(f"Maintenance failed: {e}")
        return {"status": "error", "message": str(e)}, 500
EOF
    
    # Create requirements.txt
    cat > "${func_dir}/requirements.txt" << EOF
functions-framework==3.4.0
PyMySQL==1.1.0
google-cloud-monitoring==2.15.1
google-cloud-storage==2.10.0
google-cloud-sql==0.4.0
EOF
    
    # Deploy function
    local connection_name="${PROJECT_ID}:${REGION}:${DB_INSTANCE_NAME}"
    
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python39 \
        --trigger=http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=256MB \
        --timeout=540s \
        --set-env-vars="DB_USER=${DB_USER},DB_NAME=${DB_NAME},DB_PASSWORD=${DB_PASSWORD},BUCKET_NAME=${BUCKET_NAME},CONNECTION_NAME=${connection_name}" \
        --add-cloudsql-instances="${connection_name}" \
        --source="${func_dir}" \
        --quiet; then
        success "Cloud Function deployed: ${FUNCTION_NAME}"
    else
        error "Failed to deploy Cloud Function"
        rm -rf "${func_dir}"
        exit 1
    fi
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    log "Function URL: ${FUNCTION_URL}"
    
    # Clean up temporary directory
    rm -rf "${func_dir}"
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    log "Creating Cloud Scheduler jobs..."
    
    # Create daily maintenance job
    if gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 2 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --description="Daily database maintenance automation" \
        --time-zone="America/New_York" \
        --attempt-deadline=10m \
        --max-retry-attempts=3 \
        --min-backoff=1m \
        --max-backoff=5m \
        --quiet; then
        success "Daily maintenance job created: ${SCHEDULER_JOB_NAME}"
    else
        error "Failed to create daily maintenance job"
        exit 1
    fi
    
    # Create monitoring job
    if gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}-monitor" \
        --location="${REGION}" \
        --schedule="0 */6 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --description="Database performance monitoring" \
        --time-zone="America/New_York" \
        --attempt-deadline=5m \
        --max-retry-attempts=2 \
        --quiet; then
        success "Performance monitoring job created: ${SCHEDULER_JOB_NAME}-monitor"
    else
        warning "Failed to create monitoring job, but continuing deployment"
    fi
}

# Function to create monitoring alerts
create_monitoring_alerts() {
    log "Creating Cloud Monitoring alerting policies..."
    
    # Create CPU alert policy
    cat > /tmp/cpu-alert-policy.json << EOF
{
  "displayName": "Cloud SQL High CPU Usage",
  "documentation": {
    "content": "Alert when Cloud SQL CPU usage exceeds 80% for 5 minutes"
  },
  "conditions": [
    {
      "displayName": "Cloud SQL CPU > 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\"",
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
  "enabled": true,
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    
    # Create connection alert policy
    cat > /tmp/connection-alert-policy.json << EOF
{
  "displayName": "Cloud SQL High Connection Count",
  "documentation": {
    "content": "Alert when active connections exceed 80% of max connections"
  },
  "conditions": [
    {
      "displayName": "High Connection Count",
      "conditionThreshold": {
        "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/mysql/connections\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 80,
        "duration": "300s"
      }
    }
  ],
  "enabled": true
}
EOF
    
    # Apply alerting policies
    if gcloud alpha monitoring policies create --policy-from-file=/tmp/cpu-alert-policy.json --quiet; then
        success "CPU monitoring alert created"
    else
        warning "Failed to create CPU monitoring alert"
    fi
    
    if gcloud alpha monitoring policies create --policy-from-file=/tmp/connection-alert-policy.json --quiet; then
        success "Connection monitoring alert created"
    else
        warning "Failed to create connection monitoring alert"
    fi
    
    # Clean up policy files
    rm -f /tmp/cpu-alert-policy.json /tmp/connection-alert-policy.json
}

# Function to create monitoring dashboard
create_dashboard() {
    log "Creating monitoring dashboard..."
    
    cat > /tmp/dashboard-config.json << EOF
{
  "displayName": "Database Maintenance Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Database CPU Utilization",
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
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Active Connections",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/mysql/connections\"",
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
      }
    ]
  }
}
EOF
    
    if gcloud monitoring dashboards create --config-from-file=/tmp/dashboard-config.json --quiet; then
        success "Monitoring dashboard created"
    else
        warning "Failed to create monitoring dashboard"
    fi
    
    rm -f /tmp/dashboard-config.json
}

# Function to save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    local config_file="deployment-config.json"
    
    cat > "${config_file}" << EOF
{
  "deployment_timestamp": "$(date -Iseconds)",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "zone": "${ZONE}",
  "resources": {
    "db_instance_name": "${DB_INSTANCE_NAME}",
    "function_name": "${FUNCTION_NAME}",
    "scheduler_job_name": "${SCHEDULER_JOB_NAME}",
    "bucket_name": "${BUCKET_NAME}",
    "db_user": "${DB_USER}",
    "db_name": "${DB_NAME}",
    "function_url": "${FUNCTION_URL}"
  }
}
EOF
    
    success "Deployment configuration saved to ${config_file}"
    log "Please keep this file for reference and cleanup operations"
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check Cloud SQL instance
    local sql_status=$(gcloud sql instances describe "${DB_INSTANCE_NAME}" --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$sql_status" = "RUNNABLE" ]; then
        success "Cloud SQL instance is running"
    else
        error "Cloud SQL instance validation failed"
        return 1
    fi
    
    # Check Cloud Function
    local func_status=$(gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$func_status" = "ACTIVE" ]; then
        success "Cloud Function is active"
    else
        error "Cloud Function validation failed"
        return 1
    fi
    
    # Check Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        success "Storage bucket is accessible"
    else
        error "Storage bucket validation failed"
        return 1
    fi
    
    # Check Scheduler jobs
    local job_count=$(gcloud scheduler jobs list --location="${REGION}" --filter="name~${SCHEDULER_JOB_NAME}" --format="value(name)" | wc -l)
    if [ "$job_count" -ge 1 ]; then
        success "Scheduler jobs are configured"
    else
        warning "Some scheduler jobs may not be configured"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    echo
    success "=== Database Maintenance Automation Deployment Complete ==="
    echo
    log "Deployed Resources:"
    log "  • Cloud SQL Instance: ${DB_INSTANCE_NAME}"
    log "  • Cloud Function: ${FUNCTION_NAME}"
    log "  • Storage Bucket: gs://${BUCKET_NAME}"
    log "  • Scheduler Jobs: ${SCHEDULER_JOB_NAME}, ${SCHEDULER_JOB_NAME}-monitor"
    echo
    log "Access Information:"
    log "  • Function URL: ${FUNCTION_URL}"
    log "  • Database User: ${DB_USER}"
    log "  • Database Name: ${DB_NAME}"
    log "  • Database Password: ${DB_PASSWORD}"
    echo
    log "Next Steps:"
    log "  1. Access Cloud Console > Cloud SQL to view database instance"
    log "  2. Check Cloud Console > Cloud Functions for function status"
    log "  3. Review Cloud Console > Cloud Scheduler for job schedules"
    log "  4. View Cloud Console > Monitoring for dashboards and alerts"
    log "  5. Monitor Cloud Console > Cloud Storage for maintenance reports"
    echo
    warning "Save the database password and deployment configuration for future reference"
    echo
}

# Main deployment function
main() {
    log "Starting Database Maintenance Automation deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_sql_instance
    deploy_function
    create_scheduler_jobs
    create_monitoring_alerts
    create_dashboard
    save_deployment_config
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Some resources may need manual cleanup."; exit 1' INT TERM

# Run main function
main "$@"