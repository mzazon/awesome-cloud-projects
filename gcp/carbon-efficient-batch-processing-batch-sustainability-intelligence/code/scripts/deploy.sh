#!/bin/bash

# Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence
# Deploy Script - Sets up complete carbon-aware batch processing infrastructure
# 
# This script deploys:
# - Cloud Batch for carbon-optimized workload execution
# - Pub/Sub for event-driven coordination
# - Cloud Functions for carbon-aware scheduling
# - Cloud Storage for data and artifacts
# - Cloud Monitoring for sustainability metrics
# - Custom carbon tracking and alerting

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
    exit 1
}

warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "${LOG_FILE}"
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a "${LOG_FILE}"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Deployment failed with exit code $exit_code. Check logs at $LOG_FILE"
        log "Attempting partial cleanup..."
        # Call cleanup script if it exists
        if [ -f "${SCRIPT_DIR}/destroy.sh" ]; then
            warning "Running destroy script to clean up partial deployment..."
            bash "${SCRIPT_DIR}/destroy.sh" || true
        fi
    fi
}

trap cleanup_on_error ERR

# Start deployment
log "Starting carbon-efficient batch processing infrastructure deployment..."
log "Script directory: $SCRIPT_DIR"
log "Log file: $LOG_FILE"

# Prerequisites validation
log "Validating prerequisites..."

# Check if gcloud is installed and configured
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
fi

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
    error "gcloud is not authenticated. Please run 'gcloud auth login'"
fi

# Validate environment variables or set defaults
PROJECT_ID="${PROJECT_ID:-carbon-batch-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names to avoid conflicts
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
BATCH_JOB_NAME="${BATCH_JOB_NAME:-carbon-aware-job-${RANDOM_SUFFIX}}"
TOPIC_NAME="${TOPIC_NAME:-carbon-events-${RANDOM_SUFFIX}}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-carbon-sub-${RANDOM_SUFFIX}}"
BUCKET_NAME="${BUCKET_NAME:-carbon-batch-data-${RANDOM_SUFFIX}}"
FUNCTION_NAME="${FUNCTION_NAME:-carbon-scheduler-${RANDOM_SUFFIX}}"

log "Configuration:"
log "  Project ID: $PROJECT_ID"
log "  Region: $REGION"
log "  Zone: $ZONE"
log "  Batch Job Name: $BATCH_JOB_NAME"
log "  Topic Name: $TOPIC_NAME"
log "  Subscription Name: $SUBSCRIPTION_NAME"
log "  Bucket Name: $BUCKET_NAME"
log "  Function Name: $FUNCTION_NAME"
log "  Random Suffix: $RANDOM_SUFFIX"

# Validate or create project
log "Validating Google Cloud project..."
if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    log "Project $PROJECT_ID does not exist. Creating..."
    if ! gcloud projects create "$PROJECT_ID"; then
        error "Failed to create project $PROJECT_ID"
    fi
    log "Waiting for project to be ready..."
    sleep 10
fi

# Set default project and region
log "Setting default project and region..."
gcloud config set project "$PROJECT_ID" || error "Failed to set project"
gcloud config set compute/region "$REGION" || error "Failed to set region"
gcloud config set compute/zone "$ZONE" || error "Failed to set zone"

# Check billing account is linked
log "Checking billing configuration..."
if ! gcloud billing projects describe "$PROJECT_ID" &> /dev/null; then
    warning "Project $PROJECT_ID does not have billing enabled. This may cause API enablement to fail."
    log "Please enable billing for the project at: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
fi

# Enable required APIs
log "Enabling required Google Cloud APIs..."
apis=(
    "batch.googleapis.com"
    "pubsub.googleapis.com"
    "monitoring.googleapis.com"
    "cloudbilling.googleapis.com"
    "storage.googleapis.com"
    "cloudfunctions.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "logging.googleapis.com"
    "cloudbuild.googleapis.com"
)

for api in "${apis[@]}"; do
    log "Enabling $api..."
    if ! gcloud services enable "$api"; then
        error "Failed to enable $api"
    fi
done

success "All APIs enabled successfully"

# Wait for APIs to be fully available
log "Waiting for APIs to be fully available..."
sleep 30

