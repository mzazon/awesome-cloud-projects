"""
Cost-Aware MemoryDB Lifecycle Management Lambda Function

This Lambda function provides intelligent cost optimization for MemoryDB clusters
by analyzing cost patterns and making automated scaling decisions based on
business hours, usage patterns, and cost thresholds.

Features:
- Cost Explorer API integration for real-time cost analysis
- MemoryDB cluster scaling based on node type modifications
- CloudWatch custom metrics publishing
- Intelligent scaling recommendations
- Comprehensive error handling and logging

Environment Variables:
- LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- CLUSTER_NAME: MemoryDB cluster name to manage
- COST_NAMESPACE: CloudWatch namespace for custom cost metrics
"""

import json
import boto3
import datetime
import logging
import os
from typing import Dict, Any, Optional

# Configure logging based on environment variable
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', '${log_level}')
logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

# Initialize AWS clients
memorydb = boto3.client('memorydb')
ce = boto3.client('ce')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Main Lambda handler for cost-aware MemoryDB cluster management.
    
    Analyzes cost patterns and adjusts cluster configuration based on thresholds,
    business hours, and optimization strategies.
    
    Args:
        event: Lambda event containing cluster_name, action, and cost_threshold
        context: Lambda runtime context
        
    Returns:
        Dict containing optimization results and recommendations
    """
    
    cluster_name = event.get('cluster_name')
    action = event.get('action', 'analyze')
    cost_threshold = event.get('cost_threshold', 100.0)
    
    logger.info(f"Starting cost optimization for cluster: {cluster_name}, action: {action}")
    
    if not cluster_name:
        error_msg = 'cluster_name is required in event payload'
        logger.error(error_msg)
        return {
            'statusCode': 400,
            'body': {'error': error_msg}
        }
    
    try:
        # Get current cluster status and configuration
        cluster_info = get_cluster_info(cluster_name)
        if not cluster_info:
            return {
                'statusCode': 404,
                'body': {'error': f'Cluster {cluster_name} not found or unavailable'}
            }
        
        logger.info(f"Cluster {cluster_name} status: {cluster_info['status']}, "
                   f"node_type: {cluster_info['node_type']}")
        
        # Only proceed with optimization if cluster is available
        if cluster_info['status'] != 'available':
            logger.warning(f"Cluster {cluster_name} is not available for modifications")
            return {
                'statusCode': 200,
                'body': {
                    'message': f'Cluster not available for modification, status: {cluster_info["status"]}',
                    'cluster_status': cluster_info['status']
                }
            }
        
        # Analyze cost patterns and trends
        cost_analysis = analyze_cost_patterns()
        logger.info(f"Cost analysis completed: ${cost_analysis['total_cost']:.2f} weekly cost")
        
        # Generate scaling recommendation based on current state and cost analysis
        scaling_recommendation = generate_scaling_recommendation(
            cost_analysis, cost_threshold, cluster_info, action
        )
        
        logger.info(f"Scaling recommendation: {scaling_recommendation['action']}")
        
        # Execute scaling action if recommended and conditions are met
        execution_result = None
        if (scaling_recommendation['action'] != 'none' and 
            cluster_info['status'] == 'available'):
            execution_result = execute_scaling_action(cluster_name, scaling_recommendation)
            logger.info(f"Scaling execution result: {execution_result['status']}")
        
        # Publish metrics to CloudWatch for monitoring and alerting
        publish_optimization_metrics(cluster_name, cost_analysis, scaling_recommendation)
        
        # Prepare comprehensive response
        response_body = {
            'cluster_name': cluster_name,
            'cluster_info': cluster_info,
            'cost_analysis': cost_analysis,
            'recommendation': scaling_recommendation,
            'execution_result': execution_result,
            'timestamp': datetime.datetime.now().isoformat(),
            'action_requested': action
        }
        
        logger.info("Cost optimization completed successfully")
        return {
            'statusCode': 200,
            'body': response_body
        }
        
    except Exception as e:
        error_msg = f"Error in cost optimization: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return {
            'statusCode': 500,
            'body': {'error': error_msg}
        }

def get_cluster_info(cluster_name: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve current MemoryDB cluster information and status.
    
    Args:
        cluster_name: Name of the MemoryDB cluster
        
    Returns:
        Dict containing cluster info or None if not found
    """
    try:
        response = memorydb.describe_clusters(ClusterName=cluster_name)
        
        if not response['Clusters']:
            logger.warning(f"No clusters found with name: {cluster_name}")
            return None
            
        cluster = response['Clusters'][0]
        
        return {
            'cluster_name': cluster['Name'],
            'status': cluster['Status'],
            'node_type': cluster['NodeType'],
            'num_shards': cluster['NumberOfShards'],
            'num_replicas_per_shard': cluster.get('NumReplicasPerShard', 0),
            'engine_version': cluster.get('EngineVersion'),
            'availability_mode': cluster.get('AvailabilityMode', 'SingleAZ')
        }
        
    except Exception as e:
        logger.error(f"Failed to retrieve cluster info for {cluster_name}: {str(e)}")
        return None

