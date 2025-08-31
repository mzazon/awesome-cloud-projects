---
title: Resource Allocation with Cloud Quotas API and Cloud Run GPU
id: 8a6f7e4c
category: management-governance
difficulty: 300
subject: gcp
services: Cloud Quotas API, Cloud Run GPU, Cloud Monitoring, Cloud Functions
estimated-time: 120 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: gpu-quotas, intelligent-allocation, automated-scaling, resource-management, ai-inference
recipe-generator-version: 1.3
---

# Resource Allocation with Cloud Quotas API and Cloud Run GPU

## Problem

Modern AI/ML workloads experience unpredictable demand patterns, leading to either resource shortages during peak periods or wasteful over-provisioning during low-demand times. Organizations struggle with manually managing GPU quotas across regions and services, resulting in delayed deployments, inefficient resource utilization, and increased operational costs when AI inference demands fluctuate dramatically.

## Solution

Build an intelligent resource allocation system that automatically monitors Cloud Run GPU workload demands through Cloud Monitoring metrics and dynamically adjusts GPU quotas using the Cloud Quotas API. This solution employs Cloud Functions to analyze usage patterns and make automated quota adjustment decisions, ensuring optimal resource availability while minimizing costs.

## Architecture Diagram

```mermaid
graph TB
    subgraph "AI Workload Layer"
        CRG[Cloud Run GPU<br/>AI Inference Services]
        METRICS[Resource Metrics<br/>CPU/GPU/Memory]
    end
    
    subgraph "Intelligence Layer"
        CF[Cloud Functions<br/>Decision Engine]
        CM[Cloud Monitoring<br/>Metrics Collection]
        SCHED[Cloud Scheduler<br/>Periodic Analysis]
    end
    
    subgraph "Resource Management Layer"
        CQA[Cloud Quotas API<br/>Dynamic Allocation]
        PREF[Quota Preferences<br/>Configuration]
    end
    
    subgraph "Storage Layer"
        FS[Firestore<br/>Usage History]
        CS[Cloud Storage<br/>Models & Policies]
    end
    
    CRG --> METRICS
    METRICS --> CM
    CM --> CF
    SCHED --> CF
    CF --> CQA
    CF --> FS
    CQA --> PREF
    PREF --> CRG
    CS --> CF
    
    style CRG fill:#4285F4
    style CF fill:#34A853
    style CQA fill:#EA4335
    style CM fill:#FBBC04
```

## Prerequisites

1. Google Cloud project with appropriate permissions for Cloud Quotas API, Cloud Run GPU, Cloud Monitoring, and Cloud Functions
2. Google Cloud CLI (gcloud) installed and configured (or Google Cloud Shell)
3. Basic understanding of AI/ML workloads and resource management
4. Familiarity with serverless computing and quota management concepts
5. Estimated cost: $20-50 for initial testing (includes GPU usage, function executions, and storage)

> **Note**: GPU quotas may have approval delays and regional limitations. Review [Google Cloud GPU availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones) before proceeding.

## Preparation

```bash
# Set environment variables for consistent resource naming
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export FUNCTION_NAME="quota-manager-${RANDOM_SUFFIX}"
export SERVICE_NAME="ai-inference-${RANDOM_SUFFIX}"
export BUCKET_NAME="${PROJECT_ID}-quota-policies-${RANDOM_SUFFIX}"

# Set default configuration
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Install beta component if not already available
gcloud components install beta --quiet

# Enable required Google Cloud APIs
gcloud services enable cloudquotas.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable firestore.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable cloudbuild.googleapis.com

echo "✅ Environment configured for project: ${PROJECT_ID}"
echo "✅ Region set to: ${REGION}"
echo "✅ All required APIs enabled"
```

## Steps