# Create Pub/Sub infrastructure
log "Creating Pub/Sub topic and subscription..."

# Create topic
if ! gcloud pubsub topics create "$TOPIC_NAME"; then
    error "Failed to create Pub/Sub topic $TOPIC_NAME"
fi
success "Created Pub/Sub topic: $TOPIC_NAME"

# Create subscription
if ! gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
    --topic="$TOPIC_NAME" \
    --ack-deadline=600; then
    error "Failed to create Pub/Sub subscription $SUBSCRIPTION_NAME"
fi
success "Created Pub/Sub subscription: $SUBSCRIPTION_NAME"

# Create Cloud Storage bucket
log "Creating Cloud Storage bucket for carbon data and artifacts..."

# Check if bucket name is available (globally unique)
if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
    warning "Bucket gs://$BUCKET_NAME already exists. Using existing bucket."
else
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        error "Failed to create Cloud Storage bucket gs://$BUCKET_NAME"
    fi
    success "Created Cloud Storage bucket: gs://$BUCKET_NAME"
fi

# Enable versioning for data protection
log "Enabling versioning on bucket..."
if ! gsutil versioning set on "gs://$BUCKET_NAME"; then
    error "Failed to enable versioning on bucket"
fi

# Create organized directory structure
log "Creating organized directory structure in bucket..."
echo "carbon-data/" | gsutil cp - "gs://$BUCKET_NAME/carbon-data/.keep" || error "Failed to create carbon-data directory"
echo "job-scripts/" | gsutil cp - "gs://$BUCKET_NAME/job-scripts/.keep" || error "Failed to create job-scripts directory"
echo "results/" | gsutil cp - "gs://$BUCKET_NAME/results/.keep" || error "Failed to create results directory"

success "Cloud Storage bucket configured with organized structure"

# Create carbon-aware job script
log "Creating carbon-aware batch job script..."

cat > "${SCRIPT_DIR}/carbon_aware_job.py" << 'EOF'
#!/usr/bin/env python3
"""
Carbon-Aware Batch Job Script

This script demonstrates intelligent batch processing that adapts its behavior
based on regional carbon-free energy (CFE) availability and carbon intensity data.
It integrates with Google Cloud's sustainability intelligence to minimize
environmental impact while maintaining processing performance.
"""

import os
import time
import json
import logging
import random
from datetime import datetime
from google.cloud import pubsub_v1
from google.cloud import monitoring_v3
from google.cloud import storage

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def get_regional_carbon_data():
    """
    Fetch regional carbon intensity and CFE data.
    In production, this would integrate with Google Cloud's Carbon Footprint API
    and real-time grid carbon intensity services.
    """
    regions_data = {
        "us-central1": {
            "cfe_percent": 85,
            "carbon_intensity": 120,
            "renewable_sources": ["wind", "solar"],
            "grid_operator": "SPP"
        },
        "europe-west1": {
            "cfe_percent": 92,
            "carbon_intensity": 95,
            "renewable_sources": ["wind", "hydro", "solar"],
            "grid_operator": "ENTSO-E"
        },
        "asia-northeast1": {
            "cfe_percent": 45,
            "carbon_intensity": 380,
            "renewable_sources": ["solar", "wind"],
            "grid_operator": "TEPCO"
        },
        "us-west1": {
            "cfe_percent": 78,
            "carbon_intensity": 135,
            "renewable_sources": ["solar", "wind", "hydro"],
            "grid_operator": "CAISO"
        }
    }
    
    current_region = os.environ.get('REGION', 'us-central1')
    return regions_data.get(current_region, regions_data['us-central1'])

