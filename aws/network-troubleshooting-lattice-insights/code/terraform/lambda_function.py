"""
Lambda function for automated network troubleshooting.
This function is triggered by CloudWatch alarms via SNS and automatically
initiates Systems Manager automation for network reachability analysis.
"""
import json
import boto3
import logging
import os
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ssm_client = boto3.client('ssm')
ec2_client = boto3.client('ec2')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for automated network troubleshooting.
    
    Args:
        event: Lambda event containing SNS message
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Parse SNS message from event
        sns_records = extract_sns_records(event)
        if not sns_records:
            logger.warning("No SNS records found in event")
            return create_response(200, {'message': 'No SNS records to process'})
        
        # Get environment variables
        automation_role = os.environ.get('AUTOMATION_ROLE_ARN', '')
        default_instance = os.environ.get('DEFAULT_INSTANCE_ID', '')
        automation_document = os.environ.get('AUTOMATION_DOCUMENT_NAME', '')
        
        if not all([automation_role, default_instance, automation_document]):
            error_msg = "Missing required environment variables"
            logger.error(error_msg)
            return create_response(400, {'error': error_msg})
        
        results = []
        
        # Process each SNS record
        for record in sns_records:
            try:
                result = process_sns_record(
                    record, 
                    automation_role, 
                    default_instance, 
                    automation_document
                )
                results.append(result)
                
            except Exception as e:
                logger.error(f"Error processing SNS record: {str(e)}")
                results.append({
                    'status': 'error',
                    'error': str(e),
                    'record_id': record.get('Sns', {}).get('MessageId', 'unknown')
                })
        
        # Return aggregated results
        success_count = sum(1 for r in results if r.get('status') == 'success')
        total_count = len(results)
        
        return create_response(200, {
            'message': f'Processed {success_count}/{total_count} records successfully',
            'results': results
        })
        
    except Exception as e:
        logger.error(f"Unexpected error in lambda_handler: {str(e)}")
        return create_response(500, {'error': str(e)})


