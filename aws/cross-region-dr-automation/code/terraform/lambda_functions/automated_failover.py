"""
AWS Elastic Disaster Recovery Automated Failover Lambda Function

This Lambda function orchestrates automated failover procedures for AWS DRS,
including recovery job initiation, DNS updates, and stakeholder notifications.
"""

import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for automated disaster recovery failover.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    
    # Initialize AWS clients
    dr_region = os.environ.get('DR_REGION', '${dr_region}')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
    
    drs_client = boto3.client('drs', region_name=dr_region)
    route53_client = boto3.client('route53')
    sns_client = boto3.client('sns')
    
    logger.info(f"Starting automated DR failover in region: {dr_region}")
    
    try:
        # Check if this is a test invocation
        test_mode = event.get('test', False)
        
        if test_mode:
            logger.info("Running in test mode - no actual failover will occur")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Test mode - DR failover simulation completed successfully',
                    'timestamp': datetime.utcnow().isoformat(),
                    'test_mode': True
                })
            }
        
        # Get source servers for recovery
        logger.info("Retrieving source servers for recovery")
        response = drs_client.describe_source_servers()
        source_servers = response.get('sourceServers', [])
        
        if not source_servers:
            logger.warning("No source servers found for recovery")
            send_notification(
                sns_client, 
                sns_topic_arn, 
                "DR Failover Warning", 
                "No source servers found for recovery. Please verify DRS configuration."
            )
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'No source servers found for recovery'})
            }
        
        # Filter servers that are ready for recovery
        ready_servers = [
            server for server in source_servers 
            if server.get('dataReplicationInfo', {}).get('replicationState') == 'CONTINUOUS'
        ]
        
        if not ready_servers:
            logger.error("No servers ready for recovery")
            send_notification(
                sns_client, 
                sns_topic_arn, 
                "DR Failover Failed", 
                "No servers are ready for recovery. Check replication status."
            )
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'No servers ready for recovery'})
            }
        
        # Start recovery jobs for ready servers
        recovery_jobs = start_recovery_jobs(drs_client, ready_servers)
        
        # Update Route 53 DNS records for failover
        dns_update_result = update_dns_records(route53_client, dr_region)
        
        # Send success notification
        message = f"""
        Automated DR failover initiated successfully:
        
        Recovery Jobs Started: {len(recovery_jobs)}
        Jobs: {recovery_jobs}
        DNS Updates: {dns_update_result}
        Timestamp: {datetime.utcnow().isoformat()}
        
        Please monitor the recovery progress in the AWS DRS console.
        """
        
        send_notification(sns_client, sns_topic_arn, "DR Failover Activated", message)
        
        logger.info(f"DR failover completed successfully. Jobs: {recovery_jobs}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Failover initiated successfully',
                'recoveryJobs': recovery_jobs,
                'serversProcessed': len(ready_servers),
                'dnsUpdated': dns_update_result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f"DR failover failed: {str(e)}"
        logger.error(error_message, exc_info=True)
        
        # Send failure notification
        send_notification(
            sns_client, 
            sns_topic_arn, 
            "DR Failover Failed", 
            f"{error_message}\\n\\nTimestamp: {datetime.utcnow().isoformat()}"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def start_recovery_jobs(drs_client: Any, source_servers: List[Dict]) -> List[str]:
    """
    Start recovery jobs for source servers.
    
    Args:
        drs_client: DRS boto3 client
        source_servers: List of source server dictionaries
        
    Returns:
        List of recovery job IDs
    """
    recovery_jobs = []
    
    for server in source_servers:
        try:
            server_id = server['sourceServerID']
            logger.info(f"Starting recovery for server: {server_id}")
            
            # Start recovery job
            job_response = drs_client.start_recovery(
                sourceServers=[{
                    'sourceServerID': server_id,
                    'recoverySnapshotID': 'LATEST'
                }],
                tags={
                    'Purpose': 'AutomatedDR',
                    'Timestamp': datetime.utcnow().isoformat(),
                    'TriggerType': 'Lambda'
                }
            )
            
            job_id = job_response['job']['jobID']
            recovery_jobs.append(job_id)
            logger.info(f"Recovery job {job_id} started for server {server_id}")
            
        except Exception as e:
            logger.error(f"Failed to start recovery for server {server_id}: {str(e)}")
            continue
    
    return recovery_jobs

def update_dns_records(route53_client: Any, dr_region: str) -> Dict[str, Any]:
    """
    Update Route 53 DNS records for failover to DR region.
    
    Args:
        route53_client: Route53 boto3 client
        dr_region: Disaster recovery region
        
    Returns:
        Dictionary with DNS update results
    """
    dns_results = {'updated_zones': [], 'errors': []}
    
    try:
        # Get hosted zones
        hosted_zones = route53_client.list_hosted_zones()
        
        for zone in hosted_zones['HostedZones']:
            zone_name = zone['Name']
            zone_id = zone['Id']
            
            # Skip private zones and zones that don't match common patterns
            if zone.get('Config', {}).get('PrivateZone', False):
                continue
                
            # Update DNS record for application endpoints
            # This is a template - customize based on your DNS structure
            try:
                change_batch = {
                    'Changes': [{
                        'Action': 'UPSERT',
                        'ResourceRecordSet': {
                            'Name': f"app.{zone_name}",
                            'Type': 'A',
                            'SetIdentifier': 'DR-Failover',
                            'Failover': 'SECONDARY',
                            'TTL': 60,
                            'ResourceRecords': [{'Value': '10.100.1.100'}]  # DR IP placeholder
                        }
                    }]
                }
                
                route53_client.change_resource_record_sets(
                    HostedZoneId=zone_id,
                    ChangeBatch=change_batch
                )
                
                dns_results['updated_zones'].append(zone_name)
                logger.info(f"Updated DNS for zone: {zone_name}")
                
            except Exception as e:
                error_msg = f"Failed to update DNS for zone {zone_name}: {str(e)}"
                dns_results['errors'].append(error_msg)
                logger.error(error_msg)
                
    except Exception as e:
        error_msg = f"Failed to retrieve hosted zones: {str(e)}"
        dns_results['errors'].append(error_msg)
        logger.error(error_msg)
    
    return dns_results

def send_notification(sns_client: Any, topic_arn: str, subject: str, message: str) -> None:
    """
    Send SNS notification.
    
    Args:
        sns_client: SNS boto3 client
        topic_arn: SNS topic ARN
        subject: Message subject
        message: Message body
    """
    try:
        sns_client.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=subject
        )
        logger.info(f"SNS notification sent: {subject}")
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")