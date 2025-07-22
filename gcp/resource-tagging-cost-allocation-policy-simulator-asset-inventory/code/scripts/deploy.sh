#!/bin/bash

# Resource Tagging and Cost Allocation Deployment Script
# This script deploys a comprehensive cost allocation system using Policy Simulator and Cloud Asset Inventory

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

# Function to check prerequisites
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
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available. Please install it."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate environment variables
validate_environment() {
    log_info "Validating environment configuration..."
    
    # Get project ID
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "No default project set. Run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
    
    # Get organization ID
    export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null)
    if [[ -z "${ORGANIZATION_ID}" ]]; then
        log_error "No organization found. This script requires organization-level access."
        exit 1
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)")
    export DATASET_NAME="cost_allocation_${RANDOM_SUFFIX}"
    export FUNCTION_NAME="tag-compliance-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-billing-export-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Organization ID: ${ORGANIZATION_ID}"
    log_info "Region: ${REGION}"
    log_info "Dataset: ${DATASET_NAME}"
    log_success "Environment validation completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudasset.googleapis.com"
        "policysimulator.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "bigquery.googleapis.com"
        "cloudbilling.googleapis.com"
        "orgpolicy.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
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

# Function to create organization policy constraints
create_org_policy() {
    log_info "Creating organization policy constraints for mandatory tagging..."
    
    # Create temporary constraint file
    local constraint_file="/tmp/mandatory-tags-constraint.yaml"
    cat > "${constraint_file}" <<EOF
name: organizations/${ORGANIZATION_ID}/customConstraints/custom.mandatoryResourceTags
resourceTypes:
- compute.googleapis.com/Instance
- storage.googleapis.com/Bucket
- container.googleapis.com/Cluster
methodTypes:
- CREATE
- UPDATE
condition: |
  has(resource.labels.department) &&
  has(resource.labels.cost_center) &&
  has(resource.labels.environment) &&
  has(resource.labels.project_code)
actionType: ALLOW
displayName: "Mandatory Resource Tags"
description: "Requires department, cost_center, environment, and project_code labels on all resources"
EOF
    
    # Deploy the custom constraint
    if gcloud org-policies set-custom-constraint "${constraint_file}" --quiet; then
        log_success "Custom organization policy constraint created"
    else
        log_warning "Failed to create organization policy constraint (may already exist)"
    fi
    
    # Clean up temporary file
    rm -f "${constraint_file}"
}

# Function to create Pub/Sub infrastructure
create_pubsub() {
    log_info "Creating Pub/Sub infrastructure..."
    
    # Create topic for asset changes
    if gcloud pubsub topics create asset-changes --quiet 2>/dev/null; then
        log_success "Created Pub/Sub topic: asset-changes"
    else
        log_warning "Pub/Sub topic 'asset-changes' may already exist"
    fi
    
    # Create asset feed
    log_info "Creating Cloud Asset Inventory feed..."
    if gcloud asset feeds create resource-compliance-feed \
        --organization="${ORGANIZATION_ID}" \
        --asset-types=compute.googleapis.com/Instance,storage.googleapis.com/Bucket,container.googleapis.com/Cluster \
        --content-type=resource \
        --pubsub-topic="projects/${PROJECT_ID}/topics/asset-changes" \
        --quiet 2>/dev/null; then
        log_success "Created asset inventory feed"
    else
        log_warning "Asset feed may already exist"
    fi
}

