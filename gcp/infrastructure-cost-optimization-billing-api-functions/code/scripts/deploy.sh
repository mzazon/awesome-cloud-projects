#!/bin/bash

# Infrastructure Cost Optimization with Cloud Billing API and Cloud Functions - Deploy Script
# This script deploys a comprehensive cost optimization system using Google Cloud services

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/tmp/cost-optimization-deploy-$(date +%Y%m%d-%H%M%S).log"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_BUDGET_AMOUNT="1000"

# Global variables
PROJECT_ID=""
BILLING_ACCOUNT_ID=""
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
BUDGET_AMOUNT="${DEFAULT_BUDGET_AMOUNT}"
RANDOM_SUFFIX=""
DATASET_NAME=""
FUNCTION_PREFIX=""
BUDGET_NAME=""
SKIP_CONFIRMATIONS=false
DRY_RUN=false

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
    log_error "Deployment failed. Check log file: ${LOG_FILE}"
    log_error "To clean up any partially created resources, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Infrastructure Cost Optimization Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required)
    -b, --billing-account ACCOUNT   Billing Account ID (required)
    -r, --region REGION             Deployment region (default: ${DEFAULT_REGION})
    -z, --zone ZONE                 Deployment zone (default: ${DEFAULT_ZONE})
    -a, --budget-amount AMOUNT      Budget amount in USD (default: ${DEFAULT_BUDGET_AMOUNT})
    -y, --yes                       Skip confirmation prompts
    --dry-run                       Show what would be deployed without making changes
    -h, --help                      Show this help message

EXAMPLES:
    $0 -p my-project-123 -b 01234A-5678BC-9DEFGH
    $0 -p my-project -b my-billing-account -r us-west1 -a 2000 -y

REQUIREMENTS:
    - gcloud CLI installed and authenticated
    - Billing Account Administrator or Billing Account Costs Manager roles
    - Project Editor or Owner permissions on target project

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -b|--billing-account)
                BILLING_ACCOUNT_ID="$2"
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
            -a|--budget-amount)
                BUDGET_AMOUNT="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRMATIONS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use -p or --project-id"
        exit 1
    fi

    if [[ -z "$BILLING_ACCOUNT_ID" ]]; then
        log_error "Billing Account ID is required. Use -b or --billing-account"
        exit 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or is not accessible."
        exit 1
    fi

    # Validate billing account
    if ! gcloud beta billing accounts describe "$BILLING_ACCOUNT_ID" &> /dev/null; then
        log_error "Billing account '$BILLING_ACCOUNT_ID' does not exist or is not accessible."
        exit 1
    fi

    # Check if project is linked to billing account
    CURRENT_BILLING=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ "$CURRENT_BILLING" != "billingAccounts/$BILLING_ACCOUNT_ID" ]]; then
        log_warning "Project is not linked to the specified billing account. Will attempt to link during deployment."
    fi

    log_success "Prerequisites validation completed"
}

# Initialize variables
initialize_variables() {
    log_info "Initializing deployment variables..."

    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    DATASET_NAME="cost_optimization_${RANDOM_SUFFIX}"
    FUNCTION_PREFIX="cost-opt-${RANDOM_SUFFIX}"
    BUDGET_NAME="cost-optimization-budget-${RANDOM_SUFFIX}"

    log_info "Using random suffix: ${RANDOM_SUFFIX}"
    log_info "Dataset name: ${DATASET_NAME}"
    log_info "Function prefix: ${FUNCTION_PREFIX}"
    log_info "Budget name: ${BUDGET_NAME}"
}

