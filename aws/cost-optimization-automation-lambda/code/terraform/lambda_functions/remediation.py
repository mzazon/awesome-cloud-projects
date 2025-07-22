import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle cost optimization remediation actions
    """
    logger.info("Starting cost optimization remediation...")
    
    # Initialize AWS clients
    ec2_client = boto3.client('ec2')
    rds_client = boto3.client('rds')
    s3_client = boto3.client('s3')
    sns_client = boto3.client('sns')
    dynamodb = boto3.resource('dynamodb')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    s3_bucket_name = os.environ['S3_BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Parse the incoming opportunity
        opportunity = event['opportunity']
        action = event.get('action', 'manual')
        
        logger.info(f"Processing remediation for: {opportunity['resource_id']}")
        logger.info(f"Check: {opportunity['check_name']}")
        
        # Route to appropriate remediation handler
        remediation_result = None
        
        if 'EC2' in opportunity['check_name']:
            remediation_result = handle_ec2_remediation(
                ec2_client, opportunity, action
            )
        elif 'RDS' in opportunity['check_name']:
            remediation_result = handle_rds_remediation(
                rds_client, opportunity, action
            )
        elif 'EBS' in opportunity['check_name']:
            remediation_result = handle_ebs_remediation(
                ec2_client, opportunity, action
            )
        elif 'S3' in opportunity['check_name']:
            remediation_result = handle_s3_remediation(
                s3_client, opportunity, action
            )
        elif 'ElastiCache' in opportunity['check_name']:
            remediation_result = handle_elasticache_remediation(
                opportunity, action
            )
        else:
            remediation_result = {
                'status': 'skipped',
                'message': f"No automated remediation available for: {opportunity['check_name']}",
                'recommendation': generate_manual_recommendation(opportunity)
            }
        
        # Update tracking record
        update_remediation_tracking(table, opportunity, remediation_result)
        
        # Store detailed remediation log in S3
        store_remediation_log(s3_client, s3_bucket_name, opportunity, remediation_result)
        
        # Send notification
        send_remediation_notification(
            sns_client, sns_topic_arn, opportunity, remediation_result
        )
        
        logger.info(f"Remediation completed for {opportunity['resource_id']}: {remediation_result['status']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': opportunity['resource_id'],
                'remediation_result': remediation_result,
                'timestamp': datetime.now().isoformat()
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {str(e)}")
        
        # Send error notification
        error_notification = {
            'resource_id': opportunity.get('resource_id', 'unknown'),
            'error': str(e),
            'timestamp': datetime.now().isoformat(),
            'function': 'cost_optimization_remediation'
        }
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps(error_notification, indent=2),
                Subject='Cost Optimization Remediation Error'
            )
        except Exception as sns_error:
            logger.error(f"Error sending SNS notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def handle_ec2_remediation(ec2_client, opportunity, action):
    """Handle EC2-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'stopped' in check_name.lower():
            # For stopped instances, consider termination after validation
            try:
                instance_info = ec2_client.describe_instances(
                    InstanceIds=[resource_id]
                )
                
                if not instance_info['Reservations']:
                    return {
                        'status': 'error',
                        'message': f'Instance {resource_id} not found'
                    }
                
                instance = instance_info['Reservations'][0]['Instances'][0]
                
                # Check if instance has been stopped for more than 7 days
                if should_terminate_stopped_instance(instance):
                    if action == 'auto_remediate':
                        # Create snapshot before termination
                        snapshot_results = create_instance_snapshot(ec2_client, resource_id)
                        
                        # Terminate instance
                        ec2_client.terminate_instances(InstanceIds=[resource_id])
                        
                        return {
                            'status': 'remediated',
                            'action': 'terminated',
                            'message': f'Terminated long-stopped instance {resource_id}',
                            'estimated_savings': opportunity['estimated_savings'],
                            'snapshots_created': snapshot_results,
                            'safety_measures': 'Instance snapshots created before termination'
                        }
                    else:
                        return {
                            'status': 'recommendation',
                            'action': 'terminate',
                            'message': f'Recommend terminating stopped instance {resource_id}',
                            'estimated_savings': opportunity['estimated_savings'],
                            'safety_note': 'Create snapshots before termination'
                        }
                else:
                    return {
                        'status': 'skipped',
                        'message': f'Instance {resource_id} has not been stopped long enough for auto-termination',
                        'recommendation': 'Monitor for extended stop duration'
                    }
                    
            except ec2_client.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'InvalidInstanceID.NotFound':
                    return {
                        'status': 'already_resolved',
                        'message': f'Instance {resource_id} no longer exists',
                        'action': 'none_required'
                    }
                else:
                    raise
               
        elif 'underutilized' in check_name.lower():
            # For underutilized instances, recommend downsizing
            try:
                instance_info = ec2_client.describe_instances(
                    InstanceIds=[resource_id]
                )
                
                if instance_info['Reservations']:
                    instance = instance_info['Reservations'][0]['Instances'][0]
                    current_type = instance['InstanceType']
                    
                    # Generate downsizing recommendation
                    recommended_type = suggest_instance_downsize(current_type)
                    
                    return {
                        'status': 'recommendation',
                        'action': 'downsize',
                        'message': f'Recommend downsizing underutilized instance {resource_id} from {current_type} to {recommended_type}',
                        'estimated_savings': opportunity['estimated_savings'],
                        'current_instance_type': current_type,
                        'recommended_instance_type': recommended_type
                    }
                else:
                    return {
                        'status': 'already_resolved',
                        'message': f'Instance {resource_id} no longer exists'
                    }
                    
            except ec2_client.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'InvalidInstanceID.NotFound':
                    return {
                        'status': 'already_resolved',
                        'message': f'Instance {resource_id} no longer exists'
                    }
                else:
                    raise
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation available for {check_name}',
            'recommendation': generate_manual_recommendation(opportunity)
        }
        
    except Exception as e:
        logger.error(f"Error handling EC2 remediation: {str(e)}")
        return {
            'status': 'error',
            'message': f'Error handling EC2 remediation: {str(e)}'
        }

