"""
Secure Package Distribution Function

This Cloud Function handles secure package distribution workflows by:
1. Retrieving packages from Artifact Registry
2. Accessing credentials from Secret Manager
3. Distributing packages to target environments
4. Logging all operations for audit trails
"""

import json
import logging
import os
import time
from typing import Dict, Any, Optional

from google.cloud import secretmanager
from google.cloud import tasks_v2
from google.cloud import logging as cloud_logging
from google.cloud import artifactregistry_v1
from google.auth import default
import functions_framework

# Initialize Cloud Logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Initialize clients
SECRET_CLIENT = secretmanager.SecretManagerServiceClient()
TASKS_CLIENT = tasks_v2.CloudTasksClient()
ARTIFACT_CLIENT = artifactregistry_v1.ArtifactRegistryClient()

# Environment variables
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = os.environ.get('REGION', 'us-central1')
RANDOM_SUFFIX = os.environ.get('RANDOM_SUFFIX')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')


@functions_framework.http
def distribute_package(request):
    """
    Main function to handle package distribution requests.
    
    Expected request format:
    {
        "package_name": "webapp",
        "package_version": "1.0.0",
        "environment": "development",
        "repository_format": "docker",
        "distribution_strategy": "blue-green"
    }
    """
    try:
        # Parse and validate request
        request_data = _parse_request(request)
        if not request_data:
            return {'error': 'Invalid request format'}, 400
        
        package_name = request_data['package_name']
        package_version = request_data.get('package_version', 'latest')
        target_environment = request_data.get('environment', 'development')
        repository_format = request_data.get('repository_format', 'docker')
        
        logger.info(f"Starting distribution: {package_name}:{package_version} "
                   f"to {target_environment} ({repository_format})")
        
        # Validate package exists in Artifact Registry
        if not _validate_package_exists(package_name, package_version, repository_format):
            return {'error': f'Package {package_name}:{package_version} not found'}, 404
        
        # Retrieve environment credentials
        credentials = _get_environment_credentials(target_environment)
        if not credentials:
            return {'error': f'Failed to retrieve credentials for {target_environment}'}, 500
        
        # Get distribution configuration
        config = _get_distribution_config()
        if not config:
            return {'error': 'Failed to retrieve distribution configuration'}, 500
        
        # Perform secure package distribution
        result = _perform_secure_distribution(
            package_name, package_version, target_environment, 
            repository_format, credentials, config
        )
        
        if result['success']:
            logger.info(f"Successfully distributed {package_name}:{package_version} "
                       f"to {target_environment}")
            return {
                'status': 'success',
                'message': f'Package {package_name}:{package_version} distributed to {target_environment}',
                'details': result,
                'timestamp': time.time()
            }, 200
        else:
            logger.error(f"Failed to distribute {package_name}:{package_version}: {result['error']}")
            return {'error': result['error']}, 500
            
    except Exception as e:
        logger.error(f"Unexpected error in distribute_package: {str(e)}")
        return {'error': f'Internal server error: {str(e)}'}, 500


def _parse_request(request) -> Optional[Dict[str, Any]]:
    """Parse and validate incoming request."""
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return None
        
        # Validate required fields
        if 'package_name' not in request_json:
            return None
        
        return request_json
    except Exception as e:
        logger.error(f"Failed to parse request: {str(e)}")
        return None


def _validate_package_exists(package_name: str, package_version: str, repository_format: str) -> bool:
    """Validate that the package exists in Artifact Registry."""
    try:
        # Construct repository name
        repository_name = f"projects/{PROJECT_ID}/locations/{REGION}/repositories/secure-packages-{RANDOM_SUFFIX}-{repository_format}"
        
        # List packages in repository
        request = artifactregistry_v1.ListPackagesRequest(
            parent=repository_name,
            filter=f'name="{package_name}"'
        )
        
        packages = ARTIFACT_CLIENT.list_packages(request=request)
        
        # Check if package exists
        for package in packages:
            if package_name in package.name:
                logger.info(f"Package {package_name} found in repository")
                return True
        
        logger.warning(f"Package {package_name} not found in repository")
        return False
        
    except Exception as e:
        logger.error(f"Error validating package existence: {str(e)}")
        return False


def _get_environment_credentials(environment: str) -> Optional[str]:
    """Retrieve credentials for the specified environment from Secret Manager."""
    try:
        secret_name = f"projects/{PROJECT_ID}/secrets/secure-packages-{RANDOM_SUFFIX}-registry-credentials-{environment}/versions/latest"
        
        response = SECRET_CLIENT.access_secret_version(request={"name": secret_name})
        credentials = response.payload.data.decode("UTF-8")
        
        logger.info(f"Successfully retrieved credentials for {environment}")
        return credentials
        
    except Exception as e:
        logger.error(f"Failed to retrieve credentials for {environment}: {str(e)}")
        return None


def _get_distribution_config() -> Optional[Dict[str, Any]]:
    """Retrieve distribution configuration from Secret Manager."""
    try:
        secret_name = f"projects/{PROJECT_ID}/secrets/secure-packages-{RANDOM_SUFFIX}-distribution-config/versions/latest"
        
        response = SECRET_CLIENT.access_secret_version(request={"name": secret_name})
        config_json = response.payload.data.decode("UTF-8")
        
        config = json.loads(config_json)
        logger.info("Successfully retrieved distribution configuration")
        return config
        
    except Exception as e:
        logger.error(f"Failed to retrieve distribution config: {str(e)}")
        return None


