import json
import boto3
from datetime import datetime, timedelta
import os

def lambda_handler(event, context):
    """
    Lambda function to analyze container performance and provide optimization recommendations.
    
    This function analyzes CPU and memory utilization metrics from CloudWatch Container Insights
    and provides actionable recommendations for optimizing container resource allocation.
    """
    
    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    ecs_client = boto3.client('ecs')
    eks_client = boto3.client('eks')
    sns_client = boto3.client('sns')
    
    # Get environment variables
    eks_cluster_name = os.environ.get('EKS_CLUSTER_NAME', '${eks_cluster_name}')
    ecs_cluster_name = os.environ.get('ECS_CLUSTER_NAME', '${ecs_cluster_name}')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '')
    
    # Time range for analysis (last 2 hours)
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=2)
    
    recommendations = []
    
    try:
        # Analyze EKS cluster metrics
        eks_recommendations = analyze_eks_metrics(
            cloudwatch, eks_cluster_name, start_time, end_time
        )
        recommendations.extend(eks_recommendations)
        
        # Analyze ECS cluster metrics
        ecs_recommendations = analyze_ecs_metrics(
            cloudwatch, ecs_cluster_name, start_time, end_time
        )
        recommendations.extend(ecs_recommendations)
        
        # Generate cost optimization recommendations
        cost_recommendations = generate_cost_optimization_recommendations(
            cloudwatch, eks_cluster_name, ecs_cluster_name, start_time, end_time
        )
        recommendations.extend(cost_recommendations)
        
        # Send recommendations via SNS if there are high-priority items
        high_priority_recommendations = [
            r for r in recommendations if r.get('severity') == 'HIGH'
        ]
        
        if high_priority_recommendations and sns_topic_arn:
            send_sns_notification(
                sns_client, sns_topic_arn, high_priority_recommendations
            )
        
        # Return comprehensive analysis
        return {
            'statusCode': 200,
            'body': json.dumps({
                'recommendations': recommendations,
                'analysis_timestamp': datetime.utcnow().isoformat(),
                'clusters_analyzed': {
                    'eks': eks_cluster_name,
                    'ecs': ecs_cluster_name
                },
                'high_priority_count': len(high_priority_recommendations),
                'total_recommendations': len(recommendations)
            }, indent=2)
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def analyze_eks_metrics(cloudwatch, cluster_name, start_time, end_time):
    """Analyze EKS cluster metrics and provide recommendations."""
    recommendations = []
    
    try:
        # Get CPU utilization metrics
        cpu_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ContainerInsights',
            MetricName='pod_cpu_utilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum', 'Minimum']
        )
        
        # Get memory utilization metrics
        memory_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ContainerInsights',
            MetricName='pod_memory_utilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum', 'Minimum']
        )
        
        # Analyze CPU metrics
        if cpu_metrics['Datapoints']:
            cpu_datapoints = cpu_metrics['Datapoints']
            avg_cpu = sum(point['Average'] for point in cpu_datapoints) / len(cpu_datapoints)
            max_cpu = max(point['Maximum'] for point in cpu_datapoints)
            min_cpu = min(point['Minimum'] for point in cpu_datapoints)
            
            # CPU optimization recommendations
            if avg_cpu < 20:
                recommendations.append({
                    'type': 'CPU_OPTIMIZATION',
                    'category': 'COST_REDUCTION',
                    'cluster': cluster_name,
                    'cluster_type': 'EKS',
                    'metric': 'CPU',
                    'message': f'Average CPU utilization is {avg_cpu:.1f}%. Consider reducing CPU requests to optimize costs.',
                    'severity': 'MEDIUM',
                    'current_value': avg_cpu,
                    'threshold': 20,
                    'action': 'REDUCE_CPU_REQUESTS',
                    'potential_savings': 'Up to 30% on compute costs'
                })
            elif max_cpu > 90:
                recommendations.append({
                    'type': 'CPU_SCALING',
                    'category': 'PERFORMANCE',
                    'cluster': cluster_name,
                    'cluster_type': 'EKS',
                    'metric': 'CPU',
                    'message': f'Maximum CPU utilization reached {max_cpu:.1f}%. Consider increasing CPU limits or adding nodes.',
                    'severity': 'HIGH',
                    'current_value': max_cpu,
                    'threshold': 90,
                    'action': 'INCREASE_CPU_LIMITS',
                    'potential_impact': 'Prevents CPU throttling and improves performance'
                })
            elif avg_cpu > 70:
                recommendations.append({
                    'type': 'CPU_MONITORING',
                    'category': 'CAPACITY_PLANNING',
                    'cluster': cluster_name,
                    'cluster_type': 'EKS',
                    'metric': 'CPU',
                    'message': f'Average CPU utilization is {avg_cpu:.1f}%. Monitor closely and consider scaling preparation.',
                    'severity': 'LOW',
                    'current_value': avg_cpu,
                    'threshold': 70,
                    'action': 'MONITOR_CLOSELY',
                    'potential_impact': 'Proactive capacity planning'
                })
        
        # Analyze memory metrics
        if memory_metrics['Datapoints']:
            memory_datapoints = memory_metrics['Datapoints']
            avg_memory = sum(point['Average'] for point in memory_datapoints) / len(memory_datapoints)
            max_memory = max(point['Maximum'] for point in memory_datapoints)
            min_memory = min(point['Minimum'] for point in memory_datapoints)
            
            # Memory optimization recommendations
            if avg_memory < 25:
                recommendations.append({
                    'type': 'MEMORY_OPTIMIZATION',
                    'category': 'COST_REDUCTION',
                    'cluster': cluster_name,
                    'cluster_type': 'EKS',
                    'metric': 'Memory',
                    'message': f'Average memory utilization is {avg_memory:.1f}%. Consider reducing memory requests.',
                    'severity': 'MEDIUM',
                    'current_value': avg_memory,
                    'threshold': 25,
                    'action': 'REDUCE_MEMORY_REQUESTS',
                    'potential_savings': 'Up to 25% on memory costs'
                })
            elif max_memory > 85:
                recommendations.append({
                    'type': 'MEMORY_SCALING',
                    'category': 'PERFORMANCE',
                    'cluster': cluster_name,
                    'cluster_type': 'EKS',
                    'metric': 'Memory',
                    'message': f'Maximum memory utilization reached {max_memory:.1f}%. Consider increasing memory limits.',
                    'severity': 'HIGH',
                    'current_value': max_memory,
                    'threshold': 85,
                    'action': 'INCREASE_MEMORY_LIMITS',
                    'potential_impact': 'Prevents OOM kills and improves stability'
                })
        
        # Check for pod restart patterns
        restart_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ContainerInsights',
            MetricName='pod_number_of_container_restarts',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Sum']
        )
        
        if restart_metrics['Datapoints']:
            total_restarts = sum(point['Sum'] for point in restart_metrics['Datapoints'])
            if total_restarts > 5:
                recommendations.append({
                    'type': 'RELIABILITY_ISSUE',
                    'category': 'STABILITY',
                    'cluster': cluster_name,
                    'cluster_type': 'EKS',
                    'metric': 'Container Restarts',
                    'message': f'Detected {total_restarts} container restarts. Investigate pod stability issues.',
                    'severity': 'HIGH',
                    'current_value': total_restarts,
                    'threshold': 5,
                    'action': 'INVESTIGATE_RESTARTS',
                    'potential_impact': 'Improves application reliability'
                })
        
    except Exception as e:
        print(f"Error analyzing EKS metrics: {str(e)}")
        recommendations.append({
            'type': 'ANALYSIS_ERROR',
            'category': 'SYSTEM',
            'cluster': cluster_name,
            'cluster_type': 'EKS',
            'message': f'Error analyzing EKS metrics: {str(e)}',
            'severity': 'LOW',
            'action': 'CHECK_PERMISSIONS'
        })
    
    return recommendations