# Display deployment plan
show_deployment_plan() {
    cat << EOF

${BLUE}=== DEPLOYMENT PLAN ===${NC}

Project ID:           ${PROJECT_ID}
Billing Account:      ${BILLING_ACCOUNT_ID}
Region:              ${REGION}
Zone:                ${ZONE}
Budget Amount:       \$${BUDGET_AMOUNT} USD

Resources to be created:
├── BigQuery Dataset: ${DATASET_NAME}
├── Cloud Functions:
│   ├── ${FUNCTION_PREFIX}-cost-analysis
│   ├── ${FUNCTION_PREFIX}-anomaly-detection
│   └── ${FUNCTION_PREFIX}-optimization
├── Pub/Sub:
│   ├── Topic: cost-optimization-alerts
│   ├── Subscription: budget-alerts-sub
│   └── Subscription: anomaly-detection-sub
├── Cloud Scheduler:
│   ├── Job: cost-analysis-scheduler
│   └── Job: optimization-scheduler
└── Budget: ${BUDGET_NAME}

Estimated monthly cost: \$15-25 USD

EOF

    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: No resources will be created"
        exit 0
    fi

    if [[ "$SKIP_CONFIRMATIONS" != true ]]; then
        read -p "Do you want to proceed with this deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Configure Google Cloud project
configure_project() {
    log_info "Configuring Google Cloud project..."

    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"

    # Link project to billing account if needed
    CURRENT_BILLING=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ "$CURRENT_BILLING" != "billingAccounts/$BILLING_ACCOUNT_ID" ]]; then
        log_info "Linking project to billing account..."
        gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
    fi

    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "cloudbilling.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "monitoring.googleapis.com"
        "pubsub.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "$api"
    done

    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30

    log_success "All required APIs enabled"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."

    # Create dataset
    bq mk --dataset \
        --location="$REGION" \
        --description="Cost optimization and billing analytics dataset" \
        "$PROJECT_ID:$DATASET_NAME"

    # Create cost anomalies table
    bq mk --table \
        "$PROJECT_ID:$DATASET_NAME.cost_anomalies" \
        detection_date:TIMESTAMP,project_id:STRING,service:STRING,expected_cost:FLOAT,actual_cost:FLOAT,deviation_percent:FLOAT,anomaly_type:STRING

    log_success "BigQuery resources created"
}

# Set up billing export
setup_billing_export() {
    log_info "Setting up billing data export to BigQuery..."

    # Note: Billing export setup typically requires manual configuration
    # through the Cloud Console as it involves billing account level permissions
    log_warning "Billing export to BigQuery requires manual setup through Cloud Console"
    log_info "Please follow these steps in Cloud Console:"
    log_info "1. Go to Billing > Billing export"
    log_info "2. Create export to BigQuery dataset: $PROJECT_ID:$DATASET_NAME"
    log_info "3. Enable both standard and detailed usage cost data"

    log_success "Billing export configuration noted (manual setup required)"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topics and subscriptions..."

    # Create topic
    gcloud pubsub topics create cost-optimization-alerts

    # Create subscriptions
    gcloud pubsub subscriptions create budget-alerts-sub \
        --topic=cost-optimization-alerts

    gcloud pubsub subscriptions create anomaly-detection-sub \
        --topic=cost-optimization-alerts

    log_success "Pub/Sub resources created"
}

# Create function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."

    local functions_dir="$PROJECT_ROOT/functions"
    mkdir -p "$functions_dir"

    # Create cost analysis function
    mkdir -p "$functions_dir/cost-analysis"
    cat > "$functions_dir/cost-analysis/main.py" << 'EOF'
import functions_framework
from google.cloud import bigquery
from google.cloud import monitoring_v3
import json
import os
from datetime import datetime, timedelta

@functions_framework.http
def analyze_costs(request):
    """Analyze cost trends and generate optimization recommendations."""
    
    client = bigquery.Client()
    project_id = os.environ.get('GCP_PROJECT')
    dataset_name = os.environ.get('DATASET_NAME')
    
    try:
        # Query for cost trends over the last 30 days
        query = f"""
        SELECT 
            service.description as service_name,
            DATE(usage_start_time) as usage_date,
            SUM(cost) as daily_cost,
            AVG(cost) OVER (
                PARTITION BY service.description 
                ORDER BY DATE(usage_start_time) 
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ) as avg_weekly_cost
        FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
        WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY service_name, usage_date
        ORDER BY usage_date DESC, daily_cost DESC
        """
        
        results = client.query(query).result()
        
        # Analyze results for optimization opportunities
        recommendations = []
        for row in results:
            if row.daily_cost > row.avg_weekly_cost * 1.2:
                recommendations.append({
                    'service': row.service_name,
                    'date': row.usage_date.isoformat(),
                    'current_cost': row.daily_cost,
                    'average_cost': row.avg_weekly_cost,
                    'recommendation': f'Cost spike detected for {row.service_name}. Consider reviewing resource usage.'
                })
        
        return {
            'status': 'success',
            'timestamp': datetime.now().isoformat(),
            'recommendations': recommendations[:10],
            'total_recommendations': len(recommendations)
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }
EOF

    cat > "$functions_dir/cost-analysis/requirements.txt" << 'EOF'
