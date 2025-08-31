# Cloud Function for Metrics Collection
# This function collects and stores comprehensive code review metrics

import json
import os
from datetime import datetime, timedelta
from google.cloud import monitoring_v3
from google.cloud import logging
from google.cloud import storage
import functions_framework

# Configuration from template variables
PROJECT_ID = "${project_id}"
REGION = "${region}"

# Initialize clients
logging_client = logging.Client()
logger = logging_client.logger('code-review-metrics')
monitoring_client = monitoring_v3.MetricServiceClient()
storage_client = storage.Client()

@functions_framework.http
def collect_review_metrics(request):
    """Collect and store comprehensive code review metrics."""
    
    try:
        request_data = request.get_json(silent=True)
        if not request_data:
            logger.warning("No metrics data provided")
            return {'error': 'No metrics data provided'}, 400
        
        project_id = PROJECT_ID
        if not project_id:
            logger.error("PROJECT_ID not configured")
            return {'error': 'Configuration error'}, 500
        
        project_name = f"projects/{project_id}"
        
        # Extract metrics from request
        metrics_data = {
            'review_duration': request_data.get('review_duration', 0),
            'issues_found': request_data.get('issues_count', 0),
            'code_quality_score': request_data.get('quality_score', 0),
            'files_analyzed': request_data.get('files_analyzed', 0),
            'security_issues': request_data.get('security_issues', 0),
            'performance_issues': request_data.get('performance_issues', 0),
            'test_coverage': request_data.get('test_coverage', 0),
            'build_duration': request_data.get('build_duration', 0)
        }
        
        # Create detailed metrics for monitoring
        metrics_logged = 0
        
        for metric_name, value in metrics_data.items():
            if value > 0:  # Only log meaningful metrics
                try:
                    # Log structured metric data
                    logger.info(
                        f"Code review metric: {metric_name}",
                        extra={
                            'metric_name': metric_name,
                            'metric_value': value,
                            'repo_name': request_data.get('repo_name', ''),
                            'commit_sha': request_data.get('commit_sha', ''),
                            'branch': request_data.get('branch', 'main'),
                            'review_type': request_data.get('review_type', 'automated'),
                            'timestamp': datetime.utcnow().isoformat()
                        }
                    )
                    metrics_logged += 1
                    
                except Exception as e:
                    logger.error(f"Failed to log metric {metric_name}: {str(e)}")
        
        # Store aggregate metrics for analysis
        try:
            aggregate_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'repository': request_data.get('repo_name', ''),
                'metrics': metrics_data,
                'metadata': {
                    'commit_sha': request_data.get('commit_sha', ''),
                    'branch': request_data.get('branch', 'main'),
                    'review_type': request_data.get('review_type', 'automated'),
                    'reviewer': request_data.get('reviewer', 'ai-agent')
                }
            }
            
            # Store in Cloud Storage for long-term analysis
            bucket_name = os.environ.get('METRICS_BUCKET')
            if bucket_name:
                date_prefix = datetime.utcnow().strftime('%Y/%m/%d')
                filename = f"{date_prefix}/metrics-{datetime.utcnow().strftime('%H%M%S')}.json"
                
                try:
                    bucket = storage_client.bucket(bucket_name)
                    blob = bucket.blob(filename)
                    blob.upload_from_string(json.dumps(aggregate_data, indent=2))
                    logger.info(f"Metrics stored to gs://{bucket_name}/{filename}")
                except Exception as e:
                    logger.warning(f"Failed to store metrics to Cloud Storage: {str(e)}")
            else:
                logger.warning("METRICS_BUCKET not configured - skipping storage")
        
        except Exception as e:
            logger.error(f"Failed to process aggregate metrics: {str(e)}")
        
        # Return success response
        response_data = {
            'status': 'success',
            'metrics_recorded': metrics_logged,
            'timestamp': datetime.utcnow().isoformat(),
            'project_id': project_id
        }
        
        logger.info(f"Successfully processed {metrics_logged} metrics")
        return response_data
        
    except Exception as e:
        logger.error(f"Unhandled error in collect_review_metrics: {str(e)}")
        return {'error': 'Internal server error'}, 500