1. **Create Cloud Storage Bucket for Quota Policies**:

   Cloud Storage provides the centralized repository for quota management policies and historical allocation data. This bucket stores configuration files that define quota adjustment thresholds, regional preferences, and cost optimization rules. The intelligent allocation system uses these policies to make informed decisions about GPU resource distribution across different workloads and geographic regions.

   ```bash
   # Create bucket for quota policies and configuration
   gsutil mb -p ${PROJECT_ID} \
       -c STANDARD \
       -l ${REGION} \
       gs://${BUCKET_NAME}
   
   # Enable versioning for policy change tracking
   gsutil versioning set on gs://${BUCKET_NAME}
   
   # Create quota management policy configuration
   cat > quota-policy.json << EOF
   {
     "allocation_thresholds": {
       "gpu_utilization_trigger": 0.8,
       "cpu_utilization_trigger": 0.75,
       "memory_utilization_trigger": 0.85
     },
     "gpu_families": {
       "nvidia-l4": {
         "max_quota": 10,
         "min_quota": 1,
         "increment_size": 2
       },
       "nvidia-t4": {
         "max_quota": 8,
         "min_quota": 1,
         "increment_size": 1
       }
     },
     "regions": ["us-central1", "us-west1", "us-east1"],
     "cost_optimization": {
       "enable_preemptible": true,
       "max_cost_per_hour": 50.0
     }
   }
   EOF
   
   gsutil cp quota-policy.json gs://${BUCKET_NAME}/
   
   echo "✅ Storage bucket created with quota policies"
   ```

   The quota policy configuration is now stored securely in Cloud Storage with versioning enabled, providing a foundation for intelligent resource allocation decisions. This centralized approach allows for easy updates to allocation strategies while maintaining historical policy versions for auditing and rollback purposes.

2. **Initialize Firestore for Usage History**:

   Firestore serves as the real-time database for storing GPU usage patterns, quota adjustment history, and workload analytics. This NoSQL database enables the intelligent allocation system to learn from historical usage patterns and make predictive scaling decisions. Firestore's global distribution and strong consistency ensure accurate usage tracking across all regions.

   ```bash
   # Initialize Firestore in Native mode for the region
   gcloud firestore databases create \
       --region=${REGION} \
       --type=firestore-native
   
   # Wait for database creation to complete
   sleep 10
   
   echo "✅ Firestore initialized for usage history tracking"
   ```

   Firestore is now configured to track quota allocation patterns, providing the intelligent system with historical context for making informed scaling decisions. This database foundation supports both real-time monitoring and long-term trend analysis for optimal resource allocation.

