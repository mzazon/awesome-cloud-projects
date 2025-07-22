import json
import boto3
import logging
from datetime import datetime, timezone

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
iot = boto3.client('iot')

def lambda_handler(event, context):
    """
    Pre-provisioning hook to validate and authorize device provisioning
    """
    try:
        # Extract device information from provisioning request
        certificate_pem = event.get('certificatePem', '')
        template_arn = event.get('templateArn', '')
        parameters = event.get('parameters', {})
        
        serial_number = parameters.get('SerialNumber', '')
        device_type = parameters.get('DeviceType', '')
        firmware_version = parameters.get('FirmwareVersion', '')
        manufacturer = parameters.get('Manufacturer', '')
        
        logger.info(f"Processing provisioning request for device: {serial_number}")
        
        # Validate required parameters
        if not all([serial_number, device_type, manufacturer]):
            return create_response(False, "Missing required device parameters")
        
        # Validate device type
        valid_device_types = ['temperature-sensor', 'humidity-sensor', 'pressure-sensor', 'gateway']
        if device_type not in valid_device_types:
            return create_response(False, f"Invalid device type: {device_type}")
        
        # Check if device is already registered
        table = dynamodb.Table('${device_registry_table}')
        
        try:
            response = table.get_item(Key={'serialNumber': serial_number})
            if 'Item' in response:
                existing_status = response['Item'].get('status', '')
                if existing_status == 'provisioned':
                    return create_response(False, "Device already provisioned")
                elif existing_status == 'revoked':
                    return create_response(False, "Device has been revoked")
        except Exception as e:
            logger.error(f"Error checking device registry: {str(e)}")
        
        # Validate firmware version (basic check)
        if firmware_version and not firmware_version.startswith('v'):
            return create_response(False, "Invalid firmware version format")
        
        # Store device information in registry
        try:
            device_item = {
                'serialNumber': serial_number,
                'deviceType': device_type,
                'manufacturer': manufacturer,
                'firmwareVersion': firmware_version,
                'status': 'provisioning',
                'provisioningTimestamp': datetime.now(timezone.utc).isoformat(),
                'templateArn': template_arn
            }
            
            table.put_item(Item=device_item)
            logger.info(f"Device {serial_number} registered in device registry")
            
        except Exception as e:
            logger.error(f"Error storing device in registry: {str(e)}")
            return create_response(False, "Failed to register device")
        
        # Determine thing group based on device type
        thing_group = f"{device_type}-devices"
        
        # Create response with device-specific parameters
        response_parameters = {
            'ThingName': f"{device_type}-{serial_number}",
            'ThingGroupName': thing_group,
            'DeviceLocation': parameters.get('Location', 'unknown'),
            'ProvisioningTime': datetime.now(timezone.utc).isoformat()
        }
        
        return create_response(True, "Device validation successful", response_parameters)
        
    except Exception as e:
        logger.error(f"Unexpected error in provisioning hook: {str(e)}")
        return create_response(False, "Internal provisioning error")

def create_response(allow_provisioning, message, parameters=None):
    """Create standardized response for provisioning hook"""
    response = {
        'allowProvisioning': allow_provisioning,
        'message': message
    }
    
    if parameters:
        response['parameters'] = parameters
    
    logger.info(f"Provisioning response: {response}")
    return response