# Function to create BigQuery infrastructure
create_bigquery() {
    log_info "Creating BigQuery infrastructure..."
    
    # Create dataset
    if bq mk --dataset \
        --description="Cost allocation and tagging analytics" \
        --location="${REGION}" \
        "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null; then
        log_success "Created BigQuery dataset: ${DATASET_NAME}"
    else
        log_warning "BigQuery dataset may already exist"
    fi
    
    # Create tag compliance table
    log_info "Creating tag compliance table..."
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.tag_compliance" \
        resource_name:STRING,resource_type:STRING,labels:JSON,compliant:BOOLEAN,timestamp:TIMESTAMP,cost_center:STRING,department:STRING,environment:STRING,project_code:STRING
    
    # Create cost allocation table
    log_info "Creating cost allocation table..."
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.cost_allocation" \
        billing_date:DATE,project_id:STRING,service:STRING,sku:STRING,cost:FLOAT,currency:STRING,department:STRING,cost_center:STRING,environment:STRING,project_code:STRING
    
    log_success "BigQuery infrastructure created"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Create temporary directory for function code
    local function_dir="/tmp/cloud-function-${RANDOM_SUFFIX}"
    mkdir -p "${function_dir}"
    
    # Create tag compliance function
    cat > "${function_dir}/main.py" <<EOF
import json
import base64
from google.cloud import bigquery
from google.cloud import asset_v1
import functions_framework
from datetime import datetime

client = bigquery.Client()

@functions_framework.cloud_event
def process_asset_change(cloud_event):
    """Process asset change notifications for tag compliance."""
    
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        asset_data = json.loads(message_data)
        
        # Extract resource information
        resource_name = asset_data.get("name", "")
        resource_type = asset_data.get("assetType", "")
        resource_data = asset_data.get("resource", {}).get("data", {})
        labels = resource_data.get("labels", {})
        
        # Check tag compliance
        required_tags = ["department", "cost_center", "environment", "project_code"]
        compliant = all(tag in labels for tag in required_tags)
        
        # Insert compliance record
        table_id = "${PROJECT_ID}.${DATASET_NAME}.tag_compliance"
        row = {
            "resource_name": resource_name,
            "resource_type": resource_type,
            "labels": json.dumps(labels),
            "compliant": compliant,
            "timestamp": datetime.utcnow().isoformat(),
            "cost_center": labels.get("cost_center", ""),
            "department": labels.get("department", ""),
            "environment": labels.get("environment", ""),
            "project_code": labels.get("project_code", "")
        }
        
        table = client.get_table(table_id)
        errors = client.insert_rows_json(table, [row])
        
        if errors:
            print(f"Error inserting row: {errors}")
        else:
            print(f"Processed asset: {resource_name}, Compliant: {compliant}")
            
    except Exception as e:
        print(f"Error processing asset change: {str(e)}")
        raise
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" <<EOF
google-cloud-bigquery>=3.0.0
google-cloud-asset>=3.0.0
functions-framework>=3.0.0
EOF
    
    # Deploy tag compliance function
    log_info "Deploying tag compliance monitoring function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python311 \
        --region="${REGION}" \
        --source="${function_dir}" \
        --entry-point=process_asset_change \
        --trigger-topic=asset-changes \
        --memory=256MB \
        --timeout=60s \
        --quiet; then
        log_success "Deployed tag compliance function: ${FUNCTION_NAME}"
    else
        log_error "Failed to deploy tag compliance function"
        exit 1
    fi
    
    # Create reporting function
    mkdir -p "/tmp/reporting-function-${RANDOM_SUFFIX}"
    local reporting_dir="/tmp/reporting-function-${RANDOM_SUFFIX}"
    
    cat > "${reporting_dir}/main.py" <<EOF
import json
from google.cloud import bigquery
from google.cloud import storage
import pandas as pd
from datetime import datetime, timedelta
import functions_framework

@functions_framework.http
def generate_cost_report(request):
    """Generate weekly cost allocation report."""
    
    try:
        client = bigquery.Client()
        
        # Query cost allocation data
        query = f"""
        SELECT *
        FROM \`${PROJECT_ID}.${DATASET_NAME}.cost_allocation_summary\`
        WHERE billing_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        ORDER BY total_cost DESC
        """
        
        try:
            df = client.query(query).to_dataframe()
        except Exception as e:
            # If view doesn't exist yet, return basic response
            return json.dumps({
                'report_date': datetime.now().isoformat(),
                'status': 'No data available yet',
                'message': 'Billing export and views need to be configured manually'
            }, indent=2)
        
        # Generate report summary
        if not df.empty:
            total_cost = df['total_cost'].sum()
            top_departments = df.groupby('department')['total_cost'].sum().head(5)
            
            report = {
                'report_date': datetime.now().isoformat(),
                'total_weekly_cost': float(total_cost),
                'currency': df['currency'].iloc[0] if not df.empty else 'USD',
                'top_departments': top_departments.to_dict(),
                'resource_count': len(df),
                'compliance_summary': 'See compliance dashboard for details'
            }
        else:
            report = {
                'report_date': datetime.now().isoformat(),
                'total_weekly_cost': 0.0,
                'currency': 'USD',
                'top_departments': {},
                'resource_count': 0,
                'compliance_summary': 'No data available'
            }
        
        # Store report in Cloud Storage if bucket exists
        try:
            storage_client = storage.Client()
            bucket = storage_client.bucket('${BUCKET_NAME}')
            blob = bucket.blob(f"reports/cost-allocation-{datetime.now().strftime('%Y-%m-%d')}.json")
            blob.upload_from_string(json.dumps(report, indent=2))
        except Exception as e:
            print(f"Warning: Could not store report in Cloud Storage: {e}")
        
        return json.dumps(report, indent=2)
        
    except Exception as e:
        error_response = {
            'error': str(e),
            'report_date': datetime.now().isoformat(),
            'status': 'error'
        }
        return json.dumps(error_response, indent=2)
EOF
    
    cat > "${reporting_dir}/requirements.txt" <<EOF
google-cloud-bigquery>=3.0.0
google-cloud-storage>=2.0.0
pandas>=1.5.0
functions-framework>=3.0.0
EOF
    
    # Deploy reporting function
    log_info "Deploying cost allocation reporting function..."
    if gcloud functions deploy cost-allocation-reporter \
        --gen2 \
        --runtime=python311 \
        --region="${REGION}" \
        --source="${reporting_dir}" \
        --entry-point=generate_cost_report \
        --trigger-http \
        --allow-unauthenticated \
        --memory=512MB \
        --timeout=300s \
        --quiet; then
        log_success "Deployed reporting function: cost-allocation-reporter"
    else
        log_error "Failed to deploy reporting function"
        exit 1
    fi
    
    # Clean up temporary directories
    rm -rf "${function_dir}" "${reporting_dir}"
}

