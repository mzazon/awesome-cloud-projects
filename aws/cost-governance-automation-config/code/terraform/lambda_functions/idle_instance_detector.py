"""
Idle Instance Detection Lambda Function for Cost Governance
Analyzes EC2 instances for low CPU utilization and tags idle resources
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for idle instance detection
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing execution results
    """
    logger.info(f"Starting idle instance detection. Event: {json.dumps(event)}")
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Get CPU threshold from environment or use default
        cpu_threshold = float(os.environ.get('CPU_THRESHOLD', '${cpu_threshold}'))
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        if not sns_topic_arn:
            raise ValueError("SNS_TOPIC_ARN environment variable not set")
        
        # Get all running instances with cost optimization enabled
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']},
                {'Name': 'tag:CostOptimization', 'Values': ['enabled', 'true']}
            ]
        )
        
        idle_instances = []
        total_instances_checked = 0
        
        # Process each instance
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                total_instances_checked += 1
                instance_id = instance['InstanceId']
                instance_type = instance['InstanceType']
                launch_time = instance['LaunchTime']
                
                logger.info(f"Checking instance {instance_id} ({instance_type})")
                
                # Check CPU utilization for last 7 days
                end_time = datetime.utcnow()
                start_time = end_time - timedelta(days=7)
                
                try:
                    cpu_response = cloudwatch.get_metric_statistics(
                        Namespace='AWS/EC2',
                        MetricName='CPUUtilization',
                        Dimensions=[
                            {'Name': 'InstanceId', 'Value': instance_id}
                        ],
                        StartTime=start_time,
                        EndTime=end_time,
                        Period=3600,  # 1 hour periods
                        Statistics=['Average']
                    )
                    
                    if cpu_response['Datapoints']:
                        # Calculate average CPU utilization
                        datapoints = cpu_response['Datapoints']
                        avg_cpu = sum(dp['Average'] for dp in datapoints) / len(datapoints)
                        max_cpu = max(dp['Average'] for dp in datapoints)
                        min_cpu = min(dp['Average'] for dp in datapoints)
                        
                        logger.info(f"Instance {instance_id}: Avg CPU: {avg_cpu:.2f}%, Max: {max_cpu:.2f}%, Min: {min_cpu:.2f}%")
                        
                        # Check if instance is idle (below threshold)
                        if avg_cpu < cpu_threshold:
                            # Calculate estimated monthly cost savings (rough estimates)
                            cost_estimates = {
                                't3.micro': 8.50, 't3.small': 16.79, 't3.medium': 33.58,
                                't3.large': 67.16, 't3.xlarge': 134.32, 't3.2xlarge': 268.64,
                                'm5.large': 87.60, 'm5.xlarge': 175.20, 'm5.2xlarge': 350.40,
                                'c5.large': 77.76, 'c5.xlarge': 155.52, 'c5.2xlarge': 311.04
                            }
                            estimated_monthly_cost = cost_estimates.get(instance_type, 100.0)
                            
                            idle_instance_data = {
                                'InstanceId': instance_id,
                                'InstanceType': instance_type,
                                'AvgCPU': round(avg_cpu, 2),
                                'MaxCPU': round(max_cpu, 2),
                                'MinCPU': round(min_cpu, 2),
                                'LaunchTime': launch_time.isoformat(),
                                'DatapointsCount': len(datapoints),
                                'EstimatedMonthlyCost': estimated_monthly_cost,
                                'PotentialMonthlySavings': estimated_monthly_cost * 0.8  # 80% savings if stopped
                            }
                            
                            idle_instances.append(idle_instance_data)
                            
                            # Tag instance as idle for tracking
                            try:
                                ec2.create_tags(
                                    Resources=[instance_id],
                                    Tags=[
                                        {'Key': 'CostOptimization:Status', 'Value': 'Idle'},
                                        {'Key': 'CostOptimization:DetectedDate', 'Value': datetime.utcnow().isoformat()},
                                        {'Key': 'CostOptimization:AvgCPU', 'Value': str(round(avg_cpu, 2))},
                                        {'Key': 'CostOptimization:Threshold', 'Value': str(cpu_threshold)}
                                    ]
                                )
                                logger.info(f"Tagged instance {instance_id} as idle")
                            except Exception as tag_error:
                                logger.error(f"Failed to tag instance {instance_id}: {str(tag_error)}")
                        
                        else:
                            logger.info(f"Instance {instance_id} is active (CPU: {avg_cpu:.2f}%)")
                    
                    else:
                        logger.warning(f"No CPU metrics available for instance {instance_id}")
                
                except Exception as metric_error:
                    logger.error(f"Error checking metrics for instance {instance_id}: {str(metric_error)}")
                    continue
        
        # Calculate total potential savings
        total_potential_savings = sum(instance['PotentialMonthlySavings'] for instance in idle_instances)
        
        # Send notification if idle instances found
        if idle_instances:
            message = {
                'Alert': 'Idle EC2 Instances Detected',
                'Timestamp': datetime.utcnow().isoformat(),
                'Summary': {
                    'TotalInstancesChecked': total_instances_checked,
                    'IdleInstancesFound': len(idle_instances),
                    'TotalPotentialMonthlySavings': f'${total_potential_savings:.2f}'
                },
                'IdleInstances': idle_instances,
                'Recommendations': [
                    'Review idle instances for potential right-sizing or termination',
                    'Consider stopping non-critical idle instances during off-hours',
                    'Evaluate if workloads can be moved to smaller instance types',
                    'Implement auto-scaling to handle variable workloads'
                ],
                'NextSteps': [
                    'Verify instances are truly idle and not experiencing temporary low usage',
                    'Check with application owners before taking action',
                    'Consider implementing scheduled start/stop for development instances'
                ]
            }
            
            try:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Subject=f'Cost Governance Alert: {len(idle_instances)} Idle EC2 Instances Detected',
                    Message=json.dumps(message, indent=2)
                )
                logger.info(f"Sent notification about {len(idle_instances)} idle instances")
            except Exception as sns_error:
                logger.error(f"Failed to send SNS notification: {str(sns_error)}")
        
        else:
            logger.info("No idle instances detected")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed {total_instances_checked} instances',
                'idle_instances_found': len(idle_instances),
                'total_potential_monthly_savings': f'${total_potential_savings:.2f}',
                'cpu_threshold_used': cpu_threshold,
                'idle_instances': idle_instances
            }, default=str)
        }
    
    except Exception as e:
        logger.error(f"Error in idle instance detection: {str(e)}")
        
        # Send error notification
        try:
            error_message = {
                'Alert': 'Error in Idle Instance Detection',
                'Timestamp': datetime.utcnow().isoformat(),
                'Error': str(e),
                'Function': context.function_name if context else 'Unknown',
                'RequestId': context.aws_request_id if context else 'Unknown'
            }
            
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN', ''),
                Subject='Cost Governance Error: Idle Instance Detection Failed',
                Message=json.dumps(error_message, indent=2)
            )
        except:
            pass  # Avoid cascading errors
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process idle instance detection'
            })
        }


