"""
Lambda function for EKS cost optimization automation
This function analyzes EKS cluster metrics and triggers cost optimization alerts
"""

import boto3
import json
import os
from datetime import datetime, timedelta
from typing import Dict, Any, Optional


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for cost optimization automation
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    
    # Get environment variables
    cluster_name = os.environ.get('CLUSTER_NAME', '')
    namespace = os.environ.get('NAMESPACE', 'cost-optimization')
    topic_arn = os.environ.get('TOPIC_ARN', '')
    threshold = float(os.environ.get('THRESHOLD', '30'))
    
    print(f"Processing cost optimization for cluster: {cluster_name}")
    print(f"Monitoring namespace: {namespace}")
    print(f"Utilization threshold: {threshold}%")
    
    try:
        # Initialize AWS clients
        cloudwatch = boto3.client('cloudwatch')
        sns = boto3.client('sns')
        
        # Get current time for metric queries
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=2)  # Look back 2 hours
        
        # Query CPU utilization metrics
        cpu_utilization = get_metric_average(
            cloudwatch=cloudwatch,
            namespace='ContainerInsights',
            metric_name='pod_cpu_utilization',
            dimensions=[{'Name': 'Namespace', 'Value': namespace}],
            start_time=start_time,
            end_time=end_time
        )
        
        # Query memory utilization metrics
        memory_utilization = get_metric_average(
            cloudwatch=cloudwatch,
            namespace='ContainerInsights',
            metric_name='pod_memory_utilization',
            dimensions=[{'Name': 'Namespace', 'Value': namespace}],
            start_time=start_time,
            end_time=end_time
        )
        
        # Query resource reservation metrics
        cpu_reserved = get_metric_average(
            cloudwatch=cloudwatch,
            namespace='ContainerInsights',
            metric_name='pod_cpu_reserved_capacity',
            dimensions=[{'Name': 'Namespace', 'Value': namespace}],
            start_time=start_time,
            end_time=end_time
        )
        
        memory_reserved = get_metric_average(
            cloudwatch=cloudwatch,
            namespace='ContainerInsights',
            metric_name='pod_memory_reserved_capacity',
            dimensions=[{'Name': 'Namespace', 'Value': namespace}],
            start_time=start_time,
            end_time=end_time
        )
        
        # Calculate waste metrics
        cpu_waste = max(0, cpu_reserved - cpu_utilization) if cpu_reserved and cpu_utilization else 0
        memory_waste = max(0, memory_reserved - memory_utilization) if memory_reserved and memory_utilization else 0
        
        # Create cost optimization report
        report = {
            'cluster_name': cluster_name,
            'namespace': namespace,
            'timestamp': end_time.isoformat(),
            'metrics': {
                'cpu_utilization': cpu_utilization,
                'memory_utilization': memory_utilization,
                'cpu_reserved': cpu_reserved,
                'memory_reserved': memory_reserved,
                'cpu_waste_percentage': cpu_waste,
                'memory_waste_percentage': memory_waste
            },
            'recommendations': []
        }
        
        # Generate recommendations based on utilization patterns
        if cpu_utilization and cpu_utilization < threshold:
            report['recommendations'].append({
                'type': 'CPU_OPTIMIZATION',
                'severity': 'HIGH' if cpu_utilization < threshold / 2 else 'MEDIUM',
                'message': f'CPU utilization ({cpu_utilization:.1f}%) is below threshold ({threshold}%). Consider reducing CPU requests.',
                'potential_savings': f'{cpu_waste:.1f}% CPU resources could be reclaimed'
            })
        
        if memory_utilization and memory_utilization < threshold:
            report['recommendations'].append({
                'type': 'MEMORY_OPTIMIZATION',
                'severity': 'HIGH' if memory_utilization < threshold / 2 else 'MEDIUM',
                'message': f'Memory utilization ({memory_utilization:.1f}%) is below threshold ({threshold}%). Consider reducing memory requests.',
                'potential_savings': f'{memory_waste:.1f}% memory resources could be reclaimed'
            })
        
        # Send alert if significant waste is detected
        if report['recommendations'] and topic_arn:
            alert_message = create_alert_message(report)
            
            sns.publish(
                TopicArn=topic_arn,
                Message=alert_message,
                Subject=f'EKS Cost Optimization Alert - {cluster_name}'
            )
            
            print("Cost optimization alert sent successfully")
        
        # Log the report
        print(f"Cost optimization report: {json.dumps(report, indent=2)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed successfully',
                'report': report
            })
        }
        
    except Exception as e:
        error_message = f"Error in cost optimization analysis: {str(e)}"
        print(error_message)
        
        # Send error alert if possible
        if topic_arn:
            try:
                sns = boto3.client('sns')
                sns.publish(
                    TopicArn=topic_arn,
                    Message=f"EKS Cost Optimization Lambda failed: {error_message}",
                    Subject=f'EKS Cost Optimization Error - {cluster_name}'
                )
            except Exception as sns_error:
                print(f"Failed to send error alert: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Cost optimization analysis failed',
                'error': error_message
            })
        }


