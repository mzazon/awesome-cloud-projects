# Cloud Function for Infrastructure Cost Optimization
#
# This function analyzes resource utilization data, generates optimization recommendations,
# and implements automated cost reduction actions based on configurable policies and
# machine learning-driven insights for Google Cloud infrastructure.

import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple

import functions_framework
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import bigquery
from google.cloud import pubsub_v1
from google.cloud import storage
from google.api_core import exceptions
import google.auth

# Configure logging for Cloud Functions
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables with validation
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_NAME = os.environ.get('DATASET_NAME')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
CPU_THRESHOLD = float(os.environ.get('CPU_THRESHOLD', '0.1'))
MEMORY_THRESHOLD = float(os.environ.get('MEMORY_THRESHOLD', '0.2'))
PUBSUB_TOPIC_EVENTS = os.environ.get('PUBSUB_TOPIC_EVENTS')
PUBSUB_TOPIC_BATCH = os.environ.get('PUBSUB_TOPIC_BATCH')

# Validate required environment variables
required_env_vars = [PROJECT_ID, DATASET_NAME, BUCKET_NAME, PUBSUB_TOPIC_EVENTS]
if not all(required_env_vars):
    raise ValueError("Missing required environment variables")

# Initialize Google Cloud clients
credentials, project = google.auth.default()
compute_client = compute_v1.InstancesClient(credentials=credentials)
monitoring_client = monitoring_v3.MetricServiceClient(credentials=credentials)
bigquery_client = bigquery.Client(project=PROJECT_ID, credentials=credentials)
pubsub_publisher = pubsub_v1.PublisherClient(credentials=credentials)
storage_client = storage.Client(project=PROJECT_ID, credentials=credentials)

# Constants for optimization algorithms
MACHINE_TYPE_COST_MAP = {
    'e2-micro': 0.008,
    'e2-small': 0.016,
    'e2-medium': 0.032,
    'e2-standard-2': 0.064,
    'e2-standard-4': 0.128,
    'e2-standard-8': 0.256,
    'n1-standard-1': 0.048,
    'n1-standard-2': 0.096,
    'n1-standard-4': 0.192,
    'n2-standard-2': 0.078,
    'n2-standard-4': 0.156,
}

OPTIMIZATION_ACTIONS = {
    'RESIZE_DOWN': 'resize_to_smaller_machine_type',
    'STOP_IDLE': 'stop_idle_instance',
    'SCHEDULE_SHUTDOWN': 'schedule_automatic_shutdown',
    'MIGRATE_PREEMPTIBLE': 'migrate_to_preemptible',
    'ADD_LABELS': 'add_cost_tracking_labels',
    'NO_ACTION': 'no_optimization_needed'
}