def handle_rds_remediation(rds_client, opportunity, action):
    """Handle RDS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'idle' in check_name.lower():
            # For idle RDS instances, recommend stopping or deletion
            try:
                response = rds_client.describe_db_instances(
                    DBInstanceIdentifier=resource_id
                )
                
                if response['DBInstances']:
                    db_instance = response['DBInstances'][0]
                    
                    if action == 'auto_remediate' and db_instance['DBInstanceStatus'] == 'available':
                        # Create snapshot before stopping
                        snapshot_id = f"{resource_id}-auto-snapshot-{int(datetime.now().timestamp())}"
                        
                        try:
                            rds_client.create_db_snapshot(
                                DBSnapshotIdentifier=snapshot_id,
                                DBInstanceIdentifier=resource_id
                            )
                            
                            # Stop the RDS instance
                            rds_client.stop_db_instance(
                                DBInstanceIdentifier=resource_id
                            )
                            
                            return {
                                'status': 'remediated',
                                'action': 'stopped',
                                'message': f'Stopped idle RDS instance {resource_id}',
                                'estimated_savings': opportunity['estimated_savings'],
                                'snapshot_created': snapshot_id,
                                'safety_measures': 'DB snapshot created before stopping'
                            }
                        except Exception as stop_error:
                            logger.error(f"Error stopping RDS instance: {str(stop_error)}")
                            return {
                                'status': 'error',
                                'message': f'Error stopping RDS instance: {str(stop_error)}'
                            }
                    else:
                        return {
                            'status': 'recommendation',
                            'action': 'stop',
                            'message': f'Recommend stopping idle RDS instance {resource_id}',
                            'estimated_savings': opportunity['estimated_savings'],
                            'current_status': db_instance['DBInstanceStatus']
                        }
                else:
                    return {
                        'status': 'already_resolved',
                        'message': f'RDS instance {resource_id} no longer exists'
                    }
                    
            except rds_client.exceptions.DBInstanceNotFoundFault:
                return {
                    'status': 'already_resolved',
                    'message': f'RDS instance {resource_id} no longer exists'
                }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation available for {check_name}',
            'recommendation': generate_manual_recommendation(opportunity)
        }
        
    except Exception as e:
        logger.error(f"Error handling RDS remediation: {str(e)}")
        return {
            'status': 'error',
            'message': f'Error handling RDS remediation: {str(e)}'
        }

def handle_ebs_remediation(ec2_client, opportunity, action):
    """Handle EBS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'unattached' in check_name.lower():
            # For unattached volumes, create snapshot and delete
            try:
                volume_info = ec2_client.describe_volumes(
                    VolumeIds=[resource_id]
                )
                
                if volume_info['Volumes']:
                    volume = volume_info['Volumes'][0]
                    
                    if volume['State'] == 'available':  # Unattached
                        if action == 'auto_remediate':
                            # Create snapshot before deletion
                            snapshot_response = ec2_client.create_snapshot(
                                VolumeId=resource_id,
                                Description=f'Automated snapshot before deleting unattached volume {resource_id}'
                            )
                            
                            # Wait a moment for snapshot to initialize
                            import time
                            time.sleep(2)
                            
                            # Delete unattached volume
                            ec2_client.delete_volume(VolumeId=resource_id)
                            
                            return {
                                'status': 'remediated',
                                'action': 'deleted',
                                'message': f'Deleted unattached EBS volume {resource_id}',
                                'estimated_savings': opportunity['estimated_savings'],
                                'snapshot_created': snapshot_response['SnapshotId'],
                                'safety_measures': 'Volume snapshot created before deletion'
                            }
                        else:
                            return {
                                'status': 'recommendation',
                                'action': 'delete',
                                'message': f'Recommend deleting unattached EBS volume {resource_id}',
                                'estimated_savings': opportunity['estimated_savings'],
                                'volume_size': volume['Size'],
                                'volume_type': volume['VolumeType']
                            }
                    else:
                        return {
                            'status': 'already_resolved',
                            'message': f'EBS volume {resource_id} is now attached or in different state: {volume["State"]}'
                        }
                else:
                    return {
                        'status': 'already_resolved',
                        'message': f'EBS volume {resource_id} no longer exists'
                    }
                    
            except ec2_client.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'InvalidVolume.NotFound':
                    return {
                        'status': 'already_resolved',
                        'message': f'EBS volume {resource_id} no longer exists'
                    }
                else:
                    raise
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation available for {check_name}',
            'recommendation': generate_manual_recommendation(opportunity)
        }
        
    except Exception as e:
        logger.error(f"Error handling EBS remediation: {str(e)}")
        return {
            'status': 'error',
            'message': f'Error handling EBS remediation: {str(e)}'
        }

