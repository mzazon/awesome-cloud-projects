import boto3
import json
import logging
import os
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to detect and report StackSet drift across organization accounts.
    
    This function:
    1. Initiates drift detection for the specified StackSet
    2. Monitors the drift detection operation
    3. Collects drift results from all stack instances
    4. Sends notifications for any detected drift
    5. Returns comprehensive drift report
    
    Args:
        event: Lambda event containing stackset_name and sns_topic_arn
        context: Lambda context object
    
    Returns:
        Dict containing drift detection results and operation status
    """
    try:
        # Initialize AWS clients
        cf_client = boto3.client('cloudformation')
        sns_client = boto3.client('sns')
        
        # Get configuration from environment variables or event
        stackset_name = event.get('stackset_name', os.environ.get('STACKSET_NAME', '${stackset_name}'))
        sns_topic_arn = event.get('sns_topic_arn', os.environ.get('SNS_TOPIC_ARN'))
        
        if not stackset_name:
            raise ValueError("StackSet name is required")
        
        logger.info(f"Starting drift detection for StackSet: {stackset_name}")
        
        # Initiate drift detection
        try:
            response = cf_client.detect_stack_set_drift(StackSetName=stackset_name)
            operation_id = response['OperationId']
            logger.info(f"Drift detection initiated with operation ID: {operation_id}")
        except Exception as e:
            logger.error(f"Failed to initiate drift detection: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': f'Failed to initiate drift detection: {str(e)}',
                    'stackset_name': stackset_name
                })
            }
        
        # Wait for operation to complete with timeout
        max_wait_time = 300  # 5 minutes maximum wait time
        wait_interval = 30   # Check every 30 seconds
        waited_time = 0
        
        while waited_time < max_wait_time:
            try:
                operation_response = cf_client.describe_stack_set_operation(
                    StackSetName=stackset_name,
                    OperationId=operation_id
                )
                
                operation_status = operation_response['Operation']['Status']
                
                if operation_status in ['SUCCEEDED', 'FAILED', 'STOPPED']:
                    logger.info(f"Drift detection operation completed with status: {operation_status}")
                    break
                elif operation_status in ['RUNNING']:
                    logger.info(f"Drift detection operation still running, waiting {wait_interval} seconds...")
                    import time
                    time.sleep(wait_interval)
                    waited_time += wait_interval
                else:
                    logger.warning(f"Unexpected operation status: {operation_status}")
                    break
                    
            except Exception as e:
                logger.error(f"Error checking operation status: {str(e)}")
                break
        
        # Check if operation timed out
        if waited_time >= max_wait_time:
            logger.warning(f"Drift detection operation timed out after {max_wait_time} seconds")
            return {
                'statusCode': 202,
                'body': json.dumps({
                    'message': 'Drift detection operation timed out, check AWS console for results',
                    'stackset_name': stackset_name,
                    'operation_id': operation_id
                })
            }
        
        # Get final operation results
        try:
            final_operation = cf_client.describe_stack_set_operation(
                StackSetName=stackset_name,
                OperationId=operation_id
            )
            
            operation_status = final_operation['Operation']['Status']
            
            if operation_status != 'SUCCEEDED':
                logger.error(f"Drift detection failed with status: {operation_status}")
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'error': f'Drift detection failed with status: {operation_status}',
                        'stackset_name': stackset_name,
                        'operation_id': operation_id
                    })
                }
                
        except Exception as e:
            logger.error(f"Error getting final operation results: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': f'Error getting operation results: {str(e)}',
                    'stackset_name': stackset_name,
                    'operation_id': operation_id
                })
            }
        
        # Get stack instances with drift status
        try:
            stack_instances = cf_client.list_stack_instances(
                StackSetName=stackset_name,
                MaxResults=100
            )
            
            all_instances = []
            drifted_instances = []
            
            # Process all stack instances
            for instance in stack_instances['Summaries']:
                instance_info = {
                    'Account': instance['Account'],
                    'Region': instance['Region'],
                    'Status': instance['Status'],
                    'DriftStatus': instance.get('DriftStatus', 'NOT_CHECKED'),
                    'StatusReason': instance.get('StatusReason', ''),
                    'LastDriftCheckTimestamp': instance.get('LastDriftCheckTimestamp', '').isoformat() if instance.get('LastDriftCheckTimestamp') else None
                }
                
                all_instances.append(instance_info)
                
                # Collect drifted instances
                if instance.get('DriftStatus') == 'DRIFTED':
                    drifted_instances.append(instance_info)
            
            # Handle pagination if needed
            next_token = stack_instances.get('NextToken')
            while next_token:
                stack_instances = cf_client.list_stack_instances(
                    StackSetName=stackset_name,
                    NextToken=next_token,
                    MaxResults=100
                )
                
                for instance in stack_instances['Summaries']:
                    instance_info = {
                        'Account': instance['Account'],
                        'Region': instance['Region'],
                        'Status': instance['Status'],
                        'DriftStatus': instance.get('DriftStatus', 'NOT_CHECKED'),
                        'StatusReason': instance.get('StatusReason', ''),
                        'LastDriftCheckTimestamp': instance.get('LastDriftCheckTimestamp', '').isoformat() if instance.get('LastDriftCheckTimestamp') else None
                    }
                    
                    all_instances.append(instance_info)
                    
                    if instance.get('DriftStatus') == 'DRIFTED':
                        drifted_instances.append(instance_info)
                
                next_token = stack_instances.get('NextToken')
            
        except Exception as e:
            logger.error(f"Error getting stack instances: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': f'Error getting stack instances: {str(e)}',
                    'stackset_name': stackset_name,
                    'operation_id': operation_id
                })
            }
        
        # Generate comprehensive drift report
        drift_report = {
            'timestamp': datetime.utcnow().isoformat(),
            'stackset_name': stackset_name,
            'operation_id': operation_id,
            'operation_status': operation_status,
            'total_instances': len(all_instances),
            'drifted_instances_count': len(drifted_instances),
            'drift_percentage': round((len(drifted_instances) / len(all_instances)) * 100, 2) if all_instances else 0,
            'drifted_instances': drifted_instances,
            'all_instances': all_instances,
            'summary': {
                'critical_drift_detected': len(drifted_instances) > 0,
                'drift_accounts': list(set([instance['Account'] for instance in drifted_instances])),
                'drift_regions': list(set([instance['Region'] for instance in drifted_instances])),
                'healthy_instances': len(all_instances) - len(drifted_instances)
            }
        }
        
        logger.info(f"Drift detection complete. Found {len(drifted_instances)} drifted instances out of {len(all_instances)} total instances")
        
        # Send SNS notification if drift detected and SNS topic provided
        if drifted_instances and sns_topic_arn:
            try:
                notification_subject = f'⚠️ StackSet Drift Alert: {stackset_name}'
                
                # Create detailed notification message
                notification_message = f"""