def _perform_secure_distribution(
    package_name: str, 
    package_version: str, 
    environment: str, 
    repository_format: str,
    credentials: str, 
    config: Dict[str, Any]
) -> Dict[str, Any]:
    """Perform the actual secure package distribution."""
    try:
        # Get environment-specific configuration
        env_config = config.get('environments', {}).get(environment)
        if not env_config:
            return {'success': False, 'error': f'No configuration for environment {environment}'}
        
        # Validate security requirements
        security_checks = _perform_security_checks(package_name, package_version, repository_format)
        if not security_checks['passed']:
            return {'success': False, 'error': f'Security checks failed: {security_checks["issues"]}'}
        
        # Create distribution task
        task_result = _create_distribution_task(
            package_name, package_version, environment, repository_format, env_config
        )
        
        if not task_result['success']:
            return {'success': False, 'error': f'Failed to create distribution task: {task_result["error"]}'}
        
        # Simulate distribution process
        distribution_result = _simulate_distribution(
            package_name, package_version, environment, env_config
        )
        
        if distribution_result['success']:
            # Log successful distribution for audit
            _log_distribution_event(
                package_name, package_version, environment, repository_format, 'SUCCESS'
            )
            
            return {
                'success': True,
                'package': f"{package_name}:{package_version}",
                'environment': environment,
                'format': repository_format,
                'endpoint': env_config['endpoint'],
                'timestamp': int(time.time()),
                'task_id': task_result.get('task_id'),
                'security_checks': security_checks
            }
        else:
            # Log failed distribution
            _log_distribution_event(
                package_name, package_version, environment, repository_format, 'FAILED'
            )
            
            return {'success': False, 'error': distribution_result['error']}
            
    except Exception as e:
        logger.error(f"Error in secure distribution: {str(e)}")
        return {'success': False, 'error': str(e)}


def _perform_security_checks(package_name: str, package_version: str, repository_format: str) -> Dict[str, Any]:
    """Perform security validation checks on the package."""
    try:
        checks = {
            'vulnerability_scan': True,  # Would integrate with Container Analysis API
            'signature_verification': True,  # Would integrate with Binary Authorization
            'policy_compliance': True,  # Would check against organizational policies
            'access_control': True  # Would verify proper access controls
        }
        
        # Simulate security checks
        issues = []
        for check_name, passed in checks.items():
            if not passed:
                issues.append(check_name)
        
        return {
            'passed': len(issues) == 0,
            'issues': issues,
            'checks_performed': list(checks.keys())
        }
        
    except Exception as e:
        logger.error(f"Error performing security checks: {str(e)}")
        return {'passed': False, 'issues': ['security_check_error'], 'checks_performed': []}


def _create_distribution_task(
    package_name: str, 
    package_version: str, 
    environment: str, 
    repository_format: str,
    env_config: Dict[str, Any]
) -> Dict[str, Any]:
    """Create a task in Cloud Tasks for distribution tracking."""
    try:
        # Choose appropriate queue based on environment
        queue_name = "prod-distribution-queue" if environment == "prod" else "distribution-queue"
        parent = f"projects/{PROJECT_ID}/locations/{REGION}/queues/secure-packages-{RANDOM_SUFFIX}-{queue_name}"
        
        # Create task payload
        task_payload = {
            'package_name': package_name,
            'package_version': package_version,
            'environment': environment,
            'repository_format': repository_format,
            'created_at': int(time.time())
        }
        
        # Create task
        task = {
            'http_request': {
                'http_method': tasks_v2.HttpMethod.POST,
                'url': f'https://example.com/webhook',  # Would be actual endpoint
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(task_payload).encode()
            }
        }
        
        # Note: In a real implementation, you would actually create the task
        # For this example, we'll simulate task creation
        task_id = f"task-{int(time.time())}"
        
        logger.info(f"Created distribution task {task_id} for {package_name}:{package_version}")
        
        return {
            'success': True,
            'task_id': task_id,
            'queue': queue_name
        }
        
    except Exception as e:
        logger.error(f"Error creating distribution task: {str(e)}")
        return {'success': False, 'error': str(e)}


def _simulate_distribution(
    package_name: str, 
    package_version: str, 
    environment: str, 
    env_config: Dict[str, Any]
) -> Dict[str, Any]:
    """Simulate the actual package distribution process."""
    try:
        # Simulate distribution logic
        endpoint = env_config['endpoint']
        timeout = env_config['timeout']
        
        logger.info(f"Distributing to endpoint: {endpoint} with timeout: {timeout}s")
        
        # In a real implementation, this would:
        # 1. Pull package from Artifact Registry
        # 2. Apply security policies
        # 3. Deploy to target environment
        # 4. Verify deployment health
        # 5. Update monitoring dashboards
        
        # Simulate processing time
        time.sleep(1)
        
        return {
            'success': True,
            'endpoint': endpoint,
            'deployment_time': timeout,
            'health_check': 'passed'
        }
        
    except Exception as e:
        logger.error(f"Error in distribution simulation: {str(e)}")
        return {'success': False, 'error': str(e)}


def _log_distribution_event(
    package_name: str, 
    package_version: str, 
    environment: str, 
    repository_format: str,
    status: str
) -> None:
    """Log distribution event for audit and monitoring."""
    try:
        log_entry = {
            'event_type': 'package_distribution',
            'package_name': package_name,
            'package_version': package_version,
            'environment': environment,
            'repository_format': repository_format,
            'status': status,
            'timestamp': int(time.time()),
            'project_id': PROJECT_ID,
            'region': REGION
        }
        
        logger.info(f"Distribution event logged", extra=log_entry)
        
    except Exception as e:
        logger.error(f"Failed to log distribution event: {str(e)}")


# Health check endpoint
@functions_framework.http
def health_check(request):
    """Simple health check endpoint."""
    return {
        'status': 'healthy',
        'timestamp': int(time.time()),
        'project_id': PROJECT_ID,
        'region': REGION,
        'environment': ENVIRONMENT
    }, 200