def analyze_cost_patterns() -> Dict[str, float]:
    """
    Analyze recent MemoryDB costs using Cost Explorer API.
    
    Retrieves 7-day cost data and calculates trends to inform
    scaling decisions and cost optimization strategies.
    
    Returns:
        Dict containing cost analysis results
    """
    try:
        end_date = datetime.datetime.now()
        start_date = end_date - datetime.timedelta(days=7)
        
        logger.debug(f"Analyzing costs from {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}")
        
        cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
            ]
        )
        
        # Calculate MemoryDB-specific costs
        memorydb_cost = 0.0
        daily_costs = []
        
        for result_by_time in cost_response['ResultsByTime']:
            daily_memorydb_cost = 0.0
            for group in result_by_time['Groups']:
                service_name = group['Keys'][0]
                cost_amount = float(group['Metrics']['BlendedCost']['Amount'])
                
                # Match MemoryDB services (including ElastiCache for compatibility)
                if any(service in service_name.lower() for service in ['memorydb', 'elasticache']):
                    daily_memorydb_cost += cost_amount
                    
            daily_costs.append(daily_memorydb_cost)
            memorydb_cost += daily_memorydb_cost
        
        # Calculate cost trend (positive = increasing, negative = decreasing)
        cost_trend = 0.0
        if len(daily_costs) >= 2:
            recent_avg = sum(daily_costs[-3:]) / len(daily_costs[-3:])  # Last 3 days
            older_avg = sum(daily_costs[:4]) / len(daily_costs[:4])     # First 4 days
            cost_trend = recent_avg - older_avg
        
        logger.info(f"7-day MemoryDB cost: ${memorydb_cost:.2f}, trend: ${cost_trend:.2f}/day")
        
        return {
            'total_cost': memorydb_cost,
            'daily_average': memorydb_cost / 7,
            'cost_trend': cost_trend,
            'analysis_period_days': 7
        }
        
    except Exception as e:
        logger.warning(f"Could not retrieve comprehensive cost data: {str(e)}")
        # Return minimal cost analysis with zero values to allow optimization to continue
        return {
            'total_cost': 0.0,
            'daily_average': 0.0,
            'cost_trend': 0.0,
            'analysis_period_days': 7,
            'cost_data_available': False
        }

def generate_scaling_recommendation(
    cost_analysis: Dict[str, float], 
    cost_threshold: float, 
    cluster_info: Dict[str, Any], 
    action: str
) -> Dict[str, Any]:
    """
    Generate intelligent scaling recommendations based on cost analysis,
    business hours, and current cluster configuration.
    
    Args:
        cost_analysis: Results from cost pattern analysis
        cost_threshold: Cost threshold for scaling decisions
        cluster_info: Current cluster configuration
        action: Requested action (scale_up, scale_down, analyze)
        
    Returns:
        Dict containing scaling recommendation and rationale
    """
    
    current_node_type = cluster_info['node_type']
    current_cost = cost_analysis['total_cost']
    cost_trend = cost_analysis.get('cost_trend', 0.0)
    
    logger.debug(f"Generating recommendation: action={action}, cost=${current_cost:.2f}, "
                f"threshold=${cost_threshold:.2f}, node_type={current_node_type}")
    
    # Business hours scale-down optimization (typically evenings/weekends)
    if action == 'scale_down':
        if 'large' in current_node_type:
            target_node_type = current_node_type.replace('large', 'small')
            return {
                'action': 'modify_node_type',
                'current_node_type': current_node_type,
                'target_node_type': target_node_type,
                'reason': 'Off-peak cost optimization - scaling down from large to small',
                'estimated_savings_percent': '30-40%',
                'cost_impact': f'Reduce costs during off-peak hours'
            }
        elif 'medium' in current_node_type:
            target_node_type = current_node_type.replace('medium', 'small')
            return {
                'action': 'modify_node_type',
                'current_node_type': current_node_type,
                'target_node_type': target_node_type,
                'reason': 'Off-peak cost optimization - scaling down from medium to small',
                'estimated_savings_percent': '20-30%',
                'cost_impact': f'Reduce costs during off-peak hours'
            }
        else:
            return {
                'action': 'none',
                'reason': f'Already at optimal size ({current_node_type}) for off-peak hours'
            }
    
    # Business hours scale-up optimization (typically mornings)
    elif action == 'scale_up':
        if 'small' in current_node_type and current_cost < cost_threshold:
            target_node_type = current_node_type.replace('small', 'medium')
            return {
                'action': 'modify_node_type',
                'current_node_type': current_node_type,
                'target_node_type': target_node_type,
                'reason': 'Business hours performance optimization - scaling up for peak workloads',
                'performance_impact': 'Improved performance for business-critical workloads',
                'cost_impact': f'Increase costs for enhanced performance during business hours'
            }
        else:
            return {
                'action': 'none',
                'reason': f'Node type {current_node_type} appropriate for business hours or cost threshold exceeded'
            }
    
    # Weekly cost analysis and trend-based recommendations
    elif action == 'analyze':
        if current_cost > cost_threshold:
            if cost_trend > 0:
                return {
                    'action': 'cost_alert',
                    'reason': f'Weekly cost (${current_cost:.2f}) exceeds threshold (${cost_threshold:.2f}) with increasing trend',
                    'recommendation': 'Consider scaling down during off-peak hours or optimizing workload patterns',
                    'cost_trend': f'${cost_trend:.2f}/day increase'
                }
            else:
                return {
                    'action': 'cost_monitoring',
                    'reason': f'Weekly cost (${current_cost:.2f}) exceeds threshold but trend is stable/decreasing',
                    'recommendation': 'Continue monitoring cost patterns',
                    'cost_trend': f'${cost_trend:.2f}/day change'
                }
        else:
            return {
                'action': 'none',
                'reason': f'Weekly cost (${current_cost:.2f}) within acceptable threshold (${cost_threshold:.2f})',
                'status': 'cost_optimized'
            }
    
    # Default recommendation for unknown actions
    return {
        'action': 'none',
        'reason': f'No specific recommendation for action: {action}'
    }

