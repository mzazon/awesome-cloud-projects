import json
import boto3
import datetime
import uuid
import os
from typing import Dict, List

def lambda_handler(event, context):
    """
    BC Test Orchestrator Lambda Function
    
    Coordinates business continuity testing based on test type and schedules.
    Executes different combinations of tests (backup, database, application)
    and generates comprehensive reports.
    """
    ssm = boto3.client('ssm')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    test_type = event.get('testType', 'daily')
    test_id = str(uuid.uuid4())
    
    test_results = {
        'testId': test_id,
        'testType': test_type,
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'results': []
    }
    
    try:
        # Execute tests based on type
        if test_type in ['daily', 'weekly', 'monthly']:
            # Execute backup validation for all test types
            backup_result = execute_backup_validation(ssm, test_id)
            test_results['results'].append(backup_result)
        
        if test_type in ['weekly', 'monthly']:
            # Execute database recovery test for weekly and monthly
            db_result = execute_database_recovery_test(ssm, test_id)
            test_results['results'].append(db_result)
        
        if test_type == 'monthly':
            # Execute full application failover test only for monthly
            app_result = execute_application_failover_test(ssm, test_id)
            test_results['results'].append(app_result)
        
        # Store results in S3
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=f'test-results/{test_type}/{test_id}/results.json',
            Body=json.dumps(test_results, indent=2),
            ContentType='application/json'
        )
        
        # Generate summary report
        summary = generate_test_summary(test_results)
        
        # Send notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'BC Testing {test_type.title()} Report - {test_id[:8]}',
            Message=summary
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'testId': test_id,
                'summary': summary,
                'resultsLocation': f's3://{os.environ["RESULTS_BUCKET"]}/test-results/{test_type}/{test_id}/results.json'
            })
        }
        
    except Exception as e:
        error_message = f'BC testing failed: {str(e)}'
        print(f'Error: {error_message}')
        
        # Send failure notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'BC Testing Failed - {test_id[:8]}',
            Message=error_message
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'testId': test_id
            })
        }

def execute_backup_validation(ssm, test_id):
    """Execute backup validation automation document"""
    try:
        response = ssm.start_automation_execution(
            DocumentName=f'BC-BackupValidation-${project_id}',
            Parameters={
                'InstanceId': [os.environ.get('TEST_INSTANCE_ID', 'i-1234567890abcdef0')],
                'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
                'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
            }
        )
        
        return {
            'test': 'backup_validation',
            'executionId': response['AutomationExecutionId'],
            'status': 'started',
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            'test': 'backup_validation',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }

def execute_database_recovery_test(ssm, test_id):
    """Execute database recovery automation document"""
    try:
        response = ssm.start_automation_execution(
            DocumentName=f'BC-DatabaseRecovery-${project_id}',
            Parameters={
                'DBInstanceIdentifier': [os.environ.get('DB_INSTANCE_ID', 'prod-db')],
                'DBSnapshotIdentifier': [os.environ.get('DB_SNAPSHOT_ID', 'latest-snapshot')],
                'TestDBInstanceIdentifier': [f'test-db-{test_id[:8]}'],
                'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
            }
        )
        
        return {
            'test': 'database_recovery',
            'executionId': response['AutomationExecutionId'],
            'status': 'started',
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            'test': 'database_recovery',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }

def execute_application_failover_test(ssm, test_id):
    """Execute application failover automation document"""
    try:
        response = ssm.start_automation_execution(
            DocumentName=f'BC-ApplicationFailover-${project_id}',
            Parameters={
                'PrimaryLoadBalancerArn': [os.environ.get('PRIMARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/1234567890123456')],
                'SecondaryLoadBalancerArn': [os.environ.get('SECONDARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/secondary/6543210987654321')],
                'Route53HostedZoneId': [os.environ.get('HOSTED_ZONE_ID', 'Z1234567890123')],
                'DomainName': [os.environ.get('DOMAIN_NAME', 'app.example.com')],
                'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
            }
        )
        
        return {
            'test': 'application_failover',
            'executionId': response['AutomationExecutionId'],
            'status': 'started',
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {
            'test': 'application_failover',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }

def generate_test_summary(test_results):
    """Generate human-readable test summary"""
    total_tests = len(test_results['results'])
    successful_tests = sum(1 for result in test_results['results'] if result['status'] == 'started')
    failed_tests = total_tests - successful_tests
    
    summary = f"""
Business Continuity Testing Summary
Test ID: {test_results['testId']}
Test Type: {test_results['testType'].title()}
Timestamp: {test_results['timestamp']}

Tests Executed: {total_tests}
Successfully Started: {successful_tests}
Failed to Start: {failed_tests}

Test Results:
"""
    
    for result in test_results['results']:
        status_icon = "✅" if result['status'] == 'started' else "❌"
        summary += f"{status_icon} {result['test'].replace('_', ' ').title()}: {result['status']}\n"
        if 'executionId' in result:
            summary += f"   Execution ID: {result['executionId']}\n"
        if 'error' in result:
            summary += f"   Error: {result['error']}\n"
    
    summary += f"""
Results stored in: s3://{os.environ['RESULTS_BUCKET']}/test-results/{test_results['testType']}/{test_results['testId']}/

View execution details in Systems Manager Console:
https://console.aws.amazon.com/systems-manager/automation/executions

Monitor progress in CloudWatch Dashboard.
"""
    
    return summary