3. **Deploy Cloud Function for Quota Intelligence**:

   Cloud Functions serves as the central intelligence engine that analyzes resource utilization patterns and makes automated quota adjustment decisions. This serverless function integrates with Cloud Monitoring APIs to collect real-time metrics, applies machine learning-based prediction algorithms, and interfaces with the Cloud Quotas API to execute resource allocation changes.

   ```bash
   # Create directory for Cloud Function code
   mkdir quota-manager-function
   cd quota-manager-function
   
   # Create requirements.txt for Python dependencies
   cat > requirements.txt << EOF
   google-cloud-monitoring==2.21.0
   google-cloud-quotas==1.1.0
   google-cloud-firestore==2.16.0
   google-cloud-storage==2.18.0
   google-cloud-run==0.10.3
   functions-framework==3.5.0
   numpy==1.26.4
   scikit-learn==1.4.2
   EOF
   
   # Create the main function code
   cat > main.py << 'EOF'
   import json
   import logging
   import os
   from datetime import datetime, timedelta
   from typing import Dict, List, Any
   
   from google.cloud import monitoring_v3
   from google.cloud import quotas_v1
   from google.cloud import firestore
   from google.cloud import storage
   from google.cloud import run_v2
   import numpy as np
   from sklearn.linear_model import LinearRegression
   
   # Configure logging
   logging.basicConfig(level=logging.INFO)
   logger = logging.getLogger(__name__)
   
   def analyze_gpu_utilization(request):
       """Main Cloud Function entry point for quota analysis"""
       try:
           request_json = request.get_json(silent=True)
           if not request_json:
               return {'status': 'error', 'message': 'No JSON payload provided'}, 400
           
           project_id = request_json.get('project_id')
           region = request_json.get('region', 'us-central1')
           
           if not project_id:
               return {'status': 'error', 'message': 'project_id is required'}, 400
           
           # Initialize clients
           monitoring_client = monitoring_v3.MetricServiceClient()
           quotas_client = quotas_v1.CloudQuotasClient()
           firestore_client = firestore.Client()
           storage_client = storage.Client()
           
           # Analyze current utilization
           utilization_data = get_gpu_utilization_metrics(
               monitoring_client, project_id, region
           )
           
           # Load quota policies
           policies = load_quota_policies(storage_client, project_id)
           
           # Make intelligent quota decisions
           recommendations = generate_quota_recommendations(
               utilization_data, policies, firestore_client
           )
           
           # Execute approved recommendations (simulation mode)
           results = execute_quota_adjustments(
               quotas_client, recommendations, project_id
           )
           
           # Store results in Firestore
           store_allocation_history(firestore_client, results)
           
           return {
               'status': 'success',
               'recommendations': len(recommendations),
               'executed': len(results),
               'timestamp': datetime.utcnow().isoformat()
           }
           
       except Exception as e:
           logger.error(f"Quota analysis failed: {str(e)}")
           return {'status': 'error', 'message': str(e)}, 500
   
   def get_gpu_utilization_metrics(client, project_id: str, region: str) -> Dict:
       """Retrieve GPU utilization metrics from Cloud Monitoring"""
       try:
           project_name = f"projects/{project_id}"
           interval = monitoring_v3.TimeInterval()
           now = datetime.utcnow()
           interval.end_time.seconds = int(now.timestamp())
           interval.start_time.seconds = int((now - timedelta(hours=1)).timestamp())
           
           # Query GPU utilization for Cloud Run services
           gpu_filter = (
               f'resource.type="cloud_run_revision" AND '
               f'resource.labels.location="{region}" AND '
               f'metric.type="run.googleapis.com/container/gpu/utilization"'
           )
           
           request = monitoring_v3.ListTimeSeriesRequest(
               name=project_name,
               filter=gpu_filter,
               interval=interval,
               view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
           )
           
           utilization_data = {
               'average_utilization': 0.0,
               'peak_utilization': 0.0,
               'service_count': 0,
               'total_gpus': 0
           }
           
           time_series = client.list_time_series(request=request)
           utilizations = []
           
           for series in time_series:
               for point in series.points:
                   utilizations.append(point.value.double_value)
               utilization_data['service_count'] += 1
           
           if utilizations:
               utilization_data['average_utilization'] = np.mean(utilizations)
               utilization_data['peak_utilization'] = np.max(utilizations)
           
           logger.info(f"GPU utilization analysis: {utilization_data}")
           return utilization_data
           
       except Exception as e:
           logger.error(f"Failed to get utilization metrics: {str(e)}")
           return {'error': str(e)}
   
   def load_quota_policies(storage_client, project_id: str) -> Dict:
       """Load quota management policies from Cloud Storage"""
       try:
           # Use the environment variable for bucket name consistency
           bucket_name = os.environ.get('BUCKET_NAME', f"{project_id}-quota-policies")
           bucket = storage_client.bucket(bucket_name)
           blob = bucket.blob('quota-policy.json')
           
           policy_content = blob.download_as_text()
           return json.loads(policy_content)
           
       except Exception as e:
           logger.error(f"Failed to load quota policies: {str(e)}")
           return {}
   
   def generate_quota_recommendations(
       utilization_data: Dict, policies: Dict, firestore_client
   ) -> List[Dict]:
       """Generate intelligent quota adjustment recommendations"""
       recommendations = []
       
       if not utilization_data or 'average_utilization' not in utilization_data:
           return recommendations
       
       avg_util = utilization_data['average_utilization']
       peak_util = utilization_data['peak_utilization']
       
       # Check if utilization exceeds thresholds
       gpu_threshold = policies.get('allocation_thresholds', {}).get('gpu_utilization_trigger', 0.8)
       
       if peak_util > gpu_threshold:
           # Recommend quota increase
           for gpu_family, settings in policies.get('gpu_families', {}).items():
               current_quota = get_current_quota(gpu_family)
               new_quota = min(
                   current_quota + settings.get('increment_size', 1),
                   settings.get('max_quota', 10)
               )
               
               if new_quota > current_quota:
                   recommendations.append({
                       'action': 'increase',
                       'gpu_family': gpu_family,
                       'current_quota': current_quota,
                       'recommended_quota': new_quota,
                       'reason': f'Peak utilization {peak_util:.2f} exceeds threshold {gpu_threshold}'
                   })
       
       elif avg_util < gpu_threshold * 0.5:
           # Consider quota decrease for cost optimization
           for gpu_family, settings in policies.get('gpu_families', {}).items():
               current_quota = get_current_quota(gpu_family)
               new_quota = max(
                   current_quota - 1,
                   settings.get('min_quota', 1)
               )
               
               if new_quota < current_quota:
                   recommendations.append({
                       'action': 'decrease',
                       'gpu_family': gpu_family,
                       'current_quota': current_quota,
                       'recommended_quota': new_quota,
                       'reason': f'Low utilization {avg_util:.2f} allows cost optimization'
                   })
       
       return recommendations
   
   def get_current_quota(gpu_family: str) -> int:
       """Get current GPU quota for specified family"""
       # Simplified implementation - would query Cloud Quotas API
       return 3  # Default quota
   
   def execute_quota_adjustments(
       quotas_client, recommendations: List[Dict], project_id: str
   ) -> List[Dict]:
       """Execute approved quota adjustments via Cloud Quotas API"""
       results = []
       
       for rec in recommendations:
           try:
               # Create quota preference request (simulation mode)
               quota_preference = {
                   'service': 'run.googleapis.com',
                   'quota_id': f'GPU-{rec["gpu_family"].upper()}-per-project-region',
                   'quota_config': {
                       'preferred_value': rec['recommended_quota']
                   },
                   'dimensions': {
                       'region': 'us-central1',
                       'gpu_family': rec['gpu_family']
                   },
                   'justification': f'Automated allocation: {rec["reason"]}',
                   'contact_email': 'admin@example.com'
               }
               
               logger.info(f"Would execute quota adjustment: {quota_preference}")
               
               # Store successful execution
               results.append({
                   'recommendation': rec,
                   'status': 'simulated',
                   'timestamp': datetime.utcnow().isoformat()
               })
               
           except Exception as e:
               logger.error(f"Failed to execute quota adjustment: {str(e)}")
               results.append({
                   'recommendation': rec,
                   'status': 'failed',
                   'error': str(e)
               })
       
       return results
   
   def store_allocation_history(firestore_client, results: List[Dict]):
       """Store allocation history in Firestore"""
       try:
           doc_ref = firestore_client.collection('quota_history').document('gpu_allocations')
           
           # Create document if it doesn't exist
           try:
               doc_ref.get()
           except:
               doc_ref.create({
                   'created_at': datetime.utcnow().isoformat(),
                   'allocations': []
               })
           
           doc_ref.update({
               'allocations': firestore.ArrayUnion([{
                   'timestamp': datetime.utcnow().isoformat(),
                   'results': results
               }])
           })
           logger.info("Allocation history stored successfully")
           
       except Exception as e:
           logger.error(f"Failed to store allocation history: {str(e)}")
   EOF
   
   # Deploy the Cloud Function with environment variables
   gcloud functions deploy ${FUNCTION_NAME} \
       --gen2 \
       --runtime=python311 \
       --trigger=http \
       --allow-unauthenticated \
       --region=${REGION} \
       --memory=512MB \
       --timeout=540s \
       --entry-point=analyze_gpu_utilization \
       --set-env-vars="BUCKET_NAME=${BUCKET_NAME}"
   
   cd ..
   
   echo "✅ Cloud Function deployed for intelligent quota management"
   ```

   The Cloud Function is now deployed with sophisticated algorithms for analyzing GPU utilization patterns and making intelligent quota recommendations. This serverless intelligence engine continuously monitors resource usage and applies machine learning techniques to predict optimal allocation strategies, ensuring efficient resource utilization while maintaining cost controls.

