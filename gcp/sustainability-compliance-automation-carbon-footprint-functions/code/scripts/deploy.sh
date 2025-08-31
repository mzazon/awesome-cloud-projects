#!/bin/bash

# Sustainability Compliance Automation with Carbon Footprint and Functions
# Deployment Script for GCP
# 
# This script deploys the complete sustainability compliance automation infrastructure
# including BigQuery datasets, Cloud Functions, Carbon Footprint export, and Cloud Scheduler jobs.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Progress tracking
STEP_COUNT=0
TOTAL_STEPS=8

step() {
    STEP_COUNT=$((STEP_COUNT + 1))
    log_info "Step ${STEP_COUNT}/${TOTAL_STEPS}: $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources created so far..."
    
    # Clean up Cloud Functions if they exist
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null || true
    fi
    if [[ -n "${REPORT_FUNCTION:-}" ]]; then
        gcloud functions delete "${REPORT_FUNCTION}" --region="${REGION}" --quiet 2>/dev/null || true
    fi
    if [[ -n "${ALERT_FUNCTION:-}" ]]; then
        gcloud functions delete "${ALERT_FUNCTION}" --region="${REGION}" --quiet 2>/dev/null || true
    fi
    
    # Clean up BigQuery dataset if it exists
    if [[ -n "${DATASET_NAME:-}" ]] && [[ -n "${PROJECT_ID:-}" ]]; then
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null || true
    fi
    
    # Clean up Cloud Scheduler jobs if they exist
    gcloud scheduler jobs delete process-carbon-data --quiet 2>/dev/null || true
    gcloud scheduler jobs delete generate-esg-reports --quiet 2>/dev/null || true
    gcloud scheduler jobs delete carbon-alerts-check --quiet 2>/dev/null || true
    
    # Clean up local directories
    rm -rf carbon-processing-function esg-report-function carbon-alert-function 2>/dev/null || true
    
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites validation
check_prerequisites() {
    step "Validating prerequisites and dependencies"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes."
        exit 1
    fi
    
    log_success "All prerequisites validated"
}

# Environment setup
setup_environment() {
    step "Setting up environment variables and configuration"
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-sustainability-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATASET_NAME="carbon_footprint_${RANDOM_SUFFIX}"
    export FUNCTION_NAME="process-carbon-data-${RANDOM_SUFFIX}"
    export REPORT_FUNCTION="generate-esg-report-${RANDOM_SUFFIX}"
    export ALERT_FUNCTION="carbon-alerts-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Dataset Name: ${DATASET_NAME}"
    log_info "Function Names: ${FUNCTION_NAME}, ${REPORT_FUNCTION}, ${ALERT_FUNCTION}"
    
    # Get billing account
    BILLING_ACCOUNT_ID=$(gcloud billing accounts list --format="value(name)" | head -1)
    if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
        log_error "No billing account found. Please ensure you have access to a billing account."
        exit 1
    fi
    export BILLING_ACCOUNT_ID
    
    log_info "Billing Account: ${BILLING_ACCOUNT_ID}"
    log_success "Environment variables configured"
}

# Project configuration
configure_project() {
    step "Configuring Google Cloud project settings"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# API enablement
enable_apis() {
    step "Enabling required Google Cloud APIs"
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "cloudscheduler.googleapis.com"
        "bigquerydatatransfer.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# BigQuery setup
setup_bigquery() {
    step "Creating BigQuery dataset and analytics table"
    
    # Create BigQuery dataset for carbon footprint data
    log_info "Creating BigQuery dataset: ${DATASET_NAME}"
    bq mk --location="${REGION}" \
        --description="Carbon footprint and sustainability data for ESG compliance" \
        "${PROJECT_ID}:${DATASET_NAME}"
    
    # Create custom analytics table for processed metrics
    log_info "Creating sustainability metrics table..."
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.sustainability_metrics" \
        project_id:STRING,month:DATE,total_emissions:FLOAT,scope_1:FLOAT,scope_2_location:FLOAT,scope_2_market:FLOAT,scope_3:FLOAT,service:STRING,region:STRING
    
    log_success "BigQuery dataset and analytics table created"
}

# Carbon Footprint export configuration
configure_carbon_export() {
    step "Configuring Carbon Footprint export to BigQuery"
    
    log_info "Setting up Carbon Footprint data transfer to BigQuery..."
    
    # Create the data transfer configuration using the correct data source ID
    bq mk --transfer_config \
        --project_id="${PROJECT_ID}" \
        --data_source=61cede5a-0000-2440-ad42-883d24f8f7b8 \
        --display_name="Carbon Footprint Export ${RANDOM_SUFFIX}" \
        --target_dataset="${DATASET_NAME}" \
        --params="{\"billing_accounts\":\"${BILLING_ACCOUNT_ID}\"}"
    
    log_success "Carbon Footprint export configured"
    log_info "Note: Carbon footprint data exports automatically on the 15th of each month with a 1-month delay"
}

# Cloud Functions deployment
deploy_functions() {
    step "Deploying Cloud Functions for data processing, reporting, and alerting"
    
    # Create and deploy data processing function
    log_info "Creating data processing function..."
    mkdir -p carbon-processing-function
    cd carbon-processing-function
    
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import functions_v1
import logging

def process_carbon_data(request):
    """Process carbon footprint data and calculate sustainability metrics."""
    try:
        client = bigquery.Client()
        
        # Query latest carbon footprint data
        query = f"""
        SELECT 
            project.id as project_id,
            usage_month,
            SUM(carbon_footprint_total_kgCO2e.amount) as total_emissions,
            SUM(carbon_footprint_kgCO2e.scope1) as scope_1,
            SUM(carbon_footprint_kgCO2e.scope2.location_based) as scope_2_location,
            SUM(carbon_footprint_kgCO2e.scope2.market_based) as scope_2_market,
            SUM(carbon_footprint_kgCO2e.scope3) as scope_3,
            service.description as service,
            location.region as region
        FROM `{client.project}.{os.environ['DATASET_NAME']}.carbon_footprint`
        WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
        GROUP BY project_id, usage_month, service, region
        ORDER BY usage_month DESC
        """
        
        # Execute query and insert into analytics table
        job_config = bigquery.QueryJobConfig()
        job_config.destination = f"{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics"
        job_config.write_disposition = bigquery.WriteDisposition.WRITE_APPEND
        
        query_job = client.query(query, job_config=job_config)
        results = query_job.result()
        
        # Calculate sustainability KPIs
        kpi_query = f"""
        SELECT 
            COUNT(DISTINCT project_id) as active_projects,
            AVG(total_emissions) as avg_monthly_emissions,
            SUM(total_emissions) as total_org_emissions,
            MAX(usage_month) as latest_month
        FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
        WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
        """
        
        kpi_results = list(client.query(kpi_query).result())
        
        logging.info(f"Processed carbon data: {len(list(results))} records")
        logging.info(f"KPIs: {kpi_results[0] if kpi_results else 'No data'}")
        
        return {
            'status': 'success',
            'records_processed': query_job.num_dml_affected_rows,
            'processing_time': datetime.now().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Error processing carbon data: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.25.0
google-cloud-functions==1.16.5
EOF
    
    log_info "Deploying data processing function..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point process_carbon_data \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME}" \
        --quiet
    
    cd ..
    
    # Create and deploy ESG report generation function
    log_info "Creating ESG report generation function..."
    mkdir -p esg-report-function
    cd esg-report-function
    
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import storage
import csv
import io
import logging

def generate_esg_report(request):
    """Generate ESG compliance report from carbon footprint data."""
    try:
        client = bigquery.Client()
        storage_client = storage.Client()
        
        # Generate comprehensive ESG report query
        report_query = f"""
        WITH monthly_trends AS (
            SELECT 
                usage_month,
                SUM(total_emissions) as monthly_total,
                AVG(total_emissions) OVER (ORDER BY usage_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as three_month_avg
            FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
            WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
            GROUP BY usage_month
        ),
        service_breakdown AS (
            SELECT 
                service,
                SUM(total_emissions) as service_emissions,
                ROUND(SUM(total_emissions) / SUM(SUM(total_emissions)) OVER () * 100, 2) as percentage
            FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
            WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
            GROUP BY service
        )
        SELECT 
            'Monthly Trends' as report_section,
            TO_JSON_STRING(ARRAY_AGG(STRUCT(usage_month, monthly_total, three_month_avg))) as data
        FROM monthly_trends
        UNION ALL
        SELECT 
            'Service Breakdown' as report_section,
            TO_JSON_STRING(ARRAY_AGG(STRUCT(service, service_emissions, percentage))) as data
        FROM service_breakdown
        """
        
        results = list(client.query(report_query).result())
        
        # Create ESG report
        report_data = {
            'report_date': datetime.now().isoformat(),
            'organization': client.project,
            'reporting_period': '12 months',
            'methodology': 'GHG Protocol compliant via Google Cloud Carbon Footprint',
            'sections': {}
        }
        
        for row in results:
            report_data['sections'][row.report_section] = json.loads(row.data)
        
        # Save report to Cloud Storage
        bucket_name = f"esg-reports-{os.environ['RANDOM_SUFFIX']}"
        
        try:
            bucket = storage_client.create_bucket(bucket_name)
        except Exception:
            bucket = storage_client.bucket(bucket_name)
        
        blob_name = f"esg-report-{datetime.now().strftime('%Y-%m-%d')}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(report_data, indent=2))
        
        logging.info(f"ESG report generated: gs://{bucket_name}/{blob_name}")
        
        return {
            'status': 'success',
            'report_location': f"gs://{bucket_name}/{blob_name}",
            'generation_time': datetime.now().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Error generating ESG report: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.25.0
google-cloud-storage==2.17.0
EOF
    
    log_info "Deploying ESG report generation function..."
    gcloud functions deploy "${REPORT_FUNCTION}" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_esg_report \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME},RANDOM_SUFFIX=${RANDOM_SUFFIX}" \
        --quiet
    
    cd ..
    
    # Create and deploy carbon alert function
    log_info "Creating carbon alert function..."
    mkdir -p carbon-alert-function
    cd carbon-alert-function
    
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
import logging

def carbon_alerts(request):
    """Monitor carbon emissions and generate sustainability alerts."""
    try:
        client = bigquery.Client()
        
        # Define sustainability thresholds
        MONTHLY_THRESHOLD = 1000  # kg CO2e
        GROWTH_THRESHOLD = 0.15   # 15% month-over-month growth
        
        # Check for threshold violations
        alert_query = f"""
        WITH current_month AS (
            SELECT 
                SUM(total_emissions) as current_emissions,
                MAX(usage_month) as current_month
            FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
            WHERE usage_month = (
                SELECT MAX(usage_month) 
                FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
            )
        ),
        previous_month AS (
            SELECT 
                SUM(total_emissions) as previous_emissions
            FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
            WHERE usage_month = DATE_SUB((
                SELECT MAX(usage_month) 
                FROM `{client.project}.{os.environ['DATASET_NAME']}.sustainability_metrics`
            ), INTERVAL 1 MONTH)
        )
        SELECT 
            c.current_emissions,
            p.previous_emissions,
            c.current_month,
            CASE 
                WHEN c.current_emissions > {MONTHLY_THRESHOLD} THEN 'THRESHOLD_EXCEEDED'
                WHEN p.previous_emissions > 0 AND 
                     (c.current_emissions - p.previous_emissions) / p.previous_emissions > {GROWTH_THRESHOLD} 
                     THEN 'HIGH_GROWTH'
                ELSE 'NORMAL'
            END as alert_type,
            ROUND(
                CASE WHEN p.previous_emissions > 0 
                     THEN (c.current_emissions - p.previous_emissions) / p.previous_emissions * 100 
                     ELSE 0 END, 2
            ) as growth_percentage
        FROM current_month c
        CROSS JOIN previous_month p
        """
        
        results = list(client.query(alert_query).result())
        
        alerts = []
        for row in results:
            if row.alert_type != 'NORMAL':
                alert = {
                    'alert_type': row.alert_type,
                    'current_emissions': float(row.current_emissions),
                    'previous_emissions': float(row.previous_emissions or 0),
                    'growth_percentage': float(row.growth_percentage),
                    'month': row.current_month.isoformat(),
                    'timestamp': datetime.now().isoformat()
                }
                alerts.append(alert)
        
        # Log alerts for monitoring
        if alerts:
            for alert in alerts:
                logging.warning(f"Sustainability Alert: {alert}")
        else:
            logging.info("No sustainability alerts triggered")
        
        return {
            'status': 'success',
            'alerts_count': len(alerts),
            'alerts': alerts,
            'check_time': datetime.now().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Error checking carbon alerts: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.25.0
EOF
    
    log_info "Deploying carbon alert function..."
    gcloud functions deploy "${ALERT_FUNCTION}" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point carbon_alerts \
        --memory 256MB \
        --timeout 120s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME}" \
        --quiet
    
    cd ..
    
    log_success "All Cloud Functions deployed successfully"
}

# Cloud Scheduler configuration
configure_scheduler() {
    step "Configuring Cloud Scheduler for automated processing"
    
    # Create scheduled job for data processing (monthly on 16th at 9 AM)
    log_info "Creating scheduled job for carbon data processing..."
    gcloud scheduler jobs create http process-carbon-data \
        --schedule="0 9 16 * *" \
        --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"scheduled"}' \
        --description="Process carbon footprint data monthly"
    
    # Create scheduled job for ESG report generation (monthly on 16th at 10 AM)
    log_info "Creating scheduled job for ESG report generation..."
    gcloud scheduler jobs create http generate-esg-reports \
        --schedule="0 10 16 * *" \
        --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${REPORT_FUNCTION}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"scheduled"}' \
        --description="Generate monthly ESG compliance reports"
    
    # Create scheduled job for carbon alerts (weekly on Mondays at 8 AM)
    log_info "Creating scheduled job for carbon emissions monitoring..."
    gcloud scheduler jobs create http carbon-alerts-check \
        --schedule="0 8 * * 1" \
        --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${ALERT_FUNCTION}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"scheduled"}' \
        --description="Weekly carbon emissions monitoring"
    
    log_success "Cloud Scheduler jobs configured"
}

# Deployment validation
validate_deployment() {
    step "Validating deployment and testing components"
    
    # Verify BigQuery dataset and table creation
    log_info "Verifying BigQuery resources..."
    if bq ls "${PROJECT_ID}" | grep -q "${DATASET_NAME}"; then
        log_success "BigQuery dataset verified"
    else
        log_error "BigQuery dataset validation failed"
        exit 1
    fi
    
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" | grep -q "sustainability_metrics"; then
        log_success "Sustainability metrics table verified"
    else
        log_error "Sustainability metrics table validation failed"
        exit 1
    fi
    
    # Test Cloud Functions deployment
    log_info "Testing Cloud Functions deployment..."
    
    # Test data processing function
    local response1
    response1=$(curl -s -X POST "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}" \
         -H "Content-Type: application/json" \
         -d '{"test": true}' || true)
    
    if [[ -n "${response1}" ]]; then
        log_success "Data processing function is responding"
    else
        log_warning "Data processing function may not be fully ready yet"
    fi
    
    # Test report generation function
    local response2
    response2=$(curl -s -X POST "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${REPORT_FUNCTION}" \
         -H "Content-Type: application/json" \
         -d '{"test": true}' || true)
    
    if [[ -n "${response2}" ]]; then
        log_success "ESG report generation function is responding"
    else
        log_warning "ESG report generation function may not be fully ready yet"
    fi
    
    # Test alert function
    local response3
    response3=$(curl -s -X POST "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${ALERT_FUNCTION}" \
         -H "Content-Type: application/json" \
         -d '{"test": true}' || true)
    
    if [[ -n "${response3}" ]]; then
        log_success "Carbon alert function is responding"
    else
        log_warning "Carbon alert function may not be fully ready yet"
    fi
    
    # Verify Cloud Scheduler jobs
    log_info "Verifying Cloud Scheduler jobs..."
    local job_count
    job_count=$(gcloud scheduler jobs list --format="value(name)" | wc -l)
    
    if [[ "${job_count}" -ge 3 ]]; then
        log_success "Cloud Scheduler jobs verified"
    else
        log_warning "Some Cloud Scheduler jobs may not be configured correctly"
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    echo "================================================================"
    echo "    Sustainability Compliance Automation Deployment Script"
    echo "================================================================"
    echo ""
    
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    setup_bigquery
    configure_carbon_export
    deploy_functions
    configure_scheduler
    validate_deployment
    
    echo ""
    echo "================================================================"
    echo "              DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "================================================================"
    echo ""
    log_success "Sustainability compliance automation infrastructure deployed!"
    echo ""
    echo "📊 RESOURCES CREATED:"
    echo "   • Project: ${PROJECT_ID}"
    echo "   • BigQuery Dataset: ${DATASET_NAME}"
    echo "   • Data Processing Function: ${FUNCTION_NAME}"
    echo "   • ESG Report Function: ${REPORT_FUNCTION}"
    echo "   • Carbon Alert Function: ${ALERT_FUNCTION}"
    echo "   • Carbon Footprint Export: Configured"
    echo "   • Cloud Scheduler Jobs: 3 jobs created"
    echo ""
    echo "🔗 FUNCTION URLS:"
    echo "   • Data Processing: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    echo "   • ESG Reports: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${REPORT_FUNCTION}"
    echo "   • Carbon Alerts: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${ALERT_FUNCTION}"
    echo ""
    echo "📅 SCHEDULER JOBS:"
    echo "   • process-carbon-data: Monthly on 16th at 9:00 AM"
    echo "   • generate-esg-reports: Monthly on 16th at 10:00 AM"
    echo "   • carbon-alerts-check: Weekly on Mondays at 8:00 AM"
    echo ""
    echo "💡 NEXT STEPS:"
    echo "   1. Carbon footprint data will be exported automatically on the 15th of each month"
    echo "   2. Monitor function logs in Cloud Logging for processing status"
    echo "   3. ESG reports will be stored in Cloud Storage bucket: esg-reports-${RANDOM_SUFFIX}"
    echo "   4. Review and customize alert thresholds in the carbon alert function as needed"
    echo ""
    echo "🧹 CLEANUP:"
    echo "   Run './destroy.sh' to remove all created resources and avoid ongoing charges"
    echo ""
    echo "📋 ESTIMATED MONTHLY COST: \$5-15 for typical usage"
    echo "================================================================"
}

# Execute main function
main "$@"