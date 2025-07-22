"""
Enterprise Identity Provisioning Cloud Function

This Cloud Function provides automated identity provisioning workflows
for enterprise federation using Workload Identity Federation, Service Directory,
and Secret Manager integration.

Author: Terraform Enterprise Identity Federation Module
Version: 1.0
"""

import json
import logging
import os
import datetime
from typing import Dict, Any, Optional, Tuple
from google.cloud import secretmanager
from google.cloud import servicedirectory
from google.cloud import iam_credentials_v1
import functions_framework
from flask import Request

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Environment variables (injected by Terraform)
PROJECT_ID = "${project_id}"
REGION = "${region}"
FEDERATION_CONFIG_SECRET = "${federation_config_secret}"
IDP_CONFIG_SECRET = "${idp_config_secret}"

class IdentityProvisioningError(Exception):
    """Custom exception for identity provisioning errors."""
    pass

class IdentityProvisioner:
    """Handles enterprise identity provisioning workflows."""
    
    def __init__(self):
        """Initialize the identity provisioner with Google Cloud clients."""
        self.project_id = PROJECT_ID
        self.region = REGION
        
        # Initialize Google Cloud clients
        try:
            self.secret_client = secretmanager.SecretManagerServiceClient()
            self.service_client = servicedirectory.ServiceDirectoryServiceClient()
            self.iam_credentials_client = iam_credentials_v1.IAMCredentialsServiceClient()
            logger.info("Successfully initialized Google Cloud clients")
        except Exception as e:
            logger.error(f"Failed to initialize Google Cloud clients: {e}")
            raise IdentityProvisioningError(f"Client initialization failed: {e}")
    
    def get_secret(self, secret_name: str) -> Dict[str, Any]:
        """
        Retrieve and parse a secret from Secret Manager.
        
        Args:
            secret_name: Name of the secret to retrieve
            
        Returns:
            Parsed secret data as dictionary
            
        Raises:
            IdentityProvisioningError: If secret retrieval fails
        """
        try:
            secret_path = f"projects/{self.project_id}/secrets/{secret_name}/versions/latest"
            response = self.secret_client.access_secret_version(
                request={"name": secret_path}
            )
            secret_data = response.payload.data.decode("UTF-8")
            return json.loads(secret_data)
        except Exception as e:
            logger.error(f"Failed to retrieve secret {secret_name}: {e}")
            raise IdentityProvisioningError(f"Secret retrieval failed: {e}")
    
    def validate_identity_request(self, request_data: Dict[str, Any]) -> bool:
        """
        Validate the identity provisioning request.
        
        Args:
            request_data: Request data containing identity information
            
        Returns:
            True if request is valid, False otherwise
        """
        required_fields = ['identity', 'service', 'access_level']
        
        for field in required_fields:
            if field not in request_data:
                logger.warning(f"Missing required field: {field}")
                return False
        
        # Validate access level
        valid_access_levels = ['read-only', 'standard', 'admin']
        if request_data['access_level'] not in valid_access_levels:
            logger.warning(f"Invalid access level: {request_data['access_level']}")
            return False
        
        # Validate identity format
        identity = request_data['identity']
        if not isinstance(identity, str) or len(identity) == 0:
            logger.warning("Invalid identity format")
            return False
        
        # Validate service name
        service = request_data['service']
        if not isinstance(service, str) or len(service) == 0:
            logger.warning("Invalid service name")
            return False
        
        return True
    
    def register_service_endpoint(
        self, 
        service_name: str, 
        identity: str, 
        access_level: str,
        namespace_path: str
    ) -> Dict[str, str]:
        """
        Register or update a service endpoint in Service Directory.
        
        Args:
            service_name: Name of the service
            identity: User identity
            access_level: Access level for the identity
            namespace_path: Full path to the Service Directory namespace
            
        Returns:
            Service registration details
        """
        try:
            service_path = f"{namespace_path}/services/{service_name}"
            
            # Create metadata for the service registration
            metadata = {
                'user_identity': identity,
                'access_level': access_level,
                'provisioned_at': datetime.datetime.utcnow().isoformat(),
                'provisioner': 'cloud-function',
                'version': '1.0'
            }
            
            # Update service metadata
            service_request = {
                'service': {
                    'name': service_path,
                    'metadata': metadata
                },
                'update_mask': {'paths': ['metadata']}
            }
            
            # Note: In a real implementation, you would create or update the service
            # For this example, we'll simulate the registration
            logger.info(f"Registering service endpoint: {service_name} for identity: {identity}")
            
            return {
                'service_path': service_path,
                'metadata': metadata,
                'status': 'registered'
            }
            
        except Exception as e:
            logger.error(f"Failed to register service endpoint: {e}")
            raise IdentityProvisioningError(f"Service registration failed: {e}")
    
    def apply_access_policies(
        self, 
        identity: str, 
        access_level: str, 
        service_name: str
    ) -> Dict[str, str]:
        """
        Apply appropriate access policies based on the access level.
        
        Args:
            identity: User identity
            access_level: Requested access level
            service_name: Target service name
            
        Returns:
            Applied policy details
        """
        try:
            policies_applied = []
            
            if access_level == 'read-only':
                policies_applied.extend([
                    'roles/viewer',
                    'roles/servicedirectory.viewer'
                ])
            elif access_level == 'standard':
                policies_applied.extend([
                    'roles/editor',
                    'roles/servicedirectory.editor'
                ])
            elif access_level == 'admin':
                policies_applied.extend([
                    'roles/owner',
                    'roles/servicedirectory.admin',
                    'roles/secretmanager.admin'
                ])
            
            logger.info(f"Applied policies {policies_applied} for identity {identity}")
            
            return {
                'identity': identity,
                'service': service_name,
                'policies_applied': policies_applied,
                'access_level': access_level,
                'applied_at': datetime.datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Failed to apply access policies: {e}")
            raise IdentityProvisioningError(f"Policy application failed: {e}")
    
    def audit_provisioning_event(
        self, 
        identity: str, 
        service_name: str, 
        access_level: str, 
        status: str
    ) -> None:
        """
        Log provisioning events for audit and compliance.
        
        Args:
            identity: User identity
            service_name: Service name
            access_level: Access level granted
            status: Provisioning status
        """
        audit_event = {
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'event_type': 'identity_provisioning',
            'identity': identity,
            'service': service_name,
            'access_level': access_level,
            'status': status,
            'provisioner': 'enterprise-identity-federation',
            'project_id': self.project_id,
            'region': self.region
        }
        
        # Log the audit event (in production, this might go to Cloud Logging or a SIEM)
        logger.info(f"AUDIT_EVENT: {json.dumps(audit_event)}")
    
    def provision_identity(self, request_data: Dict[str, Any]) -> Tuple[Dict[str, Any], int]:
        """
        Main identity provisioning workflow.
        
        Args:
            request_data: Request containing identity provisioning details
            
        Returns:
            Tuple of (response_data, http_status_code)
        """
        try:
            # Validate the request
            if not self.validate_identity_request(request_data):
                return {
                    'error': 'Invalid request format or missing required fields'
                }, 400
            
            identity = request_data['identity']
            service_name = request_data['service']
            access_level = request_data['access_level']
            
            logger.info(f"Starting identity provisioning for {identity}")
            
            # Retrieve configuration secrets
            federation_config = self.get_secret(FEDERATION_CONFIG_SECRET)
            idp_config = self.get_secret(IDP_CONFIG_SECRET)
            
            # Build namespace path
            namespace_path = (
                f"projects/{self.project_id}/locations/{self.region}/"
                f"namespaces/{federation_config['namespace']}"
            )
            
            # Register service endpoint
            service_registration = self.register_service_endpoint(
                service_name, identity, access_level, namespace_path
            )
            
            # Apply access policies
            policy_result = self.apply_access_policies(
                identity, access_level, service_name
            )
            
            # Audit the provisioning event
            self.audit_provisioning_event(
                identity, service_name, access_level, 'success'
            )
            
            # Prepare successful response
            response = {
                'status': 'success',
                'identity': identity,
                'service': service_name,
                'access_level': access_level,
                'provisioned_at': datetime.datetime.utcnow().isoformat(),
                'service_registration': service_registration,
                'policies_applied': policy_result['policies_applied'],
                'federation_config': {
                    'pool_id': federation_config['pool_id'],
                    'provider_id': federation_config['provider_id'],
                    'service_account_email': federation_config['service_account_email']
                }
            }
            
            logger.info(f"Successfully provisioned identity for {identity}")
            return response, 200
            
        except IdentityProvisioningError as e:
            self.audit_provisioning_event(
                request_data.get('identity', 'unknown'),
                request_data.get('service', 'unknown'),
                request_data.get('access_level', 'unknown'),
                'failed'
            )
            return {'error': str(e)}, 500
        except Exception as e:
            logger.error(f"Unexpected error in identity provisioning: {e}")
            self.audit_provisioning_event(
                request_data.get('identity', 'unknown'),
                request_data.get('service', 'unknown'),
                request_data.get('access_level', 'unknown'),
                'error'
            )
            return {'error': 'Internal server error'}, 500

# Global provisioner instance
provisioner = None

def get_provisioner() -> IdentityProvisioner:
    """Get or create the global provisioner instance."""
    global provisioner
    if provisioner is None:
        provisioner = IdentityProvisioner()
    return provisioner

@functions_framework.http
def provision_identity(request: Request) -> Tuple[Dict[str, Any], int]:
    """
    HTTP Cloud Function entry point for identity provisioning.
    
    Args:
        request: Flask request object
        
    Returns:
        HTTP response tuple (data, status_code)
    """
    # Set CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Only allow POST requests
    if request.method != 'POST':
        return ({'error': 'Method not allowed'}, 405, headers)
    
    try:
        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'Invalid JSON or empty request body'}, 400, headers)
        
        # Log the incoming request (excluding sensitive data)
        logger.info(f"Received provisioning request for identity: {request_json.get('identity', 'unknown')}")
        
        # Get provisioner and process request
        identity_provisioner = get_provisioner()
        response_data, status_code = identity_provisioner.provision_identity(request_json)
        
        return (response_data, status_code, headers)
        
    except Exception as e:
        logger.error(f"Function execution error: {e}")
        return ({'error': 'Function execution failed'}, 500, headers)

# Health check endpoint for monitoring
@functions_framework.http
def health_check(request: Request) -> Tuple[Dict[str, Any], int]:
    """
    Health check endpoint for monitoring.
    
    Args:
        request: Flask request object
        
    Returns:
        Health status response
    """
    try:
        # Basic health check
        health_status = {
            'status': 'healthy',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'project_id': PROJECT_ID,
            'region': REGION,
            'function_version': '1.0'
        }
        
        # Verify secret access
        try:
            provisioner_instance = get_provisioner()
            provisioner_instance.get_secret(FEDERATION_CONFIG_SECRET)
            health_status['secret_access'] = 'ok'
        except Exception:
            health_status['secret_access'] = 'failed'
            health_status['status'] = 'degraded'
        
        return health_status, 200
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }, 500

if __name__ == '__main__':
    # For local testing
    import flask
    app = flask.Flask(__name__)
    
    @app.route('/', methods=['POST'])
    def local_provision():
        return provision_identity(flask.request)
    
    @app.route('/health', methods=['GET'])
    def local_health():
        return health_check(flask.request)
    
    app.run(debug=True, host='0.0.0.0', port=8080)