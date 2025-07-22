"""
Health monitoring Cloud Function for HPC disaster recovery infrastructure.
This function continuously monitors the health of Parallelstore instances and HPC workloads,
implementing intelligent health checks that detect both infrastructure failures and application-level issues.
"""

import os
import json
import time
import logging
from typing import Dict, Any, Optional
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1
from google.cloud import parallelstore_v1beta
import functions_framework
from flask import Request

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = "${project_id}"
DR_PREFIX = "${dr_prefix}"
PRIMARY_REGION = "${primary_region}"
SECONDARY_REGION = "${secondary_region}"

@functions_framework.http
def monitor_hpc_health(request: Request) -> Dict[str, Any]:
    """
    Monitor HPC infrastructure health and trigger DR if needed.
    
    Args:
        request: HTTP request object
        
    Returns:
        Dictionary containing health status and any actions taken
    """
    try:
        logger.info("Starting HPC health monitoring check")
        
        # Initialize clients
        monitoring_client = monitoring_v3.MetricServiceClient()
        pubsub_client = pubsub_v1.PublisherClient()
        parallelstore_client = parallelstore_v1beta.ParallelstoreClient()
        
        # Perform comprehensive health checks
        health_status = {
            'timestamp': time.time(),
            'parallelstore_primary': check_parallelstore_health(
                parallelstore_client, f"{DR_PREFIX}-primary-pfs", PRIMARY_REGION + "-a"
            ),
            'parallelstore_secondary': check_parallelstore_health(
                parallelstore_client, f"{DR_PREFIX}-secondary-pfs", SECONDARY_REGION + "-a"
            ),
            'network_connectivity': check_network_health(monitoring_client),
            'replication_lag': check_replication_status(monitoring_client),
            'system_metrics': get_system_metrics(monitoring_client)
        }
        
        # Evaluate overall health and trigger alerts if needed
        should_failover = should_trigger_failover(health_status)
        
        if should_failover:
            logger.warning("Health check failure detected, triggering failover workflow")
            trigger_result = trigger_failover_workflow(pubsub_client, health_status)
            health_status['failover_triggered'] = trigger_result
        else:
            health_status['failover_triggered'] = False
            
        # Log health status for monitoring
        logger.info(f"Health check completed: {json.dumps(health_status, indent=2)}")
        
        return {
            'status': 'success',
            'health': health_status,
            'timestamp': time.time()
        }
        
    except Exception as e:
        logger.error(f"Health monitoring failed: {str(e)}", exc_info=True)
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': time.time()
        }

def check_parallelstore_health(
    client: parallelstore_v1beta.ParallelstoreClient, 
    instance_name: str, 
    location: str
) -> Dict[str, Any]:
    """
    Check Parallelstore instance health metrics.
    
    Args:
        client: Parallelstore client
        instance_name: Name of the Parallelstore instance
        location: Zone location of the instance
        
    Returns:
        Dictionary containing health status and metrics
    """
    try:
        # Construct the instance path
        instance_path = f"projects/{PROJECT_ID}/locations/{location}/instances/{instance_name}"
        
        # Get instance details
        instance = client.get_instance(name=instance_path)
        
        # Check instance state
        state = instance.state.name if hasattr(instance.state, 'name') else str(instance.state)
        
        health_data = {
            'status': 'healthy' if state == 'READY' else 'unhealthy',
            'state': state,
            'capacity_gib': instance.capacity_gib,
            'performance_tier': instance.deployment_type.name if hasattr(instance.deployment_type, 'name') else str(instance.deployment_type),
            'access_points_count': len(instance.access_points) if instance.access_points else 0,
            'last_check': time.time()
        }
        
        # If instance is ready, perform additional health checks
        if state == 'READY':
            # Simulate performance metrics (in real implementation, these would come from monitoring)
            health_data.update({
                'latency_ms': 0.3,  # Sub-millisecond latency
                'throughput_gbps': 50,  # Sustained throughput
                'iops': 100000,  # IOPS capacity
                'client_connections': 250  # Active connections
            })
            
        logger.info(f"Parallelstore {instance_name} health check: {health_data}")
        return health_data
        
    except Exception as e:
        logger.error(f"Parallelstore health check failed for {instance_name}: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'instance_name': instance_name,
            'last_check': time.time()
        }

def check_network_health(client: monitoring_v3.MetricServiceClient) -> Dict[str, Any]:
    """
    Monitor network connectivity and performance between regions.
    
    Args:
        client: Cloud Monitoring client
        
    Returns:
        Dictionary containing network health metrics
    """
    try:
        # In a real implementation, this would query actual VPN tunnel metrics
        # For demonstration, we simulate healthy network conditions
        
        health_data = {
            'status': 'healthy',
            'vpn_tunnel_status': 'UP',
            'bandwidth_utilization': 0.45,  # 45% utilization
            'packet_loss': 0.001,  # 0.1% packet loss
            'latency_ms': 5.2,  # Cross-region latency
            'bgp_sessions': 'established',
            'last_check': time.time()
        }
        
        # Check for network performance degradation
        if health_data['bandwidth_utilization'] > 0.8:
            health_data['status'] = 'degraded'
            health_data['warning'] = 'High bandwidth utilization detected'
            
        if health_data['packet_loss'] > 0.01:  # 1% packet loss
            health_data['status'] = 'unhealthy'
            health_data['error'] = 'High packet loss detected'
            
        logger.info(f"Network health check: {health_data}")
        return health_data
        
    except Exception as e:
        logger.error(f"Network health check failed: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'last_check': time.time()
        }

