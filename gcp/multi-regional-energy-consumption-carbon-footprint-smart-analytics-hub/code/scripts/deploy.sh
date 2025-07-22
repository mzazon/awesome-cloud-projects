#!/bin/bash

# Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub - Deployment Script
# This script deploys a comprehensive carbon optimization system using Google Cloud services
# 
# Prerequisites:
# - Google Cloud SDK installed and authenticated
# - Billing account configured
# - Project Owner or Editor permissions
# - Required APIs enabled

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
BILLING_ACCOUNT_ID=""
DRY_RUN=false
VERBOSE=false
SKIP_APIS=false

# Resource naming variables
RANDOM_SUFFIX=""
DATASET_NAME=""
EXCHANGE_NAME=""
FUNCTION_NAME=""
SCHEDULER_JOB=""

# Required APIs
readonly REQUIRED_APIS=(
    "cloudfunctions.googleapis.com"
    "cloudscheduler.googleapis.com"
    "bigquery.googleapis.com"
    "monitoring.googleapis.com"
    "cloudbuild.googleapis.com"
    "analyticshub.googleapis.com"
)

# Function to log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log "INFO" "${message}"
}

# Function to print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION            GCP region (default: us-central1)
    -z, --zone ZONE                GCP zone (default: us-central1-a)
    -b, --billing-account BILLING  Billing account ID (required)
    -d, --dry-run                  Show what would be deployed without executing
    -v, --verbose                  Enable verbose output
    -s, --skip-apis               Skip API enablement (assumes APIs are enabled)
    -h, --help                    Show this help message

EXAMPLES:
    $0 -p my-project-id -b 01234-56789A-BCDEF0
    $0 --project-id my-project --billing-account 01234-56789A-BCDEF0 --region europe-west1
    $0 -p my-project -b 01234-56789A-BCDEF0 --dry-run

EOF
}