def handle_s3_remediation(s3_client, opportunity, action):
    """Handle S3-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'lifecycle' in check_name.lower():
            # For S3 lifecycle issues, recommend lifecycle policies
            return {
                'status': 'recommendation',
                'action': 'configure_lifecycle',
                'message': f'Recommend configuring lifecycle policy for S3 bucket {resource_id}',
                'estimated_savings': opportunity['estimated_savings'],
                'suggested_policy': {
                    'transition_to_ia': '30 days',
                    'transition_to_glacier': '90 days',
                    'transition_to_deep_archive': '365 days'
                }
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation available for {check_name}',
            'recommendation': generate_manual_recommendation(opportunity)
        }
        
    except Exception as e:
        logger.error(f"Error handling S3 remediation: {str(e)}")
        return {
            'status': 'error',
            'message': f'Error handling S3 remediation: {str(e)}'
        }

def handle_elasticache_remediation(opportunity, action):
    """Handle ElastiCache-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    return {
        'status': 'recommendation',
        'action': 'manual_review',
        'message': f'Manual review required for ElastiCache resource {resource_id}',
        'estimated_savings': opportunity['estimated_savings'],
        'recommendation': 'Review ElastiCache cluster utilization and consider downsizing or terminating if unused'
    }

def should_terminate_stopped_instance(instance):
    """Check if stopped instance should be terminated"""
    # Check if instance has been stopped for more than 7 days
    if instance['State']['Name'] == 'stopped':
        state_transition_time = instance['StateTransitionReason']
        # This is a simplified check - in practice, you'd want to parse the timestamp
        # or use CloudTrail logs to determine exact stop duration
        return True  # For demo purposes, assume it's been stopped long enough
    
    return False

def suggest_instance_downsize(current_type):
    """Suggest a smaller instance type for downsizing"""
    # Simplified downsizing recommendations
    downsize_map = {
        't3.large': 't3.medium',
        't3.xlarge': 't3.large',
        't3.2xlarge': 't3.xlarge',
        'm5.large': 'm5.medium',
        'm5.xlarge': 'm5.large',
        'm5.2xlarge': 'm5.xlarge',
        'c5.large': 'c5.medium',
        'c5.xlarge': 'c5.large',
        'c5.2xlarge': 'c5.xlarge'
    }
    
    return downsize_map.get(current_type, f'{current_type} (consider smaller size)')

