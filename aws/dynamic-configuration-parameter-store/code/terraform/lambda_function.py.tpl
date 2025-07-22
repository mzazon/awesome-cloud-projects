import json
import os
import urllib3
import boto3
from datetime import datetime
import traceback

# Initialize HTTP client for Parameters and Secrets Extension
http = urllib3.PoolManager()

# Initialize CloudWatch client for custom metrics
cloudwatch = boto3.client('cloudwatch')

def get_parameter_from_extension(parameter_name):
    """
    Retrieve parameter using the AWS Parameters and Secrets Extension.
    This provides local caching and improved performance over direct SSM calls.
    
    Args:
        parameter_name (str): Full parameter name including path
        
    Returns:
        str: Parameter value or None if retrieval fails
    """
    try:
        # Use localhost endpoint provided by the extension layer
        port = os.environ.get('PARAMETERS_SECRETS_EXTENSION_HTTP_PORT', '2773')
        url = f'http://localhost:{port}/systemsmanager/parameters/get/?name={parameter_name}'
        
        print(f"Retrieving parameter: {parameter_name}")
        response = http.request('GET', url)
        
        if response.status == 200:
            data = json.loads(response.data.decode('utf-8'))
            print(f"Successfully retrieved parameter: {parameter_name}")
            return data['Parameter']['Value']
        else:
            print(f"Extension request failed with status {response.status} for parameter: {parameter_name}")
            raise Exception(f"HTTP {response.status}: Failed to retrieve parameter from extension")
            
    except Exception as e:
        print(f"Error retrieving parameter {parameter_name} from extension: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")
        # Fallback to direct SSM call if extension fails
        return get_parameter_direct(parameter_name)

def get_parameter_direct(parameter_name):
    """
    Fallback method using direct SSM API call when extension is unavailable.
    
    Args:
        parameter_name (str): Full parameter name including path
        
    Returns:
        str: Parameter value or None if retrieval fails
    """
    try:
        print(f"Using direct SSM call for parameter: {parameter_name}")
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
        print(f"Successfully retrieved parameter via direct SSM: {parameter_name}")
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error with direct SSM call for {parameter_name}: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")
        return None

def send_custom_metric(metric_name, value, unit='Count', dimensions=None):
    """
    Send custom metric to CloudWatch for monitoring configuration management operations.
    
    Args:
        metric_name (str): Name of the metric
        value (int/float): Metric value
        unit (str): Metric unit (Count, Seconds, etc.)
        dimensions (dict): Optional metric dimensions
    """
    try:
        metric_data = {
            'MetricName': metric_name,
            'Value': value,
            'Unit': unit,
            'Timestamp': datetime.utcnow()
        }
        
        if dimensions:
            metric_data['Dimensions'] = [
                {'Name': k, 'Value': v} for k, v in dimensions.items()
            ]
        
        cloudwatch.put_metric_data(
            Namespace='ConfigManager',
            MetricData=[metric_data]
        )
        print(f"Successfully sent metric: {metric_name} = {value}")
    except Exception as e:
        print(f"Error sending metric {metric_name}: {str(e)}")

def validate_configuration(config):
    """
    Validate retrieved configuration parameters for consistency and correctness.
    
    Args:
        config (dict): Configuration dictionary
        
    Returns:
        bool: True if configuration is valid, False otherwise
    """
    try:
        # Validate database port is numeric
        if 'port' in config:
            port = int(config['port'])
            if port < 1 or port > 65535:
                print(f"Invalid port number: {port}")
                return False
        
        # Validate timeout is numeric and reasonable
        if 'timeout' in config:
            timeout = int(config['timeout'])
            if timeout < 1 or timeout > 300:
                print(f"Invalid timeout value: {timeout}")
                return False
        
        # Validate boolean feature flags
        if 'new-ui' in config:
            if config['new-ui'].lower() not in ['true', 'false']:
                print(f"Invalid boolean value for new-ui: {config['new-ui']}")
                return False
        
        print("Configuration validation passed")
        return True
        
    except Exception as e:
        print(f"Configuration validation error: {str(e)}")
        return False

