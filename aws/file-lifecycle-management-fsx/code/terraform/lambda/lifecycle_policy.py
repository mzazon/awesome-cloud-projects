#!/usr/bin/env python3
"""
FSx Lifecycle Policy Management Lambda Function

This function monitors FSx CloudWatch metrics to analyze file access patterns
and automatically adjusts storage policies based on usage data.
"""

import json
import boto3
import datetime
import logging
import os
from typing import Dict, List, Optional
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# AWS clients
fsx_client = boto3.client('fsx')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Main Lambda handler function for FSx lifecycle policy management
    """
    logger.info("Starting FSx lifecycle policy analysis")
    
    try:
        # Get environment variables
        fsx_file_system_id = os.environ.get('FSX_FILE_SYSTEM_ID', '${fsx_file_system_id}')
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
        
        if not fsx_file_system_id or fsx_file_system_id.startswith('$'):
            logger.error("FSX_FILE_SYSTEM_ID environment variable not properly set")
            return create_error_response("Missing FSX_FILE_SYSTEM_ID environment variable")
        
        # Get FSx file system information
        file_systems = fsx_client.describe_file_systems(
            FileSystemIds=[fsx_file_system_id]
        )
        
        if not file_systems['FileSystems']:
            logger.error(f"FSx file system {fsx_file_system_id} not found")
            return create_error_response(f"FSx file system {fsx_file_system_id} not found")
        
        fs = file_systems['FileSystems'][0]
        logger.info(f"Analyzing FSx file system: {fs['FileSystemId']}")
        
        # Get cache hit ratio metrics
        cache_metrics = get_cache_metrics(fsx_file_system_id)
        logger.info(f"Retrieved {len(cache_metrics)} cache metrics data points")
        
        # Get storage utilization metrics
        storage_metrics = get_storage_metrics(fsx_file_system_id)
        logger.info(f"Retrieved {len(storage_metrics)} storage metrics data points")
        
        # Get throughput metrics
        throughput_metrics = get_throughput_metrics(fsx_file_system_id)
        logger.info(f"Retrieved {len(throughput_metrics)} throughput metrics data points")
        
        # Analyze access patterns and generate recommendations
        recommendations = analyze_access_patterns(
            fs, cache_metrics, storage_metrics, throughput_metrics
        )
        logger.info(f"Generated {len(recommendations.get('actions', []))} recommendations")
        
        # Send notifications if there are actionable recommendations
        if recommendations.get('actions'):
            send_notifications(sns_topic_arn, fsx_file_system_id, recommendations)
            logger.info("Notifications sent successfully")
        
        # Put custom metrics to CloudWatch
        put_custom_metrics(fsx_file_system_id, recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Lifecycle policy analysis completed successfully',
                'file_system_id': fsx_file_system_id,
                'recommendations': recommendations
            }, default=str)
        }
        
    except ClientError as e:
        error_msg = f"AWS API error: {e.response['Error']['Code']} - {e.response['Error']['Message']}"
        logger.error(error_msg)
        return create_error_response(error_msg)
    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return create_error_response(error_msg)

def get_cache_metrics(file_system_id: str) -> List[Dict]:
    """Get FSx cache hit ratio metrics from CloudWatch"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=2)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='FileServerCacheHitRatio',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5-minute periods
            Statistics=['Average', 'Maximum', 'Minimum']
        )
        return response.get('Datapoints', [])
    except ClientError as e:
        logger.error(f"Error getting cache metrics: {e}")
        return []

def get_storage_metrics(file_system_id: str) -> List[Dict]:
    """Get FSx storage utilization metrics from CloudWatch"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=2)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='StorageUtilization',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5-minute periods
            Statistics=['Average', 'Maximum', 'Minimum']
        )
        return response.get('Datapoints', [])
    except ClientError as e:
        logger.error(f"Error getting storage metrics: {e}")
        return []

def get_throughput_metrics(file_system_id: str) -> List[Dict]:
    """Get FSx network throughput utilization metrics from CloudWatch"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=2)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='NetworkThroughputUtilization',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5-minute periods
            Statistics=['Average', 'Maximum', 'Minimum']
        )
        return response.get('Datapoints', [])
    except ClientError as e:
        logger.error(f"Error getting throughput metrics: {e}")
        return []