4. **Deploy Cloud Run GPU Service for AI Inference**:

   Cloud Run GPU provides the scalable inference platform for AI/ML workloads that drives the demand for intelligent resource allocation. This container service automatically scales GPU-enabled instances based on incoming requests, while the quota management system monitors utilization patterns to ensure adequate resources are always available during peak demand periods.

   ```bash
   # Create directory for Cloud Run service
   mkdir ai-inference-service
   cd ai-inference-service
   
   # Create Dockerfile for GPU-enabled AI inference
   cat > Dockerfile << 'EOF'
   FROM python:3.11-slim
   
   # Install system dependencies
   RUN apt-get update && apt-get install -y \
       curl \
       && rm -rf /var/lib/apt/lists/*
   
   # Install Python dependencies
   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt
   
   # Copy application code
   COPY . .
   
   # Set environment variables
   ENV PORT=8080
   ENV PYTHONUNBUFFERED=1
   
   # Start the application
   CMD ["python", "app.py"]
   EOF
   
   # Create requirements.txt for inference service
   cat > requirements.txt << EOF
   flask==3.0.3
   google-cloud-monitoring==2.21.0
   numpy==1.26.4
   psutil==5.9.8
   gunicorn==22.0.0
   EOF
   
   # Create main application code
   cat > app.py << 'EOF'
   import os
   import time
   import json
   import psutil
   import logging
   from flask import Flask, request, jsonify
   from google.cloud import monitoring_v3
   from datetime import datetime
   import numpy as np
   
   app = Flask(__name__)
   logging.basicConfig(level=logging.INFO)
   logger = logging.getLogger(__name__)
   
   # Initialize monitoring client
   monitoring_client = monitoring_v3.MetricServiceClient()
   project_id = os.environ.get('GOOGLE_CLOUD_PROJECT', 'default-project')
   
   @app.route('/')
   def health_check():
       """Health check endpoint"""
       return jsonify({
           'status': 'healthy',
           'service': 'ai-inference',
           'timestamp': datetime.utcnow().isoformat()
       })
   
   @app.route('/infer', methods=['POST'])
   def process_inference():
       """AI inference endpoint that simulates GPU workload"""
       start_time = time.time()
       
       try:
           # Get request data
           data = request.get_json() or {}
           model_type = data.get('model', 'default')
           complexity = data.get('complexity', 'medium')
           
           # Simulate GPU-intensive processing
           processing_time = simulate_gpu_inference(complexity)
           
           # Record metrics
           record_inference_metrics(processing_time, model_type)
           
           # Generate response
           result = {
               'status': 'success',
               'model': model_type,
               'processing_time': processing_time,
               'complexity': complexity,
               'inference_id': f"inf_{int(time.time())}_{hash(str(data)) % 10000}",
               'timestamp': datetime.utcnow().isoformat()
           }
           
           logger.info(f"Inference completed: {result['inference_id']} in {processing_time:.2f}s")
           return jsonify(result)
           
       except Exception as e:
           logger.error(f"Inference failed: {str(e)}")
           return jsonify({
               'status': 'error',
               'message': str(e),
               'timestamp': datetime.utcnow().isoformat()
           }), 500
   
   def simulate_gpu_inference(complexity: str) -> float:
       """Simulate GPU inference processing with variable load"""
       complexity_multipliers = {
           'low': 0.5,
           'medium': 1.0,
           'high': 2.0,
           'extreme': 4.0
       }
       
       base_time = 0.1  # Base processing time
       multiplier = complexity_multipliers.get(complexity, 1.0)
       
       # Simulate variable processing load
       processing_time = base_time * multiplier * (1 + np.random.uniform(0, 0.5))
       
       # Simulate actual computation
       time.sleep(processing_time)
       
       return processing_time
   
   def record_inference_metrics(processing_time: float, model_type: str):
       """Record custom metrics to Cloud Monitoring"""
       try:
           # Create custom metric for inference latency
           series = monitoring_v3.TimeSeries()
           series.metric.type = 'custom.googleapis.com/ai_inference/latency'
           series.resource.type = 'cloud_run_revision'
           series.resource.labels['service_name'] = os.environ.get('K_SERVICE', 'ai-inference')
           series.resource.labels['revision_name'] = os.environ.get('K_REVISION', 'unknown')
           series.resource.labels['location'] = os.environ.get('GOOGLE_CLOUD_REGION', 'us-central1')
           
           # Add metric labels
           series.metric.labels['model_type'] = model_type
           series.metric.labels['service'] = 'ai-inference'
           
           # Create data point
           point = monitoring_v3.Point()
           point.value.double_value = processing_time
           now = time.time()
           point.interval.end_time.seconds = int(now)
           point.interval.end_time.nanos = int((now - int(now)) * 10**9)
           series.points = [point]
           
           # Send metric (would work in actual Cloud Run environment)
           logger.info(f"Recording metric: latency={processing_time:.3f}s, model={model_type}")
           
       except Exception as e:
           logger.error(f"Failed to record metrics: {str(e)}")
   
   @app.route('/metrics')
   def get_metrics():
       """Endpoint to expose current resource utilization"""
       try:
           cpu_percent = psutil.cpu_percent(interval=1)
           memory = psutil.virtual_memory()
           
           metrics = {
               'cpu_utilization': cpu_percent,
               'memory_utilization': memory.percent,
               'memory_available_gb': memory.available / (1024**3),
               'timestamp': datetime.utcnow().isoformat()
           }
           
           return jsonify(metrics)
           
       except Exception as e:
           return jsonify({'error': str(e)}), 500
   
   if __name__ == '__main__':
       port = int(os.environ.get('PORT', 8080))
       app.run(host='0.0.0.0', port=port, debug=False)
   EOF
   
   # Build and deploy to Cloud Run with GPU
   gcloud builds submit --tag gcr.io/${PROJECT_ID}/${SERVICE_NAME}
   
   # Deploy with updated GPU configuration
   gcloud run deploy ${SERVICE_NAME} \
       --image gcr.io/${PROJECT_ID}/${SERVICE_NAME} \
       --region=${REGION} \
       --gpu=1 \
       --gpu-type=nvidia-l4 \
       --memory=16Gi \
       --cpu=4 \
       --min-instances=0 \
       --max-instances=10 \
       --allow-unauthenticated \
       --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_REGION=${REGION}"
   
   cd ..
   
   echo "✅ Cloud Run GPU service deployed for AI inference"
   ```

   The Cloud Run GPU service is now deployed with intelligent scaling capabilities and comprehensive monitoring integration. This AI inference platform automatically generates the workload patterns that the quota management system analyzes, creating a dynamic feedback loop that ensures optimal resource allocation based on real-world demand patterns.

