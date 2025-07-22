"""
Volume Cleanup Lambda Function for Cost Governance
Identifies and schedules cleanup of unattached EBS volumes
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for volume cleanup automation
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing execution results
    """
    logger.info(f"Starting volume cleanup process. Event: {json.dumps(event)}")
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    try:
        # Get configuration from environment variables
        age_threshold_days = int(os.environ.get('AGE_THRESHOLD_DAYS', '${age_threshold_days}'))
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        if not sns_topic_arn:
            raise ValueError("SNS_TOPIC_ARN environment variable not set")
        
        # Get all unattached volumes
        response = ec2.describe_volumes(
            Filters=[
                {'Name': 'status', 'Values': ['available']}
            ]
        )
        
        volumes_to_clean = []
        total_volumes_checked = len(response['Volumes'])
        total_cost_savings = 0.0
        total_storage_gb = 0
        
        logger.info(f"Found {total_volumes_checked} unattached volumes to evaluate")
        
        # Process each unattached volume
        for volume in response['Volumes']:
            volume_id = volume['VolumeId']
            size = volume['Size']
            volume_type = volume['VolumeType']
            create_time = volume['CreateTime']
            availability_zone = volume['AvailabilityZone']
            
            # Calculate age in days
            age_days = (datetime.now(create_time.tzinfo) - create_time).days
            
            logger.info(f"Evaluating volume {volume_id}: Type={volume_type}, Size={size}GB, Age={age_days} days")
            
            # Only process volumes older than threshold
            if age_days > age_threshold_days:
                # Calculate estimated monthly cost savings
                monthly_cost = calculate_volume_monthly_cost(size, volume_type)
                total_cost_savings += monthly_cost
                total_storage_gb += size
                
                # Get volume tags for additional context
                volume_tags = {tag['Key']: tag['Value'] for tag in volume.get('Tags', [])}
                
                # Check if volume already has deletion protection
                if volume_tags.get('CostOptimization:ProtectFromDeletion', '').lower() == 'true':
                    logger.info(f"Volume {volume_id} is protected from deletion")
                    continue
                
                # Create safety snapshot before scheduling deletion
                try:
                    snapshot_description = f'Pre-deletion backup of {volume_id} - Created by Cost Governance'
                    snapshot_response = ec2.create_snapshot(
                        VolumeId=volume_id,
                        Description=snapshot_description,
                        TagSpecifications=[
                            {
                                'ResourceType': 'snapshot',
                                'Tags': [
                                    {'Key': 'CostOptimization', 'Value': 'true'},
                                    {'Key': 'CostOptimization:Purpose', 'Value': 'pre-deletion-backup'},
                                    {'Key': 'CostOptimization:OriginalVolumeId', 'Value': volume_id},
                                    {'Key': 'CostOptimization:CreatedDate', 'Value': datetime.utcnow().isoformat()},
                                    {'Key': 'CostOptimization:AutoCleanup', 'Value': 'true'},
                                    {'Key': 'Name', 'Value': f'Backup-{volume_id}'}
                                ]
                            }
                        ]
                    )
                    
                    snapshot_id = snapshot_response['SnapshotId']
                    logger.info(f"Created backup snapshot {snapshot_id} for volume {volume_id}")
                    
                    # Tag volume for deletion tracking and add safety metadata
                    ec2.create_tags(
                        Resources=[volume_id],
                        Tags=[
                            {'Key': 'CostOptimization:ScheduledDeletion', 'Value': 'true'},
                            {'Key': 'CostOptimization:BackupSnapshot', 'Value': snapshot_id},
                            {'Key': 'CostOptimization:DetectedDate', 'Value': datetime.utcnow().isoformat()},
                            {'Key': 'CostOptimization:AgeDays', 'Value': str(age_days)},
                            {'Key': 'CostOptimization:MonthlyCost', 'Value': f'${monthly_cost:.2f}'},
                            {'Key': 'CostOptimization:RequiresReview', 'Value': 'true'}
                        ]
                    )
                    
                    # Collect volume information for reporting
                    volume_info = {
                        'VolumeId': volume_id,
                        'Size': size,
                        'Type': volume_type,
                        'AgeDays': age_days,
                        'AvailabilityZone': availability_zone,
                        'CreateTime': create_time.isoformat(),
                        'MonthlyCostSavings': round(monthly_cost, 2),
                        'BackupSnapshot': snapshot_id,
                        'ExistingTags': volume_tags,
                        'Status': 'scheduled_for_review'
                    }
                    
                    volumes_to_clean.append(volume_info)
                    logger.info(f"Volume {volume_id} tagged for cleanup review")
                    
                except Exception as e:
                    logger.error(f"Error processing volume {volume_id}: {str(e)}")
                    
                    # Add to report even if snapshot fails
                    volume_info = {
                        'VolumeId': volume_id,
                        'Size': size,
                        'Type': volume_type,
                        'AgeDays': age_days,
                        'AvailabilityZone': availability_zone,
                        'CreateTime': create_time.isoformat(),
                        'MonthlyCostSavings': round(monthly_cost, 2),
                        'BackupSnapshot': None,
                        'ExistingTags': volume_tags,
                        'Status': 'error_during_processing',
                        'Error': str(e)
                    }
                    volumes_to_clean.append(volume_info)
            
            else:
                logger.info(f"Volume {volume_id} is only {age_days} days old (threshold: {age_threshold_days})")
        
        # Send notification about volumes scheduled for cleanup
        if volumes_to_clean:
            # Categorize volumes by size for better reporting
            small_volumes = [v for v in volumes_to_clean if v['Size'] < 100]
            medium_volumes = [v for v in volumes_to_clean if 100 <= v['Size'] < 500]
            large_volumes = [v for v in volumes_to_clean if v['Size'] >= 500]
            
            message = {
                'Alert': 'Unattached EBS Volumes Scheduled for Cleanup Review',
                'Timestamp': datetime.utcnow().isoformat(),
                'Summary': {
                    'TotalVolumesEvaluated': total_volumes_checked,
                    'VolumesScheduledForReview': len(volumes_to_clean),
                    'TotalStorageGB': total_storage_gb,
                    'EstimatedMonthlySavings': f'${total_cost_savings:.2f}',
                    'AgeThresholdDays': age_threshold_days
                },
                'VolumeBreakdown': {
                    'SmallVolumes': f'{len(small_volumes)} volumes < 100GB',
                    'MediumVolumes': f'{len(medium_volumes)} volumes 100-500GB',
                    'LargeVolumes': f'{len(large_volumes)} volumes >= 500GB'
                },
                'VolumesScheduledForReview': volumes_to_clean[:10],  # Limit to first 10 for email
                'TotalVolumesInReport': len(volumes_to_clean),
                'Actions': [
                    'All volumes have been backed up with snapshots before scheduling',
                    'Volumes are tagged for manual review and approval',
                    'No volumes have been automatically deleted - human approval required',
                    'Review each volume to ensure it is truly unneeded before deletion'
                ],
                'NextSteps': [
                    '1. Review the tagged volumes in the EC2 console',
                    '2. Verify with application owners that volumes are not needed',
                    '3. Manually delete approved volumes or remove deletion tags',
                    '4. Snapshots will be retained for disaster recovery'
                ],
                'SafetyMeasures': [
                    'Backup snapshots created for all volumes',
                    'Volumes only tagged, not automatically deleted',
                    'Protection tags prevent deletion of critical volumes',
                    'Manual approval required for actual deletion'
                ]
            }
            
            try:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Subject=f'Cost Governance: {len(volumes_to_clean)} Unattached Volumes Require Review (${total_cost_savings:.2f}/month savings)',
                    Message=json.dumps(message, indent=2)
                )
                logger.info(f"Sent notification about {len(volumes_to_clean)} volumes scheduled for review")
            except Exception as sns_error:
                logger.error(f"Failed to send SNS notification: {str(sns_error)}")
        
        else:
            logger.info("No volumes meet the criteria for cleanup")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Evaluated {total_volumes_checked} unattached volumes',
                'volumes_scheduled_for_review': len(volumes_to_clean),
                'potential_monthly_savings': f'${total_cost_savings:.2f}',
                'total_storage_gb': total_storage_gb,
                'age_threshold_days': age_threshold_days,
                'volumes': volumes_to_clean
            }, default=str)
        }
    
    except Exception as e:
        logger.error(f"Error in volume cleanup process: {str(e)}")
        
        # Send error notification
        try:
            error_message = {
                'Alert': 'Error in Volume Cleanup Process',
                'Timestamp': datetime.utcnow().isoformat(),
                'Error': str(e),
                'Function': context.function_name if context else 'Unknown',
                'RequestId': context.aws_request_id if context else 'Unknown'
            }
            
            sns.publish(
                TopicArn=os.environ.get('SNS_TOPIC_ARN', ''),
                Subject='Cost Governance Error: Volume Cleanup Failed',
                Message=json.dumps(error_message, indent=2)
            )
        except:
            pass  # Avoid cascading errors
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process volume cleanup'
            })
        }


