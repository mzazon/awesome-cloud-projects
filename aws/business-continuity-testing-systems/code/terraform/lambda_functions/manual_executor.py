import json
import boto3
import uuid
import datetime
import os

def lambda_handler(event, context):
    """
    BC Manual Test Executor Lambda Function
    
    Provides on-demand execution of business continuity tests.
    Supports individual component testing or comprehensive testing
    based on user requirements.
    """
    ssm = boto3.client('ssm')
    
    test_type = event.get('testType', 'comprehensive')
    test_components = event.get('components', ['backup', 'database', 'application'])
    test_id = str(uuid.uuid4())
    
    execution_results = []
    
    try:
        print(f"Starting manual BC test execution - Type: {test_type}, Components: {test_components}")
        
        for component in test_components:
            if component == 'backup':
                result = execute_backup_test(ssm, test_id)
                execution_results.append(result)
            elif component == 'database':
                result = execute_database_test(ssm, test_id)
                execution_results.append(result)
            elif component == 'application':
                result = execute_application_test(ssm, test_id)
                execution_results.append(result)
            else:
                execution_results.append({
                    'component': component,
                    'status': 'skipped',
                    'message': f'Unknown component: {component}',
                    'timestamp': datetime.datetime.utcnow().isoformat()
                })
        
        # Generate summary
        successful_tests = sum(1 for result in execution_results if result['status'] == 'started')
        total_tests = len(execution_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'testType': test_type,
                'executionId': test_id,
                'summary': {
                    'totalTests': total_tests,
                    'successfulTests': successful_tests,
                    'failedTests': total_tests - successful_tests
                },
                'results': execution_results,
                'message': f'Manual BC test execution completed. {successful_tests}/{total_tests} tests started successfully.'
            }, indent=2)
        }
        
    except Exception as e:
        error_message = f'Failed to execute manual BC tests: {str(e)}'
        print(f'Error: {error_message}')
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'testType': test_type,
                'executionId': test_id,
                'partialResults': execution_results
            })
        }

def execute_backup_test(ssm, test_id):
    """Execute backup validation test"""
    try:
        print(f"Executing backup validation test for execution ID: {test_id}")
        
        # Check if required environment variables are set
        test_instance_id = os.environ.get('TEST_INSTANCE_ID')
        if not test_instance_id or test_instance_id == '':
            return {
                'component': 'backup',
                'status': 'skipped',
                'message': 'TEST_INSTANCE_ID not configured. Please set this variable to enable backup testing.',
                'timestamp': datetime.datetime.utcnow().isoformat()
            }
        
        response = ssm.start_automation_execution(
            DocumentName=f'BC-BackupValidation-{os.environ["PROJECT_ID"]}',
            Parameters={
                'InstanceId': [test_instance_id],
                'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
                'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
            }
        )
        
        return {
            'component': 'backup',
            'executionId': response['AutomationExecutionId'],
            'status': 'started',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'message': 'Backup validation test started successfully'
        }
        
    except Exception as e:
        return {
            'component': 'backup',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'message': f'Failed to start backup validation test: {str(e)}'
        }

def execute_database_test(ssm, test_id):
    """Execute database recovery test"""
    try:
        print(f"Executing database recovery test for execution ID: {test_id}")
        
        # Check if required environment variables are set
        db_instance_id = os.environ.get('DB_INSTANCE_ID')
        if not db_instance_id or db_instance_id == '':
            return {
                'component': 'database',
                'status': 'skipped',
                'message': 'DB_INSTANCE_ID not configured. Please set this variable to enable database testing.',
                'timestamp': datetime.datetime.utcnow().isoformat()
            }
        
        # Generate unique test database identifier
        test_db_id = f'manual-test-{test_id[:8]}'
        
        response = ssm.start_automation_execution(
            DocumentName=f'BC-DatabaseRecovery-{os.environ["PROJECT_ID"]}',
            Parameters={
                'DBInstanceIdentifier': [db_instance_id],
                'DBSnapshotIdentifier': [os.environ.get('DB_SNAPSHOT_ID', 'latest-snapshot')],
                'TestDBInstanceIdentifier': [test_db_id],
                'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
            }
        )
        
        return {
            'component': 'database',
            'executionId': response['AutomationExecutionId'],
            'status': 'started',
            'testDatabaseId': test_db_id,
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'message': 'Database recovery test started successfully'
        }
        
    except Exception as e:
        return {
            'component': 'database',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'message': f'Failed to start database recovery test: {str(e)}'
        }

def execute_application_test(ssm, test_id):
    """Execute application failover test"""
    try:
        print(f"Executing application failover test for execution ID: {test_id}")
        
        # Check if required environment variables are set
        primary_alb = os.environ.get('PRIMARY_ALB_ARN')
        secondary_alb = os.environ.get('SECONDARY_ALB_ARN')
        hosted_zone_id = os.environ.get('HOSTED_ZONE_ID')
        domain_name = os.environ.get('DOMAIN_NAME')
        
        missing_config = []
        if not primary_alb or primary_alb == '':
            missing_config.append('PRIMARY_ALB_ARN')
        if not secondary_alb or secondary_alb == '':
            missing_config.append('SECONDARY_ALB_ARN')
        if not hosted_zone_id or hosted_zone_id == '':
            missing_config.append('HOSTED_ZONE_ID')
        if not domain_name or domain_name == '':
            missing_config.append('DOMAIN_NAME')
        
        if missing_config:
            return {
                'component': 'application',
                'status': 'skipped',
                'message': f'Application failover configuration incomplete. Missing: {", ".join(missing_config)}',
                'timestamp': datetime.datetime.utcnow().isoformat()
            }
        
        response = ssm.start_automation_execution(
            DocumentName=f'BC-ApplicationFailover-{os.environ["PROJECT_ID"]}',
            Parameters={
                'PrimaryLoadBalancerArn': [primary_alb],
                'SecondaryLoadBalancerArn': [secondary_alb],
                'Route53HostedZoneId': [hosted_zone_id],
                'DomainName': [domain_name],
                'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
            }
        )
        
        return {
            'component': 'application',
            'executionId': response['AutomationExecutionId'],
            'status': 'started',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'message': 'Application failover test started successfully',
            'testConfiguration': {
                'primaryALB': primary_alb,
                'secondaryALB': secondary_alb,
                'hostedZoneId': hosted_zone_id,
                'domainName': domain_name
            }
        }
        
    except Exception as e:
        return {
            'component': 'application',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'message': f'Failed to start application failover test: {str(e)}'
        }

def get_test_status(ssm, execution_id):
    """Get the status of a specific automation execution"""
    try:
        response = ssm.describe_automation_executions(
            Filters=[
                {
                    'Key': 'ExecutionId',
                    'Values': [execution_id]
                }
            ]
        )
        
        if response['AutomationExecutions']:
            execution = response['AutomationExecutions'][0]
            return {
                'executionId': execution_id,
                'status': execution['AutomationExecutionStatus'],
                'startTime': execution.get('ExecutionStartTime', '').isoformat() if execution.get('ExecutionStartTime') else None,
                'endTime': execution.get('ExecutionEndTime', '').isoformat() if execution.get('ExecutionEndTime') else None,
                'documentName': execution['DocumentName']
            }
        else:
            return {
                'executionId': execution_id,
                'status': 'NOT_FOUND',
                'message': 'Execution not found'
            }
            
    except Exception as e:
        return {
            'executionId': execution_id,
            'status': 'ERROR',
            'error': str(e)
        }