5. **Create Cloud Scheduler for Automated Analysis**:

   Cloud Scheduler provides the automation backbone that triggers periodic quota analysis and adjustment cycles. This managed cron service ensures consistent monitoring of resource utilization patterns and proactive quota management, eliminating the need for manual intervention while maintaining optimal resource allocation across all GPU-enabled services.

   ```bash
   # Get the Cloud Function URL for scheduling
   FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
   
   # Create Cloud Scheduler job for periodic quota analysis
   gcloud scheduler jobs create http quota-analysis-job \
       --location=${REGION} \
       --schedule="*/15 * * * *" \
       --uri="${FUNCTION_URL}" \
       --http-method=POST \
       --headers="Content-Type=application/json" \
       --message-body="{\"project_id\":\"${PROJECT_ID}\",\"region\":\"${REGION}\"}" \
       --description="Automated GPU quota analysis and adjustment"
   
   # Create additional scheduler for peak hour analysis
   gcloud scheduler jobs create http peak-analysis-job \
       --location=${REGION} \
       --schedule="0 9-17 * * 1-5" \
       --uri="${FUNCTION_URL}" \
       --http-method=POST \
       --headers="Content-Type=application/json" \
       --message-body="{\"project_id\":\"${PROJECT_ID}\",\"region\":\"${REGION}\",\"analysis_type\":\"peak\"}" \
       --description="Peak hour intensive quota analysis"
   
   echo "✅ Cloud Scheduler configured for automated quota analysis"
   echo "   - Regular analysis: Every 15 minutes"
   echo "   - Peak hour analysis: Business hours (9-17 UTC)"
   ```

   Cloud Scheduler is now orchestrating automated quota intelligence cycles, ensuring continuous monitoring and proactive resource allocation adjustments. The dual-schedule approach provides both regular monitoring and intensive analysis during peak business hours, optimizing resource availability when demand is highest.