# Function to validate prerequisites
validate_prerequisites() {
    print_status "${BLUE}" "🔍 Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_status "${RED}" "❌ Google Cloud SDK is not installed"
        log "ERROR" "gcloud command not found"
        exit 1
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        print_status "${RED}" "❌ Not authenticated with Google Cloud SDK"
        log "ERROR" "No active gcloud authentication found"
        exit 1
    fi

    # Validate project ID format
    if [[ ! "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        print_status "${RED}" "❌ Invalid project ID format: ${PROJECT_ID}"
        log "ERROR" "Project ID must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi

    # Validate billing account format
    if [[ ! "${BILLING_ACCOUNT_ID}" =~ ^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$ ]]; then
        print_status "${RED}" "❌ Invalid billing account format: ${BILLING_ACCOUNT_ID}"
        log "ERROR" "Billing account ID should be in format: 01234-56789A-BCDEF0"
        exit 1
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        print_status "${YELLOW}" "⚠️  Project ${PROJECT_ID} does not exist or is not accessible"
        log "WARN" "Project ${PROJECT_ID} not found"
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            read -p "Do you want to create the project? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "${BLUE}" "📝 Creating project ${PROJECT_ID}..."
                gcloud projects create "${PROJECT_ID}" --name="${PROJECT_ID}" || {
                    print_status "${RED}" "❌ Failed to create project"
                    exit 1
                }
            else
                print_status "${RED}" "❌ Cannot proceed without valid project"
                exit 1
            fi
        fi
    fi

    print_status "${GREEN}" "✅ Prerequisites validation completed"
}

# Function to set up project configuration
setup_project() {
    print_status "${BLUE}" "🔧 Setting up project configuration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would set project to: ${PROJECT_ID}"
        print_status "${YELLOW}" "[DRY RUN] Would set region to: ${REGION}"
        print_status "${YELLOW}" "[DRY RUN] Would set zone to: ${ZONE}"
        return 0
    fi

    # Set default project
    gcloud config set project "${PROJECT_ID}" || {
        print_status "${RED}" "❌ Failed to set project configuration"
        exit 1
    }

    # Set default region and zone
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"

    # Link billing account if provided
    if [[ -n "${BILLING_ACCOUNT_ID}" ]]; then
        print_status "${BLUE}" "💳 Linking billing account..."
        gcloud billing projects link "${PROJECT_ID}" \
            --billing-account="${BILLING_ACCOUNT_ID}" || {
            print_status "${RED}" "❌ Failed to link billing account"
            exit 1
        }
    fi

    print_status "${GREEN}" "✅ Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    if [[ "${SKIP_APIS}" == "true" ]]; then
        print_status "${YELLOW}" "⏭️  Skipping API enablement (--skip-apis flag set)"
        return 0
    fi

    print_status "${BLUE}" "🔌 Enabling required APIs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        for api in "${REQUIRED_APIS[@]}"; do
            print_status "${YELLOW}" "[DRY RUN] Would enable API: ${api}"
        done
        return 0
    fi

    # Enable APIs in parallel for faster deployment
    local api_jobs=()
    for api in "${REQUIRED_APIS[@]}"; do
        print_status "${BLUE}" "📡 Enabling ${api}..."
        (
            gcloud services enable "${api}" --quiet && \
            log "INFO" "Successfully enabled ${api}"
        ) &
        api_jobs+=($!)
    done

    # Wait for all API enablement jobs to complete
    local failed_apis=()
    for i in "${!api_jobs[@]}"; do
        if ! wait "${api_jobs[$i]}"; then
            failed_apis+=("${REQUIRED_APIS[$i]}")
        fi
    done

    if [[ ${#failed_apis[@]} -gt 0 ]]; then
        print_status "${RED}" "❌ Failed to enable APIs: ${failed_apis[*]}"
        exit 1
    fi

    print_status "${GREEN}" "✅ All required APIs enabled successfully"
}

# Function to generate unique resource names
generate_resource_names() {
    print_status "${BLUE}" "🏷️  Generating unique resource names..."

    # Generate random suffix for uniqueness
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with random suffix
    DATASET_NAME="carbon_analytics_${RANDOM_SUFFIX}"
    EXCHANGE_NAME="energy-optimization-exchange-${RANDOM_SUFFIX}"
    FUNCTION_NAME="workload-optimizer-${RANDOM_SUFFIX}"
    SCHEDULER_JOB="carbon-optimizer-${RANDOM_SUFFIX}"

    if [[ "${VERBOSE}" == "true" ]]; then
        print_status "${BLUE}" "📋 Resource names:"
        echo "  Dataset: ${DATASET_NAME}"
        echo "  Exchange: ${EXCHANGE_NAME}"
        echo "  Function: ${FUNCTION_NAME}"
        echo "  Scheduler: ${SCHEDULER_JOB}"
    fi

    print_status "${GREEN}" "✅ Resource names generated"
}

# Function to create BigQuery resources
create_bigquery_resources() {
    print_status "${BLUE}" "📊 Creating BigQuery resources..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would create BigQuery dataset: ${DATASET_NAME}"
        print_status "${YELLOW}" "[DRY RUN] Would create tables: carbon_footprint, workload_schedules"
        return 0
    fi

    # Create BigQuery dataset
    bq mk --dataset \
        --description "Carbon footprint and energy optimization analytics" \
        --location="${REGION}" \
        "${PROJECT_ID}:${DATASET_NAME}" || {
        print_status "${RED}" "❌ Failed to create BigQuery dataset"
        exit 1
    }

    # Create carbon footprint table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.carbon_footprint" \
        timestamp:TIMESTAMP,region:STRING,service:STRING,carbon_emissions_kg:FLOAT,energy_kwh:FLOAT,carbon_intensity:FLOAT || {
        print_status "${RED}" "❌ Failed to create carbon_footprint table"
        exit 1
    }

    # Create workload schedules table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.workload_schedules" \
        timestamp:TIMESTAMP,workload_id:STRING,source_region:STRING,target_region:STRING,carbon_savings_kg:FLOAT,reason:STRING || {
        print_status "${RED}" "❌ Failed to create workload_schedules table"
        exit 1
    }

    print_status "${GREEN}" "✅ BigQuery resources created successfully"
}

# Function to set up Analytics Hub
setup_analytics_hub() {
    print_status "${BLUE}" "🔄 Setting up Analytics Hub..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would create Analytics Hub exchange: ${EXCHANGE_NAME}"
        print_status "${YELLOW}" "[DRY RUN] Would create carbon footprint listing"
        return 0
    fi

    # Create Analytics Hub data exchange
    bq mk --data_exchange \
        --location="${REGION}" \
        --display_name="Energy Optimization Exchange" \
        --description="Shared carbon footprint and energy optimization data" \
        "${EXCHANGE_NAME}" || {
        print_status "${RED}" "❌ Failed to create Analytics Hub exchange"
        exit 1
    }

    # Create listing for carbon footprint dataset
    bq mk --listing \
        --data_exchange="${EXCHANGE_NAME}" \
        --location="${REGION}" \
        --display_name="Carbon Footprint Analytics" \
        --description="Regional carbon emissions and energy optimization data" \
        --source_dataset="${PROJECT_ID}:${DATASET_NAME}" \
        carbon-footprint-listing || {
        print_status "${RED}" "❌ Failed to create Analytics Hub listing"
        exit 1
    }

    print_status "${GREEN}" "✅ Analytics Hub configured successfully"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    print_status "${BLUE}" "⚡ Deploying Cloud Functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would deploy Cloud Function: ${FUNCTION_NAME}"
        print_status "${YELLOW}" "[DRY RUN] Would deploy workload migration function"
        return 0
    fi

    # Create temporary directory for function source
    local function_dir=$(mktemp -d)
    cd "${function_dir}"

    # Create main.py for carbon data collection
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timedelta
import requests
from google.cloud import bigquery
from google.cloud import monitoring_v3
import functions_framework

# Initialize clients
bq_client = bigquery.Client()
monitoring_client = monitoring_v3.MetricServiceClient()

@functions_framework.http
def collect_carbon_data(request):
    """Collect and process carbon footprint data for optimization."""
    try:
        # Get current carbon footprint data
        carbon_data = get_carbon_footprint_data()
        
        # Get grid carbon intensity data
        grid_data = get_grid_carbon_intensity()
        
        # Process and store data
        optimized_schedule = process_optimization_data(carbon_data, grid_data)
        
        # Store results in BigQuery
        store_results(carbon_data, optimized_schedule)
        
        return json.dumps({
            'status': 'success',
            'regions_analyzed': len(carbon_data),
            'optimization_recommendations': len(optimized_schedule)
        }), 200
        
    except Exception as e:
        logging.error(f"Error in carbon data collection: {str(e)}")
        return json.dumps({'status': 'error', 'message': str(e)}), 500

def get_carbon_footprint_data():
    """Retrieve carbon footprint data from Google Cloud API."""
    # Simulate carbon footprint API data collection
    regions = ['us-central1', 'europe-west1', 'asia-northeast1']
    carbon_data = []
    
    for region in regions:
        # In production, this would call the actual Carbon Footprint API
        data = {
            'timestamp': datetime.utcnow(),
            'region': region,
            'service': 'compute',
            'carbon_emissions_kg': 2.5 + (hash(region) % 10) / 10,
            'energy_kwh': 15.0 + (hash(region) % 20) / 10,
            'carbon_intensity': 0.4 + (hash(region) % 30) / 100
        }
        carbon_data.append(data)
    
    return carbon_data

def get_grid_carbon_intensity():
    """Get real-time grid carbon intensity data."""
    # Simulate external grid data API
    regions = ['us-central1', 'europe-west1', 'asia-northeast1']
    grid_data = {}
    
    for region in regions:
        grid_data[region] = {
            'renewable_percentage': 45 + (hash(region) % 40),
            'carbon_intensity_live': 0.3 + (hash(region) % 25) / 100,
            'predicted_low_carbon_hours': [2, 3, 4, 14, 15, 16]
        }
    
    return grid_data

def process_optimization_data(carbon_data, grid_data):
    """Process data to create workload optimization recommendations."""
    recommendations = []
    
    # Find regions with lowest carbon intensity
    sorted_regions = sorted(carbon_data, key=lambda x: x['carbon_intensity'])
    best_region = sorted_regions[0]['region']
    
    for data in carbon_data[1:]:  # Skip the best region
        if data['carbon_intensity'] > sorted_regions[0]['carbon_intensity'] * 1.2:
            recommendations.append({
                'timestamp': datetime.utcnow(),
                'workload_id': f"workload-{hash(data['region']) % 1000}",
                'source_region': data['region'],
                'target_region': best_region,
                'carbon_savings_kg': data['carbon_emissions_kg'] - sorted_regions[0]['carbon_emissions_kg'],
                'reason': f"Moving to region with {sorted_regions[0]['carbon_intensity']:.3f} vs {data['carbon_intensity']:.3f} carbon intensity"
            })
    
    return recommendations

def store_results(carbon_data, recommendations):
    """Store carbon data and recommendations in BigQuery."""
    import os
    dataset_id = os.environ.get('DATASET_NAME', 'carbon_analytics')
    project_id = os.environ.get('PROJECT_ID')
    
    # Store carbon footprint data
    table_id = f'{dataset_id}.carbon_footprint'
    errors = bq_client.insert_rows_json(
        f'{project_id}.{table_id}',
        carbon_data
    )
    
    if errors:
        raise Exception(f"BigQuery insert errors: {errors}")
    
    # Store optimization recommendations
    if recommendations:
        table_id = f'{dataset_id}.workload_schedules'
        errors = bq_client.insert_rows_json(
            f'{project_id}.{table_id}',
            recommendations
        )
        
        if errors:
            raise Exception(f"BigQuery insert errors: {errors}")
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.11.4
google-cloud-monitoring==2.15.1
requests==2.31.0
functions-framework==3.4.0
EOF

    # Deploy the Cloud Function
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point collect_carbon_data \
        --memory 512MB \
        --timeout 540s \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},DATASET_NAME=${DATASET_NAME}" || {
        print_status "${RED}" "❌ Failed to deploy Cloud Function"
        exit 1
    }

    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${function_dir}"

    print_status "${GREEN}" "✅ Cloud Functions deployed successfully"
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    print_status "${BLUE}" "⏰ Creating Cloud Scheduler jobs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would create scheduler job: ${SCHEDULER_JOB}"
        print_status "${YELLOW}" "[DRY RUN] Would create renewable energy scheduler"
        return 0
    fi

    # Get Cloud Function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)") || {
        print_status "${RED}" "❌ Failed to get Cloud Function URL"
        exit 1
    }

    # Create main scheduler job for carbon optimization
    gcloud scheduler jobs create http "${SCHEDULER_JOB}" \
        --location="${REGION}" \
        --schedule="0 */2 * * *" \
        --uri="${function_url}" \
        --http-method=GET \
        --description="Automated carbon footprint optimization every 2 hours" || {
        print_status "${RED}" "❌ Failed to create main scheduler job"
        exit 1
    }

    # Create renewable energy peak time scheduler
    gcloud scheduler jobs create http "${SCHEDULER_JOB}-renewable" \
        --location="${REGION}" \
        --schedule="0 14 * * *" \
        --uri="${function_url}" \
        --http-method=GET \
        --description="Optimization during peak renewable energy hours" || {
        print_status "${RED}" "❌ Failed to create renewable energy scheduler"
        exit 1
    }

    print_status "${GREEN}" "✅ Cloud Scheduler jobs created successfully"
}

# Function to create BigQuery analytics views
create_analytics_views() {
    print_status "${BLUE}" "📈 Creating analytics views..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would create regional carbon summary view"
        print_status "${YELLOW}" "[DRY RUN] Would create optimization impact view"
        return 0
    fi

    # Create regional carbon summary view
    bq query --use_legacy_sql=false << EOF
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.regional_carbon_summary\` AS
    SELECT 
      region,
      DATE(timestamp) as date,
      AVG(carbon_intensity) as avg_carbon_intensity,
      SUM(carbon_emissions_kg) as total_emissions_kg,
      SUM(energy_kwh) as total_energy_kwh,
      COUNT(*) as measurements
    FROM \`${PROJECT_ID}.${DATASET_NAME}.carbon_footprint\`
    GROUP BY region, DATE(timestamp)
    ORDER BY date DESC, region;
EOF

    # Create optimization impact view
    bq query --use_legacy_sql=false << EOF
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.optimization_impact\` AS
    SELECT 
      DATE(timestamp) as date,
      COUNT(*) as workloads_optimized,
      SUM(carbon_savings_kg) as total_carbon_savings_kg,
      AVG(carbon_savings_kg) as avg_savings_per_workload,
      STRING_AGG(DISTINCT target_region) as preferred_regions
    FROM \`${PROJECT_ID}.${DATASET_NAME}.workload_schedules\`
    GROUP BY DATE(timestamp)
    ORDER BY date DESC;
EOF

    print_status "${GREEN}" "✅ Analytics views created successfully"
}

# Function to run initial data collection
run_initial_collection() {
    print_status "${BLUE}" "🚀 Running initial data collection..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "[DRY RUN] Would trigger initial Cloud Function execution"
        return 0
    fi

    # Get Cloud Function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)") || {
        print_status "${RED}" "❌ Failed to get Cloud Function URL"
        exit 1
    }

    # Trigger initial data collection
    local response
    response=$(curl -s -w "%{http_code}" "${function_url}") || {
        print_status "${RED}" "❌ Failed to trigger initial data collection"
        exit 1
    }

    local http_code="${response: -3}"
    if [[ "${http_code}" == "200" ]]; then
        print_status "${GREEN}" "✅ Initial data collection completed successfully"
    else
        print_status "${RED}" "❌ Initial data collection failed with HTTP ${http_code}"
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    print_status "${GREEN}" "🎉 Deployment completed successfully!"
    
    cat << EOF

📋 DEPLOYMENT SUMMARY
====================
Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}

🏗️  Resources Created:
  • BigQuery Dataset: ${DATASET_NAME}
  • Analytics Hub Exchange: ${EXCHANGE_NAME}
  • Cloud Function: ${FUNCTION_NAME}
  • Scheduler Jobs: ${SCHEDULER_JOB}, ${SCHEDULER_JOB}-renewable

🔗 Access Information:
  • BigQuery Console: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}
  • Analytics Hub: https://console.cloud.google.com/marketplace/browse?project=${PROJECT_ID}
  • Cloud Functions: https://console.cloud.google.com/functions/list?project=${PROJECT_ID}
  • Cloud Scheduler: https://console.cloud.google.com/cloudscheduler?project=${PROJECT_ID}

📊 Next Steps:
  1. Monitor carbon footprint data collection in BigQuery
  2. Set up Looker Studio dashboards for visualization
  3. Configure additional workload optimization policies
  4. Review Analytics Hub shared datasets

⚠️  Important Notes:
  • Initial carbon data may take 24-48 hours to appear
  • Review and adjust scheduler frequency based on needs
  • Monitor costs in Cloud Billing console

📝 Log File: ${LOG_FILE}

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
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
            -b|--billing-account)
                BILLING_ACCOUNT_ID="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--skip-apis)
                SKIP_APIS=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_status "${RED}" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        print_status "${RED}" "❌ Project ID is required"
        usage
        exit 1
    fi

    if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
        print_status "${RED}" "❌ Billing account ID is required"
        usage
        exit 1
    fi
}

# Main execution function
main() {
    print_status "${BLUE}" "🚀 Starting Multi-Regional Carbon Footprint Analytics Hub deployment..."
    log "INFO" "Deployment started with arguments: $*"

    # Initialize log file
    echo "Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub - Deployment Log" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    echo "Script version: 1.0" >> "${LOG_FILE}"
    echo "----------------------------------------" >> "${LOG_FILE}"

    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "${YELLOW}" "🧪 Running in DRY RUN mode - no resources will be created"
    fi

    validate_prerequisites
    setup_project
    enable_apis
    generate_resource_names
    create_bigquery_resources
    setup_analytics_hub
    deploy_cloud_functions
    create_scheduler_jobs
    create_analytics_views
    run_initial_collection
    
    display_summary
    
    log "INFO" "Deployment completed successfully"
    print_status "${GREEN}" "✅ All deployment steps completed successfully!"
}

# Trap for cleanup on script exit
trap 'log "INFO" "Script execution finished"' EXIT

# Execute main function with all arguments
main "$@"