functions-framework==3.8.1
google-cloud-bigquery==3.25.0
google-cloud-monitoring==2.22.2
EOF

    # Create anomaly detection function
    mkdir -p "$functions_dir/anomaly-detection"
    cat > "$functions_dir/anomaly-detection/main.py" << 'EOF'
import functions_framework
from google.cloud import bigquery
from google.cloud import pubsub_v1
import json
import os
import statistics
from datetime import datetime, timedelta

@functions_framework.cloud_event
def detect_anomalies(cloud_event):
    """Detect cost anomalies and send alerts."""
    
    client = bigquery.Client()
    publisher = pubsub_v1.PublisherClient()
    
    project_id = os.environ.get('GCP_PROJECT')
    dataset_name = os.environ.get('DATASET_NAME')
    topic_path = publisher.topic_path(project_id, 'cost-optimization-alerts')
    
    try:
        # Query recent cost data for anomaly detection
        query = f"""
        WITH daily_costs AS (
            SELECT 
                project.id as project_id,
                service.description as service_name,
                DATE(usage_start_time) as usage_date,
                SUM(cost) as daily_cost
            FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
            WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
            GROUP BY project_id, service_name, usage_date
        ),
        stats AS (
            SELECT 
                project_id,
                service_name,
                AVG(daily_cost) as avg_cost,
                STDDEV(daily_cost) as std_cost
            FROM daily_costs
            WHERE usage_date < CURRENT_DATE()
            GROUP BY project_id, service_name
        )
        SELECT 
            dc.project_id,
            dc.service_name,
            dc.daily_cost,
            s.avg_cost,
            s.std_cost,
            ABS(dc.daily_cost - s.avg_cost) / s.std_cost as z_score
        FROM daily_costs dc
        JOIN stats s ON dc.project_id = s.project_id AND dc.service_name = s.service_name
        WHERE dc.usage_date = CURRENT_DATE()
        AND ABS(dc.daily_cost - s.avg_cost) / s.std_cost > 2.0
        ORDER BY z_score DESC
        """
        
        results = client.query(query).result()
        
        # Process anomalies and send alerts
        for row in results:
            anomaly = {
                'type': 'cost_anomaly',
                'project_id': row.project_id,
                'service': row.service_name,
                'current_cost': float(row.daily_cost),
                'expected_cost': float(row.avg_cost),
                'z_score': float(row.z_score),
                'severity': 'high' if row.z_score > 3.0 else 'medium',
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to Pub/Sub
            message = json.dumps(anomaly).encode('utf-8')
            publisher.publish(topic_path, message)
            
            # Store in BigQuery for tracking
            insert_query = f"""
            INSERT INTO `{project_id}.{dataset_name}.cost_anomalies`
            VALUES (
                CURRENT_TIMESTAMP(),
                '{row.project_id}',
                '{row.service_name}',
                {row.avg_cost},
                {row.daily_cost},
                {(row.daily_cost - row.avg_cost) / row.avg_cost * 100},
                'statistical_anomaly'
            )
            """
            client.query(insert_query)
        
        return f"Processed {results.total_rows} potential anomalies"
        
    except Exception as e:
        print(f"Error in anomaly detection: {str(e)}")
        return f"Error: {str(e)}"
EOF

    cat > "$functions_dir/anomaly-detection/requirements.txt" << 'EOF'
functions-framework==3.8.1
google-cloud-bigquery==3.25.0
google-cloud-pubsub==2.26.1
EOF

    # Create optimization function
    mkdir -p "$functions_dir/optimization"
    cat > "$functions_dir/optimization/main.py" << 'EOF'
import functions_framework
from google.cloud import bigquery
from google.cloud import monitoring_v3
import json
import os
from datetime import datetime, timedelta

@functions_framework.http
def optimize_resources(request):
    """Generate resource optimization recommendations."""
    
    client = bigquery.Client()
    monitoring_client = monitoring_v3.MetricServiceClient()
    
    project_id = os.environ.get('GCP_PROJECT')
    dataset_name = os.environ.get('DATASET_NAME')
    
    try:
        # Analyze compute instance usage patterns
        compute_query = f"""
        SELECT 
            resource.labels.instance_id,
            resource.labels.zone,
            SUM(cost) as total_cost,
            COUNT(DISTINCT DATE(usage_start_time)) as active_days
        FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
        WHERE service.description = 'Compute Engine'
        AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY instance_id, zone
        HAVING total_cost > 0
        ORDER BY total_cost DESC
        """
        
        compute_results = client.query(compute_query).result()
        
        # Analyze storage usage
        storage_query = f"""
        SELECT 
            sku.description,
            SUM(cost) as total_cost,
            SUM(usage.amount) as usage_amount,
            usage.unit
        FROM `{project_id}.{dataset_name}.gcp_billing_export_v1_*`
        WHERE service.description = 'Cloud Storage'
        AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY sku.description, usage.unit
        ORDER BY total_cost DESC
        """
        
        storage_results = client.query(storage_query).result()
        
        # Generate optimization recommendations
        recommendations = []
        
        # Compute optimizations
        for row in compute_results:
            if row.active_days < 7:
                recommendations.append({
                    'type': 'compute_scheduling',
                    'resource': row.instance_id,
                    'zone': row.zone,
                    'current_cost': float(row.total_cost),
                    'recommendation': 'Consider scheduling instance shutdown during off-hours',
                    'potential_savings': float(row.total_cost) * 0.3
                })
        
        # Storage optimizations
        for row in storage_results:
            if 'Standard' in row.sku_description and row.total_cost > 50:
                recommendations.append({
                    'type': 'storage_lifecycle',
                    'resource': row.sku_description,
                    'current_cost': float(row.total_cost),
                    'recommendation': 'Implement lifecycle policies for long-term storage',
                    'potential_savings': float(row.total_cost) * 0.4
                })
        
        # Calculate total potential savings
        total_savings = sum(r.get('potential_savings', 0) for r in recommendations)
        
        return {
            'status': 'success',
            'timestamp': datetime.now().isoformat(),
            'recommendations': recommendations[:15],
            'total_potential_savings': total_savings,
            'summary': {
                'compute_recommendations': len([r for r in recommendations if r['type'] == 'compute_scheduling']),
                'storage_recommendations': len([r for r in recommendations if r['type'] == 'storage_lifecycle'])
            }
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }
EOF

    cat > "$functions_dir/optimization/requirements.txt" << 'EOF'
functions-framework==3.8.1
google-cloud-bigquery==3.25.0
google-cloud-monitoring==2.22.2
EOF

    log_success "Cloud Function source code created"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."

    local functions_dir="$PROJECT_ROOT/functions"

    # Deploy cost analysis function
    log_info "Deploying cost analysis function..."
    (cd "$functions_dir/cost-analysis" && \
        gcloud functions deploy "$FUNCTION_PREFIX-cost-analysis" \
            --runtime=python311 \
            --trigger=http \
            --entry-point=analyze_costs \
            --memory=512MB \
            --timeout=540s \
            --set-env-vars="DATASET_NAME=$DATASET_NAME" \
            --allow-unauthenticated)

    # Deploy anomaly detection function
    log_info "Deploying anomaly detection function..."
    (cd "$functions_dir/anomaly-detection" && \
        gcloud functions deploy "$FUNCTION_PREFIX-anomaly-detection" \
            --runtime=python311 \
            --trigger=topic=cost-optimization-alerts \
            --entry-point=detect_anomalies \
            --memory=512MB \
            --timeout=540s \
            --set-env-vars="DATASET_NAME=$DATASET_NAME")

    # Deploy optimization function
    log_info "Deploying optimization function..."
    (cd "$functions_dir/optimization" && \
        gcloud functions deploy "$FUNCTION_PREFIX-optimization" \
            --runtime=python311 \
            --trigger=http \
            --entry-point=optimize_resources \
            --memory=512MB \
            --timeout=540s \
            --set-env-vars="DATASET_NAME=$DATASET_NAME" \
            --allow-unauthenticated)

    log_success "Cloud Functions deployed"
}

