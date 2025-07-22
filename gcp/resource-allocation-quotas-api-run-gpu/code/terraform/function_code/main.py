import json
import logging
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
        # Parse request data
        request_json = request.get_json() or {}
        project_id = request_json.get('project_id', '${project_id}')
        region = request_json.get('region', '${region}')
        analysis_type = request_json.get('analysis_type', 'regular')
        
        logger.info(f"Starting quota analysis for project {project_id}, region {region}")
        
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
        policies = load_quota_policies(storage_client, '${bucket_name}')
        
        # Make intelligent quota decisions
        recommendations = generate_quota_recommendations(
            utilization_data, policies, firestore_client, analysis_type
        )
        
        # Execute approved recommendations
        results = execute_quota_adjustments(
            quotas_client, recommendations, project_id, region
        )
        
        # Store results in Firestore
        store_allocation_history(firestore_client, results)
        
        response = {
            'status': 'success',
            'analysis_type': analysis_type,
            'recommendations': len(recommendations),
            'executed': len(results),
            'utilization_data': utilization_data,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        logger.info(f"Quota analysis completed: {response}")
        return response
        
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
            'total_gpus': 0,
            'region': region
        }
        
        try:
            time_series = client.list_time_series(request=request)
            utilizations = []
            
            for series in time_series:
                for point in series.points:
                    utilizations.append(point.value.double_value)
                utilization_data['service_count'] += 1
            
            if utilizations:
                utilization_data['average_utilization'] = float(np.mean(utilizations))
                utilization_data['peak_utilization'] = float(np.max(utilizations))
            
            logger.info(f"GPU utilization analysis: {utilization_data}")
            
        except Exception as e:
            logger.warning(f"Could not retrieve GPU metrics: {str(e)}")
            # Use simulated data for demonstration
            utilization_data['average_utilization'] = 0.7
            utilization_data['peak_utilization'] = 0.85
            utilization_data['service_count'] = 1
        
        return utilization_data
        
    except Exception as e:
        logger.error(f"Failed to get utilization metrics: {str(e)}")
        return {'error': str(e)}

def load_quota_policies(storage_client, bucket_name: str) -> Dict:
    """Load quota management policies from Cloud Storage"""
    try:
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob('quota-policy.json')
        
        policy_content = blob.download_as_text()
        policies = json.loads(policy_content)
        
        logger.info(f"Loaded quota policies: {policies}")
        return policies
        
    except Exception as e:
        logger.error(f"Failed to load quota policies: {str(e)}")
        # Return default policies
        return {
            'allocation_thresholds': {
                'gpu_utilization_trigger': 0.8,
                'cpu_utilization_trigger': 0.75,
                'memory_utilization_trigger': 0.85
            },
            'gpu_families': {
                'nvidia-l4': {
                    'max_quota': 10,
                    'min_quota': 1,
                    'increment_size': 2
                }
            },
            'regions': ['${region}'],
            'cost_optimization': {
                'enable_preemptible': True,
                'max_cost_per_hour': 50.0
            }
        }

def generate_quota_recommendations(
    utilization_data: Dict, policies: Dict, firestore_client, analysis_type: str
) -> List[Dict]:
    """Generate intelligent quota adjustment recommendations"""
    recommendations = []
    
    if 'error' in utilization_data or not utilization_data:
        logger.warning("No valid utilization data available")
        return recommendations
    
    avg_util = utilization_data.get('average_utilization', 0)
    peak_util = utilization_data.get('peak_utilization', 0)
    
    # Check if utilization exceeds thresholds
    gpu_threshold = policies.get('allocation_thresholds', {}).get('gpu_utilization_trigger', 0.8)
    
    logger.info(f"Analyzing utilization: avg={avg_util:.2f}, peak={peak_util:.2f}, threshold={gpu_threshold}")
    
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
                    'reason': f'Peak utilization {peak_util:.2f} exceeds threshold {gpu_threshold}',
                    'analysis_type': analysis_type
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
                    'reason': f'Low utilization {avg_util:.2f} allows cost optimization',
                    'analysis_type': analysis_type
                })
    
    logger.info(f"Generated {len(recommendations)} recommendations")
    return recommendations

def get_current_quota(gpu_family: str) -> int:
    """Get current GPU quota for specified family"""
    # Simplified implementation - would query Cloud Quotas API in production
    quota_map = {
        'nvidia-l4': 3,
        'nvidia-t4': 2
    }
    return quota_map.get(gpu_family, 1)

def execute_quota_adjustments(
    quotas_client, recommendations: List[Dict], project_id: str, region: str
) -> List[Dict]:
    """Execute approved quota adjustments via Cloud Quotas API"""
    results = []
    
    for rec in recommendations:
        try:
            # Create quota preference request
            quota_preference = {
                'service': 'run.googleapis.com',
                'quota_id': f'GPU-{rec["gpu_family"].upper()}-per-project-region',
                'quota_config': {
                    'preferred_value': rec['recommended_quota']
                },
                'dimensions': {
                    'region': region,
                    'gpu_family': rec['gpu_family']
                },
                'justification': f'Automated allocation: {rec["reason"]}',
                'contact_email': 'admin@example.com'
            }
            
            logger.info(f"Would execute quota adjustment: {quota_preference}")
            
            # Note: Actual quota adjustment would require proper permissions and approval
            # This is a simulation for demonstration purposes
            
            # Store successful execution
            results.append({
                'recommendation': rec,
                'status': 'simulated',
                'quota_preference': quota_preference,
                'timestamp': datetime.utcnow().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Failed to execute quota adjustment: {str(e)}")
            results.append({
                'recommendation': rec,
                'status': 'failed',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
    
    return results

def store_allocation_history(firestore_client, results: List[Dict]):
    """Store allocation history in Firestore"""
    try:
        collection_ref = firestore_client.collection('quota_history')
        doc_ref = collection_ref.document('gpu_allocations')
        
        # Create document if it doesn't exist
        doc = doc_ref.get()
        if not doc.exists:
            doc_ref.set({
                'created_at': datetime.utcnow(),
                'allocations': []
            })
        
        # Add new allocation record
        allocation_record = {
            'timestamp': datetime.utcnow(),
            'results': results,
            'analysis_count': len(results)
        }
        
        doc_ref.update({
            'allocations': firestore.ArrayUnion([allocation_record]),
            'last_updated': datetime.utcnow()
        })
        
        logger.info(f"Stored allocation history with {len(results)} results")
        
    except Exception as e:
        logger.error(f"Failed to store allocation history: {str(e)}")