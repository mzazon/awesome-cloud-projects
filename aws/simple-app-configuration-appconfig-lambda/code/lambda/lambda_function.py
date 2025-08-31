"""
AWS Lambda Function for AppConfig Integration Demo

This Lambda function demonstrates how to retrieve configuration data from
AWS AppConfig using the AppConfig Lambda Extension. The extension provides
a local HTTP endpoint that caches configuration data and handles retrieval
automatically.

Key Features:
- Retrieves configuration from AppConfig via local extension endpoint
- Handles configuration parsing and error scenarios
- Logs configuration usage for debugging and monitoring
- Returns configuration summary in API response
"""

import json
import os
import urllib3
from typing import Dict, Any, Optional


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda function handler that retrieves and uses AppConfig configuration.
    
    Args:
        event: Lambda event data (not used in this demo)
        context: Lambda runtime information
        
    Returns:
        Dict containing status code and response body with configuration summary
    """
    try:
        # Get configuration from AppConfig
        config_data = get_appconfig_configuration()
        
        if config_data is None:
            return create_error_response(
                500, 
                "Failed to retrieve configuration from AppConfig"
            )
        
        # Extract and use configuration values
        database_config = config_data.get('database', {})
        features_config = config_data.get('features', {})
        api_config = config_data.get('api', {})
        
        # Extract specific configuration values with defaults
        max_connections = database_config.get('max_connections', 50)
        enable_logging = features_config.get('enable_logging', False)
        rate_limit = api_config.get('rate_limit', 500)
        debug_mode = features_config.get('debug_mode', False)
        
        # Log configuration usage if logging is enabled
        if enable_logging:
            print(f"Configuration loaded successfully:")
            print(f"  - Database max connections: {max_connections}")
            print(f"  - API rate limit: {rate_limit}")
            print(f"  - Debug mode: {debug_mode}")
            print(f"  - Logging enabled: {enable_logging}")
        
        # Create response with configuration summary
        response_body = {
            'message': 'Configuration loaded successfully from AppConfig',
            'timestamp': context.aws_request_id,
            'config_summary': {
                'database_max_connections': max_connections,
                'database_timeout_seconds': database_config.get('timeout_seconds', 30),
                'database_retry_attempts': database_config.get('retry_attempts', 3),
                'features_logging_enabled': enable_logging,
                'features_metrics_enabled': features_config.get('enable_metrics', False),
                'features_debug_mode': debug_mode,
                'api_rate_limit': rate_limit,
                'api_cache_ttl': api_config.get('cache_ttl', 300)
            },
            'metadata': {
                'function_name': context.function_name,
                'function_version': context.function_version,
                'memory_limit': context.memory_limit_in_mb,
                'remaining_time': context.get_remaining_time_in_millis()
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache'
            },
            'body': json.dumps(response_body, indent=2)
        }
        
    except Exception as e:
        error_message = f"Unexpected error in Lambda function: {str(e)}"
        print(f"ERROR: {error_message}")
        
        return create_error_response(500, error_message)


def get_appconfig_configuration() -> Optional[Dict[str, Any]]:
    """
    Retrieve configuration data from AppConfig via the Lambda extension.
    
    The AppConfig Lambda extension provides a local HTTP endpoint at
    localhost:2772 that handles configuration retrieval, caching, and polling.
    
    Returns:
        Dict containing configuration data, or None if retrieval fails
    """
    try:
        # AppConfig extension endpoint (local to Lambda execution environment)
        appconfig_endpoint = 'http://localhost:2772'
        
        # Get AppConfig parameters from environment variables
        application_id = os.environ.get('APPCONFIG_APPLICATION_ID')
        environment_id = os.environ.get('APPCONFIG_ENVIRONMENT_ID')
        configuration_profile_id = os.environ.get('APPCONFIG_CONFIGURATION_PROFILE_ID')
        
        # Validate required environment variables
        if not all([application_id, environment_id, configuration_profile_id]):
            print("ERROR: Missing required AppConfig environment variables")
            print(f"  - APPCONFIG_APPLICATION_ID: {application_id}")
            print(f"  - APPCONFIG_ENVIRONMENT_ID: {environment_id}")
            print(f"  - APPCONFIG_CONFIGURATION_PROFILE_ID: {configuration_profile_id}")
            return None
        
        # Create HTTP connection pool manager
        http = urllib3.PoolManager(timeout=urllib3.Timeout(connect=2.0, read=5.0))
        
        # Construct AppConfig extension URL
        config_url = (
            f"{appconfig_endpoint}/applications/{application_id}/"
            f"environments/{environment_id}/"
            f"configurations/{configuration_profile_id}"
        )
        
        print(f"Retrieving configuration from: {config_url}")
        
        # Make request to AppConfig extension
        response = http.request('GET', config_url)
        
        if response.status == 200:
            # Parse JSON configuration data
            config_data = json.loads(response.data.decode('utf-8'))
            print(f"Successfully retrieved configuration (size: {len(response.data)} bytes)")
            
            return config_data
        else:
            print(f"AppConfig extension returned status {response.status}")
            print(f"Response: {response.data.decode('utf-8')}")
            return None
            
    except urllib3.exceptions.TimeoutError:
        print("ERROR: Timeout connecting to AppConfig extension")
        return None
    except urllib3.exceptions.ConnectionError:
        print("ERROR: Connection error to AppConfig extension")
        return None
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse configuration JSON: {str(e)}")
        return None
    except Exception as e:
        print(f"ERROR: Unexpected error retrieving configuration: {str(e)}")
        return None


def create_error_response(status_code: int, error_message: str) -> Dict[str, Any]:
    """
    Create a standardized error response.
    
    Args:
        status_code: HTTP status code for the error
        error_message: Description of the error
        
    Returns:
        Dict containing error response structure
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache'
        },
        'body': json.dumps({
            'error': True,
            'message': error_message,
            'statusCode': status_code
        })
    }


def validate_configuration(config_data: Dict[str, Any]) -> bool:
    """
    Validate configuration data structure and required fields.
    
    Args:
        config_data: Configuration data to validate
        
    Returns:
        True if configuration is valid, False otherwise
    """
    try:
        # Check for required top-level sections
        required_sections = ['database', 'features', 'api']
        for section in required_sections:
            if section not in config_data:
                print(f"ERROR: Missing required configuration section: {section}")
                return False
        
        # Validate database section
        database = config_data['database']
        if not isinstance(database.get('max_connections'), int) or database['max_connections'] <= 0:
            print("ERROR: Invalid database.max_connections value")
            return False
        
        # Validate features section
        features = config_data['features']
        boolean_features = ['enable_logging', 'enable_metrics', 'debug_mode']
        for feature in boolean_features:
            if not isinstance(features.get(feature), bool):
                print(f"ERROR: Invalid features.{feature} value (must be boolean)")
                return False
        
        # Validate API section
        api = config_data['api']
        if not isinstance(api.get('rate_limit'), int) or api['rate_limit'] <= 0:
            print("ERROR: Invalid api.rate_limit value")
            return False
        
        return True
        
    except Exception as e:
        print(f"ERROR: Configuration validation failed: {str(e)}")
        return False