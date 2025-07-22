#!/usr/bin/env python3
"""
FSx Alert Handler Lambda Function

This function processes CloudWatch alarms and provides intelligent analysis
of FSx performance issues with automated response recommendations.
"""

import json
import boto3
import logging
import os
import datetime
from typing import Dict, Optional
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# AWS clients
fsx_client = boto3.client('fsx')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Main Lambda handler function for processing FSx alerts
    """
    logger.info("Processing FSx alert")
    
    try:
        # Parse SNS message from CloudWatch alarm
        if 'Records' not in event or not event['Records']:
            logger.error("No SNS records found in event")
            return create_error_response("Invalid event format - no SNS records")
        
        # Process each SNS record (usually just one)
        for record in event['Records']:
            if record.get('EventSource') == 'aws:sns':
                sns_message = json.loads(record['Sns']['Message'])
                process_alarm_notification(sns_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Alert processed successfully',
                'timestamp': datetime.datetime.utcnow().isoformat()
            })
        }
        
    except json.JSONDecodeError as e:
        error_msg = f"Error parsing SNS message: {str(e)}"
        logger.error(error_msg)
        return create_error_response(error_msg)
    except Exception as e:
        error_msg = f"Unexpected error processing alert: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return create_error_response(error_msg)

def process_alarm_notification(sns_message: Dict):
    """Process CloudWatch alarm notification and generate intelligent response"""
    try:
        alarm_name = sns_message.get('AlarmName', 'Unknown')
        new_state = sns_message.get('NewStateValue', 'UNKNOWN')
        old_state = sns_message.get('OldStateValue', 'UNKNOWN')
        alarm_description = sns_message.get('AlarmDescription', '')
        state_reason = sns_message.get('NewStateReason', '')
        timestamp = sns_message.get('StateChangeTime', datetime.datetime.utcnow().isoformat())
        
        logger.info(f"Processing alarm: {alarm_name}, State: {old_state} -> {new_state}")
        
        # Only process ALARM state (not OK or INSUFFICIENT_DATA)
        if new_state != 'ALARM':
            logger.info(f"Alarm state is {new_state}, no action required")
            return
        
        # Get environment variables
        fsx_file_system_id = os.environ.get('FSX_FILE_SYSTEM_ID', '${fsx_file_system_id}')
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
        
        # Determine alert type and generate appropriate response
        alert_response = None
        
        if 'storage-utilization' in alarm_name.lower():
            alert_response = handle_storage_utilization_alarm(fsx_file_system_id, sns_message)
        elif 'cache-hit-ratio' in alarm_name.lower():
            alert_response = handle_cache_hit_ratio_alarm(fsx_file_system_id, sns_message)
        elif 'network' in alarm_name.lower() or 'throughput' in alarm_name.lower():
            alert_response = handle_network_utilization_alarm(fsx_file_system_id, sns_message)
        elif 'lambda' in alarm_name.lower() and 'error' in alarm_name.lower():
            alert_response = handle_lambda_error_alarm(sns_message)
        else:
            alert_response = handle_generic_alarm(fsx_file_system_id, sns_message)
        
        # Send intelligent alert response
        if alert_response and sns_topic_arn and not sns_topic_arn.startswith('$'):
            send_intelligent_alert(sns_topic_arn, alert_response)
            
    except Exception as e:
        logger.error(f"Error processing alarm notification: {str(e)}", exc_info=True)

def handle_storage_utilization_alarm(file_system_id: str, sns_message: Dict) -> Optional[Dict]:
    """Handle high storage utilization alarm with intelligent analysis"""
    try:
        # Get current file system information
        if not file_system_id or file_system_id.startswith('$'):
            logger.warning("File system ID not available for storage analysis")
            return None
            
        fs_response = fsx_client.describe_file_systems(FileSystemIds=[file_system_id])
        if not fs_response['FileSystems']:
            logger.error(f"File system {file_system_id} not found")
            return None
            
        fs = fs_response['FileSystems'][0]
        storage_capacity = fs.get('StorageCapacity', 0)
        storage_type = fs.get('StorageType', 'Unknown')
        
        # Get recent storage utilization metrics for trend analysis
        utilization_trend = get_storage_utilization_trend(file_system_id)
        
        # Analyze severity and generate recommendations
        severity = 'HIGH' if utilization_trend.get('current', 0) > 90 else 'MEDIUM'
        trend_direction = analyze_trend(utilization_trend.get('datapoints', []))
        
        return {
            'alert_type': 'Storage Utilization',
            'severity': severity,
            'file_system_id': file_system_id,
            'current_metrics': {
                'storage_capacity_gb': storage_capacity,
                'storage_type': storage_type,
                'utilization_percentage': utilization_trend.get('current', 0),
                'trend': trend_direction
            },
            'analysis': generate_storage_analysis(utilization_trend, storage_capacity, storage_type),
            'recommendations': generate_storage_recommendations(utilization_trend, storage_capacity, storage_type, severity),
            'urgency': 'Immediate action required' if severity == 'HIGH' else 'Monitor closely',
            'original_alarm': sns_message.get('AlarmName', 'Unknown')
        }
        
    except ClientError as e:
        logger.error(f"Error handling storage utilization alarm: {e}")
        return None

def handle_cache_hit_ratio_alarm(file_system_id: str, sns_message: Dict) -> Optional[Dict]:
    """Handle low cache hit ratio alarm with performance analysis"""
    try:
        if not file_system_id or file_system_id.startswith('$'):
            return None
            
        # Get cache hit ratio trend
        cache_trend = get_cache_hit_ratio_trend(file_system_id)
        
        # Get file system configuration for cache analysis
        fs_response = fsx_client.describe_file_systems(FileSystemIds=[file_system_id])
        if not fs_response['FileSystems']:
            return None
            
        fs = fs_response['FileSystems'][0]
        throughput_capacity = fs.get('ThroughputCapacity', 0)
        
        # Determine severity based on cache hit ratio
        current_ratio = cache_trend.get('current', 0)
        severity = 'HIGH' if current_ratio < 50 else 'MEDIUM' if current_ratio < 70 else 'LOW'
        
        return {
            'alert_type': 'Cache Performance',
            'severity': severity,
            'file_system_id': file_system_id,
            'current_metrics': {
                'cache_hit_ratio': round(current_ratio, 1),
                'throughput_capacity_mbps': throughput_capacity,
                'trend': analyze_trend(cache_trend.get('datapoints', []))
            },
            'analysis': generate_cache_analysis(cache_trend, throughput_capacity),
            'recommendations': generate_cache_recommendations(cache_trend, severity),
            'urgency': 'Performance optimization needed' if severity == 'HIGH' else 'Consider optimization',
            'original_alarm': sns_message.get('AlarmName', 'Unknown')
        }
        
    except ClientError as e:
        logger.error(f"Error handling cache hit ratio alarm: {e}")
        return None

def handle_network_utilization_alarm(file_system_id: str, sns_message: Dict) -> Optional[Dict]:
    """Handle high network utilization alarm with throughput analysis"""
    try:
        if not file_system_id or file_system_id.startswith('$'):
            return None
            
        # Get network throughput trend
        network_trend = get_network_utilization_trend(file_system_id)
        
        fs_response = fsx_client.describe_file_systems(FileSystemIds=[file_system_id])
        if not fs_response['FileSystems']:
            return None
            
        fs = fs_response['FileSystems'][0]
        throughput_capacity = fs.get('ThroughputCapacity', 0)
        
        current_utilization = network_trend.get('current', 0)
        severity = 'HIGH' if current_utilization > 90 else 'MEDIUM'
        
        return {
            'alert_type': 'Network Throughput',
            'severity': severity,
            'file_system_id': file_system_id,
            'current_metrics': {
                'network_utilization': round(current_utilization, 1),
                'provisioned_throughput_mbps': throughput_capacity,
                'trend': analyze_trend(network_trend.get('datapoints', []))
            },
            'analysis': generate_network_analysis(network_trend, throughput_capacity),
            'recommendations': generate_network_recommendations(network_trend, throughput_capacity, severity),
            'urgency': 'Scale immediately' if severity == 'HIGH' else 'Consider scaling',
            'original_alarm': sns_message.get('AlarmName', 'Unknown')
        }
        
    except ClientError as e:
        logger.error(f"Error handling network utilization alarm: {e}")
        return None

def handle_lambda_error_alarm(sns_message: Dict) -> Optional[Dict]:
    """Handle Lambda function error rate alarm"""
    return {
        'alert_type': 'Lambda Function Errors',
        'severity': 'HIGH',
        'file_system_id': 'N/A',
        'current_metrics': {
            'error_rate': 'Above threshold',
            'affected_function': 'FSx Lifecycle Management'
        },
        'analysis': [
            'Lambda function error rate has exceeded the acceptable threshold',
            'This may indicate issues with FSx API calls, permissions, or function code',
            'Automated lifecycle management may be impacted'
        ],
        'recommendations': [
            {
                'action': 'Check CloudWatch Logs',
                'description': 'Review Lambda function logs for specific error details',
                'priority': 'immediate'
            },
            {
                'action': 'Verify IAM Permissions',
                'description': 'Ensure Lambda execution role has necessary permissions',
                'priority': 'immediate'
            },
            {
                'action': 'Test Function Manually',
                'description': 'Invoke function manually to reproduce and diagnose issues',
                'priority': 'high'
            }
        ],
        'urgency': 'Immediate investigation required',
        'original_alarm': sns_message.get('AlarmName', 'Unknown')
    }

def handle_generic_alarm(file_system_id: str, sns_message: Dict) -> Dict:
    """Handle generic alarm with basic analysis"""
    return {
        'alert_type': 'Generic FSx Alert',
        'severity': 'MEDIUM',
        'file_system_id': file_system_id,
        'current_metrics': {
            'alarm_name': sns_message.get('AlarmName', 'Unknown'),
            'alarm_description': sns_message.get('AlarmDescription', 'No description')
        },
        'analysis': [
            'A CloudWatch alarm has been triggered for your FSx file system',
            'Please review the alarm details and file system metrics'
        ],
        'recommendations': [
            {
                'action': 'Review CloudWatch Metrics',
                'description': 'Check FSx metrics in CloudWatch console for detailed analysis',
                'priority': 'high'
            },
            {
                'action': 'Check File System Status',
                'description': 'Verify file system is healthy and accessible',
                'priority': 'medium'
            }
        ],
        'urgency': 'Review recommended',
        'original_alarm': sns_message.get('AlarmName', 'Unknown')
    }

def get_storage_utilization_trend(file_system_id: str) -> Dict:
    """Get recent storage utilization metrics for trend analysis"""
    return get_metric_trend(file_system_id, 'StorageUtilization', hours=6)

def get_cache_hit_ratio_trend(file_system_id: str) -> Dict:
    """Get recent cache hit ratio metrics for trend analysis"""
    return get_metric_trend(file_system_id, 'FileServerCacheHitRatio', hours=2)

def get_network_utilization_trend(file_system_id: str) -> Dict:
    """Get recent network utilization metrics for trend analysis"""
    return get_metric_trend(file_system_id, 'NetworkThroughputUtilization', hours=2)

def get_metric_trend(file_system_id: str, metric_name: str, hours: int = 2) -> Dict:
    """Generic function to get metric trend data"""
    try:
        end_time = datetime.datetime.utcnow()
        start_time = end_time - datetime.timedelta(hours=hours)
        
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName=metric_name,
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5-minute periods
            Statistics=['Average']
        )
        
        datapoints = sorted(response.get('Datapoints', []), key=lambda x: x['Timestamp'])
        current_value = datapoints[-1]['Average'] if datapoints else 0
        
        return {
            'current': current_value,
            'datapoints': datapoints,
            'metric_name': metric_name,
            'period_hours': hours
        }
        
    except ClientError as e:
        logger.error(f"Error getting {metric_name} trend: {e}")
        return {'current': 0, 'datapoints': [], 'metric_name': metric_name}

def analyze_trend(datapoints: List[Dict]) -> str:
    """Analyze trend direction from metric datapoints"""
    if len(datapoints) < 3:
        return 'insufficient_data'
    
    # Get first third and last third averages
    third = len(datapoints) // 3
    early_avg = sum(dp['Average'] for dp in datapoints[:third]) / third
    recent_avg = sum(dp['Average'] for dp in datapoints[-third:]) / third
    
    # Determine trend
    diff_percent = ((recent_avg - early_avg) / early_avg * 100) if early_avg > 0 else 0
    
    if diff_percent > 10:
        return 'increasing'
    elif diff_percent < -10:
        return 'decreasing'
    else:
        return 'stable'

def generate_storage_analysis(utilization_trend: Dict, capacity_gb: int, storage_type: str) -> List[str]:
    """Generate intelligent storage analysis"""
    current_util = utilization_trend.get('current', 0)
    trend = analyze_trend(utilization_trend.get('datapoints', []))
    
    analysis = [
        f"Current storage utilization: {current_util:.1f}% of {capacity_gb} GiB capacity",
        f"Storage type: {storage_type}",
        f"Utilization trend: {trend}"
    ]
    
    if current_util > 85:
        analysis.append("🚨 Critical: Storage utilization is dangerously high")
    elif current_util > 70:
        analysis.append("⚠️ Warning: Storage utilization is elevated")
    
    if trend == 'increasing':
        analysis.append("📈 Trend shows increasing storage usage - capacity planning needed")
    elif trend == 'decreasing':
        analysis.append("📉 Trend shows decreasing storage usage - potential for optimization")
    
    return analysis

def generate_storage_recommendations(utilization_trend: Dict, capacity_gb: int, storage_type: str, severity: str) -> List[Dict]:
    """Generate intelligent storage recommendations"""
    recommendations = []
    current_util = utilization_trend.get('current', 0)
    trend = analyze_trend(utilization_trend.get('datapoints', []))
    
    if severity == 'HIGH':
        recommendations.extend([
            {
                'action': 'Immediate Capacity Review',
                'description': f'Storage is at {current_util:.1f}% - review and clean up unnecessary files',
                'priority': 'immediate'
            },
            {
                'action': 'Plan Capacity Expansion',
                'description': 'Prepare to increase storage capacity if cleanup is insufficient',
                'priority': 'immediate'
            }
        ])
    
    if trend == 'increasing':
        recommendations.append({
            'action': 'Capacity Forecasting',
            'description': 'Implement monitoring to forecast when additional capacity will be needed',
            'priority': 'high'
        })
    
    if storage_type != 'INTELLIGENT_TIERING':
        recommendations.append({
            'action': 'Consider Intelligent Tiering',
            'description': 'Migrate to Intelligent Tiering for automatic cost optimization',
            'priority': 'medium'
        })
    
    recommendations.append({
        'action': 'Implement Data Lifecycle Policies',
        'description': 'Set up automated archiving and deletion policies for old data',
        'priority': 'medium'
    })
    
    return recommendations

def generate_cache_analysis(cache_trend: Dict, throughput_capacity: int) -> List[str]:
    """Generate intelligent cache analysis"""
    current_ratio = cache_trend.get('current', 0)
    trend = analyze_trend(cache_trend.get('datapoints', []))
    
    return [
        f"Current cache hit ratio: {current_ratio:.1f}%",
        f"Provisioned throughput: {throughput_capacity} MBps",
        f"Cache performance trend: {trend}",
        "💡 Optimal cache hit ratio should be above 80% for best performance" if current_ratio < 80 else "✅ Cache hit ratio is within acceptable range"
    ]

def generate_cache_recommendations(cache_trend: Dict, severity: str) -> List[Dict]:
    """Generate intelligent cache recommendations"""
    recommendations = []
    
    if severity == 'HIGH':
        recommendations.extend([
            {
                'action': 'Analyze Access Patterns',
                'description': 'Review file access patterns to understand cache misses',
                'priority': 'immediate'
            },
            {
                'action': 'Consider Cache Optimization',
                'description': 'Evaluate if cache configuration can be optimized',
                'priority': 'high'
            }
        ])
    
    recommendations.extend([
        {
            'action': 'Monitor Client Access Patterns',
            'description': 'Review how clients are accessing the file system',
            'priority': 'medium'
        },
        {
            'action': 'Optimize Data Layout',
            'description': 'Consider reorganizing frequently accessed data',
            'priority': 'low'
        }
    ])
    
    return recommendations

def generate_network_analysis(network_trend: Dict, throughput_capacity: int) -> List[str]:
    """Generate intelligent network analysis"""
    current_util = network_trend.get('current', 0)
    trend = analyze_trend(network_trend.get('datapoints', []))
    
    return [
        f"Current network utilization: {current_util:.1f}%",
        f"Provisioned throughput capacity: {throughput_capacity} MBps",
        f"Network usage trend: {trend}",
        "🚨 High network utilization may cause performance bottlenecks" if current_util > 80 else "✅ Network utilization is within acceptable range"
    ]

def generate_network_recommendations(network_trend: Dict, throughput_capacity: int, severity: str) -> List[Dict]:
    """Generate intelligent network recommendations"""
    recommendations = []
    
    if severity == 'HIGH':
        recommendations.extend([
            {
                'action': 'Scale Throughput Capacity',
                'description': f'Consider increasing throughput capacity from {throughput_capacity} MBps',
                'priority': 'immediate'
            },
            {
                'action': 'Analyze Client Connections',
                'description': 'Review client connection patterns and distribution',
                'priority': 'high'
            }
        ])
    
    recommendations.extend([
        {
            'action': 'Implement Connection Pooling',
            'description': 'Optimize client connection management',
            'priority': 'medium'
        },
        {
            'action': 'Load Distribution Review',
            'description': 'Ensure workload is properly distributed across clients',
            'priority': 'medium'
        }
    ])
    
    return recommendations

def send_intelligent_alert(topic_arn: str, alert_response: Dict):
    """Send intelligent alert notification via SNS"""
    try:
        # Format the intelligent alert message
        message_parts = [
            f"🔔 FSx Intelligent Alert - {alert_response['alert_type']}",
            f"Severity: {alert_response['severity']}",
            f"File System: {alert_response['file_system_id']}",
            f"Urgency: {alert_response['urgency']}",
            "",
            "📊 CURRENT METRICS:"
        ]
        
        # Add current metrics
        for key, value in alert_response.get('current_metrics', {}).items():
            formatted_key = key.replace('_', ' ').title()
            message_parts.append(f"  • {formatted_key}: {value}")
        
        message_parts.append("")
        message_parts.append("🔍 ANALYSIS:")
        
        # Add analysis points
        for point in alert_response.get('analysis', []):
            message_parts.append(f"  • {point}")
        
        message_parts.append("")
        message_parts.append("💡 RECOMMENDATIONS:")
        
        # Add recommendations
        for rec in alert_response.get('recommendations', []):
            priority_emoji = {"immediate": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"}.get(rec.get('priority', 'medium'), "🔵")
            message_parts.append(f"  {priority_emoji} {rec['action']}: {rec['description']}")
        
        message_parts.extend([
            "",
            f"Original Alarm: {alert_response['original_alarm']}",
            f"Generated: {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}"
        ])
        
        message = "\n".join(message_parts)
        
        # Send the intelligent alert
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=f"🤖 FSx Intelligent Alert: {alert_response['alert_type']} - {alert_response['severity']}"
        )
        
        logger.info("Intelligent alert sent successfully")
        
    except ClientError as e:
        logger.error(f"Error sending intelligent alert: {e}")

def create_error_response(error_message: str) -> Dict:
    """Create standardized error response"""
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.datetime.utcnow().isoformat()
        })
    }