def calculate_carbon_aware_parameters(carbon_data):
    """
    Calculate processing parameters based on carbon efficiency.
    Higher CFE% enables more intensive processing, lower CFE% reduces intensity.
    """
    cfe_percent = carbon_data['cfe_percent']
    
    if cfe_percent >= 80:
        # High CFE% - run at full intensity
        return {
            "intensity_multiplier": 1.0,
            "iterations": 1000,
            "parallel_workers": 4,
            "processing_mode": "high_performance",
            "justification": f"High CFE% ({cfe_percent}%) - optimal for full intensity processing"
        }
    elif cfe_percent >= 60:
        # Medium CFE% - moderate intensity
        return {
            "intensity_multiplier": 0.75,
            "iterations": 750,
            "parallel_workers": 3,
            "processing_mode": "balanced",
            "justification": f"Medium CFE% ({cfe_percent}%) - balanced processing approach"
        }
    elif cfe_percent >= 40:
        # Low CFE% - reduced intensity
        return {
            "intensity_multiplier": 0.5,
            "iterations": 500,
            "parallel_workers": 2,
            "processing_mode": "eco_mode",
            "justification": f"Low CFE% ({cfe_percent}%) - reduced intensity for sustainability"
        }
    else:
        # Very low CFE% - minimal processing or defer
        return {
            "intensity_multiplier": 0.25,
            "iterations": 250,
            "parallel_workers": 1,
            "processing_mode": "minimal",
            "justification": f"Very low CFE% ({cfe_percent}%) - minimal processing to reduce impact"
        }

def simulate_workload(processing_params):
    """
    Simulate carbon-aware compute workload with adaptive intensity.
    """
    logger.info("Starting carbon-aware batch processing...")
    logger.info(f"Processing mode: {processing_params['processing_mode']}")
    logger.info(f"Justification: {processing_params['justification']}")
    
    iterations = processing_params['iterations']
    parallel_workers = processing_params['parallel_workers']
    
    # Simulate parallel processing
    start_time = time.time()
    total_operations = 0
    
    for worker in range(parallel_workers):
        logger.info(f"Starting worker {worker + 1}/{parallel_workers}")
        
        for i in range(iterations // parallel_workers):
            # Simulate compute-intensive work
            result = sum(range(random.randint(100, 1000)))
            total_operations += 1
            
            # Progress reporting
            if total_operations % 100 == 0:
                logger.info(f"Completed {total_operations}/{iterations} operations")
                
            # Small delay to simulate realistic processing
            time.sleep(0.001 * processing_params['intensity_multiplier'])
    
    processing_time = time.time() - start_time
    
    logger.info(f"Processing completed in {processing_time:.2f}s")
    logger.info(f"Total operations: {total_operations}")
    
    return {
        "processing_time": processing_time,
        "total_operations": total_operations,
        "workers_used": parallel_workers,
        "processing_mode": processing_params['processing_mode']
    }

def calculate_carbon_impact(carbon_data, processing_results):
    """
    Calculate estimated carbon impact of the processing workload.
    """
    # Simplified carbon calculation based on processing time and regional intensity
    processing_time_hours = processing_results['processing_time'] / 3600
    carbon_intensity = carbon_data['carbon_intensity']  # gCO2e/kWh
    
    # Estimate compute power usage (simplified)
    estimated_power_kw = 0.1 * processing_results['workers_used']  # Approximate
    
    # Calculate carbon impact
    carbon_impact_gco2e = processing_time_hours * estimated_power_kw * carbon_intensity
    carbon_impact_kgco2e = carbon_impact_gco2e / 1000
    
    # Calculate carbon efficiency score
    cfe_benefit = (carbon_data['cfe_percent'] / 100) * carbon_impact_kgco2e
    net_carbon_impact = carbon_impact_kgco2e - cfe_benefit
    
    return {
        "gross_carbon_impact_kgco2e": carbon_impact_kgco2e,
        "cfe_benefit_kgco2e": cfe_benefit,
        "net_carbon_impact_kgco2e": max(0, net_carbon_impact),
        "carbon_efficiency_score": carbon_data['cfe_percent'] / carbon_data['carbon_intensity'] * 100,
        "estimated_power_kwh": processing_time_hours * estimated_power_kw
    }

def publish_carbon_metrics(carbon_data, processing_results, carbon_impact):
    """
    Publish comprehensive carbon efficiency metrics to Pub/Sub.
    """
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(
            os.environ['PROJECT_ID'], 
            os.environ['TOPIC_NAME']
        )
        
        # Comprehensive metrics payload
        message_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "job_metadata": {
                "job_id": os.environ.get('BATCH_JOB_NAME', 'unknown'),
                "region": os.environ.get('REGION', 'unknown'),
                "zone": os.environ.get('ZONE', 'unknown')
            },
            "carbon_intelligence": {
                "regional_cfe_percent": carbon_data['cfe_percent'],
                "carbon_intensity_gco2e_kwh": carbon_data['carbon_intensity'],
                "renewable_sources": carbon_data['renewable_sources'],
                "grid_operator": carbon_data['grid_operator']
            },
            "processing_metrics": processing_results,
            "carbon_impact": carbon_impact,
            "sustainability_score": {
                "carbon_efficiency": carbon_impact['carbon_efficiency_score'],
                "renewable_energy_utilization": carbon_data['cfe_percent'],
                "optimization_level": processing_results['processing_mode']
            }
        }
        
        message = json.dumps(message_data, indent=2).encode('utf-8')
        future = publisher.publish(topic_path, message)
        
        logger.info(f"Published carbon metrics message: {future.result()}")
        logger.info(f"Carbon efficiency score: {carbon_impact['carbon_efficiency_score']:.2f}")
        
    except Exception as e:
        logger.error(f"Failed to publish metrics: {e}")
        raise