@functions_framework.http
def optimize_infrastructure(request) -> Tuple[Dict[str, Any], int]:
    """
    HTTP Cloud Function entry point for infrastructure cost optimization.
    
    Processes cost optimization requests from various triggers including:
    - Cloud Scheduler (daily/weekly analysis)
    - Pub/Sub messages (event-driven optimization)
    - Manual HTTP requests (on-demand analysis)
    
    Args:
        request: HTTP request object containing trigger information
        
    Returns:
        Tuple of (response_dict, http_status_code)
    """
    try:
        # Parse request data
        request_data = _parse_request_data(request)
        analysis_type = request_data.get('analysis_type', 'full_scan')
        source = request_data.get('source', 'manual')
        
        logger.info(f"Starting cost optimization analysis: type={analysis_type}, source={source}")
        
        # Collect infrastructure data
        infrastructure_data = _collect_infrastructure_data()
        
        # Analyze resource utilization and generate recommendations
        recommendations = _analyze_and_recommend(infrastructure_data)
        
        # Log metrics to BigQuery for tracking and analytics
        _log_metrics_to_bigquery(infrastructure_data, recommendations)
        
        # Execute approved optimization actions
        executed_actions = _execute_optimization_actions(recommendations)
        
        # Publish results to Pub/Sub for downstream processing
        _publish_optimization_results(recommendations, executed_actions, source)
        
        # Generate response summary
        response = {
            'status': 'success',
            'analysis_type': analysis_type,
            'source': source,
            'timestamp': datetime.utcnow().isoformat(),
            'summary': {
                'resources_analyzed': len(infrastructure_data.get('instances', [])),
                'recommendations_generated': len(recommendations),
                'actions_executed': len(executed_actions),
                'estimated_monthly_savings': sum(r.get('estimated_savings', 0) for r in recommendations)
            },
            'recommendations': recommendations[:5],  # Include top 5 recommendations
            'executed_actions': executed_actions
        }
        
        logger.info(f"Cost optimization completed successfully: {response['summary']}")
        return response, 200
        
    except Exception as e:
        error_message = f"Cost optimization failed: {str(e)}"
        logger.error(error_message, exc_info=True)
        
        # Log error to BigQuery for troubleshooting
        _log_error_to_bigquery(error_message, request_data if 'request_data' in locals() else {})
        
        return {
            'status': 'error',
            'message': error_message,
            'timestamp': datetime.utcnow().isoformat()
        }, 500