def analyze_ecs_metrics(cloudwatch, cluster_name, start_time, end_time):
    """Analyze ECS cluster metrics and provide recommendations."""
    recommendations = []
    
    try:
        # Get ECS service metrics
        cpu_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ECS',
            MetricName='CPUUtilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        memory_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ECS',
            MetricName='MemoryUtilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze CPU metrics
        if cpu_metrics['Datapoints']:
            cpu_datapoints = cpu_metrics['Datapoints']
            avg_cpu = sum(point['Average'] for point in cpu_datapoints) / len(cpu_datapoints)
            max_cpu = max(point['Maximum'] for point in cpu_datapoints)
            
            if avg_cpu < 15:
                recommendations.append({
                    'type': 'ECS_CPU_OPTIMIZATION',
                    'category': 'COST_REDUCTION',
                    'cluster': cluster_name,
                    'cluster_type': 'ECS',
                    'metric': 'CPU',
                    'message': f'ECS average CPU utilization is {avg_cpu:.1f}%. Consider reducing task CPU allocation.',
                    'severity': 'MEDIUM',
                    'current_value': avg_cpu,
                    'threshold': 15,
                    'action': 'REDUCE_TASK_CPU',
                    'potential_savings': 'Up to 35% on Fargate costs'
                })
            elif max_cpu > 80:
                recommendations.append({
                    'type': 'ECS_CPU_SCALING',
                    'category': 'PERFORMANCE',
                    'cluster': cluster_name,
                    'cluster_type': 'ECS',
                    'metric': 'CPU',
                    'message': f'ECS maximum CPU utilization reached {max_cpu:.1f}%. Consider increasing task CPU or scaling out.',
                    'severity': 'HIGH',
                    'current_value': max_cpu,
                    'threshold': 80,
                    'action': 'INCREASE_TASK_CPU',
                    'potential_impact': 'Improves task performance and response times'
                })
        
        # Analyze memory metrics
        if memory_metrics['Datapoints']:
            memory_datapoints = memory_metrics['Datapoints']
            avg_memory = sum(point['Average'] for point in memory_datapoints) / len(memory_datapoints)
            max_memory = max(point['Maximum'] for point in memory_datapoints)
            
            if avg_memory < 20:
                recommendations.append({
                    'type': 'ECS_MEMORY_OPTIMIZATION',
                    'category': 'COST_REDUCTION',
                    'cluster': cluster_name,
                    'cluster_type': 'ECS',
                    'metric': 'Memory',
                    'message': f'ECS average memory utilization is {avg_memory:.1f}%. Consider reducing task memory allocation.',
                    'severity': 'MEDIUM',
                    'current_value': avg_memory,
                    'threshold': 20,
                    'action': 'REDUCE_TASK_MEMORY',
                    'potential_savings': 'Up to 30% on memory costs'
                })
            elif max_memory > 80:
                recommendations.append({
                    'type': 'ECS_MEMORY_SCALING',
                    'category': 'PERFORMANCE',
                    'cluster': cluster_name,
                    'cluster_type': 'ECS',
                    'metric': 'Memory',
                    'message': f'ECS maximum memory utilization reached {max_memory:.1f}%. Consider increasing task memory.',
                    'severity': 'HIGH',
                    'current_value': max_memory,
                    'threshold': 80,
                    'action': 'INCREASE_TASK_MEMORY',
                    'potential_impact': 'Prevents memory exhaustion and task failures'
                })
        
    except Exception as e:
        print(f"Error analyzing ECS metrics: {str(e)}")
        recommendations.append({
            'type': 'ANALYSIS_ERROR',
            'category': 'SYSTEM',
            'cluster': cluster_name,
            'cluster_type': 'ECS',
            'message': f'Error analyzing ECS metrics: {str(e)}',
            'severity': 'LOW',
            'action': 'CHECK_PERMISSIONS'
        })
    
    return recommendations