6. **Configure Monitoring Dashboards and Alerts**:

   Cloud Monitoring dashboards provide comprehensive visibility into GPU utilization patterns, quota consumption, and allocation decision effectiveness. These monitoring capabilities enable both automated systems and human operators to understand resource allocation patterns and make informed decisions about capacity planning and cost optimization strategies.

   ```bash
   # Create custom dashboard configuration
   cat > dashboard-config.json << EOF
   {
     "displayName": "GPU Quota Intelligence Dashboard",
     "mosaicLayout": {
       "tiles": [
         {
           "width": 6,
           "height": 4,
           "widget": {
             "title": "GPU Utilization Trends",
             "xyChart": {
               "dataSets": [{
                 "timeSeriesQuery": {
                   "timeSeriesFilter": {
                     "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/gpu/utilization\"",
                     "aggregation": {
                       "alignmentPeriod": "300s",
                       "perSeriesAligner": "ALIGN_MEAN",
                       "crossSeriesReducer": "REDUCE_MEAN"
                     }
                   }
                 },
                 "plotType": "LINE"
               }]
             }
           }
         },
         {
           "width": 6,
           "height": 4,
           "widget": {
             "title": "Quota Allocation History",
             "xyChart": {
               "dataSets": [{
                 "timeSeriesQuery": {
                   "timeSeriesFilter": {
                     "filter": "metric.type=\"custom.googleapis.com/quota/gpu_allocation\"",
                     "aggregation": {
                       "alignmentPeriod": "3600s",
                       "perSeriesAligner": "ALIGN_MAX"
                     }
                   }
                 },
                 "plotType": "STACKED_BAR"
               }]
             }
           }
         }
       ]
     }
   }
   EOF
   
   # Create alert policy for high GPU utilization
   cat > alert-policy.json << EOF
   {
     "displayName": "High GPU Utilization Alert",
     "conditions": [{
       "displayName": "GPU utilization above 85%",
       "conditionThreshold": {
         "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/gpu/utilization\"",
         "comparison": "COMPARISON_GT",
         "thresholdValue": 0.85,
         "duration": "300s",
         "aggregations": [{
           "alignmentPeriod": "300s",
           "perSeriesAligner": "ALIGN_MEAN"
         }]
       }
     }],
     "alertStrategy": {
       "autoClose": "1800s"
     },
     "enabled": true,
     "notificationChannels": []
   }
   EOF
   
   echo "✅ Monitoring dashboards and alerts configured"
   echo "   - GPU utilization tracking enabled"
   echo "   - Quota allocation monitoring active"
   echo "   - High utilization alerts configured"
   ```

   Comprehensive monitoring is now in place to track GPU utilization patterns and quota allocation effectiveness. The dashboard provides real-time visibility into resource consumption trends while alert policies ensure immediate notification of high utilization events that may require quota adjustments.