def _parse_request_data(request) -> Dict[str, Any]:
    """Parse and validate HTTP request data."""
    try:
        if request.method == 'POST':
            request_json = request.get_json(silent=True)
            if request_json:
                return request_json
        
        # Default request data for GET requests or missing JSON
        return {
            'analysis_type': 'quick_scan',
            'source': 'manual_http',
            'timestamp': datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.warning(f"Failed to parse request data: {e}")
        return {'source': 'unknown', 'analysis_type': 'default'}


def _collect_infrastructure_data() -> Dict[str, Any]:
    """
    Collect comprehensive infrastructure data for cost analysis.
    
    Returns:
        Dictionary containing instances, clusters, and other resource data
    """
    logger.info("Collecting infrastructure data for cost analysis")
    
    infrastructure_data = {
        'instances': [],
        'clusters': [],
        'collection_timestamp': datetime.utcnow().isoformat()
    }
    
    try:
        # Collect Compute Engine instances across all zones
        instances = _get_compute_instances()
        infrastructure_data['instances'] = instances
        logger.info(f"Collected {len(instances)} compute instances")
        
        # Collect GKE clusters (if available)
        try:
            clusters = _get_gke_clusters()
            infrastructure_data['clusters'] = clusters
            logger.info(f"Collected {len(clusters)} GKE clusters")
        except Exception as e:
            logger.warning(f"Failed to collect GKE clusters: {e}")
            infrastructure_data['clusters'] = []
        
    except Exception as e:
        logger.error(f"Failed to collect infrastructure data: {e}")
        raise
    
    return infrastructure_data


def _get_compute_instances() -> List[Dict[str, Any]]:
    """Retrieve all Compute Engine instances with utilization metrics."""
    instances = []
    
    try:
        # List all zones in the project
        zones_client = compute_v1.ZonesClient(credentials=credentials)
        zones_request = compute_v1.ListZonesRequest(project=PROJECT_ID)
        zones = zones_client.list(request=zones_request)
        
        for zone in zones:
            zone_name = zone.name
            
            try:
                # List instances in this zone
                request = compute_v1.ListInstancesRequest(
                    project=PROJECT_ID,
                    zone=zone_name
                )
                zone_instances = compute_client.list(request=request)
                
                for instance in zone_instances:
                    instance_data = _analyze_instance(instance, zone_name)
                    if instance_data:
                        instances.append(instance_data)
                        
            except exceptions.Forbidden:
                logger.warning(f"No permission to access zone {zone_name}")
                continue
            except Exception as e:
                logger.warning(f"Failed to collect instances from zone {zone_name}: {e}")
                continue
    
    except Exception as e:
        logger.error(f"Failed to list zones: {e}")
        raise
    
    return instances


def _analyze_instance(instance: compute_v1.Instance, zone: str) -> Optional[Dict[str, Any]]:
    """
    Analyze individual compute instance for optimization opportunities.
    
    Args:
        instance: Compute Engine instance object
        zone: Zone where the instance is located
        
    Returns:
        Dictionary with instance analysis data or None if analysis fails
    """
    try:
        # Extract basic instance information
        instance_data = {
            'resource_id': instance.name,
            'resource_type': 'compute_instance',
            'project_id': PROJECT_ID,
            'zone': zone,
            'machine_type': instance.machine_type.split('/')[-1],
            'status': instance.status,
            'creation_timestamp': instance.creation_timestamp,
            'labels': dict(instance.labels) if instance.labels else {}
        }
        
        # Skip terminated or stopping instances
        if instance.status in ['TERMINATED', 'STOPPING']:
            return None
        
        # Get utilization metrics for running instances
        if instance.status == 'RUNNING':
            utilization_metrics = _get_instance_utilization(instance.name, zone)
            instance_data.update(utilization_metrics)
            
            # Calculate cost information
            cost_info = _calculate_instance_cost(instance_data['machine_type'])
            instance_data.update(cost_info)
        
        return instance_data
        
    except Exception as e:
        logger.warning(f"Failed to analyze instance {instance.name}: {e}")
        return None


def _get_instance_utilization(instance_name: str, zone: str) -> Dict[str, float]:
    """
    Retrieve CPU and memory utilization metrics for a specific instance.
    
    Args:
        instance_name: Name of the compute instance
        zone: Zone where the instance is located
        
    Returns:
        Dictionary with utilization metrics
    """
    utilization_data = {
        'cpu_utilization': 0.0,
        'memory_utilization': 0.0,
        'network_in_utilization': 0.0,
        'network_out_utilization': 0.0
    }
    
    try:
        # Define time range for metrics (last 24 hours)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=24)
        
        # Create time interval
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": int(end_time.timestamp())},
            "start_time": {"seconds": int(start_time.timestamp())}
        })
        
        # Query CPU utilization
        cpu_filter = (
            f'resource.type="gce_instance" AND '
            f'resource.labels.instance_name="{instance_name}" AND '
            f'resource.labels.zone="{zone}" AND '
            f'metric.type="compute.googleapis.com/instance/cpu/utilization"'
        )
        
        cpu_request = monitoring_v3.ListTimeSeriesRequest(
            name=f"projects/{PROJECT_ID}",
            filter=cpu_filter,
            interval=interval,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        )
        
        cpu_results = monitoring_client.list_time_series(request=cpu_request)
        cpu_values = []
        
        for result in cpu_results:
            for point in result.points:
                cpu_values.append(point.value.double_value)
        
        if cpu_values:
            utilization_data['cpu_utilization'] = sum(cpu_values) / len(cpu_values)
        
        # Query memory utilization (if available)
        memory_filter = (
            f'resource.type="gce_instance" AND '
            f'resource.labels.instance_name="{instance_name}" AND '
            f'resource.labels.zone="{zone}" AND '
            f'metric.type="compute.googleapis.com/instance/memory/utilization"'
        )
        
        memory_request = monitoring_v3.ListTimeSeriesRequest(
            name=f"projects/{PROJECT_ID}",
            filter=memory_filter,
            interval=interval,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        )
        
        try:
            memory_results = monitoring_client.list_time_series(request=memory_request)
            memory_values = []
            
            for result in memory_results:
                for point in result.points:
                    memory_values.append(point.value.double_value)
            
            if memory_values:
                utilization_data['memory_utilization'] = sum(memory_values) / len(memory_values)
        except Exception:
            # Memory metrics might not be available for all instances
            logger.debug(f"Memory metrics not available for instance {instance_name}")
        
    except Exception as e:
        logger.warning(f"Failed to get utilization metrics for {instance_name}: {e}")
    
    return utilization_data


