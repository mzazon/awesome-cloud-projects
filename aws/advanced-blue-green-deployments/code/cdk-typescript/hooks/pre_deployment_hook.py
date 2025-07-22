import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codedeploy = boto3.client('codedeploy')
ecs = boto3.client('ecs')
lambda_client = boto3.client('lambda')

def lambda_handler(event, context):
    """
    Pre-deployment validation hook
    """
    try:
        # Extract deployment information
        deployment_id = event['DeploymentId']
        lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']
        
        logger.info(f"Running pre-deployment validation for deployment: {deployment_id}")
        
        # Perform validation checks
        validation_result = validate_deployment_readiness(event)
        
        # Report back to CodeDeploy
        if validation_result['success']:
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Succeeded'
            )
            logger.info("Pre-deployment validation passed")
        else:
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Failed'
            )
            logger.error(f"Pre-deployment validation failed: {validation_result['reason']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        logger.error(f"Error in pre-deployment hook: {str(e)}")
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

def validate_deployment_readiness(event):
    """
    Validate that the deployment is ready to proceed
    """
    try:
        # Check if it's ECS or Lambda deployment
        if 'ECS' in event.get('ApplicationName', ''):
            return validate_ecs_readiness(event)
        else:
            return validate_lambda_readiness(event)
            
    except Exception as e:
        return {'success': False, 'reason': f'Validation error: {str(e)}'}

def validate_ecs_readiness(event):
    """
    Validate ECS deployment readiness
    """
    try:
        # In a real implementation, you would:
        # 1. Check ECS cluster capacity
        # 2. Validate task definition
        # 3. Check ALB health
        # 4. Verify network connectivity
        # 5. Check dependent services
        
        logger.info("Validating ECS deployment readiness...")
        
        # Simulate validation checks
        checks = {
            'cluster_capacity': True,
            'task_definition_valid': True,
            'alb_healthy': True,
            'network_connectivity': True,
            'dependencies_available': True
        }
        
        all_passed = all(checks.values())
        
        if not all_passed:
            failed_checks = [k for k, v in checks.items() if not v]
            return {'success': False, 'reason': f'Failed checks: {failed_checks}'}
        
        return {'success': True, 'reason': 'All ECS validation checks passed'}
        
    except Exception as e:
        return {'success': False, 'reason': f'ECS validation error: {str(e)}'}

def validate_lambda_readiness(event):
    """
    Validate Lambda deployment readiness
    """
    try:
        # In a real implementation, you would:
        # 1. Check Lambda function exists
        # 2. Validate function configuration
        # 3. Check IAM permissions
        # 4. Verify dependencies
        # 5. Test function with sample event
        
        logger.info("Validating Lambda deployment readiness...")
        
        # Simulate validation checks
        checks = {
            'function_exists': True,
            'configuration_valid': True,
            'permissions_valid': True,
            'dependencies_available': True,
            'test_execution_successful': True
        }
        
        all_passed = all(checks.values())
        
        if not all_passed:
            failed_checks = [k for k, v in checks.items() if not v]
            return {'success': False, 'reason': f'Failed checks: {failed_checks}'}
        
        return {'success': True, 'reason': 'All Lambda validation checks passed'}
        
    except Exception as e:
        return {'success': False, 'reason': f'Lambda validation error: {str(e)}'}