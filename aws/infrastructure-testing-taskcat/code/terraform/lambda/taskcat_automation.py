#!/usr/bin/env python3
"""
TaskCat Automation Lambda Function
Provides automated TaskCat test execution and result processing
"""

import json
import boto3
import logging
import os
import subprocess
import tempfile
from datetime import datetime
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
cloudformation_client = boto3.client('cloudformation')

# Environment variables
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', '${s3_bucket_name}')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
LOG_GROUP_NAME = os.environ.get('LOG_GROUP_NAME', '${log_group_name}')
PROJECT_NAME = os.environ.get('PROJECT_NAME', '${project_name}')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for TaskCat automation
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with execution results
    """
    try:
        logger.info(f"Starting TaskCat automation for project: {PROJECT_NAME}")
        
        # Parse event data
        action = event.get('action', 'run_tests')
        test_name = event.get('test_name', '')
        notification_required = event.get('notify', True)
        
        # Execute requested action
        if action == 'run_tests':
            result = run_taskcat_tests(test_name)
        elif action == 'cleanup_stacks':
            result = cleanup_test_stacks()
        elif action == 'generate_report':
            result = generate_test_report()
        elif action == 'validate_templates':
            result = validate_templates()
        else:
            raise ValueError(f"Unknown action: {action}")
        
        # Send notification if required
        if notification_required and SNS_TOPIC_ARN:
            send_notification(result)
        
        logger.info("TaskCat automation completed successfully")
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        logger.error(f"TaskCat automation failed: {str(e)}")
        
        # Send error notification
        if SNS_TOPIC_ARN:
            send_error_notification(str(e))
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }


def run_taskcat_tests(test_name: str = '') -> Dict[str, Any]:
    """
    Execute TaskCat tests
    
    Args:
        test_name: Specific test name to run (optional)
        
    Returns:
        Test execution results
    """
    logger.info(f"Running TaskCat tests{f' for: {test_name}' if test_name else ''}")
    
    try:
        # Create temporary directory for test execution
        with tempfile.TemporaryDirectory() as temp_dir:
            
            # Download TaskCat configuration
            config_path = os.path.join(temp_dir, '.taskcat.yml')
            s3_client.download_file(
                S3_BUCKET_NAME,
                'config/.taskcat.yml',
                config_path
            )
            
            # Download CloudFormation templates
            download_templates(temp_dir)
            
            # Change to temp directory
            os.chdir(temp_dir)
            
            # Install TaskCat if not available
            try:
                subprocess.run(['taskcat', '--version'], check=True, capture_output=True)
            except (subprocess.CalledProcessError, FileNotFoundError):
                logger.info("Installing TaskCat...")
                subprocess.run(['pip', 'install', 'taskcat'], check=True)
            
            # Run TaskCat tests
            cmd = ['taskcat', 'test', 'run']
            if test_name:
                cmd.append(test_name)
            cmd.extend(['--output-directory', './outputs'])
            
            logger.info(f"Executing command: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            # Upload test results to S3
            upload_test_results(temp_dir)
            
            # Parse test results
            test_results = parse_test_results(result)
            
            return {
                'status': 'success' if result.returncode == 0 else 'failed',
                'return_code': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'test_results': test_results,
                'timestamp': datetime.utcnow().isoformat()
            }
            
    except Exception as e:
        logger.error(f"Test execution failed: {str(e)}")
        raise


def cleanup_test_stacks() -> Dict[str, Any]:
    """
    Clean up TaskCat test stacks across all regions
    
    Returns:
        Cleanup results
    """
    logger.info("Starting TaskCat stack cleanup")
    
    cleanup_results = []
    regions = ['us-east-1', 'us-west-2', 'eu-west-1']  # Default regions
    
    for region in regions:
        try:
            cf_client = boto3.client('cloudformation', region_name=region)
            
            # List stacks with TaskCat prefix
            response = cf_client.list_stacks(
                StackStatusFilter=[
                    'CREATE_COMPLETE',
                    'CREATE_FAILED',
                    'UPDATE_COMPLETE',
                    'UPDATE_FAILED',
                    'ROLLBACK_COMPLETE',
                    'ROLLBACK_FAILED'
                ]
            )
            
            taskcat_stacks = [
                stack for stack in response['StackSummaries']
                if stack['StackName'].startswith(PROJECT_NAME)
            ]
            
            for stack in taskcat_stacks:
                try:
                    logger.info(f"Deleting stack: {stack['StackName']} in {region}")
                    cf_client.delete_stack(StackName=stack['StackName'])
                    
                    cleanup_results.append({
                        'stack_name': stack['StackName'],
                        'region': region,
                        'status': 'deletion_initiated',
                        'timestamp': datetime.utcnow().isoformat()
                    })
                    
                except Exception as e:
                    logger.error(f"Failed to delete stack {stack['StackName']}: {str(e)}")
                    cleanup_results.append({
                        'stack_name': stack['StackName'],
                        'region': region,
                        'status': 'deletion_failed',
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat()
                    })
                    
        except Exception as e:
            logger.error(f"Failed to process region {region}: {str(e)}")
    
    return {
        'cleanup_results': cleanup_results,
        'total_stacks': len(cleanup_results),
        'timestamp': datetime.utcnow().isoformat()
    }


def validate_templates() -> Dict[str, Any]:
    """
    Validate CloudFormation templates using AWS CLI
    
    Returns:
        Validation results
    """
    logger.info("Validating CloudFormation templates")
    
    validation_results = []
    
    try:
        # List template files in S3
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET_NAME,
            Prefix='templates/'
        )
        
        for obj in response.get('Contents', []):
            if obj['Key'].endswith(('.yaml', '.yml', '.json')):
                try:
                    # Download template
                    template_content = s3_client.get_object(
                        Bucket=S3_BUCKET_NAME,
                        Key=obj['Key']
                    )['Body'].read().decode('utf-8')
                    
                    # Validate template
                    cloudformation_client.validate_template(
                        TemplateBody=template_content
                    )
                    
                    validation_results.append({
                        'template': obj['Key'],
                        'status': 'valid',
                        'timestamp': datetime.utcnow().isoformat()
                    })
                    
                except Exception as e:
                    logger.error(f"Template validation failed for {obj['Key']}: {str(e)}")
                    validation_results.append({
                        'template': obj['Key'],
                        'status': 'invalid',
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat()
                    })
    
    except Exception as e:
        logger.error(f"Template validation process failed: {str(e)}")
        raise
    
    return {
        'validation_results': validation_results,
        'total_templates': len(validation_results),
        'valid_templates': len([r for r in validation_results if r['status'] == 'valid']),
        'timestamp': datetime.utcnow().isoformat()
    }


def download_templates(temp_dir: str) -> None:
    """
    Download CloudFormation templates from S3
    
    Args:
        temp_dir: Temporary directory path
    """
    logger.info("Downloading CloudFormation templates")
    
    templates_dir = os.path.join(temp_dir, 'templates')
    os.makedirs(templates_dir, exist_ok=True)
    
    try:
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET_NAME,
            Prefix='templates/'
        )
        
        for obj in response.get('Contents', []):
            local_path = os.path.join(temp_dir, obj['Key'])
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            
            s3_client.download_file(
                S3_BUCKET_NAME,
                obj['Key'],
                local_path
            )
            
    except Exception as e:
        logger.error(f"Failed to download templates: {str(e)}")
        raise


def upload_test_results(temp_dir: str) -> None:
    """
    Upload test results and reports to S3
    
    Args:
        temp_dir: Temporary directory path
    """
    logger.info("Uploading test results to S3")
    
    outputs_dir = os.path.join(temp_dir, 'outputs')
    if not os.path.exists(outputs_dir):
        return
    
    try:
        for root, dirs, files in os.walk(outputs_dir):
            for file in files:
                local_path = os.path.join(root, file)
                s3_key = f"test-results/{datetime.utcnow().strftime('%Y/%m/%d')}/{file}"
                
                s3_client.upload_file(
                    local_path,
                    S3_BUCKET_NAME,
                    s3_key
                )
                
    except Exception as e:
        logger.error(f"Failed to upload test results: {str(e)}")


def parse_test_results(result: subprocess.CompletedProcess) -> Dict[str, Any]:
    """
    Parse TaskCat test execution results
    
    Args:
        result: Subprocess result from TaskCat execution
        
    Returns:
        Parsed test results
    """
    try:
        # Parse stdout for test results
        output_lines = result.stdout.split('\n')
        
        tests_passed = 0
        tests_failed = 0
        
        for line in output_lines:
            if 'PASSED' in line:
                tests_passed += 1
            elif 'FAILED' in line:
                tests_failed += 1
        
        return {
            'tests_passed': tests_passed,
            'tests_failed': tests_failed,
            'total_tests': tests_passed + tests_failed,
            'success_rate': tests_passed / (tests_passed + tests_failed) if (tests_passed + tests_failed) > 0 else 0
        }
        
    except Exception as e:
        logger.error(f"Failed to parse test results: {str(e)}")
        return {
            'tests_passed': 0,
            'tests_failed': 0,
            'total_tests': 0,
            'success_rate': 0,
            'parse_error': str(e)
        }


def generate_test_report() -> Dict[str, Any]:
    """
    Generate comprehensive test report
    
    Returns:
        Report generation results
    """
    logger.info("Generating test report")
    
    try:
        # Get latest test results from S3
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET_NAME,
            Prefix='test-results/',
            MaxKeys=100
        )
        
        report_data = {
            'project_name': PROJECT_NAME,
            'report_timestamp': datetime.utcnow().isoformat(),
            'total_test_files': len(response.get('Contents', [])),
            'latest_results': []
        }
        
        # Add latest test files to report
        for obj in response.get('Contents', [])[:10]:  # Latest 10 files
            report_data['latest_results'].append({
                'file_name': obj['Key'],
                'last_modified': obj['LastModified'].isoformat(),
                'size': obj['Size']
            })
        
        # Upload report to S3
        report_key = f"reports/test-report-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.json"
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=report_key,
            Body=json.dumps(report_data, indent=2)
        )
        
        return {
            'report_generated': True,
            'report_s3_key': report_key,
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Report generation failed: {str(e)}")
        raise


def send_notification(result: Dict[str, Any]) -> None:
    """
    Send SNS notification with test results
    
    Args:
        result: Test execution results
    """
    try:
        if not SNS_TOPIC_ARN:
            return
        
        subject = f"TaskCat Test Results - {PROJECT_NAME}"
        
        message = f"""
TaskCat Test Execution Complete

Project: {PROJECT_NAME}
Status: {result.get('status', 'unknown')}
Timestamp: {result.get('timestamp', datetime.utcnow().isoformat())}

Test Results:
{json.dumps(result.get('test_results', {}), indent=2)}

For detailed results, check the S3 bucket: {S3_BUCKET_NAME}
        """
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")


def send_error_notification(error_message: str) -> None:
    """
    Send SNS notification for errors
    
    Args:
        error_message: Error message to send
    """
    try:
        if not SNS_TOPIC_ARN:
            return
        
        subject = f"TaskCat Test Error - {PROJECT_NAME}"
        
        message = f"""
TaskCat Test Execution Failed

Project: {PROJECT_NAME}
Error: {error_message}
Timestamp: {datetime.utcnow().isoformat()}

Please check the CloudWatch logs for more details: {LOG_GROUP_NAME}
        """
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        
    except Exception as e:
        logger.error(f"Failed to send error notification: {str(e)}")