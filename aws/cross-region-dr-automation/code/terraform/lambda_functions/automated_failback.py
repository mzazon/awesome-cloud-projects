"""
AWS Elastic Disaster Recovery Automated Failback Lambda Function

This Lambda function orchestrates automated failback procedures to return
operations to the primary region after disaster recovery events.
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
    Main Lambda handler for automated disaster recovery failback.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    
    # Initialize AWS clients
    primary_region = os.environ.get('PRIMARY_REGION', '${primary_region}')
    
    drs_client = boto3.client('drs', region_name=primary_region)
    route53_client = boto3.client('route53')
    cloudwatch_client = boto3.client('cloudwatch', region_name=primary_region)
    
    logger.info(f"Starting automated DR failback to primary region: {primary_region}")
    
    try:
        # Check if this is a test invocation
        test_mode = event.get('test', False)
        
        if test_mode:
            logger.info("Running in test mode - no actual failback will occur")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Test mode - DR failback simulation completed successfully',
                    'timestamp': datetime.utcnow().isoformat(),
                    'test_mode': True
                })
            }
        
        # Validate primary region readiness
        readiness_check = validate_primary_region_readiness(drs_client, cloudwatch_client)
        
        if not readiness_check['ready']:
            logger.error(f"Primary region not ready for failback: {readiness_check['reason']}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f"Primary region not ready for failback: {readiness_check['reason']}",
                    'readiness_check': readiness_check,
                    'timestamp': datetime.utcnow().isoformat()
                })
            }
        
        # Get recovery instances in DR region
        logger.info("Retrieving recovery instances for failback")
        response = drs_client.describe_recovery_instances()
        recovery_instances = response.get('recoveryInstances', [])
        
        # Filter active recovery instances (not drills)
        active_instances = [
            instance for instance in recovery_instances 
            if not instance.get('isDrill', True) and 
               instance.get('recoveryInstanceProperties', {}).get('instanceState') == 'running'
        ]
        
        if not active_instances:
            logger.warning("No active recovery instances found for failback")
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'No active recovery instances found for failback'})
            }
        
        # Start failback jobs
        failback_jobs = start_failback_jobs(drs_client, active_instances)
        
        # Update Route 53 DNS records back to primary
        dns_update_result = update_dns_to_primary(route53_client)
        
        # Record failback metrics
        record_failback_metrics(cloudwatch_client, len(failback_jobs), len(active_instances))
        
        logger.info(f"DR failback completed successfully. Jobs: {failback_jobs}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Failback initiated successfully',
                'failbackJobs': failback_jobs,
                'instancesProcessed': len(active_instances),
                'dnsUpdated': dns_update_result,
                'readinessCheck': readiness_check,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f"DR failback failed: {str(e)}"
        logger.error(error_message, exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def validate_primary_region_readiness(drs_client: Any, cloudwatch_client: Any) -> Dict[str, Any]:
    """
    Validate that the primary region is ready for failback.
    
    Args:
        drs_client: DRS boto3 client
        cloudwatch_client: CloudWatch boto3 client
        
    Returns:
        Dictionary with readiness status and details
    """
    readiness = {'ready': False, 'reason': '', 'checks': {}}
    
    try:
        # Check 1: Verify source servers are healthy
        logger.info("Checking source server health in primary region")
        source_servers = drs_client.describe_source_servers()
        
        healthy_servers = [
            server for server in source_servers.get('sourceServers', [])
            if server.get('dataReplicationInfo', {}).get('replicationState') == 'CONTINUOUS'
        ]
        
        readiness['checks']['source_servers'] = {
            'total': len(source_servers.get('sourceServers', [])),
            'healthy': len(healthy_servers),
            'healthy_percentage': (len(healthy_servers) / max(len(source_servers.get('sourceServers', [])), 1)) * 100
        }
        
        # Check 2: Verify infrastructure health through CloudWatch
        logger.info("Checking infrastructure health metrics")
        end_time = datetime.utcnow()
        start_time = end_time.replace(minute=end_time.minute - 10)  # Last 10 minutes
        
        try:
            # Example health check - customize based on your applications
            metric_response = cloudwatch_client.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[],
                StartTime=start_time,
                EndTime=end_time,
                Period=300,
                Statistics=['Average']
            )
            
            readiness['checks']['infrastructure_metrics'] = {
                'available': len(metric_response.get('Datapoints', [])) > 0,
                'datapoints': len(metric_response.get('Datapoints', []))
            }
            
        except Exception as e:
            logger.warning(f"Could not retrieve infrastructure metrics: {str(e)}")
            readiness['checks']['infrastructure_metrics'] = {'available': False, 'error': str(e)}
        
        # Determine overall readiness
        source_server_ready = readiness['checks']['source_servers']['healthy_percentage'] >= 80
        
        if source_server_ready:
            readiness['ready'] = True
            readiness['reason'] = 'Primary region is ready for failback'
        else:
            readiness['reason'] = f"Source servers not ready: {readiness['checks']['source_servers']['healthy_percentage']:.1f}% healthy"
        
    except Exception as e:
        readiness['reason'] = f"Failed to validate readiness: {str(e)}"
        logger.error(readiness['reason'])
    
    return readiness

def start_failback_jobs(drs_client: Any, recovery_instances: List[Dict]) -> List[str]:
    """
    Start failback jobs for recovery instances.
    
    Args:
        drs_client: DRS boto3 client
        recovery_instances: List of recovery instance dictionaries
        
    Returns:
        List of failback job IDs
    """
    failback_jobs = []
    
    for instance in recovery_instances:
        try:
            instance_id = instance['recoveryInstanceID']
            logger.info(f"Starting failback for instance: {instance_id}")
            
            # Start failback job
            job_response = drs_client.start_failback_launch(
                recoveryInstanceIDs=[instance_id],
                tags={
                    'Purpose': 'AutomatedFailback',
                    'Timestamp': datetime.utcnow().isoformat(),
                    'TriggerType': 'Lambda'
                }
            )
            
            job_id = job_response['job']['jobID']
            failback_jobs.append(job_id)
            logger.info(f"Failback job {job_id} started for instance {instance_id}")
            
        except Exception as e:
            logger.error(f"Failed to start failback for instance {instance_id}: {str(e)}")
            continue
    
    return failback_jobs

def update_dns_to_primary(route53_client: Any) -> Dict[str, Any]:
    """
    Update Route 53 DNS records to point back to primary region.
    
    Args:
        route53_client: Route53 boto3 client
        
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
            
            # Skip private zones
            if zone.get('Config', {}).get('PrivateZone', False):
                continue
                
            # Update DNS record back to primary
            try:
                change_batch = {
                    'Changes': [{
                        'Action': 'UPSERT',
                        'ResourceRecordSet': {
                            'Name': f"app.{zone_name}",
                            'Type': 'A',
                            'SetIdentifier': 'Primary',
                            'Failover': 'PRIMARY',
                            'TTL': 60,
                            'ResourceRecords': [{'Value': '10.0.1.100'}]  # Primary IP placeholder
                        }
                    }]
                }
                
                route53_client.change_resource_record_sets(
                    HostedZoneId=zone_id,
                    ChangeBatch=change_batch
                )
                
                dns_results['updated_zones'].append(zone_name)
                logger.info(f"Updated DNS back to primary for zone: {zone_name}")
                
            except Exception as e:
                error_msg = f"Failed to update DNS for zone {zone_name}: {str(e)}"
                dns_results['errors'].append(error_msg)
                logger.error(error_msg)
                
    except Exception as e:
        error_msg = f"Failed to retrieve hosted zones: {str(e)}"
        dns_results['errors'].append(error_msg)
        logger.error(error_msg)
    
    return dns_results

def record_failback_metrics(cloudwatch_client: Any, jobs_started: int, instances_available: int) -> None:
    """
    Record custom metrics for failback operations.
    
    Args:
        cloudwatch_client: CloudWatch boto3 client
        jobs_started: Number of failback jobs started
        instances_available: Number of instances available for failback
    """
    try:
        timestamp = datetime.utcnow()
        
        # Put custom metrics
        cloudwatch_client.put_metric_data(
            Namespace='Custom/DRS/Failback',
            MetricData=[
                {
                    'MetricName': 'FailbackJobsStarted',
                    'Value': jobs_started,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'InstancesAvailableForFailback',
                    'Value': instances_available,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'FailbackSuccessRate',
                    'Value': (jobs_started / instances_available) * 100 if instances_available > 0 else 0,
                    'Unit': 'Percent',
                    'Timestamp': timestamp
                }
            ]
        )
        
        logger.info(f"Recorded failback metrics: {jobs_started} jobs started out of {instances_available} instances")
        
    except Exception as e:
        logger.error(f"Failed to record failback metrics: {str(e)}")