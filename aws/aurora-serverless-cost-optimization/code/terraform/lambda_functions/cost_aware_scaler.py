"""
Cost-Aware Aurora Serverless v2 Scaling Function

This Lambda function implements intelligent scaling logic for Aurora Serverless v2
based on real-time performance metrics and cost optimization strategies.
"""

import json
import boto3
import logging
from datetime import datetime, timedelta
import os
from typing import Dict, Any, Tuple

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for cost-aware Aurora Serverless v2 scaling.
    
    Args:
        event: EventBridge trigger event
        context: Lambda context object
        
    Returns:
        Response object with scaling results
    """
    cluster_id = os.environ.get('CLUSTER_ID', '${cluster_id}')
    region = os.environ.get('REGION', 'us-east-1')
    
    try:
        logger.info(f"Starting cost-aware scaling analysis for cluster: {cluster_id}")
        
        # Get current cluster configuration
        cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = cluster_response['DBClusters'][0]
        
        # Extract current scaling configuration
        current_scaling = cluster['ServerlessV2ScalingConfiguration']
        current_min = current_scaling['MinCapacity']
        current_max = current_scaling['MaxCapacity']
        
        logger.info(f"Current scaling config - Min: {current_min} ACU, Max: {current_max} ACU")
        
        # Get performance metrics
        cpu_metrics = get_cpu_utilization(cluster_id)
        connection_metrics = get_connection_count(cluster_id)
        capacity_metrics = get_current_capacity(cluster_id)
        
        logger.info(f"Metrics - CPU: {cpu_metrics}, Connections: {connection_metrics}, Capacity: {capacity_metrics}")
        
        # Calculate optimal scaling configuration
        new_min, new_max = calculate_optimal_scaling(
            cpu_metrics, connection_metrics, capacity_metrics,
            current_min, current_max
        )
        
        # Apply scaling if needed
        scaling_applied = False
        if new_min != current_min or new_max != current_max:
            update_scaling_configuration(cluster_id, new_min, new_max)
            scaling_applied = True
            
            # Send cost impact notification
            send_scaling_notification(cluster_id, current_min, current_max, new_min, new_max)
            
            logger.info(f"Scaling updated - New Min: {new_min} ACU, New Max: {new_max} ACU")
        else:
            logger.info("No scaling changes needed")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'region': region,
                'previous_scaling': {'min': current_min, 'max': current_max},
                'new_scaling': {'min': new_min, 'max': new_max},
                'scaling_applied': scaling_applied,
                'metrics': {
                    'cpu_avg': cpu_metrics.get('average', 0),
                    'cpu_max': cpu_metrics.get('maximum', 0),
                    'connections_avg': connection_metrics.get('average', 0),
                    'current_capacity': capacity_metrics.get('current', 0)
                },
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in cost-aware scaling: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'cluster': cluster_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def get_cpu_utilization(cluster_id: str) -> Dict[str, float]:
    """
    Get CPU utilization metrics for the cluster.
    
    Args:
        cluster_id: Aurora cluster identifier
        
    Returns:
        Dictionary with average and maximum CPU utilization
    """
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            datapoints = response['Datapoints']
            avg_cpu = sum(dp['Average'] for dp in datapoints) / len(datapoints)
            max_cpu = max(dp['Maximum'] for dp in datapoints)
            
            return {
                'average': round(avg_cpu, 2),
                'maximum': round(max_cpu, 2),
                'datapoint_count': len(datapoints)
            }
        
        return {'average': 0, 'maximum': 0, 'datapoint_count': 0}
        
    except Exception as e:
        logger.error(f"Error getting CPU metrics: {str(e)}")
        return {'average': 0, 'maximum': 0, 'datapoint_count': 0}

def get_connection_count(cluster_id: str) -> Dict[str, float]:
    """
    Get database connection count metrics.
    
    Args:
        cluster_id: Aurora cluster identifier
        
    Returns:
        Dictionary with average and maximum connection counts
    """
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseConnections',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            datapoints = response['Datapoints']
            avg_conn = sum(dp['Average'] for dp in datapoints) / len(datapoints)
            max_conn = max(dp['Maximum'] for dp in datapoints)
            
            return {
                'average': round(avg_conn, 2),
                'maximum': round(max_conn, 2),
                'datapoint_count': len(datapoints)
            }
        
        return {'average': 0, 'maximum': 0, 'datapoint_count': 0}
        
    except Exception as e:
        logger.error(f"Error getting connection metrics: {str(e)}")
        return {'average': 0, 'maximum': 0, 'datapoint_count': 0}

def get_current_capacity(cluster_id: str) -> Dict[str, float]:
    """
    Get current Aurora Serverless v2 capacity metrics.
    
    Args:
        cluster_id: Aurora cluster identifier
        
    Returns:
        Dictionary with current capacity information
    """
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=30)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='ServerlessDatabaseCapacity',
            Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if response['Datapoints']:
            datapoints = response['Datapoints']
            # Get the most recent capacity reading
            recent_datapoint = max(datapoints, key=lambda x: x['Timestamp'])
            
            return {
                'current': round(recent_datapoint['Average'], 2),
                'recent_max': round(max(dp['Maximum'] for dp in datapoints), 2),
                'datapoint_count': len(datapoints)
            }
        
        return {'current': 0.5, 'recent_max': 0.5, 'datapoint_count': 0}
        
    except Exception as e:
        logger.error(f"Error getting capacity metrics: {str(e)}")
        return {'current': 0.5, 'recent_max': 0.5, 'datapoint_count': 0}

def calculate_optimal_scaling(
    cpu_metrics: Dict[str, float],
    conn_metrics: Dict[str, float],
    capacity_metrics: Dict[str, float],
    current_min: float,
    current_max: float
) -> Tuple[float, float]:
    """
    Calculate optimal scaling configuration based on performance metrics.
    
    Args:
        cpu_metrics: CPU utilization metrics
        conn_metrics: Connection count metrics
        capacity_metrics: Current capacity metrics
        current_min: Current minimum capacity
        current_max: Current maximum capacity
        
    Returns:
        Tuple of (new_min_capacity, new_max_capacity)
    """
    cpu_avg = cpu_metrics.get('average', 0)
    cpu_max = cpu_metrics.get('maximum', 0)
    conn_avg = conn_metrics.get('average', 0)
    conn_max = conn_metrics.get('maximum', 0)
    current_capacity = capacity_metrics.get('current', 0.5)
    
    logger.info(f"Calculating scaling for CPU avg: {cpu_avg}%, max: {cpu_max}%, "
                f"Conn avg: {conn_avg}, max: {conn_max}, Current capacity: {current_capacity}")
    
    # Determine optimal minimum capacity
    new_min = current_min
    
    if cpu_avg < 15 and conn_avg < 5:
        # Very low utilization - aggressive scale down
        new_min = 0.5
        logger.info("Very low utilization detected - scaling down to minimum")
    elif cpu_avg < 30 and conn_avg < 15:
        # Low utilization - moderate scale down
        new_min = max(0.5, current_min - 0.5)
        logger.info("Low utilization detected - moderate scale down")
    elif cpu_avg > 70 or conn_avg > 50:
        # High utilization - scale up minimum for better responsiveness
        new_min = min(8, current_min + 1)
        logger.info("High utilization detected - scaling up minimum capacity")
    elif cpu_avg > 50 or conn_avg > 30:
        # Medium-high utilization - maintain or slight increase
        new_min = min(4, current_min + 0.5)
        logger.info("Medium-high utilization - maintaining/slight increase")
    
    # Determine optimal maximum capacity
    new_max = current_max
    
    if cpu_max > 85 or conn_max > 100:
        # Very high peak usage - increase max capacity
        new_max = min(64, current_max + 8)
        logger.info("Very high peak usage - increasing maximum capacity")
    elif cpu_max > 75 or conn_max > 80:
        # High peak usage - moderate increase
        new_max = min(32, current_max + 4)
        logger.info("High peak usage - moderate increase in maximum")
    elif cpu_max < 40 and conn_max < 20 and current_capacity < current_max * 0.5:
        # Low peak usage and underutilized - reduce max for cost savings
        new_max = max(4, current_max - 4)
        logger.info("Low peak usage - reducing maximum for cost savings")
    elif cpu_max < 60 and conn_max < 40:
        # Medium-low peak usage - slight reduction
        new_max = max(8, current_max - 2)
        logger.info("Medium-low peak usage - slight reduction in maximum")
    
    # Ensure minimum <= maximum
    new_min = min(new_min, new_max)
    
    # Round to valid ACU increments (0.5 ACU increments)
    new_min = round(new_min * 2) / 2
    new_max = round(new_max * 2) / 2
    
    # Ensure within Aurora Serverless v2 limits
    new_min = max(0.5, min(128, new_min))
    new_max = max(0.5, min(128, new_max))
    
    logger.info(f"Calculated optimal scaling - Min: {new_min} ACU, Max: {new_max} ACU")
    
    return new_min, new_max

def update_scaling_configuration(cluster_id: str, min_capacity: float, max_capacity: float) -> None:
    """
    Update Aurora Serverless v2 scaling configuration.
    
    Args:
        cluster_id: Aurora cluster identifier
        min_capacity: New minimum capacity in ACU
        max_capacity: New maximum capacity in ACU
    """
    try:
        rds.modify_db_cluster(
            DBClusterIdentifier=cluster_id,
            ServerlessV2ScalingConfiguration={
                'MinCapacity': min_capacity,
                'MaxCapacity': max_capacity
            },
            ApplyImmediately=True
        )
        logger.info(f"Successfully updated scaling configuration for {cluster_id}")
        
    except Exception as e:
        logger.error(f"Error updating scaling configuration: {str(e)}")
        raise

def send_scaling_notification(
    cluster_id: str,
    old_min: float,
    old_max: float,
    new_min: float,
    new_max: float
) -> None:
    """
    Send scaling notification and record custom metrics.
    
    Args:
        cluster_id: Aurora cluster identifier
        old_min: Previous minimum capacity
        old_max: Previous maximum capacity
        new_min: New minimum capacity
        new_max: New maximum capacity
    """
    try:
        # Calculate estimated cost impact
        cost_impact = calculate_cost_impact(old_min, old_max, new_min, new_max)
        
        # Record custom CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='Aurora/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'ScalingAdjustment',
                    'Dimensions': [
                        {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                        {'Name': 'ScalingType', 'Value': 'MinCapacity'}
                    ],
                    'Value': new_min - old_min,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'ScalingAdjustment',
                    'Dimensions': [
                        {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                        {'Name': 'ScalingType', 'Value': 'MaxCapacity'}
                    ],
                    'Value': new_max - old_max,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'EstimatedCostImpact',
                    'Dimensions': [{'Name': 'ClusterIdentifier', 'Value': cluster_id}],
                    'Value': cost_impact,
                    'Unit': 'None',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        logger.info(f"Scaling notification sent - Cost impact: ${cost_impact:+.2f}/month")
        
    except Exception as e:
        logger.error(f"Error sending scaling notification: {str(e)}")

def calculate_cost_impact(old_min: float, old_max: float, new_min: float, new_max: float) -> float:
    """
    Calculate estimated monthly cost impact of scaling changes.
    
    Args:
        old_min: Previous minimum capacity
        old_max: Previous maximum capacity
        new_min: New minimum capacity
        new_max: New maximum capacity
        
    Returns:
        Estimated monthly cost impact in USD
    """
    # Simplified cost calculation
    # Actual cost varies by region and usage patterns
    hours_per_month = 730
    cost_per_acu_hour = 0.12  # Approximate cost per ACU hour in USD
    
    # Estimate average usage based on min/max (simplified model)
    # In reality, usage patterns vary significantly
    old_estimated_avg = (old_min + old_max) / 3  # Conservative estimate
    new_estimated_avg = (new_min + new_max) / 3
    
    old_monthly_cost = old_estimated_avg * hours_per_month * cost_per_acu_hour
    new_monthly_cost = new_estimated_avg * hours_per_month * cost_per_acu_hour
    
    return round(new_monthly_cost - old_monthly_cost, 2)