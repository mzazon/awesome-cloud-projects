"""
Data Locality Optimization Cloud Function
This function analyzes Cloud Storage access patterns and triggers bucket relocation
when performance thresholds are exceeded or access patterns indicate better placement.
"""

import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Optional, Any

from google.cloud import storage
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1
import functions_framework

# Initialize clients
storage_client = storage.Client()
monitoring_client = monitoring_v3.MetricServiceClient()
publisher = pubsub_v1.PublisherClient()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def analyze_access_patterns(bucket_name: str, project_id: str) -> Dict[str, int]:
    """
    Analyze storage access patterns using Cloud Monitoring data.
    
    Args:
        bucket_name: Name of the Cloud Storage bucket to analyze
        project_id: Google Cloud project ID
        
    Returns:
        Dictionary mapping regions to access counts
    """
    try:
        # Query monitoring metrics for access patterns
        project_name = f"projects/{project_id}"
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": int(end_time.timestamp())},
            "start_time": {"seconds": int(start_time.timestamp())},
        })
        
        # Build query for storage access metrics
        filter_str = (
            f'resource.type="gcs_bucket" AND '
            f'resource.label.bucket_name="{bucket_name}"'
        )
        
        request = monitoring_v3.ListTimeSeriesRequest(
            name=project_name,
            filter=filter_str,
            interval=interval,
        )
        
        results = monitoring_client.list_time_series(request=request)
        
        access_patterns = {}
        for result in results:
            if result.resource.labels.get('location'):
                location = result.resource.labels['location']
                # Count data points as access indicators
                access_patterns[location] = access_patterns.get(location, 0) + len(result.points)
        
        logger.info(f"Analyzed access patterns for bucket {bucket_name}: {access_patterns}")
        return access_patterns
        
    except Exception as e:
        logger.error(f"Error analyzing access patterns: {str(e)}")
        return {}


def determine_optimal_location(access_patterns: Dict[str, int], current_location: str) -> Optional[str]:
    """
    Determine optimal bucket location based on access patterns.
    
    Args:
        access_patterns: Dictionary mapping regions to access counts
        current_location: Current bucket location
        
    Returns:
        Optimal region name or None if no change needed
    """
    if not access_patterns:
        logger.info("No access patterns found, keeping current location")
        return None
    
    # Find region with highest access frequency
    optimal_region = max(access_patterns, key=access_patterns.get)
    
    # Calculate access concentration (>70% from single region = consider relocation)
    total_access = sum(access_patterns.values())
    if total_access == 0:
        return None
        
    concentration = access_patterns[optimal_region] / total_access
    
    logger.info(
        f"Access concentration: {concentration:.2%} from {optimal_region}, "
        f"current location: {current_location}"
    )
    
    # Only relocate if concentration is high and different from current location
    if concentration > 0.7 and optimal_region.lower() != current_location.lower():
        return optimal_region
    
    return None


def publish_notification(project_id: str, topic_name: str, message_data: Dict[str, Any]) -> bool:
    """
    Publish notification message to Pub/Sub topic.
    
    Args:
        project_id: Google Cloud project ID
        topic_name: Pub/Sub topic name
        message_data: Message data to publish
        
    Returns:
        True if successful, False otherwise
    """
    try:
        topic_path = publisher.topic_path(project_id, topic_name)
        message_json = json.dumps(message_data, default=str)
        message_bytes = message_json.encode('utf-8')
        
        future = publisher.publish(topic_path, message_bytes)
        message_id = future.result()
        
        logger.info(f"Published notification with message ID: {message_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error publishing notification: {str(e)}")
        return False


def simulate_bucket_relocation(bucket_name: str, target_location: str, project_id: str) -> Dict[str, Any]:
    """
    Simulate bucket relocation process.
    
    Note: This is a simulation for demonstration purposes.
    In production, this would integrate with Cloud Storage's bucket relocation service.
    
    Args:
        bucket_name: Name of the bucket to relocate
        target_location: Target location for relocation
        project_id: Google Cloud project ID
        
    Returns:
        Dictionary containing relocation result information
    """
    try:
        bucket = storage_client.bucket(bucket_name)
        current_location = bucket.location
        
        # Check if relocation is actually needed
        if current_location.lower() == target_location.lower():
            return {
                "status": "no_action",
                "message": "Bucket already in optimal location",
                "current_location": current_location,
                "target_location": target_location
            }
        
        # Simulate relocation process
        # In production, this would call the actual bucket relocation API
        relocation_info = {
            "status": "initiated",
            "message": f"Bucket relocation initiated from {current_location} to {target_location}",
            "source_location": current_location,
            "target_location": target_location,
            "bucket_name": bucket_name,
            "timestamp": datetime.now().isoformat(),
            "estimated_completion": (datetime.now() + timedelta(hours=2)).isoformat(),
            "simulation": True  # Indicates this is a simulation
        }
        
        # Publish notification about the relocation
        topic_name = os.environ.get('PUBSUB_TOPIC', '')
        if topic_name:
            publish_notification(project_id, topic_name, relocation_info)
        
        logger.info(f"Simulated bucket relocation: {relocation_info}")
        return relocation_info
        
    except Exception as e:
        error_info = {
            "status": "error",
            "message": f"Relocation simulation failed: {str(e)}",
            "bucket_name": bucket_name,
            "target_location": target_location,
            "timestamp": datetime.now().isoformat()
        }
        
        logger.error(f"Relocation simulation error: {error_info}")
        return error_info


