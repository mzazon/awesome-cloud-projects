import json
import boto3
import logging
import time
import os
import urllib3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codedeploy = boto3.client('codedeploy')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Post-deployment validation hook
    """
    try:
        # Extract deployment information
        deployment_id = event['DeploymentId']
        lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']
        
        logger.info(f"Running post-deployment validation for deployment: {deployment_id}")
        
        # Perform post-deployment tests
        validation_result = validate_deployment_success(event)
        
        # Report back to CodeDeploy
        if validation_result['success']:
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Succeeded'
            )
            logger.info("Post-deployment validation passed")
        else:
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Failed'
            )
            logger.error(f"Post-deployment validation failed: {validation_result['reason']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        logger.error(f"Error in post-deployment hook: {str(e)}")
        # Report failure to CodeDeploy
        try:
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Failed'
            )
        except:
            pass
        return {'statusCode': 500}

def validate_deployment_success(event):
    """
    Validate that the deployment was successful
    """
    try:
        # Check if it's ECS or Lambda deployment
        if 'ECS' in event.get('ApplicationName', ''):
            return validate_ecs_deployment(event)
        else:
            return validate_lambda_deployment(event)
            
    except Exception as e:
        return {'success': False, 'reason': f'Validation error: {str(e)}'}

def validate_ecs_deployment(event):
    """
    Validate ECS deployment by testing endpoints
    """
    try:
        # Get ALB DNS from environment variable
        alb_dns = os.environ.get('ALB_DNS', 'example.com')
        
        logger.info(f"Testing ECS deployment at: {alb_dns}")
        
        # Create HTTP client
        http = urllib3.PoolManager()
        
        # Test health endpoint
        health_url = f"http://{alb_dns}/health"
        try:
            response = http.request('GET', health_url, timeout=10)
            if response.status != 200:
                return {'success': False, 'reason': f'Health check failed: {response.status}'}
            
            health_data = json.loads(response.data.decode('utf-8'))
            if health_data.get('status') != 'healthy':
                return {'success': False, 'reason': 'Health check returned unhealthy status'}
            
        except Exception as e:
            return {'success': False, 'reason': f'Health check request failed: {str(e)}'}
        
        # Test main endpoint
        main_url = f"http://{alb_dns}/"
        try:
            response = http.request('GET', main_url, timeout=10)
            if response.status != 200:
                return {'success': False, 'reason': f'Main endpoint failed: {response.status}'}
            
        except Exception as e:
            return {'success': False, 'reason': f'Main endpoint request failed: {str(e)}'}
        
        # Record success metrics
        cloudwatch.put_metric_data(
            Namespace='Deployment/Validation',
            MetricData=[
                {
                    'MetricName': 'PostDeploymentValidation',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'DeploymentType', 'Value': 'ECS'},
                        {'Name': 'Status', 'Value': 'Success'}
                    ]
                }
            ]
        )
        
        return {'success': True, 'reason': 'ECS deployment validation passed'}
        
    except Exception as e:
        # Record failure metrics
        cloudwatch.put_metric_data(
            Namespace='Deployment/Validation',
            MetricData=[
                {
                    'MetricName': 'PostDeploymentValidation',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'DeploymentType', 'Value': 'ECS'},
                        {'Name': 'Status', 'Value': 'Failure'}
                    ]
                }
            ]
        )
        return {'success': False, 'reason': f'ECS validation error: {str(e)}'}

def validate_lambda_deployment(event):
    """
    Validate Lambda deployment by invoking function
    """
    try:
        function_name = os.environ.get('LAMBDA_FUNCTION_NAME', 'unknown')
        
        logger.info(f"Testing Lambda deployment: {function_name}")
        
        # Test Lambda function directly
        lambda_client = boto3.client('lambda')
        
        # Test health endpoint
        test_event = {
            'httpMethod': 'GET',
            'path': '/health'
        }
        
        response = lambda_client.invoke(
            FunctionName=function_name,
            Payload=json.dumps(test_event)
        )
        
        if response['StatusCode'] != 200:
            return {'success': False, 'reason': f'Lambda invocation failed: {response["StatusCode"]}'}
        
        payload = json.loads(response['Payload'].read())
        
        if payload['statusCode'] != 200:
            return {'success': False, 'reason': f'Lambda health check failed: {payload["statusCode"]}'}
        
        # Record success metrics
        cloudwatch.put_metric_data(
            Namespace='Deployment/Validation',
            MetricData=[
                {
                    'MetricName': 'PostDeploymentValidation',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'DeploymentType', 'Value': 'Lambda'},
                        {'Name': 'Status', 'Value': 'Success'}
                    ]
                }
            ]
        )
        
        return {'success': True, 'reason': 'Lambda deployment validation passed'}
        
    except Exception as e:
        # Record failure metrics
        cloudwatch.put_metric_data(
            Namespace='Deployment/Validation',
            MetricData=[
                {
                    'MetricName': 'PostDeploymentValidation',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'DeploymentType', 'Value': 'Lambda'},
                        {'Name': 'Status', 'Value': 'Failure'}
                    ]
                }
            ]
        )
        return {'success': False, 'reason': f'Lambda validation error: {str(e)}'}