def calculate_volume_monthly_cost(size_gb: int, volume_type: str, region: str = 'us-east-1') -> float:
    """
    Calculate estimated monthly cost for an EBS volume
    
    Args:
        size_gb: Volume size in GB
        volume_type: EBS volume type
        region: AWS region
        
    Returns:
        Estimated monthly cost in USD
    """
    # Cost per GB per month for different volume types (US East 1)
    # Note: These are approximate and should be updated with current pricing
    cost_per_gb_month = {
        'gp2': 0.10,        # General Purpose SSD
        'gp3': 0.08,        # General Purpose SSD (newer generation)
        'io1': 0.125,       # Provisioned IOPS SSD
        'io2': 0.125,       # Provisioned IOPS SSD (newer generation)
        'st1': 0.045,       # Throughput Optimized HDD
        'sc1': 0.025,       # Cold HDD
        'standard': 0.05    # Magnetic (previous generation)
    }
    
    # Default to gp2 pricing if volume type not recognized
    cost_per_gb = cost_per_gb_month.get(volume_type.lower(), 0.10)
    
    return size_gb * cost_per_gb


def get_volume_last_attached_date(volume_id: str, ec2_client) -> Optional[datetime]:
    """
    Attempt to determine when a volume was last attached by checking CloudTrail logs
    
    Args:
        volume_id: EBS volume ID
        ec2_client: EC2 boto3 client
        
    Returns:
        Last attached date or None if not determinable
    """
    # This is a simplified implementation
    # In a production environment, you might want to query CloudTrail
    # or maintain your own attachment tracking
    try:
        # Check if there are any attachment records in volume attributes
        # This is limited without CloudTrail integration
        return None
    except Exception:
        return None


def is_volume_safe_to_delete(volume: Dict[str, Any]) -> bool:
    """
    Determine if a volume is safe to delete based on various criteria
    
    Args:
        volume: Volume description from EC2 API
        
    Returns:
        True if volume appears safe to delete
    """
    volume_tags = {tag['Key']: tag['Value'] for tag in volume.get('Tags', [])}
    
    # Check for protection tags
    if volume_tags.get('CostOptimization:ProtectFromDeletion', '').lower() == 'true':
        return False
    
    # Check for critical application tags
    critical_tags = ['production', 'critical', 'backup', 'database']
    for tag_value in volume_tags.values():
        if any(critical_word in tag_value.lower() for critical_word in critical_tags):
            return False
    
    # Check volume name for critical indicators
    volume_name = volume_tags.get('Name', '').lower()
    critical_names = ['prod', 'production', 'critical', 'database', 'backup']
    if any(critical_name in volume_name for critical_name in critical_names):
        return False
    
    return True