StackSet Drift Detection Results

StackSet: {stackset_name}
Detection Time: {datetime.utcnow().isoformat()}
Operation ID: {operation_id}

SUMMARY:
- Total Stack Instances: {len(all_instances)}
- Drifted Instances: {len(drifted_instances)}
- Drift Percentage: {drift_report['drift_percentage']}%
- Affected Accounts: {', '.join(drift_report['summary']['drift_accounts'])}
- Affected Regions: {', '.join(drift_report['summary']['drift_regions'])}

DRIFTED INSTANCES:
{chr(10).join([f"- Account: {instance['Account']}, Region: {instance['Region']}, Status: {instance['Status']}, Reason: {instance.get('StatusReason', 'N/A')}" for instance in drifted_instances])}

ACTION REQUIRED:
1. Review the drifted instances in the AWS CloudFormation console
2. Determine the cause of the drift
3. Either update the StackSet template to match the current state or revert the drifted resources
4. Consider implementing preventive measures to avoid future drift

AWS Console Link:
https://console.aws.amazon.com/cloudformation/home#/stacksets/{stackset_name}

This is an automated alert from the StackSet drift detection system.
                """
                
                sns_response = sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Subject=notification_subject,
                    Message=notification_message
                )
                
                logger.info(f"SNS notification sent successfully. Message ID: {sns_response['MessageId']}")
                drift_report['notification_sent'] = True
                drift_report['notification_message_id'] = sns_response['MessageId']
                
            except Exception as e:
                logger.error(f"Error sending SNS notification: {str(e)}")
                drift_report['notification_sent'] = False
                drift_report['notification_error'] = str(e)
        
        elif drifted_instances:
            logger.info("Drift detected but no SNS topic provided for notifications")
            drift_report['notification_sent'] = False
            drift_report['notification_error'] = "No SNS topic provided"
        
        else:
            logger.info("No drift detected, no notification needed")
            drift_report['notification_sent'] = False
            drift_report['notification_error'] = "No drift detected"
        
        # Return successful response
        return {
            'statusCode': 200,
            'body': json.dumps(drift_report, indent=2, default=str)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error in drift detection: {str(e)}")
        
        # Try to send error notification
        try:
            if 'sns_client' in locals() and 'sns_topic_arn' in locals() and sns_topic_arn:
                error_message = f"""
StackSet Drift Detection Error

StackSet: {stackset_name if 'stackset_name' in locals() else 'Unknown'}
Error Time: {datetime.utcnow().isoformat()}
Error: {str(e)}

The automated drift detection process encountered an error.
Please check the Lambda function logs for more details.

Lambda Function: {context.function_name if context else 'Unknown'}
Request ID: {context.aws_request_id if context else 'Unknown'}
                """
                
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Subject=f'🚨 StackSet Drift Detection Error',
                    Message=error_message
                )
                
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Unexpected error in drift detection: {str(e)}',
                'stackset_name': stackset_name if 'stackset_name' in locals() else 'Unknown',
                'timestamp': datetime.utcnow().isoformat()
            })
        }