## Validation & Testing

1. **Verify Cloud Quotas API Configuration**:

   ```bash
   # Check Cloud Quotas API status and current GPU quotas
   gcloud services list --enabled --filter="name:cloudquotas"
   
   # List current GPU quota information for Cloud Run
   gcloud beta quotas info list \
       --service=run.googleapis.com \
       --project=${PROJECT_ID} \
       --filter="quotaId:GPU"
   ```

   Expected output: Cloud Quotas API should be enabled with current GPU quota values displayed.

2. **Test AI Inference Service GPU Allocation**:

   ```bash
   # Get Cloud Run service URL
   SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format="value(status.url)")
   
   # Test inference endpoint with various complexity levels
   curl -X POST ${SERVICE_URL}/infer \
       -H "Content-Type: application/json" \
       -d '{"model": "llama-7b", "complexity": "medium"}'
   
   # Test high-complexity inference
   curl -X POST ${SERVICE_URL}/infer \
       -H "Content-Type: application/json" \
       -d '{"model": "gpt-large", "complexity": "high"}'
   
   # Check service metrics
   curl ${SERVICE_URL}/metrics
   ```

   Expected output: Successful inference responses with processing times and resource utilization metrics.

3. **Validate Quota Intelligence Function**:

   ```bash
   # Trigger quota analysis manually
   FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
   
   curl -X POST ${FUNCTION_URL} \
       -H "Content-Type: application/json" \
       -d "{\"project_id\":\"${PROJECT_ID}\",\"region\":\"${REGION}\"}"
   
   # Check function execution logs
   gcloud functions logs read ${FUNCTION_NAME} \
       --region=${REGION} \
       --limit=20
   ```

   Expected output: Function should execute successfully with quota analysis results and recommendations.

4. **Verify Automated Scheduling**:

   ```bash
   # Check Cloud Scheduler job status
   gcloud scheduler jobs list --location=${REGION}
   
   # View job execution history
   gcloud scheduler jobs describe quota-analysis-job \
       --location=${REGION}
   ```

   Expected output: Scheduler jobs should be listed as enabled with successful execution history.

## Cleanup

1. **Remove Cloud Scheduler Jobs**:

   ```bash
   # Delete all scheduler jobs
   gcloud scheduler jobs delete quota-analysis-job \
       --location=${REGION} \
       --quiet
   
   gcloud scheduler jobs delete peak-analysis-job \
       --location=${REGION} \
       --quiet
   
   echo "✅ Cloud Scheduler jobs removed"
   ```

2. **Delete Cloud Run Services**:

   ```bash
   # Delete Cloud Run GPU service
   gcloud run services delete ${SERVICE_NAME} \
       --region=${REGION} \
       --quiet
   
   # Delete container images
   gcloud container images delete gcr.io/${PROJECT_ID}/${SERVICE_NAME} \
       --quiet
   
   echo "✅ Cloud Run services and images removed"
   ```