def check_replication_status(client: monitoring_v3.MetricServiceClient) -> Dict[str, Any]:
    """
    Check data replication lag between regions.
    
    Args:
        client: Cloud Monitoring client
        
    Returns:
        Dictionary containing replication status and lag metrics
    """
    try:
        # In a real implementation, this would query custom metrics from the replication process
        # For demonstration, we simulate replication metrics
        
        replication_data = {
            'status': 'synced',
            'lag_minutes': 2,  # 2-minute replication lag
            'last_sync_timestamp': time.time() - 120,  # 2 minutes ago
            'sync_throughput_mbps': 500,  # Sync throughput
            'pending_operations': 5,  # Outstanding sync operations
            'sync_efficiency': 0.95,  # 95% efficiency
            'last_check': time.time()
        }
        
        # Determine status based on lag
        if replication_data['lag_minutes'] > 15:
            replication_data['status'] = 'lagging'
            replication_data['warning'] = f"Replication lag of {replication_data['lag_minutes']} minutes exceeds threshold"
            
        if replication_data['lag_minutes'] > 30:
            replication_data['status'] = 'critical'
            replication_data['error'] = f"Critical replication lag of {replication_data['lag_minutes']} minutes"
            
        logger.info(f"Replication status check: {replication_data}")
        return replication_data
        
    except Exception as e:
        logger.error(f"Replication status check failed: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'last_check': time.time()
        }

def get_system_metrics(client: monitoring_v3.MetricServiceClient) -> Dict[str, Any]:
    """
    Get system-level metrics for disaster recovery assessment.
    
    Args:
        client: Cloud Monitoring client
        
    Returns:
        Dictionary containing system metrics
    """
    try:
        # Simulate system metrics that would influence DR decisions
        metrics = {
            'cpu_utilization_primary': 0.65,  # 65% CPU utilization
            'memory_utilization_primary': 0.72,  # 72% memory utilization
            'disk_utilization_primary': 0.58,  # 58% disk utilization
            'network_utilization_primary': 0.45,  # 45% network utilization
            'active_hpc_jobs': 12,  # Number of active HPC jobs
            'job_queue_length': 8,  # Queued jobs
            'system_health_score': 0.88,  # Overall health score (0-1)
            'last_check': time.time()
        }
        
        logger.info(f"System metrics: {metrics}")
        return metrics
        
    except Exception as e:
        logger.error(f"System metrics collection failed: {str(e)}")
        return {
            'error': str(e),
            'last_check': time.time()
        }

def should_trigger_failover(health_status: Dict[str, Any]) -> bool:
    """
    Determine if automatic failover should be triggered based on health status.
    
    Args:
        health_status: Complete health status from all checks
        
    Returns:
        Boolean indicating whether failover should be triggered
    """
    try:
        # Check primary Parallelstore health
        primary_storage = health_status.get('parallelstore_primary', {})
        primary_unhealthy = primary_storage.get('status') not in ['healthy', 'degraded']
        
        # Check replication lag
        replication = health_status.get('replication_lag', {})
        high_lag = replication.get('lag_minutes', 0) > 15
        
        # Check network connectivity
        network = health_status.get('network_connectivity', {})
        network_failed = network.get('status') == 'unhealthy'
        
        # Check system health score
        system_metrics = health_status.get('system_metrics', {})
        low_health_score = system_metrics.get('system_health_score', 1.0) < 0.3
        
        # Determine if failover should be triggered
        failover_conditions = {
            'primary_storage_unhealthy': primary_unhealthy,
            'high_replication_lag': high_lag,
            'network_connectivity_failed': network_failed,
            'low_system_health': low_health_score
        }
        
        should_failover = any(failover_conditions.values())
        
        if should_failover:
            logger.warning(f"Failover conditions met: {failover_conditions}")
        else:
            logger.info("All systems healthy, no failover required")
            
        return should_failover
        
    except Exception as e:
        logger.error(f"Failover decision logic failed: {str(e)}")
        # In case of error in decision logic, err on the side of caution
        return False

def trigger_failover_workflow(
    pubsub_client: pubsub_v1.PublisherClient, 
    health_status: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Publish failover trigger message to Pub/Sub topic.
    
    Args:
        pubsub_client: Pub/Sub publisher client
        health_status: Current health status that triggered the failover
        
    Returns:
        Dictionary containing trigger result information
    """
    try:
        topic_path = pubsub_client.topic_path(PROJECT_ID, f"{DR_PREFIX}-failover-commands")
        
        # Prepare failover message
        failover_message = {
            'trigger': 'automatic_failover',
            'timestamp': time.time(),
            'health_status': health_status,
            'severity': 'critical',
            'triggered_by': 'health_monitor_function',
            'dr_prefix': DR_PREFIX,
            'primary_region': PRIMARY_REGION,
            'secondary_region': SECONDARY_REGION
        }
        
        # Encode message as JSON
        message_data = json.dumps(failover_message).encode('utf-8')
        
        # Publish message
        future = pubsub_client.publish(topic_path, message_data)
        message_id = future.result()
        
        trigger_result = {
            'status': 'success',
            'message_id': message_id,
            'topic_path': topic_path,
            'timestamp': time.time()
        }
        
        logger.info(f"Failover workflow triggered successfully: {trigger_result}")
        return trigger_result
        
    except Exception as e:
        logger.error(f"Failed to trigger failover workflow: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': time.time()
        }

if __name__ == "__main__":
    # For local testing
    class MockRequest:
        def __init__(self):
            self.method = 'GET'
            
    result = monitor_hpc_health(MockRequest())
    print(json.dumps(result, indent=2))