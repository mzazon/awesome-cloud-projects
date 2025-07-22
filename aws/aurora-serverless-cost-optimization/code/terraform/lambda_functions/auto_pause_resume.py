"""
Auto-Pause/Resume Aurora Serverless v2 Function

This Lambda function implements intelligent auto-pause and resume functionality
for Aurora Serverless v2 based on environment type, time schedules, and activity patterns.
"""

import json
import boto3
import logging
from datetime import datetime, time, timedelta
import os
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for auto-pause/resume functionality.
    
    Args:
        event: EventBridge trigger event
        context: Lambda context object
        
    Returns:
        Response object with pause/resume results
    """
    cluster_id = os.environ.get('CLUSTER_ID', '${cluster_id}')
    environment = os.environ.get('ENVIRONMENT', '${environment}')
    region = os.environ.get('REGION', 'us-east-1')
    
    try:
        logger.info(f"Starting auto-pause/resume analysis for cluster: {cluster_id}, environment: {environment}")
        
        # Get current time and determine action
        current_time = datetime.utcnow().time()
        current_day = datetime.utcnow().strftime('%A').lower()
        
        # Determine what action should be taken
        action = determine_action(current_time, current_day, environment)
        logger.info(f"Determined action: {action} for time {current_time} on {current_day}")
        
        # Get current cluster state
        cluster_state = get_cluster_state(cluster_id)
        
        # Execute the determined action
        if action == 'pause':
            result = pause_cluster_if_idle(cluster_id, cluster_state)
        elif action == 'resume':
            result = resume_cluster_if_needed(cluster_id, cluster_state)
        elif action == 'monitor':
            result = monitor_cluster_only(cluster_id, cluster_state)
        else:
            result = {'action': 'no_action', 'reason': 'Outside defined operating schedule'}
        
        # Record action in CloudWatch metrics
        record_pause_resume_metrics(cluster_id, action, result, environment)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'environment': environment,
                'region': region,
                'determined_action': action,
                'executed_result': result,
                'current_time': current_time.isoformat(),
                'current_day': current_day,
                'cluster_state': cluster_state,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in auto-pause/resume: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'cluster': cluster_id,
                'environment': environment,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def determine_action(current_time: time, current_day: str, environment: str) -> str:
    """
    Determine what action should be taken based on environment and schedule.
    
    Args:
        current_time: Current UTC time
        current_day: Current day of week (lowercase)
        environment: Environment type (development, staging, production)
        
    Returns:
        Action to take: 'pause', 'resume', 'monitor', or 'no_action'
    """
    # Production environments always run (monitor only)
    if environment == 'production':
        return 'monitor'
    
    # Define operating hours based on environment
    if environment == 'development':
        # Development: operate 8 AM - 8 PM UTC on weekdays
        start_hour = time(8, 0)
        end_hour = time(20, 0)
        operating_days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
    elif environment == 'staging':
        # Staging: operate 6 AM - 10 PM UTC on weekdays, reduced hours on weekends
        if current_day in ['saturday', 'sunday']:
            start_hour = time(10, 0)
            end_hour = time(18, 0)
        else:
            start_hour = time(6, 0)
            end_hour = time(22, 0)
        operating_days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
    else:
        # Unknown environment - default to monitoring only
        logger.warning(f"Unknown environment: {environment}, defaulting to monitor")
        return 'monitor'
    
    # Check if today is an operating day
    if current_day not in operating_days:
        return 'pause'
    
    # Check if current time is within operating hours
    if start_hour <= current_time <= end_hour:
        return 'resume'
    else:
        return 'pause'

def get_cluster_state(cluster_id: str) -> Dict[str, Any]:
    """
    Get current Aurora cluster state and configuration.
    
    Args:
        cluster_id: Aurora cluster identifier
        
    Returns:
        Dictionary with cluster state information
    """
    try:
        cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = cluster_response['DBClusters'][0]
        
        scaling_config = cluster.get('ServerlessV2ScalingConfiguration', {})
        
        return {
            'status': cluster['Status'],
            'engine': cluster['Engine'],
            'min_capacity': scaling_config.get('MinCapacity', 0.5),
            'max_capacity': scaling_config.get('MaxCapacity', 1),
            'endpoint': cluster.get('Endpoint'),
            'available_for_writes': cluster['Status'] == 'available'
        }
        
    except Exception as e:
        logger.error(f"Error getting cluster state: {str(e)}")
        return {
            'status': 'unknown',
            'error': str(e),
            'available_for_writes': False
        }

def pause_cluster_if_idle(cluster_id: str, cluster_state: Dict[str, Any]) -> Dict[str, Any]:
    """
    Pause cluster by scaling down to minimum if it's idle.
    
    Args:
        cluster_id: Aurora cluster identifier
        cluster_state: Current cluster state
        
    Returns:
        Dictionary with pause operation results
    """
    try:
        # Check if cluster is already in paused state (minimal capacity)
        current_min = cluster_state.get('min_capacity', 0.5)
        current_max = cluster_state.get('max_capacity', 1)
        
        if current_min <= 0.5 and current_max <= 1:
            return {
                'action': 'already_paused',
                'reason': 'Cluster already in minimal capacity state',
                'current_config': {'min': current_min, 'max': current_max}
            }
        
        # Check if cluster is idle before pausing
        if is_cluster_idle(cluster_id):
            # Scale down to minimum capacity (effectively pausing)
            rds.modify_db_cluster(
                DBClusterIdentifier=cluster_id,
                ServerlessV2ScalingConfiguration={
                    'MinCapacity': 0.5,
                    'MaxCapacity': 1
                },
                ApplyImmediately=True
            )
            
            logger.info(f"Successfully paused cluster {cluster_id}")
            return {
                'action': 'paused',
                'reason': 'Low activity detected during off-hours',
                'previous_config': {'min': current_min, 'max': current_max},
                'new_config': {'min': 0.5, 'max': 1}
            }
        else:
            return {
                'action': 'not_paused',
                'reason': 'Active connections or recent activity detected',
                'current_config': {'min': current_min, 'max': current_max}
            }
            
    except Exception as e:
        logger.error(f"Error pausing cluster: {str(e)}")
        return {
            'action': 'pause_failed',
            'reason': f'Error during pause operation: {str(e)}',
            'error': str(e)
        }

def resume_cluster_if_needed(cluster_id: str, cluster_state: Dict[str, Any]) -> Dict[str, Any]:
    """
    Resume cluster by scaling up to normal operating capacity if needed.
    
    Args:
        cluster_id: Aurora cluster identifier
        cluster_state: Current cluster state
        
    Returns:
        Dictionary with resume operation results
    """
    try:
        current_min = cluster_state.get('min_capacity', 0.5)
        current_max = cluster_state.get('max_capacity', 1)
        
        # Determine appropriate resume capacity based on environment
        environment = os.environ.get('ENVIRONMENT', 'development')
        
        if environment == 'development':
            target_min, target_max = 0.5, 8
        elif environment == 'staging':
            target_min, target_max = 0.5, 16
        else:
            target_min, target_max = 1, 32
        
        # Check if cluster is in paused state and needs resuming
        if current_min <= 0.5 and current_max <= 1:
            rds.modify_db_cluster(
                DBClusterIdentifier=cluster_id,
                ServerlessV2ScalingConfiguration={
                    'MinCapacity': target_min,
                    'MaxCapacity': target_max
                },
                ApplyImmediately=True
            )
            
            logger.info(f"Successfully resumed cluster {cluster_id}")
            return {
                'action': 'resumed',
                'reason': 'Operating hours started - scaling to normal capacity',
                'previous_config': {'min': current_min, 'max': current_max},
                'new_config': {'min': target_min, 'max': target_max}
            }
        else:
            return {
                'action': 'already_active',
                'reason': 'Cluster already in active state',
                'current_config': {'min': current_min, 'max': current_max}
            }
            
    except Exception as e:
        logger.error(f"Error resuming cluster: {str(e)}")
        return {
            'action': 'resume_failed',
            'reason': f'Error during resume operation: {str(e)}',
            'error': str(e)
        }

def monitor_cluster_only(cluster_id: str, cluster_state: Dict[str, Any]) -> Dict[str, Any]:
    """
    Monitor cluster without taking pause/resume actions (for production).
    
    Args:
        cluster_id: Aurora cluster identifier
        cluster_state: Current cluster state
        
    Returns:
        Dictionary with monitoring results
    """
    try:
        # Get recent activity metrics
        connection_activity = get_recent_connection_activity(cluster_id)
        capacity_usage = get_recent_capacity_usage(cluster_id)
        
        return {
            'action': 'monitored',
            'reason': 'Production environment - monitoring only',
            'cluster_state': cluster_state,
            'activity_metrics': {
                'connection_activity': connection_activity,
                'capacity_usage': capacity_usage
            }
        }
        
    except Exception as e:
        logger.error(f"Error monitoring cluster: {str(e)}")
        return {
            'action': 'monitor_failed',
            'reason': f'Error during monitoring: {str(e)}',
            'error': str(e)
        }

def is_cluster_idle(cluster_id: str, idle_threshold_minutes: int = 30) -> bool:
    """
    Check if cluster is idle based on connection activity.
    
    Args:
        cluster_id: Aurora cluster identifier
        idle_threshold_minutes: Minutes to check for idle activity
        
    Returns:
        True if cluster appears idle, False otherwise
    """
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=idle_threshold_minutes)
        
        # Check database connections
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseConnections',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Maximum', 'Average']
        )
        
        if response['Datapoints']:
            max_connections = max(dp['Maximum'] for dp in response['Datapoints'])
            avg_connections = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            
            # Consider idle if very few connections (≤ 2 for system connections)
            is_idle = max_connections <= 2 and avg_connections <= 1
            
            logger.info(f"Connection analysis - Max: {max_connections}, Avg: {avg_connections:.2f}, Idle: {is_idle}")
            return is_idle
        
        # No data available - assume idle
        logger.info("No connection data available - assuming idle")
        return True
        
    except Exception as e:
        logger.error(f"Error checking if cluster is idle: {str(e)}")
        # Default to not idle on error to be safe
        return False

def get_recent_connection_activity(cluster_id: str) -> Dict[str, float]:
    """Get recent connection activity metrics."""
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=2)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseConnections',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=600,  # 10-minute periods
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            datapoints = response['Datapoints']
            return {
                'average': sum(dp['Average'] for dp in datapoints) / len(datapoints),
                'maximum': max(dp['Maximum'] for dp in datapoints),
                'datapoint_count': len(datapoints)
            }
        
        return {'average': 0, 'maximum': 0, 'datapoint_count': 0}
        
    except Exception as e:
        logger.error(f"Error getting connection activity: {str(e)}")
        return {'average': 0, 'maximum': 0, 'datapoint_count': 0}

def get_recent_capacity_usage(cluster_id: str) -> Dict[str, float]:
    """Get recent capacity usage metrics."""
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=2)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='ServerlessDatabaseCapacity',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=600,  # 10-minute periods
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            datapoints = response['Datapoints']
            return {
                'average': sum(dp['Average'] for dp in datapoints) / len(datapoints),
                'maximum': max(dp['Maximum'] for dp in datapoints),
                'datapoint_count': len(datapoints)
            }
        
        return {'average': 0.5, 'maximum': 0.5, 'datapoint_count': 0}
        
    except Exception as e:
        logger.error(f"Error getting capacity usage: {str(e)}")
        return {'average': 0.5, 'maximum': 0.5, 'datapoint_count': 0}

def record_pause_resume_metrics(
    cluster_id: str,
    action: str,
    result: Dict[str, Any],
    environment: str
) -> None:
    """
    Record pause/resume actions and results in CloudWatch metrics.
    
    Args:
        cluster_id: Aurora cluster identifier
        action: Determined action (pause, resume, monitor)
        result: Result of the action execution
        environment: Environment type
    """
    try:
        executed_action = result.get('action', 'unknown')
        metric_value = 1 if executed_action in ['paused', 'resumed'] else 0
        
        # Record action metrics
        cloudwatch.put_metric_data(
            Namespace='Aurora/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'AutoPauseResumeActions',
                    'Dimensions': [
                        {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                        {'Name': 'Action', 'Value': action},
                        {'Name': 'Environment', 'Value': environment}
                    ],
                    'Value': metric_value,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'AutoPauseResumeResult',
                    'Dimensions': [
                        {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                        {'Name': 'ExecutedAction', 'Value': executed_action},
                        {'Name': 'Environment', 'Value': environment}
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        logger.info(f"Recorded metrics for action: {action}, result: {executed_action}")
        
    except Exception as e:
        logger.error(f"Error recording pause/resume metrics: {str(e)}")