# Create budget configuration
create_budget() {
    log_info "Creating budget with alerts..."

    # Create budget configuration file
    cat > "$PROJECT_ROOT/budget-config.json" << EOF
{
  "displayName": "$BUDGET_NAME",
  "budgetFilter": {
    "projects": ["projects/$PROJECT_ID"]
  },
  "amount": {
    "specifiedAmount": {
      "currencyCode": "USD",
      "units": "$BUDGET_AMOUNT"
    }
  },
  "thresholdRules": [
    {
      "thresholdPercent": 0.5,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 0.9,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 1.0,
      "spendBasis": "FORECASTED_SPEND"
    }
  ],
  "allUpdatesRule": {
    "pubsubTopic": "projects/$PROJECT_ID/topics/cost-optimization-alerts"
  }
}
EOF

    # Create budget using REST API
    local billing_account
    billing_account=$(gcloud beta billing accounts list --format="value(name.basename())" --limit=1)

    curl -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @"$PROJECT_ROOT/budget-config.json" \
        "https://billingbudgets.googleapis.com/v1/billingAccounts/$billing_account/budgets"

    log_success "Budget created with Pub/Sub notifications"
}

# Set up scheduled jobs
setup_scheduling() {
    log_info "Setting up Cloud Scheduler jobs..."

    # Create daily cost analysis job
    gcloud scheduler jobs create http cost-analysis-scheduler \
        --schedule="0 9 * * *" \
        --uri="https://$REGION-$PROJECT_ID.cloudfunctions.net/$FUNCTION_PREFIX-cost-analysis" \
        --http-method=GET \
        --description="Daily cost analysis and optimization recommendations"

    # Create weekly optimization review job
    gcloud scheduler jobs create http optimization-scheduler \
        --schedule="0 9 * * 1" \
        --uri="https://$REGION-$PROJECT_ID.cloudfunctions.net/$FUNCTION_PREFIX-optimization" \
        --http-method=GET \
        --description="Weekly resource optimization analysis"

    log_success "Cloud Scheduler jobs created"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f "$PROJECT_ROOT/budget-config.json"
    
    log_success "Temporary files cleaned up"
}