def analyze_access_patterns(
    file_system: Dict, 
    cache_metrics: List[Dict], 
    storage_metrics: List[Dict],
    throughput_metrics: List[Dict]
) -> Dict:
    """Analyze metrics to generate intelligent recommendations"""
    
    recommendations = {
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'file_system_id': file_system['FileSystemId'],
        'cache_recommendation': 'No data available',
        'storage_recommendation': 'No data available',
        'throughput_recommendation': 'No data available',
        'actions': [],
        'metrics_summary': {}
    }
    
    # Analyze cache performance
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
        max_cache_hit = max(point['Maximum'] for point in cache_metrics)
        min_cache_hit = min(point['Minimum'] for point in cache_metrics)
        
        recommendations['metrics_summary']['cache_hit_ratio'] = {
            'average': round(avg_cache_hit, 2),
            'maximum': round(max_cache_hit, 2),
            'minimum': round(min_cache_hit, 2)
        }
        
        if avg_cache_hit < 70:
            recommendations['cache_recommendation'] = f'Low cache hit ratio ({avg_cache_hit:.1f}%) - Consider increasing cache size or reviewing access patterns'
            recommendations['actions'].append({
                'type': 'cache_optimization',
                'priority': 'high',
                'description': 'Improve cache hit ratio through optimization'
            })
        elif avg_cache_hit > 95:
            recommendations['cache_recommendation'] = f'Excellent cache hit ratio ({avg_cache_hit:.1f}%) - Cache size is well-optimized'
            recommendations['actions'].append({
                'type': 'maintain_cache',
                'priority': 'low',
                'description': 'Maintain current cache configuration'
            })
        else:
            recommendations['cache_recommendation'] = f'Good cache hit ratio ({avg_cache_hit:.1f}%) - Performance is acceptable'
    
    # Analyze storage utilization
    if storage_metrics:
        avg_storage = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
        max_storage = max(point['Maximum'] for point in storage_metrics)
        
        recommendations['metrics_summary']['storage_utilization'] = {
            'average': round(avg_storage, 2),
            'maximum': round(max_storage, 2),
            'current_capacity': file_system.get('StorageCapacity', 0)
        }
        
        if avg_storage > 85:
            recommendations['storage_recommendation'] = f'High storage utilization ({avg_storage:.1f}%) - Monitor capacity closely'
            recommendations['actions'].append({
                'type': 'capacity_monitoring',
                'priority': 'high',
                'description': 'Monitor storage capacity and plan for expansion'
            })
        elif avg_storage < 30:
            recommendations['storage_recommendation'] = f'Low storage utilization ({avg_storage:.1f}%) - Consider cost optimization'
            recommendations['actions'].append({
                'type': 'cost_optimization',
                'priority': 'medium',
                'description': 'Review storage allocation for potential cost savings'
            })
        else:
            recommendations['storage_recommendation'] = f'Optimal storage utilization ({avg_storage:.1f}%)'
    
    # Analyze throughput utilization
    if throughput_metrics:
        avg_throughput = sum(point['Average'] for point in throughput_metrics) / len(throughput_metrics)
        max_throughput = max(point['Maximum'] for point in throughput_metrics)
        
        recommendations['metrics_summary']['throughput_utilization'] = {
            'average': round(avg_throughput, 2),
            'maximum': round(max_throughput, 2),
            'provisioned_capacity': file_system.get('ThroughputCapacity', 0)
        }
        
        if avg_throughput > 80:
            recommendations['throughput_recommendation'] = f'High throughput utilization ({avg_throughput:.1f}%) - Consider scaling'
            recommendations['actions'].append({
                'type': 'throughput_scaling',
                'priority': 'high',
                'description': 'Scale throughput capacity to avoid performance bottlenecks'
            })
        elif avg_throughput < 20:
            recommendations['throughput_recommendation'] = f'Low throughput utilization ({avg_throughput:.1f}%) - Consider rightsizing'
            recommendations['actions'].append({
                'type': 'throughput_optimization',
                'priority': 'medium',
                'description': 'Consider optimizing throughput capacity for cost efficiency'
            })
        else:
            recommendations['throughput_recommendation'] = f'Good throughput utilization ({avg_throughput:.1f}%)'
    
    return recommendations

