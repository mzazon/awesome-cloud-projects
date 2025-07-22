#!/bin/bash

# =============================================================================
# GCP Carbon Efficiency with FinOps Hub 2.0 Deployment Script
# =============================================================================
# 
# This script deploys the complete carbon efficiency monitoring solution that
# integrates FinOps Hub 2.0 with Cloud Carbon Footprint for automated
# optimization of both cost and environmental impact.
#
# Prerequisites:
# - Google Cloud CLI installed and configured
# - Active GCP project with billing account
# - Required IAM permissions for resource creation
# - Estimated deployment time: 15-20 minutes
#
# Usage: ./deploy.sh [--project-id PROJECT_ID] [--region REGION] [--dry-run]
#
# =============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly DEPLOYMENT_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Default configuration
DEFAULT_PROJECT_ID="carbon-efficiency-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

cleanup_on_error() {
    log_error "Deployment failed. Check $LOG_FILE for details."
    log_info "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║            GCP Carbon Efficiency with FinOps Hub 2.0 Deployment              ║
║                                                                               ║
║  This script deploys an intelligent carbon efficiency monitoring solution     ║
║  that combines FinOps Hub 2.0 waste insights with Cloud Carbon Footprint     ║
║  monitoring for automated cost and sustainability optimization.               ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
}

# =============================================================================
# Prerequisites and Validation Functions
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Google Cloud CLI version: $gcloud_version"
    
    # Check if authenticated
    if ! gcloud auth list --format="value(account)" --filter="status:ACTIVE" &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Check for required tools
    local tools=("curl" "openssl" "python3")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

validate_project() {
    local project_id="$1"
    
    log_info "Validating project: $project_id"
    
    # Check if project exists
    if ! gcloud projects describe "$project_id" &> /dev/null; then
        log_error "Project '$project_id' does not exist or is not accessible"
        exit 1
    fi
    
    # Check billing account
    local billing_account
    billing_account=$(gcloud billing projects describe "$project_id" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "$billing_account" ]]; then
        log_error "Project '$project_id' does not have a billing account linked"
        log_info "Link a billing account: https://console.cloud.google.com/billing/linkedaccount"
        exit 1
    fi
    
    log_success "Project validation completed"
}

# =============================================================================
# Configuration and Setup Functions
# =============================================================================

setup_environment() {
    local project_id="$1"
    local region="$2"
    local zone="$3"
    
    log_info "Setting up environment configuration..."
    
    # Set environment variables
    export PROJECT_ID="$project_id"
    export REGION="$region"
    export ZONE="$zone"
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Configure gcloud defaults
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    # Get billing account ID for carbon footprint access
    export BILLING_ACCOUNT_ID=$(gcloud billing accounts list \
        --format="value(name)" --limit=1 2>/dev/null || echo "")
    
    if [[ -z "$BILLING_ACCOUNT_ID" ]]; then
        log_error "No billing account found. Carbon footprint data requires a billing account."
        exit 1
    fi
    
    log_success "Environment configured successfully"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "Billing Account: $BILLING_ACCOUNT_ID"
}

enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbilling.googleapis.com"
        "recommender.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "workflows.googleapis.com"
        "logging.googleapis.com"
        "pubsub.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "$api enabled"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_success "All required APIs enabled"
}

# =============================================================================
# IAM and Security Setup
# =============================================================================