def get_metric_average(
    cloudwatch: Any,
    namespace: str,
    metric_name: str,
    dimensions: list,
    start_time: datetime,
    end_time: datetime
) -> Optional[float]:
    """
    Get average value for a CloudWatch metric
    
    Args:
        cloudwatch: CloudWatch client
        namespace: CloudWatch namespace
        metric_name: Name of the metric
        dimensions: Metric dimensions
        start_time: Start time for query
        end_time: End time for query
        
    Returns:
        Average metric value or None if no data
    """
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5 minutes
            Statistics=['Average']
        )
        
        if response['Datapoints']:
            # Calculate average across all datapoints
            total = sum(dp['Average'] for dp in response['Datapoints'])
            count = len(response['Datapoints'])
            return total / count
        
        return None
        
    except Exception as e:
        print(f"Error retrieving metric {metric_name}: {str(e)}")
        return None


def create_alert_message(report: Dict[str, Any]) -> str:
    """
    Create formatted alert message for SNS
    
    Args:
        report: Cost optimization report
        
    Returns:
        Formatted alert message
    """
    message_lines = [
        f"EKS Cost Optimization Alert",
        f"==========================",
        f"",
        f"Cluster: {report['cluster_name']}",
        f"Namespace: {report['namespace']}",
        f"Timestamp: {report['timestamp']}",
        f"",
        f"Current Resource Utilization:",
    ]
    
    metrics = report['metrics']
    if metrics.get('cpu_utilization'):
        message_lines.append(f"  - CPU: {metrics['cpu_utilization']:.1f}%")
    if metrics.get('memory_utilization'):
        message_lines.append(f"  - Memory: {metrics['memory_utilization']:.1f}%")
    
    if metrics.get('cpu_reserved') or metrics.get('memory_reserved'):
        message_lines.extend([
            f"",
            f"Resource Reservation:",
        ])
        if metrics.get('cpu_reserved'):
            message_lines.append(f"  - CPU Reserved: {metrics['cpu_reserved']:.1f}%")
        if metrics.get('memory_reserved'):
            message_lines.append(f"  - Memory Reserved: {metrics['memory_reserved']:.1f}%")
    
    if report['recommendations']:
        message_lines.extend([
            f"",
            f"Recommendations:",
        ])
        
        for i, rec in enumerate(report['recommendations'], 1):
            message_lines.extend([
                f"  {i}. [{rec['severity']}] {rec['type']}",
                f"     {rec['message']}",
                f"     {rec['potential_savings']}",
            ])
    
    message_lines.extend([
        f"",
        f"Next Steps:",
        f"1. Review VPA recommendations for affected workloads",
        f"2. Consider adjusting resource requests and limits",
        f"3. Monitor application performance after changes",
        f"4. Update deployment configurations accordingly",
        f"",
        f"Dashboard: View detailed metrics in CloudWatch Container Insights",
    ])
    
    return "\n".join(message_lines)


def analyze_trends(datapoints: list) -> Dict[str, Any]:
    """
    Analyze trends in metric datapoints
    
    Args:
        datapoints: List of CloudWatch datapoints
        
    Returns:
        Trend analysis results
    """
    if len(datapoints) < 2:
        return {'trend': 'insufficient_data'}
    
    # Sort by timestamp
    sorted_points = sorted(datapoints, key=lambda x: x['Timestamp'])
    values = [dp['Average'] for dp in sorted_points]
    
    # Calculate simple trend
    first_half = values[:len(values)//2]
    second_half = values[len(values)//2:]
    
    first_avg = sum(first_half) / len(first_half)
    second_avg = sum(second_half) / len(second_half)
    
    change_percent = ((second_avg - first_avg) / first_avg) * 100 if first_avg > 0 else 0
    
    if abs(change_percent) < 5:
        trend = 'stable'
    elif change_percent > 0:
        trend = 'increasing'
    else:
        trend = 'decreasing'
    
    return {
        'trend': trend,
        'change_percent': change_percent,
        'first_period_avg': first_avg,
        'second_period_avg': second_avg
    }