def get_bucket_metrics(bucket_name: str, project_id: str) -> Dict[str, Any]:
    """
    Get additional bucket metrics for analysis.
    
    Args:
        bucket_name: Name of the bucket
        project_id: Google Cloud project ID
        
    Returns:
        Dictionary containing bucket metrics
    """
    try:
        bucket = storage_client.bucket(bucket_name)
        
        # Get bucket metadata
        metrics = {
            "name": bucket.name,
            "location": bucket.location,
            "storage_class": bucket.storage_class,
            "created": bucket.time_created.isoformat() if bucket.time_created else None,
            "labels": dict(bucket.labels) if bucket.labels else {},
            "versioning_enabled": bucket.versioning_enabled,
            "uniform_bucket_level_access": bucket.iam_configuration.uniform_bucket_level_access_enabled
        }
        
        # Count objects (limited to avoid performance issues)
        try:
            blobs = list(bucket.list_blobs(max_results=1000))
            metrics["object_count"] = len(blobs)
            metrics["total_size_bytes"] = sum(blob.size for blob in blobs if blob.size)
        except Exception as e:
            logger.warning(f"Could not get object metrics: {str(e)}")
            metrics["object_count"] = "unknown"
            metrics["total_size_bytes"] = "unknown"
        
        return metrics
        
    except Exception as e:
        logger.error(f"Error getting bucket metrics: {str(e)}")
        return {"error": str(e)}


@functions_framework.http
def bucket_relocator(request):
    """
    Main Cloud Function entry point for bucket relocation analysis.
    
    This function analyzes bucket access patterns and determines if relocation
    would improve performance. It can be triggered by HTTP requests, Cloud Scheduler,
    or monitoring alerts.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with analysis results
    """
    try:
        # Get environment variables
        project_id = os.environ.get('GCP_PROJECT')
        bucket_name = os.environ.get('BUCKET_NAME')
        
        if not project_id or not bucket_name:
            error_response = {
                "status": "error",
                "message": "Missing required environment variables (GCP_PROJECT, BUCKET_NAME)",
                "timestamp": datetime.now().isoformat()
            }
            logger.error(f"Configuration error: {error_response}")
            return json.dumps(error_response), 400
        
        logger.info(f"Starting data locality analysis for bucket: {bucket_name}")
        
        # Get current bucket information
        bucket_metrics = get_bucket_metrics(bucket_name, project_id)
        current_location = bucket_metrics.get('location', 'unknown')
        
        # Analyze access patterns
        access_patterns = analyze_access_patterns(bucket_name, project_id)
        
        # Determine if relocation would be beneficial
        optimal_location = determine_optimal_location(access_patterns, current_location)
        
        # Prepare response
        response_data = {
            "status": "completed",
            "timestamp": datetime.now().isoformat(),
            "bucket_name": bucket_name,
            "current_location": current_location,
            "access_patterns": access_patterns,
            "optimal_location": optimal_location,
            "bucket_metrics": bucket_metrics,
            "recommendation": "no_action"
        }
        
        # Take action if relocation is recommended
        if optimal_location:
            response_data["recommendation"] = "relocate"
            relocation_result = simulate_bucket_relocation(
                bucket_name, optimal_location, project_id
            )
            response_data["relocation_result"] = relocation_result
            
            logger.info(f"Recommended relocation to {optimal_location}")
        else:
            response_data["message"] = "Current bucket location is optimal based on access patterns"
            logger.info("No relocation needed - current location is optimal")
        
        # Log analysis summary
        logger.info(f"Analysis complete: {response_data['recommendation']}")
        
        return json.dumps(response_data, indent=2)
        
    except Exception as e:
        error_response = {
            "status": "error",
            "message": f"Function execution failed: {str(e)}",
            "timestamp": datetime.now().isoformat(),
            "bucket_name": os.environ.get('BUCKET_NAME', 'unknown')
        }
        
        logger.error(f"Function execution error: {error_response}")
        return json.dumps(error_response), 500


# Health check endpoint
@functions_framework.http
def health_check(request):
    """
    Health check endpoint for monitoring function availability.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with health status
    """
    health_status = {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "service": "data-locality-optimization",
        "version": "1.0"
    }
    
    return json.dumps(health_status)