# Function to create Cloud Storage bucket
create_storage() {
    log_info "Creating Cloud Storage bucket for billing export..."
    
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" 2>/dev/null; then
        log_success "Created Cloud Storage bucket: ${BUCKET_NAME}"
    else
        log_warning "Storage bucket may already exist"
    fi
}

# Function to create BigQuery views
create_bigquery_views() {
    log_info "Creating BigQuery analysis views..."
    
    # Create cost allocation view
    local cost_view_sql="
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.cost_allocation_summary\` AS
    SELECT
      DATE(usage_start_time) as billing_date,
      project.id as project_id,
      service.description as service_name,
      sku.description as sku_description,
      SUM(cost) as total_cost,
      currency,
      labels.value as department,
      tags.value as cost_center,
      location.location as region,
      COUNT(*) as resource_count
    FROM \`${PROJECT_ID}.${DATASET_NAME}.gcp_billing_export_v1_*\`
    WHERE
      DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
      AND labels.key = 'department'
      AND tags.key = 'cost_center'
    GROUP BY
      billing_date, project_id, service_name, sku_description,
      currency, department, cost_center, region
    ORDER BY
      billing_date DESC, total_cost DESC
    "
    
    # Create compliance summary view
    local compliance_view_sql="
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.compliance_summary\` AS
    SELECT
      DATE(timestamp) as compliance_date,
      resource_type,
      department,
      cost_center,
      environment,
      COUNT(*) as total_resources,
      SUM(CASE WHEN compliant THEN 1 ELSE 0 END) as compliant_resources,
      ROUND(100.0 * SUM(CASE WHEN compliant THEN 1 ELSE 0 END) / COUNT(*), 2) as compliance_percentage
    FROM \`${PROJECT_ID}.${DATASET_NAME}.tag_compliance\`
    WHERE
      DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    GROUP BY
      compliance_date, resource_type, department, cost_center, environment
    ORDER BY
      compliance_date DESC, compliance_percentage ASC
    "
    
    # Execute view creation (these may fail if billing export isn't configured yet)
    if echo "${cost_view_sql}" | bq query --use_legacy_sql=false 2>/dev/null; then
        log_success "Created cost allocation view"
    else
        log_warning "Cost allocation view creation failed (billing export may not be configured)"
    fi
    
    if echo "${compliance_view_sql}" | bq query --use_legacy_sql=false 2>/dev/null; then
        log_success "Created compliance summary view"
    else
        log_warning "Compliance summary view creation failed"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "==================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Organization ID: ${ORGANIZATION_ID}"
    echo "Region: ${REGION}"
    echo "BigQuery Dataset: ${DATASET_NAME}"
    echo "Tag Compliance Function: ${FUNCTION_NAME}"
    echo "Reporting Function: cost-allocation-reporter"
    echo "Storage Bucket: ${BUCKET_NAME}"
    echo "Pub/Sub Topic: asset-changes"
    echo ""
    log_info "Next Steps:"
    echo "1. Configure Cloud Billing export to BigQuery dataset: ${DATASET_NAME}"
    echo "2. Test the system by creating resources with required tags"
    echo "3. Access reporting function at:"
    echo "   https://${REGION}-${PROJECT_ID}.cloudfunctions.net/cost-allocation-reporter"
    echo ""
    log_warning "IMPORTANT: Configure billing export manually in Cloud Console:"
    echo "  - Go to Cloud Billing > Billing export"
    echo "  - Enable BigQuery export to dataset: ${PROJECT_ID}:${DATASET_NAME}"
    echo "  - Enable detailed usage cost data export"
}

# Function to test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test creating a compliant resource
    log_info "Testing compliant resource creation..."
    if gcloud compute instances create "test-instance-compliant-${RANDOM_SUFFIX}" \
        --zone="${ZONE}" \
        --machine-type=e2-micro \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --labels=department=engineering,cost_center=cc-001,environment=test,project_code=proj-123 \
        --quiet 2>/dev/null; then
        log_success "Compliant test resource created successfully"
        
        # Clean up test resource
        sleep 10
        gcloud compute instances delete "test-instance-compliant-${RANDOM_SUFFIX}" \
            --zone="${ZONE}" \
            --quiet 2>/dev/null || true
        log_info "Test resource cleaned up"
    else
        log_warning "Test resource creation failed (may be expected if policies are enforced)"
    fi
    
    # Test reporting function
    log_info "Testing reporting function..."
    local function_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/cost-allocation-reporter"
    if curl -s "${function_url}" > /dev/null; then
        log_success "Reporting function is accessible"
    else
        log_warning "Reporting function test failed"
    fi
}

# Main deployment function
main() {
    log_info "Starting Resource Tagging and Cost Allocation deployment..."
    
    # Run all deployment steps
    check_prerequisites
    validate_environment
    enable_apis
    create_org_policy
    create_pubsub
    create_bigquery
    deploy_functions
    create_storage
    create_bigquery_views
    test_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"