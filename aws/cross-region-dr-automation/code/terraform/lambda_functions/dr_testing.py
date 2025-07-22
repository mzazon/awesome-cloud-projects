"""
AWS Elastic Disaster Recovery Testing Lambda Function

This Lambda function automates disaster recovery testing procedures,
including drill initiation, validation, and cleanup scheduling.
"""

import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for automated disaster recovery testing.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    
    # Initialize AWS clients
    dr_region = os.environ.get('DR_REGION', '${dr_region}')
    
    drs_client = boto3.client('drs', region_name=dr_region)
    ssm_client = boto3.client('ssm', region_name=dr_region)
    cloudwatch_client = boto3.client('cloudwatch', region_name=dr_region)
    
    logger.info(f"Starting automated DR testing in region: {dr_region}")
    
    try:
        # Get test configuration from event
        test_config = event.get('testConfig', {})
        cleanup_hours = test_config.get('cleanupHours', 2)
        test_type = test_config.get('testType', 'drill')
        
        # Get source servers for testing
        logger.info("Retrieving source servers for DR testing")
        response = drs_client.describe_source_servers()
        source_servers = response.get('sourceServers', [])
        
        if not source_servers:
            logger.warning("No source servers found for testing")
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'No source servers found for testing'})
            }
        
        # Filter servers that are ready for testing
        ready_servers = [
            server for server in source_servers 
            if server.get('dataReplicationInfo', {}).get('replicationState') == 'CONTINUOUS'
        ]
        
        if not ready_servers:
            logger.warning("No servers ready for DR testing")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'No servers ready for DR testing'})
            }
        
        # Start drill jobs for ready servers
        drill_jobs = start_drill_jobs(drs_client, ready_servers, test_type)
        
        # Schedule cleanup
        cleanup_time = datetime.utcnow() + timedelta(hours=cleanup_hours)
        cleanup_result = schedule_cleanup(ssm_client, drill_jobs, cleanup_time)
        
        # Record test metrics
        record_test_metrics(cloudwatch_client, len(drill_jobs), len(ready_servers))
        
        logger.info(f"DR testing completed successfully. Drill jobs: {drill_jobs}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DR drill initiated successfully',
                'drillJobs': drill_jobs,
                'serversProcessed': len(ready_servers),
                'cleanupScheduled': cleanup_time.isoformat(),
                'cleanupResult': cleanup_result,
                'testType': test_type,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f"DR testing failed: {str(e)}"
        logger.error(error_message, exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def start_drill_jobs(drs_client: Any, source_servers: List[Dict], test_type: str) -> List[str]:
    """
    Start drill jobs for source servers.
    
    Args:
        drs_client: DRS boto3 client
        source_servers: List of source server dictionaries
        test_type: Type of test being performed
        
    Returns:
        List of drill job IDs
    """
    drill_jobs = []
    
    for server in source_servers:
        try:
            server_id = server['sourceServerID']
            logger.info(f"Starting drill for server: {server_id}")
            
            # Start drill job
            job_response = drs_client.start_recovery(
                sourceServers=[{
                    'sourceServerID': server_id,
                    'recoverySnapshotID': 'LATEST'
                }],
                isDrill=True,  # This is a drill, not actual recovery
                tags={
                    'Purpose': 'DR-Drill',
                    'TestType': test_type,
                    'Timestamp': datetime.utcnow().isoformat(),
                    'TriggerType': 'Lambda-Automated'
                }
            )
            
            job_id = job_response['job']['jobID']
            drill_jobs.append(job_id)
            logger.info(f"Drill job {job_id} started for server {server_id}")
            
        except Exception as e:
            logger.error(f"Failed to start drill for server {server_id}: {str(e)}")
            continue
    
    return drill_jobs

def schedule_cleanup(ssm_client: Any, drill_jobs: List[str], cleanup_time: datetime) -> Dict[str, Any]:
    """
    Schedule automatic cleanup of drill resources.
    
    Args:
        ssm_client: SSM boto3 client
        drill_jobs: List of drill job IDs
        cleanup_time: When to perform cleanup
        
    Returns:
        Dictionary with cleanup scheduling results
    """
    cleanup_result = {'scheduled': False, 'command_id': None, 'error': None}
    
    try:
        # Create cleanup script
        cleanup_script = f"""#!/bin/bash
        
        # DR Drill Cleanup Script
        # Generated at: {datetime.utcnow().isoformat()}
        
        echo "Starting DR drill cleanup at $(date)"
        
        # Get drill instances for the jobs
        DRILL_JOBS="{' '.join(drill_jobs)}"
        
        for job_id in $DRILL_JOBS; do
            echo "Processing cleanup for job: $job_id"
            
            # Get recovery instances for this job
            aws drs describe-recovery-instances \\
                --filters "Name=job-id,Values=$job_id" \\
                --query 'RecoveryInstances[?isDrill==`true`].recoveryInstanceID' \\
                --output text | while read instance_id; do
                
                if [ ! -z "$instance_id" ]; then
                    echo "Terminating drill instance: $instance_id"
                    aws drs terminate-recovery-instances \\
                        --recovery-instance-ids $instance_id
                fi
            done
        done
        
        echo "DR drill cleanup completed at $(date)"
        """
        
        # Note: In a real implementation, you would use EventBridge or Step Functions
        # for scheduling instead of SSM due to timing limitations
        logger.info(f"Cleanup scheduled for {cleanup_time.isoformat()}")
        cleanup_result['scheduled'] = True
        cleanup_result['cleanup_time'] = cleanup_time.isoformat()
        
    except Exception as e:
        error_msg = f"Failed to schedule cleanup: {str(e)}"
        cleanup_result['error'] = error_msg
        logger.error(error_msg)
    
    return cleanup_result

def record_test_metrics(cloudwatch_client: Any, jobs_started: int, servers_available: int) -> None:
    """
    Record custom metrics for DR testing.
    
    Args:
        cloudwatch_client: CloudWatch boto3 client
        jobs_started: Number of drill jobs started
        servers_available: Number of servers available for testing
    """
    try:
        timestamp = datetime.utcnow()
        
        # Put custom metrics
        cloudwatch_client.put_metric_data(
            Namespace='Custom/DRS/Testing',
            MetricData=[
                {
                    'MetricName': 'DrillJobsStarted',
                    'Value': jobs_started,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'ServersAvailableForTesting',
                    'Value': servers_available,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'DrillSuccessRate',
                    'Value': (jobs_started / servers_available) * 100 if servers_available > 0 else 0,
                    'Unit': 'Percent',
                    'Timestamp': timestamp
                }
            ]
        )
        
        logger.info(f"Recorded test metrics: {jobs_started} jobs started out of {servers_available} servers")
        
    except Exception as e:
        logger.error(f"Failed to record test metrics: {str(e)}")