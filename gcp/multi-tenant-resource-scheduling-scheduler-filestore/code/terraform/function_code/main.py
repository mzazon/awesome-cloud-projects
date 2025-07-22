import json
import logging
import os
from datetime import datetime, timedelta
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging
import subprocess
import tempfile

def schedule_tenant_resources(request):
    """
    Main function to handle tenant resource scheduling requests
    """
    # Set up logging
    client = cloud_logging.Client()
    client.setup_logging()
    
    try:
        # Parse request data
        request_json = request.get_json()
        tenant_id = request_json.get('tenant_id')
        resource_type = request_json.get('resource_type', 'compute')
        requested_capacity = int(request_json.get('capacity', 1))
        duration_hours = int(request_json.get('duration', 2))
        
        logging.info(f"Processing request for tenant {tenant_id}")
        
        # Get tenant quota and current usage
        tenant_quota = get_tenant_quota(tenant_id)
        current_usage = get_current_usage(tenant_id)
        
        # Check if request can be fulfilled
        if current_usage + requested_capacity > tenant_quota:
            return {
                'status': 'denied',
                'reason': 'Quota exceeded',
                'current_usage': current_usage,
                'quota': tenant_quota
            }, 403
        
        # Schedule resource allocation
        allocation_result = allocate_resources(
            tenant_id, resource_type, requested_capacity, duration_hours
        )
        
        # Update tenant storage with allocation info
        update_tenant_storage(tenant_id, allocation_result)
        
        # Send metrics to Cloud Monitoring
        send_allocation_metrics(tenant_id, requested_capacity, 'success')
        
        return {
            'status': 'scheduled',
            'tenant_id': tenant_id,
            'allocation_id': allocation_result['allocation_id'],
            'scheduled_time': allocation_result['start_time'],
            'duration_hours': duration_hours,
            'capacity': requested_capacity
        }
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        send_allocation_metrics(tenant_id if 'tenant_id' in locals() else 'unknown', 
                              requested_capacity if 'requested_capacity' in locals() else 0, 
                              'error')
        return {'status': 'error', 'message': str(e)}, 500

def get_tenant_quota(tenant_id):
    """Get tenant resource quota from configuration"""
    # Load tenant quotas from environment variable (set by Terraform)
    try:
        tenant_quotas = json.loads(os.environ.get('TENANT_QUOTAS', '{}'))
    except:
        tenant_quotas = {
            'tenant_a': 10,
            'tenant_b': 15,
            'tenant_c': 8,
            'default': 5
        }
    
    return tenant_quotas.get(tenant_id, tenant_quotas.get('default', 5))

def get_current_usage(tenant_id):
    """Get current resource usage for tenant"""
    # In production, this would query actual resource usage
    # For demo, return simulated usage
    import random
    return random.randint(0, 3)

def allocate_resources(tenant_id, resource_type, capacity, duration):
    """Simulate resource allocation logic"""
    from uuid import uuid4
    
    allocation_id = str(uuid4())[:8]
    start_time = datetime.now().isoformat()
    
    # Create tenant directory structure in Filestore
    filestore_ip = os.environ.get('FILESTORE_IP', '${filestore_ip}')
    mount_point = f"/mnt/tenant_storage"
    tenant_dir = f"{mount_point}/tenants/{tenant_id}/allocations/{allocation_id}"
    
    # In production, this would mount Filestore and create directories
    # For demo, we simulate the allocation
    
    return {
        'allocation_id': allocation_id,
        'start_time': start_time,
        'tenant_id': tenant_id,
        'resource_type': resource_type,
        'capacity': capacity,
        'duration_hours': duration,
        'storage_path': tenant_dir
    }

def update_tenant_storage(tenant_id, allocation_info):
    """Update tenant storage with allocation information"""
    # In production, this would write to mounted Filestore
    logging.info(f"Updated storage for tenant {tenant_id}: {allocation_info}")
    
def send_allocation_metrics(tenant_id, capacity, status):
    """Send metrics to Cloud Monitoring"""
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{os.environ.get('GCP_PROJECT', '${project_id}')}"
        
        # Create a time series for the allocation metric
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/tenant/resource_allocations"
        series.metric.labels["tenant_id"] = tenant_id
        series.metric.labels["status"] = status
        
        series.resource.type = "global"
        series.resource.labels["project_id"] = os.environ.get('GCP_PROJECT', '${project_id}')
        
        now = datetime.now()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": seconds, "nanos": nanos}
        })
        
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"double_value": capacity}
        })
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        logging.info(f"Sent metrics for tenant {tenant_id}")
        
    except Exception as e:
        logging.error(f"Failed to send metrics: {str(e)}")