create_service_account() {
    log_info "Creating carbon efficiency service account..."
    
    local sa_name="carbon-efficiency-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account if it doesn't exist
    if ! gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
        gcloud iam service-accounts create "$sa_name" \
            --display-name="Carbon Efficiency Service Account" \
            --description="Service account for carbon footprint and FinOps monitoring" \
            --quiet
        log_success "Service account created: $sa_email"
    else
        log_info "Service account already exists: $sa_email"
    fi
    
    # Grant necessary IAM roles
    local roles=(
        "roles/billing.carbonViewer"
        "roles/recommender.viewer"
        "roles/monitoring.editor"
        "roles/cloudfunctions.invoker"
        "roles/workflows.invoker"
        "roles/logging.logWriter"
        "roles/pubsub.publisher"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role: $role"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$sa_email" \
            --role="$role" \
            --quiet
    done
    
    export SERVICE_ACCOUNT_EMAIL="$sa_email"
    log_success "Service account IAM configuration completed"
}

# =============================================================================
# Cloud Functions Deployment
# =============================================================================

deploy_carbon_efficiency_function() {
    log_info "Deploying carbon efficiency correlation function..."
    
    local function_dir="carbon-efficiency-function"
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create main function file
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import monitoring_v3
from google.cloud import billing_budgets_v1
from google.cloud import recommender_v1
from datetime import datetime, timedelta
import functions_framework

@functions_framework.http
def correlate_carbon_efficiency(request):
    """Correlate FinOps Hub utilization insights with carbon footprint data."""
    
    project_id = os.environ.get('GCP_PROJECT')
    billing_account = os.environ.get('BILLING_ACCOUNT_ID')
    
    try:
        # Initialize clients for data collection
        monitoring_client = monitoring_v3.MetricServiceClient()
        recommender_client = recommender_v1.RecommenderClient()
        
        # Get project resource name for metrics
        project_name = f"projects/{project_id}"
        
        # Collect utilization insights from Active Assist
        recommendations = []
        recommender_name = f"projects/{project_id}/locations/global/recommenders/google.compute.instance.MachineTypeRecommender"
        
        try:
            for recommendation in recommender_client.list_recommendations(parent=recommender_name):
                recommendations.append({
                    'name': recommendation.name,
                    'description': recommendation.description,
                    'priority': recommendation.priority.name,
                    'impact': {
                        'cost': recommendation.primary_impact.cost_projection.cost.units if recommendation.primary_impact.cost_projection else 0,
                        'category': recommendation.primary_impact.category.name
                    }
                })
        except Exception as e:
            logging.warning(f"No recommendations available: {e}")
        
        # Calculate carbon efficiency score based on utilization and recommendations
        efficiency_score = calculate_efficiency_score(recommendations)
        
        # Create monitoring metric for carbon efficiency
        series = monitoring_v3.TimeSeries()
        series.resource.type = "global"
        series.metric.type = "custom.googleapis.com/carbon_efficiency/score"
        
        point = monitoring_v3.Point()
        point.value.double_value = efficiency_score
        point.interval.end_time.seconds = int(datetime.now().timestamp())
        series.points = [point]
        
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        result = {
            'status': 'success',
            'efficiency_score': efficiency_score,
            'recommendations_count': len(recommendations),
            'timestamp': datetime.now().isoformat()
        }
        
        logging.info(f"Carbon efficiency analysis completed: {result}")
        return json.dumps(result)
        
    except Exception as e:
        logging.error(f"Error in carbon efficiency correlation: {e}")
        return json.dumps({'status': 'error', 'message': str(e)}), 500

def calculate_efficiency_score(recommendations):
    """Calculate carbon efficiency score based on recommendations."""
    if not recommendations:
        return 85.0  # Default score when no recommendations
    
    # Score based on number and impact of recommendations
    base_score = 100.0
    penalty_per_rec = min(len(recommendations) * 2, 30)  # Cap penalty at 30 points
    
    return max(base_score - penalty_per_rec, 20.0)  # Minimum score of 20
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-monitoring==2.15.1
google-cloud-billing-budgets==1.12.0
google-cloud-recommender==2.11.1
functions-framework==3.4.0
EOF
    
    # Deploy the function
    log_info "Deploying carbon efficiency correlation function..."
    gcloud functions deploy carbon-efficiency-correlator \
        --source . \
        --entry-point correlate_carbon_efficiency \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars="BILLING_ACCOUNT_ID=${BILLING_ACCOUNT_ID}" \
        --service-account="$SERVICE_ACCOUNT_EMAIL" \
        --region="$REGION" \
        --quiet
    
    cd ..
    
    export FUNCTION_URL=$(gcloud functions describe carbon-efficiency-correlator \
        --region="$REGION" --format="value(httpsTrigger.url)")
    
    log_success "Carbon efficiency correlation function deployed successfully"
    log_info "Function URL: $FUNCTION_URL"
}

deploy_optimization_function() {
    log_info "Deploying optimization automation function..."
    
    # Create Pub/Sub topic first
    if ! gcloud pubsub topics describe carbon-optimization &> /dev/null; then
        gcloud pubsub topics create carbon-optimization --quiet
        log_success "Pub/Sub topic 'carbon-optimization' created"
    else
        log_info "Pub/Sub topic 'carbon-optimization' already exists"
    fi
    
    local function_dir="optimization-automation"
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create optimization function
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import recommender_v1
from datetime import datetime
import functions_framework

@functions_framework.cloud_event
def optimize_carbon_efficiency(cloud_event):
    """Implement approved carbon efficiency optimizations."""
    
    project_id = os.environ.get('GCP_PROJECT')
    
    try:
        # Initialize clients
        compute_client = compute_v1.InstancesClient()
        recommender_client = recommender_v1.RecommenderClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        # Process the optimization trigger
        event_data = cloud_event.data
        optimization_type = event_data.get('optimization_type', 'rightsizing')
        
        if optimization_type == 'rightsizing':
            result = process_rightsizing_recommendations(
                project_id, compute_client, recommender_client
            )
        elif optimization_type == 'idle_cleanup':
            result = process_idle_resource_cleanup(
                project_id, compute_client, monitoring_client
            )
        else:
            result = {'status': 'unknown_optimization_type', 'message': optimization_type}
        
        # Log optimization results
        logging.info(f"Optimization completed: {result}")
        
        # Create metric for optimization impact
        create_optimization_metric(monitoring_client, project_id, result)
        
        return result
        
    except Exception as e:
        logging.error(f"Error in carbon efficiency optimization: {e}")
        return {'status': 'error', 'message': str(e)}

def process_rightsizing_recommendations(project_id, compute_client, recommender_client):
    """Process machine type rightsizing recommendations."""
    
    optimizations_applied = 0
    carbon_impact = 0.0
    
    # Get rightsizing recommendations
    recommender_name = f"projects/{project_id}/locations/global/recommenders/google.compute.instance.MachineTypeRecommender"
    
    try:
        for recommendation in recommender_client.list_recommendations(parent=recommender_name):
            if recommendation.state.name == 'ACTIVE':
                # Simulate optimization application (in production, implement actual changes)
                optimizations_applied += 1
                carbon_impact += estimate_carbon_impact(recommendation)
                
                logging.info(f"Would apply recommendation: {recommendation.name}")
                
    except Exception as e:
        logging.warning(f"No active recommendations: {e}")
    
    return {
        'optimization_type': 'rightsizing',
        'applied_count': optimizations_applied,
        'estimated_carbon_reduction': carbon_impact,
        'status': 'completed'
    }

def process_idle_resource_cleanup(project_id, compute_client, monitoring_client):
    """Identify and handle idle resources for carbon efficiency."""
    
    idle_instances = 0
    
    # List instances and check utilization (simplified simulation)
    request = compute_v1.AggregatedListInstancesRequest(project=project_id)
    
    try:
        for zone, instance_group in compute_client.aggregated_list(request=request):
            if hasattr(instance_group, 'instances') and instance_group.instances:
                for instance in instance_group.instances:
                    if instance.status == 'RUNNING':
                        # In production: Check actual CPU utilization metrics
                        # For simulation: Assume 20% are idle
                        if hash(instance.name) % 5 == 0:  # Simulate 20% idle
                            idle_instances += 1
                            logging.info(f"Identified idle instance: {instance.name}")
    except Exception as e:
        logging.warning(f"Error checking instances: {e}")
    
    return {
        'optimization_type': 'idle_cleanup',
        'idle_instances_found': idle_instances,
        'status': 'analysis_completed'
    }

def estimate_carbon_impact(recommendation):
    """Estimate carbon impact reduction from a recommendation."""
    cost_impact = 0
    
    if hasattr(recommendation, 'primary_impact') and recommendation.primary_impact.cost_projection:
        cost_impact = float(recommendation.primary_impact.cost_projection.cost.units or 0)
    
    # Estimate: $1 cost reduction ≈ 0.1 kg CO2e reduction (simplified)
    return cost_impact * 0.1

def create_optimization_metric(monitoring_client, project_id, result):
    """Create metric for optimization impact tracking."""
    
    project_name = f"projects/{project_id}"
    
    # Create time series for optimization impact
    series = monitoring_v3.TimeSeries()
    series.resource.type = "global"
    series.metric.type = "custom.googleapis.com/optimization/carbon_impact"
    
    point = monitoring_v3.Point()
    point.value.double_value = result.get('estimated_carbon_reduction', 0.0)
    point.interval.end_time.seconds = int(datetime.now().timestamp())
    series.points = [point]
    
    try:
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
    except Exception as e:
        logging.warning(f"Could not create metric: {e}")
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-compute==1.14.1
google-cloud-monitoring==2.15.1
google-cloud-recommender==2.11.1
functions-framework==3.4.0
EOF
    
    # Deploy optimization function
    log_info "Deploying optimization automation function..."
    gcloud functions deploy carbon-efficiency-optimizer \
        --source . \
        --entry-point optimize_carbon_efficiency \
        --runtime python39 \
        --trigger-topic carbon-optimization \
        --memory 1024MB \
        --timeout 540s \
        --service-account="$SERVICE_ACCOUNT_EMAIL" \
        --region="$REGION" \
        --quiet
    
    cd ..
    
    log_success "Optimization automation function deployed successfully"
}

# =============================================================================
# Monitoring and Dashboard Setup
# =============================================================================

create_monitoring_dashboard() {
    log_info "Creating carbon efficiency monitoring dashboard..."
    
    cat > carbon-efficiency-dashboard.json << 'EOF'
{
  "displayName": "Carbon Efficiency & FinOps Hub Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Carbon Efficiency Score",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"custom.googleapis.com/carbon_efficiency/score\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            },
            "thresholds": [
              {
                "value": 80.0,
                "color": "GREEN",
                "direction": "ABOVE"
              },
              {
                "value": 60.0,
                "color": "YELLOW",
                "direction": "ABOVE"
              }
            ]
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Compute Instance Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["resource.label.instance_name"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "CPU Utilization",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "yPos": 4,
        "width": 12,
        "height": 4,
        "widget": {
          "title": "Resource Recommendations Impact",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/carbon_efficiency/score\"",
                    "aggregation": {
                      "alignmentPeriod": "3600s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "STACKED_AREA"
              }
            ],
            "yAxis": {
              "label": "Efficiency Score",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    gcloud monitoring dashboards create \
        --config-from-file=carbon-efficiency-dashboard.json \
        --quiet
    
    log_success "Carbon efficiency dashboard created"
}

create_alert_policies() {
    log_info "Creating alert policies for carbon efficiency monitoring..."
    
    cat > efficiency-alert-policy.json << 'EOF'
{
  "displayName": "Carbon Efficiency Alert",
  "conditions": [
    {
      "displayName": "Low Carbon Efficiency Score",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/carbon_efficiency/score\"",
        "comparison": "COMPARISON_LESS_THAN",
        "thresholdValue": 70.0,
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
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true
}
EOF
    
    gcloud alpha monitoring policies create \
        --policy-from-file=efficiency-alert-policy.json \
        --quiet
    
    log_success "Alert policies created successfully"
}

# =============================================================================
# Workflow and Scheduler Setup
# =============================================================================

deploy_workflow() {
    log_info "Deploying carbon efficiency workflow..."
    
    cat > carbon-efficiency-workflow.yaml << 'EOF'
main:
  params: [args]
  steps:
    - initialize:
        assign:
          - project_id: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
          - function_url: "FUNCTION_URL_PLACEHOLDER"
    
    - collect_efficiency_data:
        call: http.post
        args:
          url: ${function_url}
          headers:
            Content-Type: "application/json"
          body:
            action: "analyze_efficiency"
            timestamp: ${sys.now()}
        result: efficiency_result
    
    - check_efficiency_score:
        switch:
          - condition: ${efficiency_result.body.efficiency_score < 70}
            next: generate_optimization_report
          - condition: ${efficiency_result.body.efficiency_score >= 70}
            next: log_healthy_status
    
    - generate_optimization_report:
        assign:
          - report_data:
              score: ${efficiency_result.body.efficiency_score}
              recommendations_count: ${efficiency_result.body.recommendations_count}
              status: "optimization_needed"
              generated_at: ${sys.now()}
        next: store_report
    
    - log_healthy_status:
        assign:
          - report_data:
              score: ${efficiency_result.body.efficiency_score}
              status: "healthy"
              generated_at: ${sys.now()}
        next: store_report
    
    - store_report:
        call: googleapis.logging.v2.entries.write
        args:
          body:
            entries:
              - logName: "projects/${project_id}/logs/carbon-efficiency-reports"
                resource:
                  type: "global"
                jsonPayload: ${report_data}
                severity: "INFO"
        result: log_result
    
    - return_result:
        return: ${report_data}
EOF
    
    # Replace function URL placeholder
    sed -i "s|FUNCTION_URL_PLACEHOLDER|${FUNCTION_URL}|g" carbon-efficiency-workflow.yaml
    
    # Deploy workflow
    gcloud workflows deploy carbon-efficiency-workflow \
        --source=carbon-efficiency-workflow.yaml \
        --location="$REGION" \
        --service-account="$SERVICE_ACCOUNT_EMAIL" \
        --quiet
    
    log_success "Carbon efficiency workflow deployed"
}

create_scheduler() {
    log_info "Creating Cloud Scheduler job for automated execution..."
    
    # Create scheduler job
    gcloud scheduler jobs create http carbon-efficiency-scheduler \
        --location="$REGION" \
        --schedule="0 9 * * *" \
        --uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/carbon-efficiency-workflow/executions" \
        --http-method=POST \
        --oidc-service-account-email="$SERVICE_ACCOUNT_EMAIL" \
        --headers="Content-Type=application/json" \
        --message-body='{"argument": "{\"trigger\": \"scheduled\"}"}' \
        --quiet
    
    log_success "Cloud Scheduler job created for daily execution at 9 AM"
}

# =============================================================================
# Validation and Testing
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    # Test function deployment
    if [[ -n "$FUNCTION_URL" ]]; then
        log_info "Testing carbon efficiency correlation function..."
        local response
        response=$(curl -s -X POST "$FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d '{"action": "test_correlation"}' || echo "error")
        
        if echo "$response" | grep -q "success"; then
            log_success "Function test passed"
        else
            log_warning "Function test returned: $response"
        fi
    fi
    
    # Check dashboard creation
    local dashboard_count
    dashboard_count=$(gcloud monitoring dashboards list \
        --filter="displayName:Carbon Efficiency" \
        --format="value(name)" | wc -l)
    
    if [[ "$dashboard_count" -gt 0 ]]; then
        log_success "Monitoring dashboard created successfully"
    else
        log_warning "Dashboard may not have been created properly"
    fi
    
    # Check workflow deployment
    if gcloud workflows describe carbon-efficiency-workflow \
        --location="$REGION" &> /dev/null; then
        log_success "Workflow deployed successfully"
    else
        log_warning "Workflow deployment may have issues"
    fi
    
    log_success "Deployment validation completed"
}

# =============================================================================
# Main Deployment Logic
# =============================================================================

print_deployment_summary() {
    cat << EOF

╔═══════════════════════════════════════════════════════════════════════════════╗
║                           DEPLOYMENT SUMMARY                                 ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                               ║
║  🎯 Project ID: ${PROJECT_ID}                                        ║
║  🌍 Region: ${REGION}                                                 ║
║  💰 Billing Account: ${BILLING_ACCOUNT_ID}                           ║
║                                                                               ║
║  📊 Resources Created:                                                        ║
║     • Service Account: carbon-efficiency-sa                                  ║
║     • Cloud Functions: carbon-efficiency-correlator, optimizer               ║
║     • Monitoring Dashboard: Carbon Efficiency & FinOps Hub                   ║
║     • Alert Policies: Carbon Efficiency Alert                                ║
║     • Workflow: carbon-efficiency-workflow                                   ║
║     • Scheduler: Daily execution at 9 AM                                     ║
║     • Pub/Sub Topic: carbon-optimization                                     ║
║                                                                               ║
║  🔗 Access Points:                                                            ║
║     • FinOps Hub: https://console.cloud.google.com/billing/finops            ║
║     • Carbon Footprint: https://console.cloud.google.com/carbon              ║
║     • Monitoring: https://console.cloud.google.com/monitoring                ║
║     • Function URL: ${FUNCTION_URL}                                           ║
║                                                                               ║
║  📝 Log File: ${LOG_FILE}                                                     ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

EOF
}

parse_arguments() {
    PROJECT_ID="$DEFAULT_PROJECT_ID"
    REGION="$DEFAULT_REGION"
    ZONE="$DEFAULT_ZONE"
    DRY_RUN=false
    
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
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Deploy GCP Carbon Efficiency with FinOps Hub 2.0 solution.

OPTIONS:
    --project-id PROJECT_ID     GCP project ID (default: auto-generated)
    --region REGION            GCP region (default: us-central1)
    --zone ZONE               GCP zone (default: us-central1-a)
    --dry-run                 Show what would be deployed without executing
    --help, -h                Show this help message

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 --project-id my-project --region us-east1
    $0 --dry-run                               # Show deployment plan

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

main() {
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    log_info "Starting deployment at $(date)"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Print banner
    print_banner
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        log_info "Would deploy to project: $PROJECT_ID"
        log_info "Would use region: $REGION"
        log_info "Would create carbon efficiency monitoring solution"
        exit 0
    fi
    
    # Main deployment sequence
    check_prerequisites
    validate_project "$PROJECT_ID"
    setup_environment "$PROJECT_ID" "$REGION" "$ZONE"
    enable_apis
    create_service_account
    deploy_carbon_efficiency_function
    deploy_optimization_function
    create_monitoring_dashboard
    create_alert_policies
    deploy_workflow
    create_scheduler
    validate_deployment
    
    # Print summary
    print_deployment_summary
    
    log_success "Deployment completed successfully at $(date)"
    log_info "Total deployment time: $((SECONDS / 60)) minutes"
    
    # Cleanup temporary files
    rm -f carbon-efficiency-dashboard.json efficiency-alert-policy.json carbon-efficiency-workflow.yaml
    rm -rf carbon-efficiency-function optimization-automation
}

# Execute main function with all arguments
main "$@"