def extract_sns_records(event: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Extract SNS records from Lambda event.
    
    Args:
        event: Lambda event dictionary
        
    Returns:
        List of SNS records
    """
    records = event.get('Records', [])
    return [record for record in records if record.get('EventSource') == 'aws:sns']


def process_sns_record(
    record: Dict[str, Any], 
    automation_role: str, 
    default_instance: str, 
    automation_document: str
) -> Dict[str, Any]:
    """
    Process a single SNS record and trigger automation.
    
    Args:
        record: SNS record from Lambda event
        automation_role: ARN of IAM role for automation
        default_instance: Default instance ID for testing
        automation_document: Name of automation document
        
    Returns:
        Dict containing processing results
    """
    sns_message = record.get('Sns', {})
    message_body = sns_message.get('Message', '{}')
    
    try:
        # Parse CloudWatch alarm message
        alarm_data = json.loads(message_body)
        alarm_name = alarm_data.get('AlarmName', 'Unknown')
        alarm_state = alarm_data.get('NewStateValue', 'Unknown')
        
        logger.info(f"Processing alarm: {alarm_name}, State: {alarm_state}")
        
        # Only process ALARM state
        if alarm_state != 'ALARM':
            logger.info(f"Ignoring alarm state: {alarm_state}")
            return {
                'status': 'skipped',
                'alarm_name': alarm_name,
                'alarm_state': alarm_state,
                'reason': 'Only ALARM state triggers automation'
            }
        
        # Get network endpoints for analysis
        source_id, destination_id = get_network_endpoints(default_instance, alarm_name)
        
        # Start automation execution
        execution_response = start_automation_execution(
            automation_document,
            automation_role,
            source_id,
            destination_id
        )
        
        execution_id = execution_response['AutomationExecutionId']
        logger.info(f"Started automation execution: {execution_id}")
        
        # Log execution details for monitoring
        log_automation_details(execution_id, alarm_name, source_id, destination_id)
        
        return {
            'status': 'success',
            'alarm_name': alarm_name,
            'alarm_state': alarm_state,
            'execution_id': execution_id,
            'source_id': source_id,
            'destination_id': destination_id
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse SNS message as JSON: {str(e)}")
        raise ValueError(f"Invalid JSON in SNS message: {str(e)}")
    
    except Exception as e:
        logger.error(f"Error processing SNS record: {str(e)}")
        raise


def get_network_endpoints(default_instance: str, alarm_name: str) -> tuple:
    """
    Determine source and destination endpoints for network analysis.
    
    Args:
        default_instance: Default instance ID
        alarm_name: CloudWatch alarm name
        
    Returns:
        Tuple of (source_id, destination_id)
    """
    # For this implementation, we use the same instance as both source and destination
    # In a real scenario, you would analyze the alarm to determine appropriate endpoints
    
    # You could extend this to:
    # 1. Parse alarm dimensions to identify specific resources
    # 2. Query VPC Lattice service network for registered targets
    # 3. Use different source/destination based on alarm type
    
    logger.info(f"Using default instance {default_instance} for both source and destination")
    return default_instance, default_instance


def start_automation_execution(
    document_name: str,
    automation_role: str,
    source_id: str,
    destination_id: str
) -> Dict[str, Any]:
    """
    Start Systems Manager automation execution.
    
    Args:
        document_name: Name of automation document
        automation_role: ARN of IAM role for automation
        source_id: Source endpoint for analysis
        destination_id: Destination endpoint for analysis
        
    Returns:
        SSM automation execution response
    """
    parameters = {
        'SourceId': [source_id],
        'DestinationId': [destination_id],
        'AutomationAssumeRole': [automation_role]
    }
    
    logger.info(f"Starting automation with parameters: {parameters}")
    
    response = ssm_client.start_automation_execution(
        DocumentName=document_name,
        Parameters=parameters
    )
    
    return response


def log_automation_details(
    execution_id: str,
    alarm_name: str,
    source_id: str,
    destination_id: str
) -> None:
    """
    Log automation execution details for monitoring and debugging.
    
    Args:
        execution_id: Automation execution ID
        alarm_name: Triggering alarm name
        source_id: Source endpoint
        destination_id: Destination endpoint
    """
    details = {
        'execution_id': execution_id,
        'trigger_alarm': alarm_name,
        'analysis_source': source_id,
        'analysis_destination': destination_id,
        'timestamp': str(boto3.Session().region_name)
    }
    
    logger.info(f"Automation details: {json.dumps(details)}")


def create_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create standardized Lambda response.
    
    Args:
        status_code: HTTP status code
        body: Response body dictionary
        
    Returns:
        Lambda response dictionary
    """
    return {
        'statusCode': status_code,
        'body': json.dumps(body, default=str),
        'headers': {
            'Content-Type': 'application/json'
        }
    }


def get_instance_network_interface(instance_id: str) -> str:
    """
    Get the primary network interface ID for an EC2 instance.
    
    Args:
        instance_id: EC2 instance ID
        
    Returns:
        Network interface ID
    """
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                network_interfaces = instance.get('NetworkInterfaces', [])
                if network_interfaces:
                    # Return the primary network interface
                    for eni in network_interfaces:
                        if eni.get('Attachment', {}).get('DeviceIndex') == 0:
                            return eni['NetworkInterfaceId']
                    
                    # Fallback to first interface if no primary found
                    return network_interfaces[0]['NetworkInterfaceId']
        
        logger.warning(f"No network interfaces found for instance {instance_id}")
        return instance_id  # Fallback to instance ID
        
    except Exception as e:
        logger.warning(f"Failed to get network interface for {instance_id}: {str(e)}")
        return instance_id  # Fallback to instance ID


# Additional utility functions for extended functionality

def validate_environment() -> Dict[str, str]:
    """
    Validate required environment variables.
    
    Returns:
        Dict of validated environment variables
    """
    required_vars = {
        'AUTOMATION_ROLE_ARN': os.environ.get('AUTOMATION_ROLE_ARN', ''),
        'DEFAULT_INSTANCE_ID': os.environ.get('DEFAULT_INSTANCE_ID', ''),
        'AUTOMATION_DOCUMENT_NAME': os.environ.get('AUTOMATION_DOCUMENT_NAME', '')
    }
    
    missing_vars = [var for var, value in required_vars.items() if not value]
    
    if missing_vars:
        raise ValueError(f"Missing required environment variables: {missing_vars}")
    
    return required_vars


def get_vpc_lattice_targets(service_network_id: str) -> List[str]:
    """
    Get target instances from VPC Lattice service network.
    This is a placeholder for more advanced target discovery.
    
    Args:
        service_network_id: VPC Lattice service network ID
        
    Returns:
        List of target instance IDs
    """
    # This would require VPC Lattice API calls to discover services and targets
    # Implementation depends on your specific service mesh configuration
    logger.info(f"Would discover targets for service network: {service_network_id}")
    return []


def create_custom_analysis_path(
    source_id: str,
    destination_id: str,
    protocol: str = "tcp",
    port: int = 80
) -> str:
    """
    Create a custom network insights path for specific analysis.
    
    Args:
        source_id: Source resource ID
        destination_id: Destination resource ID
        protocol: Network protocol
        port: Destination port
        
    Returns:
        Network insights path ID
    """
    try:
        response = ec2_client.create_network_insights_path(
            Source=source_id,
            Destination=destination_id,
            Protocol=protocol,
            DestinationPort=port,
            TagSpecifications=[
                {
                    'ResourceType': 'network-insights-path',
                    'Tags': [
                        {
                            'Key': 'Name',
                            'Value': 'LambdaTriggeredAnalysis'
                        },
                        {
                            'Key': 'AutomatedBy',
                            'Value': 'NetworkTroubleshootingLambda'
                        }
                    ]
                }
            ]
        )
        
        path_id = response['NetworkInsightsPath']['NetworkInsightsPathId']
        logger.info(f"Created network insights path: {path_id}")
        return path_id
        
    except Exception as e:
        logger.error(f"Failed to create network insights path: {str(e)}")
        raise