def get_instance_cost_estimate(instance_type: str, region: str = 'us-east-1') -> float:
    """
    Get estimated monthly cost for an EC2 instance type
    
    Args:
        instance_type: EC2 instance type
        region: AWS region
        
    Returns:
        Estimated monthly cost in USD
    """
    # Simplified cost estimates for common instance types (US East 1)
    # Note: These are approximate and should be updated with current pricing
    cost_estimates = {
        # T3 instances (burstable)
        't3.nano': 3.80, 't3.micro': 7.59, 't3.small': 15.18, 't3.medium': 30.37,
        't3.large': 60.74, 't3.xlarge': 121.47, 't3.2xlarge': 242.94,
        
        # M5 instances (general purpose)
        'm5.large': 69.35, 'm5.xlarge': 138.70, 'm5.2xlarge': 277.40,
        'm5.4xlarge': 554.80, 'm5.8xlarge': 1109.60,
        
        # C5 instances (compute optimized)
        'c5.large': 61.56, 'c5.xlarge': 123.12, 'c5.2xlarge': 246.24,
        'c5.4xlarge': 492.48, 'c5.9xlarge': 1107.59,
        
        # R5 instances (memory optimized)
        'r5.large': 90.50, 'r5.xlarge': 181.00, 'r5.2xlarge': 362.00,
        'r5.4xlarge': 724.00, 'r5.8xlarge': 1448.00
    }
    
    return cost_estimates.get(instance_type, 100.0)  # Default estimate for unknown types