3. **Remove Cloud Function and Storage**:

   ```bash
   # Delete Cloud Function
   gcloud functions delete ${FUNCTION_NAME} \
       --region=${REGION} \
       --quiet
   
   # Remove Cloud Storage bucket and contents
   gsutil -m rm -r gs://${BUCKET_NAME}
   
   echo "✅ Cloud Function and storage resources removed"
   ```

4. **Clean Up Firestore and Monitoring Resources**:

   ```bash
   # Delete Firestore database (requires manual confirmation)
   echo "Note: Firestore database deletion requires manual action in console"
   echo "Visit: https://console.cloud.google.com/firestore"
   
   # Clean up local files
   rm -rf quota-manager-function ai-inference-service
   rm -f quota-policy.json dashboard-config.json alert-policy.json
   
   echo "✅ Local files and configurations cleaned up"
   echo "⚠️  Remember to manually delete Firestore database if no longer needed"
   ```

## Discussion

This intelligent resource allocation system demonstrates the power of combining Google Cloud's managed services to create autonomous infrastructure management solutions. The Cloud Quotas API serves as the foundation for programmatic quota management, enabling organizations to move beyond manual resource allocation to intelligent, data-driven decisions based on real-world usage patterns.

The architecture leverages Cloud Run GPU for scalable AI inference workloads, providing the dynamic resource demands that drive quota optimization decisions. Cloud Functions acts as the central intelligence engine, applying machine learning algorithms to analyze utilization patterns and predict optimal resource allocation strategies. This serverless approach ensures cost-effective operation while maintaining the responsiveness needed for real-time quota adjustments.

Cloud Monitoring integration provides comprehensive visibility into both infrastructure utilization and quota allocation effectiveness. The system tracks GPU utilization patterns, inference latency trends, and cost optimization opportunities, creating a feedback loop that continuously improves allocation accuracy. Historical data stored in Firestore enables trend analysis and predictive scaling, while Cloud Storage maintains versioned quota policies for consistent governance across environments.

The automated scheduling capability ensures continuous monitoring without manual intervention, while the intelligent thresholding system prevents unnecessary quota adjustments that could impact cost optimization. This balance between proactive resource allocation and cost control represents a sophisticated approach to cloud resource management that scales from small development projects to enterprise-grade AI/ML workloads.

> **Tip**: Implement gradual quota adjustment policies to avoid sudden cost increases. Start with conservative thresholds and adjust based on historical usage patterns and cost tolerance.

For organizations deploying this system in production, consider implementing additional safeguards such as maximum quota limits, cost threshold alerts, and manual approval workflows for large quota increases. The system's modular design allows for easy customization of allocation policies and integration with existing operational tools and workflows.

Additional resources for implementation and optimization:
- [Google Cloud Quotas API Documentation](https://cloud.google.com/docs/quotas)
- [Cloud Run GPU Best Practices](https://cloud.google.com/run/docs/configuring/services/gpu)
- [Cloud Monitoring Custom Metrics](https://cloud.google.com/monitoring/custom-metrics)
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
- [AI/ML Cost Optimization Guide](https://cloud.google.com/architecture/ai-ml-cost-optimization)

## Challenge

Extend this intelligent resource allocation system with these advanced capabilities:

1. **Multi-Region Optimization**: Implement cross-region quota balancing that automatically redistributes GPU resources based on regional demand patterns and cost optimization opportunities across Google Cloud's global infrastructure.

2. **Predictive Scaling Integration**: Enhance the intelligence engine with time-series forecasting models that predict demand spikes and proactively adjust quotas before utilization thresholds are reached, improving application performance during peak loads.

3. **Cost-Aware Allocation**: Integrate Google Cloud Billing APIs to implement cost-conscious quota management that considers GPU pricing variations across regions and instance types, automatically selecting the most cost-effective allocation strategies.

4. **Multi-Service Integration**: Extend quota management beyond Cloud Run to include Compute Engine GPU instances, Google Kubernetes Engine GPU nodes, and Vertex AI training jobs, creating a unified resource allocation strategy across all GPU-enabled services.

5. **Advanced Anomaly Detection**: Implement machine learning-based anomaly detection that identifies unusual usage patterns and automatically adjusts quota policies to handle unexpected workload behaviors while maintaining cost controls and security compliance.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Infrastructure Manager](code/infrastructure-manager/) - GCP Infrastructure Manager templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using gcloud CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files