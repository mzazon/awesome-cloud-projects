import os
import json
import logging
from typing import Dict, Any
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def orchestrate_migration(request):
    """
    Orchestrate database migration workflows with Dynamic Workload Scheduler
    
    This function manages migration worker scaling based on workload demands
    and coordinates resource allocation for optimal cost and performance.
    
    Args:
        request: HTTP request containing migration parameters
        
    Returns:
        JSON response with orchestration status and configuration
    """
    
    # Initialize Cloud Logging client
    logging_client = cloud_logging.Client()
    logging_client.setup_logging()
    
    try:
        # Parse migration request
        request_json = request.get_json(silent=True) or {}
        migration_priority = request_json.get('priority', 'low')
        database_size_gb = int(request_json.get('size_gb', 100))
        migration_type = request_json.get('type', 'continuous')
        
        logger.info(f"Processing migration request: priority={migration_priority}, "
                   f"size={database_size_gb}GB, type={migration_type}")
        
        # Get environment variables
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION')
        
        if not project_id or not region:
            raise ValueError("PROJECT_ID and REGION environment variables must be set")
        
        # Calculate optimal worker count based on database size
        # Small databases (< 50GB): 1-2 workers
        # Medium databases (50-200GB): 2-4 workers  
        # Large databases (200-500GB): 4-6 workers
        # Very large databases (> 500GB): 6-8 workers
        if database_size_gb < 50:
            worker_count = max(1, database_size_gb // 25)
        elif database_size_gb < 200:
            worker_count = 2 + (database_size_gb - 50) // 75
        elif database_size_gb < 500:
            worker_count = 4 + (database_size_gb - 200) // 150
        else:
            worker_count = min(8, 6 + (database_size_gb - 500) // 250)
        
        # Ensure worker count is within bounds
        worker_count = max(1, min(8, worker_count))
        
        # Adjust for priority - high priority gets more resources
        if migration_priority == 'high':
            worker_count = min(8, worker_count + 1)
        elif migration_priority == 'low':
            worker_count = max(1, worker_count - 1)
        
        logger.info(f"Calculated optimal worker count: {worker_count}")
        
        # Initialize Compute Engine client
        compute_client = compute_v1.RegionInstanceGroupManagersClient()
        
        # Find the migration workers instance group
        instance_group_name = None
        try:
            # List instance groups to find the migration workers group
            list_request = compute_v1.ListRegionInstanceGroupManagersRequest(
                project=project_id,
                region=region
            )
            
            for instance_group in compute_client.list(request=list_request):
                if "migration-workers" in instance_group.name:
                    instance_group_name = instance_group.name
                    break
                    
        except Exception as e:
            logger.warning(f"Could not list instance groups: {e}")
            instance_group_name = "migration-workers"  # Default fallback
        
        if not instance_group_name:
            logger.warning("No migration workers instance group found, using default name")
            instance_group_name = "migration-workers"
        
        # Scale migration workers based on calculated workload
        try:
            resize_request = compute_v1.ResizeRegionInstanceGroupManagerRequest(
                project=project_id,
                region=region,
                instance_group_manager=instance_group_name,
                size=worker_count
            )
            
            operation = compute_client.resize(request=resize_request)
            
            logger.info(f"Initiated scaling operation: {operation.name}")
            
        except Exception as e:
            logger.error(f"Failed to scale migration workers: {e}")
            # Continue with other operations even if scaling fails
        
        # Determine migration mode based on priority
        migration_mode = 'calendar' if migration_priority == 'high' else 'flex-start'
        
        # Calculate estimated completion time
        # Base time per GB + overhead for initialization and finalization
        base_time_per_gb = 2  # minutes per GB
        overhead_time = 30    # minutes for setup/teardown
        
        # Adjust for worker parallelization (diminishing returns)
        parallelization_factor = min(worker_count, 4) * 0.7
        estimated_time_minutes = (database_size_gb * base_time_per_gb / parallelization_factor) + overhead_time
        
        # Create monitoring metrics
        try:
            monitoring_client = monitoring_v3.MetricServiceClient()
            
            # Create custom metric for migration progress
            project_name = f"projects/{project_id}"
            
            # This would typically create custom metrics, but for demo purposes
            # we'll just log the metrics that would be created
            logger.info(f"Would create monitoring metrics for migration tracking")
            
        except Exception as e:
            logger.warning(f"Could not create monitoring metrics: {e}")
        
        # Prepare response
        response = {
            'status': 'success',
            'worker_count': worker_count,
            'migration_mode': migration_mode,
            'estimated_time_minutes': int(estimated_time_minutes),
            'priority': migration_priority,
            'database_size_gb': database_size_gb,
            'project_id': project_id,
            'region': region,
            'instance_group': instance_group_name,
            'recommendations': []
        }
        
        # Add cost optimization recommendations
        if migration_priority == 'low':
            response['recommendations'].append(
                "Using flex-start mode for cost optimization - migration may be delayed during peak hours"
            )
        
        if database_size_gb > 500:
            response['recommendations'].append(
                "Large database detected - consider implementing parallel table migration for better performance"
            )
        
        if worker_count >= 6:
            response['recommendations'].append(
                "High worker count allocated - monitor resource utilization to optimize costs"
            )
        
        logger.info(f"Migration orchestration completed successfully: {response}")
        
        return response
        
    except Exception as e:
        error_response = {
            'status': 'error',
            'error': str(e),
            'message': 'Failed to orchestrate migration workflow'
        }
        
        logger.error(f"Migration orchestration failed: {error_response}")
        
        return error_response, 500