def save_results_to_storage(carbon_data, processing_results, carbon_impact):
    """
    Save comprehensive results to Cloud Storage for analysis and reporting.
    """
    try:
        client = storage.Client()
        bucket = client.bucket(os.environ['BUCKET_NAME'])
        
        # Create comprehensive results document
        results_document = {
            "job_execution": {
                "timestamp": datetime.utcnow().isoformat(),
                "job_id": os.environ.get('BATCH_JOB_NAME', 'unknown'),
                "region": os.environ.get('REGION', 'unknown'),
                "execution_environment": "carbon_aware_batch"
            },
            "carbon_intelligence": carbon_data,
            "processing_results": processing_results,
            "carbon_impact_analysis": carbon_impact,
            "recommendations": generate_recommendations(carbon_data, carbon_impact)
        }
        
        # Save with timestamp-based filename
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        blob_name = f"results/carbon-job-{timestamp}-{os.environ.get('BATCH_JOB_NAME', 'unknown')}.json"
        blob = bucket.blob(blob_name)
        
        blob.upload_from_string(
            json.dumps(results_document, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Results saved to Cloud Storage: gs://{os.environ['BUCKET_NAME']}/{blob_name}")
        
    except Exception as e:
        logger.error(f"Failed to save results: {e}")
        # Don't fail the job if storage save fails
        pass

def generate_recommendations(carbon_data, carbon_impact):
    """
    Generate actionable sustainability recommendations based on execution results.
    """
    recommendations = []
    
    cfe_percent = carbon_data['cfe_percent']
    efficiency_score = carbon_impact['carbon_efficiency_score']
    
    if cfe_percent < 60:
        recommendations.append({
            "type": "scheduling",
            "priority": "high",
            "message": f"Consider scheduling workloads during higher CFE periods. Current CFE: {cfe_percent}%",
            "action": "Implement time-of-day scheduling based on renewable energy forecasts"
        })
    
    if efficiency_score < 50:
        recommendations.append({
            "type": "optimization",
            "priority": "medium",
            "message": f"Carbon efficiency score is low ({efficiency_score:.1f}). Consider workload optimization.",
            "action": "Review processing algorithms for efficiency improvements"
        })
    
    if carbon_impact['net_carbon_impact_kgco2e'] > 0.1:
        recommendations.append({
            "type": "carbon_reduction",
            "priority": "medium",
            "message": f"High carbon impact detected ({carbon_impact['net_carbon_impact_kgco2e']:.4f} kgCO2e)",
            "action": "Consider regional migration or processing intensity reduction"
        })
    
    if cfe_percent > 80:
        recommendations.append({
            "type": "opportunity",
            "priority": "low",
            "message": f"Excellent CFE conditions ({cfe_percent}%). Consider scaling up processing.",
            "action": "This is an optimal time for compute-intensive workloads"
        })
    
    return recommendations

def main():
    """
    Main carbon-aware job execution orchestrator.
    """
    logger.info("🌱 Starting carbon-aware batch job execution")
    
    try:
        # Get regional carbon intelligence
        carbon_data = get_regional_carbon_data()
        logger.info(f"Regional carbon data: CFE {carbon_data['cfe_percent']}%, "
                   f"Intensity {carbon_data['carbon_intensity']} gCO2e/kWh")
        
        # Calculate carbon-aware processing parameters
        processing_params = calculate_carbon_aware_parameters(carbon_data)
        logger.info(f"Calculated processing parameters: {processing_params['processing_mode']}")
        
        # Execute workload with carbon intelligence
        processing_results = simulate_workload(processing_params)
        
        # Calculate carbon impact
        carbon_impact = calculate_carbon_impact(carbon_data, processing_results)
        logger.info(f"Estimated carbon impact: {carbon_impact['net_carbon_impact_kgco2e']:.4f} kgCO2e")
        
        # Publish sustainability metrics
        publish_carbon_metrics(carbon_data, processing_results, carbon_impact)
        
        # Save results for analysis
        save_results_to_storage(carbon_data, processing_results, carbon_impact)
        
        logger.info("🎉 Carbon-aware batch job completed successfully")
        logger.info(f"Sustainability Summary:")
        logger.info(f"  • Carbon Efficiency Score: {carbon_impact['carbon_efficiency_score']:.2f}")
        logger.info(f"  • Renewable Energy Use: {carbon_data['cfe_percent']}%")
        logger.info(f"  • Processing Mode: {processing_results['processing_mode']}")
        logger.info(f"  • Net Carbon Impact: {carbon_impact['net_carbon_impact_kgco2e']:.4f} kgCO2e")
        
        return 0
        
    except Exception as e:
        logger.error(f"Carbon-aware batch job failed: {e}")
        return 1

if __name__ == "__main__":
    exit_code = main()
    exit(exit_code)
EOF

# Upload job script to Cloud Storage
log "Uploading carbon-aware job script to Cloud Storage..."
if ! gsutil cp "${SCRIPT_DIR}/carbon_aware_job.py" "gs://$BUCKET_NAME/job-scripts/"; then
    error "Failed to upload job script to Cloud Storage"
fi
success "Carbon-aware job script created and uploaded"

# Create Cloud Batch job definition
log "Creating Cloud Batch job definition..."

cat > "${SCRIPT_DIR}/batch_job_config.json" << EOF
{
  "allocationPolicy": {
    "instances": [
      {
        "policy": {
          "machineType": "e2-standard-2",
          "provisioningModel": "PREEMPTIBLE"
        }
      }
    ],
    "location": {
      "allowedLocations": ["zones/$ZONE"]
    }
  },
  "taskGroups": [
    {
      "taskCount": "3",
      "taskSpec": {
        "runnables": [
          {
            "container": {
              "imageUri": "python:3.9-slim",
              "commands": [
                "/bin/bash"
              ],
              "options": "--workdir=/workspace"
            },
            "script": {
              "text": "pip install google-cloud-pubsub google-cloud-monitoring google-cloud-storage && gsutil cp gs://$BUCKET_NAME/job-scripts/carbon_aware_job.py /workspace/ && python /workspace/carbon_aware_job.py"
            },
            "environment": {
              "variables": {
                "PROJECT_ID": "$PROJECT_ID",
                "REGION": "$REGION",
                "ZONE": "$ZONE",
                "TOPIC_NAME": "$TOPIC_NAME",
                "BUCKET_NAME": "$BUCKET_NAME",
                "BATCH_JOB_NAME": "$BATCH_JOB_NAME"
              }
            }
          }
        ],
        "computeResource": {
          "cpuMilli": "2000",
          "memoryMib": "4096"
        },
        "maxRetryCount": 2,
        "maxRunDuration": "3600s"
      }
    }
  ],
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF

success "Batch job configuration created with sustainability optimizations"

# Create custom metric descriptors for carbon tracking
log "Creating custom monitoring metrics for carbon tracking..."

cat > "${SCRIPT_DIR}/carbon_metrics.json" << 'EOF'
{
  "type": "custom.googleapis.com/batch/carbon_impact",
  "displayName": "Batch Job Carbon Impact",
  "description": "Estimated carbon impact of batch jobs in kgCO2e",
  "metricKind": "GAUGE",
  "valueType": "DOUBLE",
  "labels": [
    {
      "key": "job_id",
      "description": "Batch job identifier"
    },
    {
      "key": "region",
      "description": "Execution region"
    },
    {
      "key": "processing_mode",
      "description": "Carbon-aware processing mode"
    }
  ]
}
EOF

# Create monitoring metrics (may fail if already exists)
log "Creating carbon monitoring metrics..."
if ! gcloud alpha monitoring metrics-descriptors create \
    --descriptor-from-file="${SCRIPT_DIR}/carbon_metrics.json" 2>/dev/null; then
    warning "Custom metric may already exist or alpha API not available"
fi

# Create carbon-aware scheduler function
log "Creating carbon-aware scheduler Cloud Function..."

# Create function directory
mkdir -p "${SCRIPT_DIR}/carbon_scheduler_function"

cat > "${SCRIPT_DIR}/carbon_scheduler_function/main.py" << 'EOF'
import json
import logging
from datetime import datetime, timedelta
from google.cloud import batch_v1
from google.cloud import pubsub_v1
from google.cloud import storage

def carbon_aware_scheduler(request):
    """
    Carbon-aware batch job scheduler function.
    
    This function analyzes regional carbon intensity and CFE data to make
    intelligent scheduling decisions that minimize environmental impact.
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        
        # Simulate regional carbon data (in production, integrate with real APIs)
        regions_carbon_data = {
            "us-central1": {"cfe_percent": 85, "carbon_intensity": 120, "renewable_forecast": "high"},
            "europe-west1": {"cfe_percent": 92, "carbon_intensity": 95, "renewable_forecast": "very_high"},
            "asia-northeast1": {"cfe_percent": 45, "carbon_intensity": 380, "renewable_forecast": "medium"},
            "us-west1": {"cfe_percent": 78, "carbon_intensity": 135, "renewable_forecast": "high"},
            "europe-north1": {"cfe_percent": 88, "carbon_intensity": 110, "renewable_forecast": "high"}
        }
        
        # Find optimal region based on carbon efficiency
        optimal_region = max(regions_carbon_data.items(), 
                           key=lambda x: x[1]['cfe_percent'])
        
        region_name = optimal_region[0]
        carbon_data = optimal_region[1]
        
        logging.info(f"Selected optimal region: {region_name} (CFE: {carbon_data['cfe_percent']}%)")
        
        # Generate scheduling decision based on carbon intelligence
        schedule_decision = generate_scheduling_decision(carbon_data, region_name)
        
        # Publish scheduling decision to Pub/Sub
        if request_json:
            publish_scheduling_decision(request_json, schedule_decision, carbon_data)
        
        return {
            "statusCode": 200,
            "decision": schedule_decision,
            "carbon_data": carbon_data,
            "optimal_region": region_name,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logging.error(f"Scheduler error: {e}")
        return {"statusCode": 500, "error": str(e)}

def generate_scheduling_decision(carbon_data, region_name):
    """Generate intelligent scheduling decision based on carbon conditions."""
    cfe_percent = carbon_data['cfe_percent']
    carbon_intensity = carbon_data['carbon_intensity']
    
    if cfe_percent >= 80:
        return {
            "action": "schedule_now",
            "region": region_name,
            "priority": "high",
            "reason": f"High CFE% ({cfe_percent}%) - optimal for immediate execution",
            "carbon_intensity": carbon_intensity,
            "recommended_intensity": "full",
            "estimated_delay": 0
        }
    elif cfe_percent >= 60:
        return {
            "action": "schedule_soon",
            "region": region_name,
            "priority": "medium",
            "delay_minutes": 15,
            "reason": f"Good CFE% ({cfe_percent}%) - schedule with brief delay for optimization",
            "carbon_intensity": carbon_intensity,
            "recommended_intensity": "high",
            "estimated_delay": 15
        }
    elif cfe_percent >= 40:
        return {
            "action": "schedule_delayed",
            "region": region_name,
            "priority": "low",
            "delay_hours": 2,
            "reason": f"Medium CFE% ({cfe_percent}%) - delay for better carbon conditions",
            "carbon_intensity": carbon_intensity,
            "recommended_intensity": "moderate",
            "estimated_delay": 120
        }
    else:
        return {
            "action": "defer",
            "region": region_name,
            "priority": "low",
            "delay_hours": 6,
            "reason": f"Low CFE% ({cfe_percent}%) - defer to significantly reduce impact",
            "carbon_intensity": carbon_intensity,
            "recommended_intensity": "eco",
            "estimated_delay": 360
        }

def publish_scheduling_decision(request_data, schedule_decision, carbon_data):
    """Publish scheduling decision to Pub/Sub for downstream processing."""
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(
            request_data.get('project_id', 'default'),
            request_data.get('topic_name', 'carbon-events')
        )
        
        message_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "event_type": "scheduling_decision",
            "scheduler_decision": schedule_decision,
            "carbon_intelligence": carbon_data,
            "metadata": {
                "scheduler_version": "1.0",
                "decision_confidence": "high",
                "carbon_optimization_enabled": True
            }
        }
        
        message = json.dumps(message_data).encode('utf-8')
        future = publisher.publish(topic_path, message)
        logging.info(f"Published scheduling decision: {future.result()}")
        
    except Exception as e:
        logging.error(f"Failed to publish scheduling decision: {e}")
EOF

cat > "${SCRIPT_DIR}/carbon_scheduler_function/requirements.txt" << 'EOF'
google-cloud-batch
google-cloud-pubsub
google-cloud-storage
google-cloud-monitoring
functions-framework
EOF

# Deploy the carbon-aware scheduler function
log "Deploying carbon-aware scheduler Cloud Function..."
cd "${SCRIPT_DIR}/carbon_scheduler_function"

if ! gcloud functions deploy "$FUNCTION_NAME" \
    --runtime python39 \
    --trigger-http \
    --allow-unauthenticated \
    --source . \
    --entry-point carbon_aware_scheduler \
    --memory 512MB \
    --timeout 60s \
    --region "$REGION"; then
    error "Failed to deploy carbon-aware scheduler function"
fi

cd "$SCRIPT_DIR"
success "Carbon-aware scheduler function deployed successfully"

# Create alert policy for high carbon impact
log "Creating carbon impact alerting policy..."

cat > "${SCRIPT_DIR}/carbon_alert_policy.json" << EOF
{
  "displayName": "High Carbon Impact Alert - $RANDOM_SUFFIX",
  "documentation": {
    "content": "Alert when batch jobs exceed carbon intensity thresholds in the carbon-efficient batch processing system",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Carbon Impact Threshold Exceeded",
      "conditionThreshold": {
        "filter": "resource.type=\\"generic_task\\" AND metric.type=\\"custom.googleapis.com/batch/carbon_impact\\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": "0.5",
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
EOF

# Create the alert policy (may fail if monitoring isn't fully ready)
log "Creating carbon impact alert policy..."
if ! gcloud alpha monitoring policies create \
    --policy-from-file="${SCRIPT_DIR}/carbon_alert_policy.json" 2>/dev/null; then
    warning "Alert policy creation failed - monitoring may not be fully ready"
fi

# Test the deployment with a sample batch job
log "Testing deployment with a sample carbon-aware batch job..."

# Submit test batch job
if ! gcloud batch jobs submit "${BATCH_JOB_NAME}-test" \
    --location="$REGION" \
    --config="${SCRIPT_DIR}/batch_job_config.json"; then
    warning "Failed to submit test batch job - this is not critical for deployment"
else
    success "Test batch job submitted successfully"
    log "Monitor job progress with: gcloud batch jobs describe ${BATCH_JOB_NAME}-test --location=$REGION"
fi

# Test the scheduler function
log "Testing carbon-aware scheduler function..."
FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --format="value(httpsTrigger.url)")

if [ -n "$FUNCTION_URL" ]; then
    log "Testing scheduler function at: $FUNCTION_URL"
    if curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"project_id\": \"$PROJECT_ID\",
            \"topic_name\": \"$TOPIC_NAME\",
            \"test\": true
        }" > /dev/null; then
        success "Scheduler function responded successfully"
    else
        warning "Scheduler function test failed - function may need time to initialize"
    fi
fi

# Create deployment summary
log "Creating deployment summary..."

cat > "${SCRIPT_DIR}/deployment_summary.json" << EOF
{
  "deployment_info": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project_id": "$PROJECT_ID",
    "region": "$REGION",
    "zone": "$ZONE",
    "deployment_status": "completed"
  },
  "resources_created": {
    "pubsub_topic": "$TOPIC_NAME",
    "pubsub_subscription": "$SUBSCRIPTION_NAME",
    "storage_bucket": "$BUCKET_NAME",
    "cloud_function": "$FUNCTION_NAME",
    "batch_job_config": "${BATCH_JOB_NAME}-config"
  },
  "access_information": {
    "cloud_console": "https://console.cloud.google.com/batch/jobs?project=$PROJECT_ID",
    "storage_bucket": "gs://$BUCKET_NAME",
    "function_url": "$FUNCTION_URL",
    "pubsub_topic": "projects/$PROJECT_ID/topics/$TOPIC_NAME"
  },
  "monitoring": {
    "cloud_logging": "https://console.cloud.google.com/logs?project=$PROJECT_ID",
    "monitoring": "https://console.cloud.google.com/monitoring?project=$PROJECT_ID",
    "carbon_metrics": "custom.googleapis.com/batch/carbon_impact"
  },
  "next_steps": [
    "Monitor batch jobs in Cloud Console",
    "Review carbon metrics in Cloud Monitoring",
    "Test scheduler function with various carbon conditions",
    "Set up additional alerting channels if needed",
    "Review cost optimization opportunities"
  ]
}
EOF

# Final validation
log "Performing final deployment validation..."

# Check if all main resources exist
validation_errors=0

# Check Pub/Sub topic
if ! gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
    error "Pub/Sub topic validation failed"
    validation_errors=$((validation_errors + 1))
fi

# Check Cloud Storage bucket
if ! gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
    error "Cloud Storage bucket validation failed"
    validation_errors=$((validation_errors + 1))
fi

# Check Cloud Function
if ! gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
    error "Cloud Function validation failed"
    validation_errors=$((validation_errors + 1))
fi

if [ $validation_errors -eq 0 ]; then
    success "All resources validated successfully"
else
    warning "$validation_errors validation errors found - review deployment"
fi

# Display deployment summary
log "==================== DEPLOYMENT COMPLETED ===================="
log ""
log "🌱 Carbon-Efficient Batch Processing Infrastructure Deployed Successfully!"
log ""
log "📊 Resource Summary:"
log "  • Project ID: $PROJECT_ID"
log "  • Region: $REGION (optimized for carbon efficiency)"
log "  • Pub/Sub Topic: $TOPIC_NAME"
log "  • Storage Bucket: gs://$BUCKET_NAME"
log "  • Cloud Function: $FUNCTION_NAME"
log "  • Random Suffix: $RANDOM_SUFFIX"
log ""
log "🔗 Access Links:"
log "  • Cloud Console: https://console.cloud.google.com/batch/jobs?project=$PROJECT_ID"
log "  • Storage Bucket: https://console.cloud.google.com/storage/browser/$BUCKET_NAME?project=$PROJECT_ID"
log "  • Function URL: $FUNCTION_URL"
log "  • Monitoring: https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
log ""
log "🧪 Testing Commands:"
log "  • Submit batch job: gcloud batch jobs submit my-job --location=$REGION --config=${SCRIPT_DIR}/batch_job_config.json"
log "  • Test scheduler: curl -X POST $FUNCTION_URL -H 'Content-Type: application/json' -d '{\"project_id\":\"$PROJECT_ID\",\"topic_name\":\"$TOPIC_NAME\"}'"
log "  • View logs: gcloud logging read 'resource.type=batch_job'"
log "  • Check metrics: gcloud monitoring time-series list --filter='metric.type=\"custom.googleapis.com/batch/carbon_impact\"'"
log ""
log "🧹 Cleanup:"
log "  • Run destroy script: bash ${SCRIPT_DIR}/destroy.sh"
log ""
log "📝 Logs: $LOG_FILE"
log "📋 Summary: ${SCRIPT_DIR}/deployment_summary.json"
log ""
log "⚡ The infrastructure is now ready for carbon-efficient batch processing!"
log "   Monitor regional CFE data and adjust workload scheduling accordingly."
log ""
log "=============================================================="

success "Deployment completed successfully in $(date)"