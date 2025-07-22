import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Automated tag remediation function for AWS Config rule violations
    
    This function responds to AWS Config compliance evaluations and applies
    default tags to non-compliant resources while sending notifications.
    """
    print(f"Received event: {json.dumps(event, default=str)}")
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    config_client = boto3.client('config')
    
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
    
    try:
        # Parse Config rule evaluation result
        if 'configurationItem' in event:
            config_item = event['configurationItem']
        elif 'configurationItemDiff' in event:
            config_item = event['configurationItemDiff']['changedProperties']
        else:
            print("No configuration item found in event")
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event format - no configuration item')
            }
        
        resource_type = config_item.get('resourceType', 'Unknown')
        resource_id = config_item.get('resourceId', 'Unknown')
        
        # Apply default tags based on resource type and current tags
        default_tags = get_default_tags(config_item)
        
        if resource_type == 'AWS::EC2::Instance':
            remediate_ec2_instance(ec2, resource_id, default_tags)
        elif resource_type == 'AWS::S3::Bucket':
            remediate_s3_bucket(resource_id, default_tags)
        elif resource_type == 'AWS::RDS::DBInstance':
            remediate_rds_instance(resource_id, default_tags)
        else:
            print(f"Resource type {resource_type} not supported for auto-tagging")
        
        # Send notification about remediation
        send_notification(sns, sns_topic_arn, resource_type, resource_id, default_tags)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed {resource_type} {resource_id}')
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        
        # Send error notification
        error_message = f"""
Tag Remediation Error

Error: {str(e)}
Event: {json.dumps(event, default=str)}

Please review the Lambda function logs for more details.
"""
        
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='Tag Remediation Error',
                Message=error_message
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_default_tags(config_item):
    """
    Generate default tags based on resource context and missing required tags
    
    Args:
        config_item: AWS Config configuration item
        
    Returns:
        List of tags to apply to the resource
    """
    tags = []
    current_tags = config_item.get('tags', {})
    
    # Add default CostCenter if missing
    if not has_tag(current_tags, 'CostCenter'):
        tags.append({'Key': 'CostCenter', 'Value': 'Unassigned'})
    
    # Add default Environment if missing
    if not has_tag(current_tags, 'Environment'):
        tags.append({'Key': 'Environment', 'Value': 'Development'})
    
    # Add default Project if missing
    if not has_tag(current_tags, 'Project'):
        tags.append({'Key': 'Project', 'Value': 'UntaggedResource'})
    
    # Add default Owner if missing
    if not has_tag(current_tags, 'Owner'):
        tags.append({'Key': 'Owner', 'Value': 'unknown@company.com'})
    
    # Add compliance tracking tag
    tags.append({
        'Key': 'AutoTagged',
        'Value': f"true-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    })
    
    # Add remediation timestamp
    tags.append({
        'Key': 'RemediationDate',
        'Value': datetime.now().isoformat()
    })
    
    return tags

def has_tag(tags_dict, tag_key):
    """
    Check if resource already has specified tag
    
    Args:
        tags_dict: Dictionary of existing resource tags
        tag_key: Tag key to check for
        
    Returns:
        Boolean indicating if tag exists
    """
    if isinstance(tags_dict, dict):
        return tag_key in tags_dict
    elif isinstance(tags_dict, list):
        return any(tag.get('Key') == tag_key for tag in tags_dict)
    return False

def remediate_ec2_instance(ec2, instance_id, tags):
    """
    Apply tags to EC2 instance
    
    Args:
        ec2: EC2 client
        instance_id: EC2 instance ID
        tags: List of tags to apply
    """
    if tags:
        try:
            ec2.create_tags(Resources=[instance_id], Tags=tags)
            print(f"Applied {len(tags)} tags to EC2 instance {instance_id}")
        except Exception as e:
            print(f"Failed to tag EC2 instance {instance_id}: {str(e)}")
            raise

def remediate_s3_bucket(bucket_name, tags):
    """
    Apply tags to S3 bucket
    
    Args:
        bucket_name: S3 bucket name
        tags: List of tags to apply
    """
    if tags:
        try:
            s3 = boto3.client('s3')
            
            # Get existing tags
            try:
                existing_tags = s3.get_bucket_tagging(Bucket=bucket_name)
                tag_set = existing_tags.get('TagSet', [])
            except s3.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchTagSet':
                    tag_set = []
                else:
                    raise
            
            # Add new tags (avoid duplicates)
            existing_keys = {tag['Key'] for tag in tag_set}
            for tag in tags:
                if tag['Key'] not in existing_keys:
                    tag_set.append(tag)
            
            # Apply updated tag set
            s3.put_bucket_tagging(
                Bucket=bucket_name,
                Tagging={'TagSet': tag_set}
            )
            print(f"Applied {len(tags)} tags to S3 bucket {bucket_name}")
        except Exception as e:
            print(f"Failed to tag S3 bucket {bucket_name}: {str(e)}")
            raise

def remediate_rds_instance(db_instance_id, tags):
    """
    Apply tags to RDS instance
    
    Args:
        db_instance_id: RDS instance identifier
        tags: List of tags to apply
    """
    if tags:
        try:
            rds = boto3.client('rds')
            
            # Construct RDS ARN
            sts = boto3.client('sts')
            account_id = sts.get_caller_identity()['Account']
            region = boto3.Session().region_name
            db_arn = f"arn:aws:rds:{region}:{account_id}:db:{db_instance_id}"
            
            # Convert tag format for RDS
            rds_tags = [{'Key': tag['Key'], 'Value': tag['Value']} for tag in tags]
            
            rds.add_tags_to_resource(
                ResourceName=db_arn,
                Tags=rds_tags
            )
            print(f"Applied {len(tags)} tags to RDS instance {db_instance_id}")
        except Exception as e:
            print(f"Failed to tag RDS instance {db_instance_id}: {str(e)}")
            raise

def send_notification(sns, topic_arn, resource_type, resource_id, tags):
    """
    Send SNS notification about tag remediation
    
    Args:
        sns: SNS client
        topic_arn: SNS topic ARN
        resource_type: AWS resource type
        resource_id: Resource identifier
        tags: List of applied tags
    """
    try:
        tag_summary = "\n".join([f"  {tag['Key']}: {tag['Value']}" for tag in tags])
        
        message = f"""
Tag Remediation Notification

Resource Details:
  Type: {resource_type}
  ID: {resource_id}
  Timestamp: {datetime.now().isoformat()}

Auto-Applied Tags:
{tag_summary}

Action Required:
Please review and update these tags with accurate business information in the AWS Console.

Cost Management Impact:
- Resources with default tags may be allocated to 'Unassigned' cost center
- Update CostCenter, Project, and Owner tags for accurate cost allocation
- Environment tag affects cost reporting and budgeting

Next Steps:
1. Review the tagged resource in AWS Console
2. Update tags with correct business values
3. Verify cost allocation in AWS Cost Explorer
4. Update tagging processes to prevent future violations
"""
        
        sns.publish(
            TopicArn=topic_arn,
            Subject=f'Auto-Tag Applied: {resource_type} ({resource_id})',
            Message=message
        )
        print(f"Sent notification about {resource_type} {resource_id}")
    except Exception as e:
        print(f"Failed to send notification: {str(e)}")
        # Don't raise here as the tagging operation was successful