def send_notifications(topic_arn: str, file_system_id: str, recommendations: Dict):
    """Send recommendations via SNS"""
    if not topic_arn or topic_arn.startswith('$'):
        logger.warning("SNS topic ARN not properly configured, skipping notifications")
        return
    
    try:
        # Create a formatted message
        message_parts = [
            f"FSx Lifecycle Policy Analysis - {file_system_id}",
            f"Timestamp: {recommendations['timestamp']}",
            "",
            "RECOMMENDATIONS:",
            f"• Cache: {recommendations['cache_recommendation']}",
            f"• Storage: {recommendations['storage_recommendation']}",
            f"• Throughput: {recommendations['throughput_recommendation']}",
            ""
        ]
        
        if recommendations.get('actions'):
            message_parts.append("ACTION ITEMS:")
            for action in recommendations['actions']:
                priority_emoji = {"high": "🔴", "medium": "🟡", "low": "🟢"}.get(action['priority'], "")
                message_parts.append(f"{priority_emoji} {action['type'].title()}: {action['description']}")
        
        if recommendations.get('metrics_summary'):
            message_parts.extend(["", "METRICS SUMMARY:"])
            for metric_name, metric_data in recommendations['metrics_summary'].items():
                if isinstance(metric_data, dict):
                    message_parts.append(f"• {metric_name.replace('_', ' ').title()}:")
                    for key, value in metric_data.items():
                        message_parts.append(f"  - {key.title()}: {value}")
        
        message = "\n".join(message_parts)
        
        # Send notification
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=f"FSx Lifecycle Analysis - {file_system_id}"
        )
        
        logger.info("Notification sent successfully")
    except ClientError as e:
        logger.error(f"Error sending notification: {e}")

def put_custom_metrics(file_system_id: str, recommendations: Dict):
    """Put custom metrics to CloudWatch for monitoring"""
    try:
        metrics_data = []
        
        # Add recommendation count metrics
        action_count_by_priority = {'high': 0, 'medium': 0, 'low': 0}
        for action in recommendations.get('actions', []):
            priority = action.get('priority', 'medium')
            action_count_by_priority[priority] += 1
        
        for priority, count in action_count_by_priority.items():
            metrics_data.append({
                'MetricName': f'RecommendationCount{priority.title()}Priority',
                'Value': count,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'FileSystemId',
                        'Value': file_system_id
                    }
                ]
            })
        
        # Add total recommendations metric
        metrics_data.append({
            'MetricName': 'TotalRecommendations',
            'Value': len(recommendations.get('actions', [])),
            'Unit': 'Count',
            'Dimensions': [
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ]
        })
        
        # Put metrics to CloudWatch
        if metrics_data:
            cloudwatch.put_metric_data(
                Namespace='FSx/LifecycleManagement',
                MetricData=metrics_data
            )
            logger.info(f"Published {len(metrics_data)} custom metrics to CloudWatch")
            
    except ClientError as e:
        logger.error(f"Error putting custom metrics: {e}")

def create_error_response(error_message: str) -> Dict:
    """Create standardized error response"""
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.datetime.utcnow().isoformat()
        })
    }