def execute_scaling_action(cluster_name: str, recommendation: Dict[str, Any]) -> Dict[str, str]:
    """
    Execute the recommended scaling action on the MemoryDB cluster.
    
    Args:
        cluster_name: Name of the MemoryDB cluster
        recommendation: Scaling recommendation from analysis
        
    Returns:
        Dict containing execution status and details
    """
    
    if recommendation['action'] != 'modify_node_type':
        return {
            'status': 'skipped',
            'message': f'No scaling action required: {recommendation.get("reason", "Unknown")}'
        }
    
    try:
        target_node_type = recommendation['target_node_type']
        current_node_type = recommendation['current_node_type']
        
        logger.info(f"Initiating cluster modification: {cluster_name} "
                   f"from {current_node_type} to {target_node_type}")
        
        response = memorydb.modify_cluster(
            ClusterName=cluster_name,
            NodeType=target_node_type
        )
        
        logger.info(f"Cluster modification initiated successfully for {cluster_name}")
        
        return {
            'status': 'initiated',
            'message': f'Cluster modification started: {current_node_type} -> {target_node_type}',
            'modification_id': response.get('Cluster', {}).get('Name'),
            'target_node_type': target_node_type,
            'estimated_completion': 'Typically completes in 15-30 minutes'
        }
        
    except Exception as e:
        error_msg = f"Failed to modify cluster {cluster_name}: {str(e)}"
        logger.error(error_msg)
        return {
            'status': 'failed',
            'message': error_msg
        }

def publish_optimization_metrics(
    cluster_name: str, 
    cost_analysis: Dict[str, float], 
    recommendation: Dict[str, Any]
) -> None:
    """
    Publish cost optimization metrics to CloudWatch for monitoring and alerting.
    
    Args:
        cluster_name: Name of the MemoryDB cluster
        cost_analysis: Cost analysis results
        recommendation: Scaling recommendation details
    """
    
    try:
        namespace = os.environ.get('COST_NAMESPACE', 'MemoryDB/CostOptimization')
        
        metric_data = [
            {
                'MetricName': 'WeeklyCost',
                'Value': cost_analysis['total_cost'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ClusterName', 'Value': cluster_name}
                ],
                'Timestamp': datetime.datetime.now()
            },
            {
                'MetricName': 'DailyCostAverage',
                'Value': cost_analysis['daily_average'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ClusterName', 'Value': cluster_name}
                ],
                'Timestamp': datetime.datetime.now()
            },
            {
                'MetricName': 'OptimizationAction',
                'Value': 1 if recommendation['action'] != 'none' else 0,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'ClusterName', 'Value': cluster_name},
                    {'Name': 'ActionType', 'Value': recommendation['action']}
                ],
                'Timestamp': datetime.datetime.now()
            }
        ]
        
        # Add cost trend metric if available
        if 'cost_trend' in cost_analysis:
            metric_data.append({
                'MetricName': 'CostTrend',
                'Value': cost_analysis['cost_trend'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ClusterName', 'Value': cluster_name}
                ],
                'Timestamp': datetime.datetime.now()
            })
        
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=metric_data
        )
        
        logger.info(f"Published {len(metric_data)} metrics to CloudWatch namespace: {namespace}")
        
    except Exception as e:
        logger.warning(f"Failed to publish CloudWatch metrics: {str(e)}")
        # Don't fail the entire function if metrics publishing fails