def generate_cost_optimization_recommendations(cloudwatch, eks_cluster, ecs_cluster, start_time, end_time):
    """Generate cost optimization recommendations based on overall usage patterns."""
    recommendations = []
    
    try:
        # Check for consistent low utilization patterns
        # This is a simplified example - in production, you'd want more sophisticated analysis
        
        recommendations.append({
            'type': 'COST_OPTIMIZATION',
            'category': 'BEST_PRACTICE',
            'cluster': 'All',
            'cluster_type': 'General',
            'message': 'Consider implementing Horizontal Pod Autoscaler (HPA) for automatic scaling based on metrics.',
            'severity': 'LOW',
            'action': 'IMPLEMENT_HPA',
            'potential_savings': 'Up to 40% during low-traffic periods'
        })
        
        recommendations.append({
            'type': 'COST_OPTIMIZATION',
            'category': 'BEST_PRACTICE',
            'cluster': 'All',
            'cluster_type': 'General',
            'message': 'Consider using Spot instances for non-critical workloads to reduce costs.',
            'severity': 'LOW',
            'action': 'EVALUATE_SPOT_INSTANCES',
            'potential_savings': 'Up to 70% on compute costs'
        })
        
        recommendations.append({
            'type': 'MONITORING_OPTIMIZATION',
            'category': 'OBSERVABILITY',
            'cluster': 'All',
            'cluster_type': 'General',
            'message': 'Optimize CloudWatch log retention policies to balance cost and compliance requirements.',
            'severity': 'LOW',
            'action': 'OPTIMIZE_LOG_RETENTION',
            'potential_savings': 'Up to 50% on logging costs'
        })
        
    except Exception as e:
        print(f"Error generating cost optimization recommendations: {str(e)}")
    
    return recommendations

def send_sns_notification(sns_client, topic_arn, high_priority_recommendations):
    """Send SNS notification for high-priority recommendations."""
    try:
        message = "High Priority Container Optimization Recommendations:\n\n"
        
        for i, rec in enumerate(high_priority_recommendations, 1):
            message += f"{i}. {rec['message']}\n"
            message += f"   Cluster: {rec['cluster']} ({rec['cluster_type']})\n"
            message += f"   Action: {rec['action']}\n"
            message += f"   Impact: {rec.get('potential_impact', 'N/A')}\n\n"
        
        message += f"Total High Priority Issues: {len(high_priority_recommendations)}\n"
        message += f"Analysis Time: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC"
        
        sns_client.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject="Container Performance Optimization Alert"
        )
        
        print(f"SNS notification sent for {len(high_priority_recommendations)} high-priority recommendations")
        
    except Exception as e:
        print(f"Error sending SNS notification: {str(e)}")

# Example usage for local testing
if __name__ == "__main__":
    # This allows for local testing with mock event and context
    test_event = {}
    test_context = {}
    
    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2))