# Display deployment summary
show_deployment_summary() {
    cat << EOF

${GREEN}=== DEPLOYMENT COMPLETED SUCCESSFULLY ===${NC}

Project: ${PROJECT_ID}
Region: ${REGION}

Created Resources:
├── BigQuery Dataset: ${DATASET_NAME}
├── Cloud Functions:
│   ├── ${FUNCTION_PREFIX}-cost-analysis
│   ├── ${FUNCTION_PREFIX}-anomaly-detection
│   └── ${FUNCTION_PREFIX}-optimization
├── Pub/Sub:
│   ├── Topic: cost-optimization-alerts
│   ├── Subscription: budget-alerts-sub
│   └── Subscription: anomaly-detection-sub
├── Cloud Scheduler:
│   ├── Job: cost-analysis-scheduler
│   └── Job: optimization-scheduler
└── Budget: ${BUDGET_NAME}

Next Steps:
1. Set up billing export in Cloud Console:
   - Go to Billing > Billing export
   - Create export to BigQuery dataset: ${PROJECT_ID}:${DATASET_NAME}

2. Test the functions:
   - Cost Analysis: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-cost-analysis
   - Optimization: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-optimization

3. Monitor the system:
   - Check Cloud Scheduler for job execution
   - Monitor Pub/Sub topics for alerts
   - Review BigQuery for cost data

Estimated Monthly Cost: \$15-25 USD

Log file: ${LOG_FILE}

EOF
}

# Main deployment function
main() {
    log_info "Starting Infrastructure Cost Optimization deployment..."
    log_info "Log file: ${LOG_FILE}"

    parse_args "$@"
    validate_prerequisites
    initialize_variables
    show_deployment_plan

    configure_project
    enable_apis
    create_bigquery_resources
    setup_billing_export
    create_pubsub_resources
    create_function_source
    deploy_functions
    create_budget
    setup_scheduling
    cleanup_temp_files

    show_deployment_summary
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"