def _calculate_instance_cost(machine_type: str) -> Dict[str, float]:
    """Calculate hourly and monthly cost estimates for an instance."""
    hourly_cost = MACHINE_TYPE_COST_MAP.get(machine_type, 0.1)  # Default cost if not found
    monthly_cost = hourly_cost * 24 * 30  # Approximate monthly cost
    
    return {
        'cost_per_hour': hourly_cost,
        'cost_per_month': monthly_cost
    }


def _get_gke_clusters() -> List[Dict[str, Any]]:
    """Retrieve GKE cluster information (simplified implementation)."""
    # This is a placeholder implementation
    # In a real scenario, you would use the container_v1 client
    return []


def _analyze_and_recommend(infrastructure_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Analyze infrastructure data and generate optimization recommendations.
    
    Args:
        infrastructure_data: Collected infrastructure metrics and details
        
    Returns:
        List of optimization recommendations with priority and estimated savings
    """
    recommendations = []
    
    for instance in infrastructure_data.get('instances', []):
        try:
            recommendation = _generate_instance_recommendation(instance)
            if recommendation and recommendation['action'] != OPTIMIZATION_ACTIONS['NO_ACTION']:
                recommendations.append(recommendation)
        except Exception as e:
            logger.warning(f"Failed to generate recommendation for {instance.get('resource_id')}: {e}")
    
    # Sort recommendations by estimated savings (highest first)
    recommendations.sort(key=lambda x: x.get('estimated_savings', 0), reverse=True)
    
    logger.info(f"Generated {len(recommendations)} optimization recommendations")
    return recommendations


def _generate_instance_recommendation(instance: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Generate optimization recommendation for a single instance."""
    cpu_util = instance.get('cpu_utilization', 0)
    memory_util = instance.get('memory_utilization', 0)
    machine_type = instance.get('machine_type', '')
    monthly_cost = instance.get('cost_per_month', 0)
    
    recommendation = {
        'resource_id': instance['resource_id'],
        'resource_type': instance['resource_type'],
        'current_state': {
            'machine_type': machine_type,
            'cpu_utilization': cpu_util,
            'memory_utilization': memory_util,
            'monthly_cost': monthly_cost
        },
        'timestamp': datetime.utcnow().isoformat(),
        'priority': 'medium',
        'estimated_savings': 0.0,
        'confidence': 0.8
    }
    
    # Determine optimization action based on utilization patterns
    if cpu_util < CPU_THRESHOLD and memory_util < MEMORY_THRESHOLD:
        if cpu_util < 0.05:  # Very low utilization
            recommendation.update({
                'action': OPTIMIZATION_ACTIONS['STOP_IDLE'],
                'recommendation': f'Stop idle instance with CPU: {cpu_util:.1%}, Memory: {memory_util:.1%}',
                'estimated_savings': monthly_cost * 0.9,  # 90% savings from stopping
                'priority': 'high',
                'confidence': 0.9
            })
        else:
            # Recommend downsizing
            new_machine_type = _suggest_smaller_machine_type(machine_type)
            if new_machine_type:
                new_cost = MACHINE_TYPE_COST_MAP.get(new_machine_type, monthly_cost) * 24 * 30
                savings = monthly_cost - new_cost
                
                recommendation.update({
                    'action': OPTIMIZATION_ACTIONS['RESIZE_DOWN'],
                    'recommendation': f'Resize from {machine_type} to {new_machine_type}',
                    'proposed_state': {'machine_type': new_machine_type, 'monthly_cost': new_cost},
                    'estimated_savings': savings,
                    'priority': 'high' if savings > 50 else 'medium'
                })
    
    elif 'preemptible' not in instance.get('labels', {}):
        # Suggest preemptible instance for non-critical workloads
        savings = monthly_cost * 0.7  # Approximate 70% savings
        recommendation.update({
            'action': OPTIMIZATION_ACTIONS['MIGRATE_PREEMPTIBLE'],
            'recommendation': 'Consider migrating to preemptible instance for cost savings',
            'estimated_savings': savings,
            'priority': 'low',
            'confidence': 0.6
        })
    
    else:
        # No optimization needed
        recommendation.update({
            'action': OPTIMIZATION_ACTIONS['NO_ACTION'],
            'recommendation': 'Instance is optimally sized',
            'priority': 'low'
        })
    
    return recommendation


def _suggest_smaller_machine_type(current_type: str) -> Optional[str]:
    """Suggest a smaller machine type for downsizing."""
    # Simple mapping to smaller machine types
    downsize_map = {
        'e2-standard-8': 'e2-standard-4',
        'e2-standard-4': 'e2-standard-2',
        'e2-standard-2': 'e2-medium',
        'e2-medium': 'e2-small',
        'n1-standard-4': 'n1-standard-2',
        'n1-standard-2': 'n1-standard-1',
        'n2-standard-4': 'n2-standard-2'
    }
    
    return downsize_map.get(current_type)


def _log_metrics_to_bigquery(infrastructure_data: Dict[str, Any], recommendations: List[Dict[str, Any]]) -> None:
    """Log infrastructure metrics and recommendations to BigQuery."""
    try:
        # Prepare utilization data for BigQuery
        utilization_rows = []
        for instance in infrastructure_data.get('instances', []):
            row = {
                'timestamp': datetime.utcnow(),
                'resource_id': instance['resource_id'],
                'resource_type': instance['resource_type'],
                'project_id': instance['project_id'],
                'zone': instance.get('zone'),
                'cpu_utilization': instance.get('cpu_utilization'),
                'memory_utilization': instance.get('memory_utilization'),
                'cost_per_hour': instance.get('cost_per_hour'),
                'recommendation': next(
                    (r['recommendation'] for r in recommendations if r['resource_id'] == instance['resource_id']),
                    'No recommendation'
                ),
                'machine_type': instance.get('machine_type'),
                'labels': json.dumps(instance.get('labels', {}))
            }
            utilization_rows.append(row)
        
        # Insert utilization data
        if utilization_rows:
            table_ref = bigquery_client.dataset(DATASET_NAME).table('resource_utilization')
            errors = bigquery_client.insert_rows_json(table_ref, utilization_rows)
            
            if errors:
                logger.error(f"Failed to insert utilization data: {errors}")
            else:
                logger.info(f"Inserted {len(utilization_rows)} utilization records to BigQuery")
        
        # Prepare optimization actions for BigQuery
        action_rows = []
        for rec in recommendations:
            if rec.get('action') != OPTIMIZATION_ACTIONS['NO_ACTION']:
                row = {
                    'timestamp': datetime.utcnow(),
                    'resource_id': rec['resource_id'],
                    'action_type': rec['action'],
                    'previous_state': json.dumps(rec.get('current_state', {})),
                    'new_state': json.dumps(rec.get('proposed_state', {})),
                    'estimated_savings': rec.get('estimated_savings', 0),
                    'status': 'pending',
                    'initiated_by': 'cost_optimizer_function'
                }
                action_rows.append(row)
        
        # Insert optimization actions
        if action_rows:
            table_ref = bigquery_client.dataset(DATASET_NAME).table('optimization_actions')
            errors = bigquery_client.insert_rows_json(table_ref, action_rows)
            
            if errors:
                logger.error(f"Failed to insert optimization actions: {errors}")
            else:
                logger.info(f"Inserted {len(action_rows)} optimization actions to BigQuery")
    
    except Exception as e:
        logger.error(f"Failed to log metrics to BigQuery: {e}")


def _execute_optimization_actions(recommendations: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Execute approved optimization actions.
    
    For safety, this implementation only executes labeling actions.
    More aggressive actions would require additional approval workflows.
    """
    executed_actions = []
    
    for rec in recommendations:
        try:
            action = rec.get('action')
            resource_id = rec.get('resource_id')
            
            if action == OPTIMIZATION_ACTIONS['ADD_LABELS']:
                # Safe action: Add cost optimization labels
                success = _add_cost_labels(resource_id, rec)
                if success:
                    executed_actions.append({
                        'resource_id': resource_id,
                        'action': action,
                        'status': 'completed',
                        'timestamp': datetime.utcnow().isoformat()
                    })
            
            # For demo purposes, we'll log other actions but not execute them
            elif action in [OPTIMIZATION_ACTIONS['RESIZE_DOWN'], OPTIMIZATION_ACTIONS['STOP_IDLE']]:
                logger.info(f"Action {action} logged for {resource_id} but not executed (safety measure)")
                executed_actions.append({
                    'resource_id': resource_id,
                    'action': action,
                    'status': 'logged_only',
                    'timestamp': datetime.utcnow().isoformat(),
                    'note': 'Action logged but not executed for safety'
                })
        
        except Exception as e:
            logger.warning(f"Failed to execute action for {rec.get('resource_id')}: {e}")
    
    logger.info(f"Executed {len(executed_actions)} optimization actions")
    return executed_actions


def _add_cost_labels(resource_id: str, recommendation: Dict[str, Any]) -> bool:
    """Add cost optimization labels to a resource."""
    try:
        # This is a placeholder implementation
        # In practice, you would use the appropriate client to add labels
        logger.info(f"Adding cost optimization labels to {resource_id}")
        return True
    except Exception as e:
        logger.error(f"Failed to add labels to {resource_id}: {e}")
        return False


def _publish_optimization_results(
    recommendations: List[Dict[str, Any]], 
    executed_actions: List[Dict[str, Any]], 
    source: str
) -> None:
    """Publish optimization results to Pub/Sub for downstream processing."""
    try:
        message_data = {
            'source': source,
            'timestamp': datetime.utcnow().isoformat(),
            'summary': {
                'recommendations_count': len(recommendations),
                'actions_executed_count': len(executed_actions),
                'total_estimated_savings': sum(r.get('estimated_savings', 0) for r in recommendations)
            },
            'high_priority_recommendations': [
                r for r in recommendations if r.get('priority') == 'high'
            ][:3]  # Top 3 high-priority recommendations
        }
        
        # Publish to cost optimization events topic
        topic_path = pubsub_publisher.topic_path(PROJECT_ID, PUBSUB_TOPIC_EVENTS.split('/')[-1])
        message_json = json.dumps(message_data)
        message_bytes = message_json.encode('utf-8')
        
        future = pubsub_publisher.publish(topic_path, message_bytes)
        message_id = future.result()
        
        logger.info(f"Published optimization results to Pub/Sub: message_id={message_id}")
    
    except Exception as e:
        logger.error(f"Failed to publish optimization results: {e}")


def _log_error_to_bigquery(error_message: str, request_data: Dict[str, Any]) -> None:
    """Log errors to BigQuery for troubleshooting and monitoring."""
    try:
        error_row = {
            'timestamp': datetime.utcnow(),
            'resource_id': 'cost_optimizer_function',
            'action_type': 'error_log',
            'previous_state': json.dumps(request_data),
            'new_state': json.dumps({'error': error_message}),
            'estimated_savings': 0.0,
            'status': 'failed',
            'initiated_by': 'cost_optimizer_function',
            'failure_reason': error_message
        }
        
        table_ref = bigquery_client.dataset(DATASET_NAME).table('optimization_actions')
        errors = bigquery_client.insert_rows_json(table_ref, [error_row])
        
        if not errors:
            logger.info("Error logged to BigQuery successfully")
    
    except Exception as e:
        logger.error(f"Failed to log error to BigQuery: {e}")