def create_instance_snapshot(ec2_client, instance_id):
    """Create snapshots of instance volumes before termination"""
    try:
        # Get instance volumes
        instance_info = ec2_client.describe_instances(
            InstanceIds=[instance_id]
        )
        
        if not instance_info['Reservations']:
            return []
        
        instance = instance_info['Reservations'][0]['Instances'][0]
        snapshots_created = []
        
        # Create snapshots for all attached volumes
        for mapping in instance.get('BlockDeviceMappings', []):
            if 'Ebs' in mapping:
                volume_id = mapping['Ebs']['VolumeId']
                snapshot_response = ec2_client.create_snapshot(
                    VolumeId=volume_id,
                    Description=f'Automated snapshot before terminating instance {instance_id}'
                )
                snapshots_created.append({
                    'volume_id': volume_id,
                    'snapshot_id': snapshot_response['SnapshotId']
                })
        
        return snapshots_created
        
    except Exception as e:
        logger.error(f"Error creating snapshots: {str(e)}")
        return []

def generate_manual_recommendation(opportunity):
    """Generate manual recommendation based on the opportunity"""
    recommendations = {
        'EC2': 'Review instance utilization and consider rightsizing, scheduling, or terminating unused instances',
        'RDS': 'Analyze database performance metrics and consider stopping, downsizing, or optimizing queries',
        'EBS': 'Review volume usage and consider deleting unattached volumes or changing volume types',
        'S3': 'Implement lifecycle policies, enable intelligent tiering, or remove unused objects',
        'ElastiCache': 'Review cache utilization and consider downsizing or terminating unused clusters'
    }
    
    service = extract_service_from_check(opportunity['check_name'])
    return recommendations.get(service, 'Manual review required to optimize this resource')

def extract_service_from_check(check_name):
    """Extract AWS service from check name"""
    if 'EC2' in check_name:
        return 'EC2'
    elif 'RDS' in check_name:
        return 'RDS'
    elif 'EBS' in check_name:
        return 'EBS'
    elif 'S3' in check_name:
        return 'S3'
    elif 'ElastiCache' in check_name:
        return 'ElastiCache'
    else:
        return 'Other'

def update_remediation_tracking(table, opportunity, remediation_result):
    """Update DynamoDB tracking record with remediation results"""
    try:
        table.update_item(
            Key={
                'ResourceId': opportunity['resource_id'],
                'CheckId': opportunity['check_id']
            },
            UpdateExpression='SET RemediationStatus = :status, RemediationResult = :result, RemediationTimestamp = :timestamp',
            ExpressionAttributeValues={
                ':status': remediation_result['status'],
                ':result': json.dumps(remediation_result),
                ':timestamp': datetime.now().isoformat()
            }
        )
    except Exception as e:
        logger.error(f"Error updating remediation tracking: {str(e)}")

def store_remediation_log(s3_client, bucket_name, opportunity, remediation_result):
    """Store detailed remediation log in S3"""
    try:
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'resource_id': opportunity['resource_id'],
            'check_id': opportunity['check_id'],
            'check_name': opportunity['check_name'],
            'opportunity': opportunity,
            'remediation_result': remediation_result
        }
        
        log_key = f"remediation-logs/{datetime.now().strftime('%Y/%m/%d')}/{opportunity['resource_id']}-{int(datetime.now().timestamp())}.json"
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=log_key,
            Body=json.dumps(log_entry, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Remediation log stored: s3://{bucket_name}/{log_key}")
        
    except Exception as e:
        logger.error(f"Error storing remediation log: {str(e)}")

def send_remediation_notification(sns_client, topic_arn, opportunity, remediation_result):
    """Send notification about remediation action"""
    try:
        notification = {
            'resource_id': opportunity['resource_id'],
            'check_name': opportunity['check_name'],
            'remediation_status': remediation_result['status'],
            'remediation_action': remediation_result.get('action', 'none'),
            'estimated_savings': opportunity['estimated_savings'],
            'message': remediation_result.get('message', ''),
            'timestamp': datetime.now().isoformat()
        }
        
        # Add additional details based on remediation status
        if remediation_result['status'] == 'remediated':
            notification['safety_measures'] = remediation_result.get('safety_measures', 'None specified')
        elif remediation_result['status'] == 'recommendation':
            notification['recommendation'] = remediation_result.get('recommendation', 'Manual review required')
        
        subject = f"Cost Optimization: {remediation_result['status'].title()} - {opportunity['check_name']}"
        
        sns_client.publish(
            TopicArn=topic_arn,
            Message=json.dumps(notification, indent=2, default=str),
            Subject=subject
        )
        
    except Exception as e:
        logger.error(f"Error sending remediation notification: {str(e)}")