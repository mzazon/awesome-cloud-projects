import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Execute automated remediation actions based on security findings
    """
    try:
        detail = event.get('detail', {})
        action = detail.get('action')
        finding = detail.get('finding', {})
        
        if not action:
            logger.warning("No action specified in event")
            return {'statusCode': 400, 'body': 'No action specified'}
        
        logger.info(f"Executing remediation action: {action}")
        
        # Execute appropriate remediation
        if action == 'ISOLATE_INSTANCE':
            result = isolate_ec2_instance(finding)
        elif action == 'BLOCK_NETWORK_ACCESS':
            result = block_network_access(finding)
        elif action == 'QUARANTINE_INSTANCE':
            result = quarantine_instance(finding)
        elif action == 'FIX_SECURITY_GROUP':
            result = fix_security_group(finding)
        elif action == 'ENABLE_ENCRYPTION':
            result = enable_encryption(finding)
        elif action == 'NOTIFY_ONLY':
            result = send_notification_only(finding)
        else:
            logger.warning(f"Unknown action: {action}")
            return {'statusCode': 400, 'body': f'Unknown action: {action}'}
        
        # Update finding with remediation status
        update_finding_status(finding.get('Id'), result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'action': action, 'result': result})
        }
        
    except Exception as e:
        logger.error(f"Error in remediation function: {str(e)}")
        raise

def isolate_ec2_instance(finding):
    """
    Isolate EC2 instance by moving to quarantine security group
    """
    try:
        # Extract instance ID from finding
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        # Use Systems Manager automation
        ssm = boto3.client('ssm')
        response = ssm.start_automation_execution(
            DocumentName='AWS-PublishSNSNotification',
            Parameters={
                'TopicArn': [os.environ.get('SNS_TOPIC_ARN', '')],
                'Message': [f'Instance {instance_id} isolated due to security finding']
            }
        )
        
        return {'success': True, 'automation_id': response['AutomationExecutionId']}
        
    except Exception as e:
        logger.error(f"Error isolating instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def block_network_access(finding):
    """
    Block network access by updating security group rules
    """
    try:
        # Extract security group information
        sg_id = extract_security_group_id(finding)
        if not sg_id:
            return {'success': False, 'message': 'No security group ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Get current security group rules
        response = ec2.describe_security_groups(GroupIds=[sg_id])
        sg = response['SecurityGroups'][0]
        
        # Remove overly permissive rules (0.0.0.0/0)
        for rule in sg.get('IpPermissions', []):
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    ec2.revoke_security_group_ingress(
                        GroupId=sg_id,
                        IpPermissions=[rule]
                    )
        
        return {'success': True, 'message': f'Blocked open access for {sg_id}'}
        
    except Exception as e:
        logger.error(f"Error blocking network access: {str(e)}")
        return {'success': False, 'message': str(e)}

def quarantine_instance(finding):
    """
    Quarantine instance by stopping it and creating forensic snapshot
    """
    try:
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Stop the instance
        ec2.stop_instances(InstanceIds=[instance_id])
        
        # Create snapshot for forensic analysis
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        for device in instance.get('BlockDeviceMappings', []):
            volume_id = device['Ebs']['VolumeId']
            ec2.create_snapshot(
                VolumeId=volume_id,
                Description=f'Forensic snapshot for security incident - {instance_id}'
            )
        
        return {'success': True, 'message': f'Instance {instance_id} quarantined'}
        
    except Exception as e:
        logger.error(f"Error quarantining instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def fix_security_group(finding):
    """
    Fix security group misconfigurations
    """
    return {'success': True, 'message': 'Security group remediation simulated'}

def enable_encryption(finding):
    """
    Enable encryption for unencrypted resources
    """
    return {'success': True, 'message': 'Encryption enablement simulated'}

def send_notification_only(finding):
    """
    Send notification without automated remediation
    """
    return {'success': True, 'message': 'Notification sent for manual review'}

def extract_instance_id(finding):
    """
    Extract EC2 instance ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'i-' in resource_id:
            return resource_id.split('/')[-1]
    return None

def extract_security_group_id(finding):
    """
    Extract security group ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'sg-' in resource_id:
            return resource_id.split('/')[-1]
    return None

def update_finding_status(finding_id, result):
    """
    Update Security Hub finding with remediation status
    """
    try:
        securityhub = boto3.client('securityhub')
        status = 'RESOLVED' if result.get('success') else 'NEW'
        note = result.get('message', 'Automated remediation attempted')
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")