def lambda_handler(event, context):
    """
    Main Lambda handler function for dynamic configuration management.
    Retrieves configuration parameters using the Parameters and Secrets Extension,
    validates the configuration, and sends monitoring metrics.
    
    Args:
        event (dict): Lambda event object
        context: Lambda context object
        
    Returns:
        dict: Response object with status code and body
    """
    start_time = datetime.utcnow()
    
    try:
        print(f"Configuration management handler started at {start_time}")
        print(f"Event: {json.dumps(event, indent=2)}")
        
        # Get parameter prefix from environment
        parameter_prefix = os.environ.get('PARAMETER_PREFIX', '${parameter_prefix}')
        print(f"Using parameter prefix: {parameter_prefix}")
        
        # Define configuration parameters to retrieve
        parameter_definitions = [
            {'name': f"{parameter_prefix}/database/host", 'key': 'host'},
            {'name': f"{parameter_prefix}/database/port", 'key': 'port'},
            {'name': f"{parameter_prefix}/api/timeout", 'key': 'timeout'},
            {'name': f"{parameter_prefix}/features/new-ui", 'key': 'new-ui'}
        ]
        
        # Track metrics for monitoring
        successful_retrievals = 0
        failed_retrievals = 0
        config = {}
        
        # Retrieve each parameter
        for param_def in parameter_definitions:
            param_name = param_def['name']
            param_key = param_def['key']
            
            value = get_parameter_from_extension(param_name)
            if value is not None:
                config[param_key] = value
                successful_retrievals += 1
                print(f"Retrieved {param_key}: {value}")
            else:
                failed_retrievals += 1
                print(f"Failed to retrieve parameter: {param_name}")
        
        # Validate retrieved configuration
        is_valid = validate_configuration(config)
        if not is_valid:
            send_custom_metric('ConfigurationValidationErrors', 1)
        
        # Calculate processing time
        end_time = datetime.utcnow()
        processing_time = (end_time - start_time).total_seconds()
        
        # Send custom metrics for monitoring
        send_custom_metric('SuccessfulParameterRetrievals', successful_retrievals)
        send_custom_metric('FailedParameterRetrievals', failed_retrievals)
        send_custom_metric('ConfigurationProcessingTime', processing_time * 1000, 'Milliseconds')
        send_custom_metric('ConfigurationRetrievals', 1, 'Count', {
            'Status': 'Success' if failed_retrievals == 0 else 'Partial'
        })
        
        # Log configuration status
        print(f"Configuration loaded: {len(config)} parameters")
        print(f"Processing time: {processing_time:.3f} seconds")
        print(f"Configuration summary: {json.dumps({k: v[:10] + '...' if len(str(v)) > 10 else v for k, v in config.items()}, indent=2)}")
        
        # Determine response status
        if failed_retrievals == 0:
            status_code = 200
            message = 'Configuration loaded successfully'
        elif successful_retrievals > 0:
            status_code = 206  # Partial content
            message = f'Configuration partially loaded: {successful_retrievals} succeeded, {failed_retrievals} failed'
        else:
            status_code = 500
            message = 'Configuration loading failed completely'
            send_custom_metric('ConfigurationErrors', 1)
        
        # Return response
        response = {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': message,
                'config': config,
                'metadata': {
                    'timestamp': end_time.isoformat(),
                    'processing_time_ms': round(processing_time * 1000, 2),
                    'successful_retrievals': successful_retrievals,
                    'failed_retrievals': failed_retrievals,
                    'parameter_prefix': parameter_prefix,
                    'validation_passed': is_valid
                }
            }, indent=2)
        }
        
        print(f"Response status: {status_code}")
        return response
        
    except Exception as e:
        error_msg = f"Error in lambda_handler: {str(e)}"
        print(error_msg)
        print(f"Traceback: {traceback.format_exc()}")
        
        # Send error metrics
        send_custom_metric('ConfigurationErrors', 1)
        send_custom_metric('LambdaHandlerErrors', 1)
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Configuration retrieval failed',
                'message': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }