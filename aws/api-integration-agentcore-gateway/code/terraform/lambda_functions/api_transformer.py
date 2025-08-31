"""
API Transformer Lambda Function
===============================
Enterprise API integration transformer that converts incoming requests into 
appropriate formats for different enterprise systems (ERP, CRM, Inventory).

This function serves as a transformation engine in the AgentCore Gateway 
integration, enabling dynamic API request and response processing with 
built-in error handling and multiple API format support.

Author: AWS Recipe - Enterprise API Integration with AgentCore Gateway
Version: 1.0
"""

import json
import urllib3
import os
import logging
from typing import Dict, Any, Optional
from datetime import datetime, timezone, timedelta

# Configure logging
log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
logging.basicConfig(
    level=getattr(logging, log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize urllib3 PoolManager for HTTP requests
http = urllib3.PoolManager()

# Configuration constants
DEFAULT_TIMEOUT = 30
MAX_RETRIES = 3
SUPPORTED_API_TYPES = ['erp', 'crm', 'inventory']


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    AWS Lambda handler for API transformation requests.
    
    This function transforms incoming requests into the appropriate format 
    for target enterprise APIs while handling authentication, validation, 
    and error management.
    
    Args:
        event: Lambda event containing API transformation parameters
        context: Lambda context object
        
    Returns:
        Dictionary with transformation results and status information
    """
    logger.info(f"Processing API transformation request: {json.dumps(event, default=str)}")
    
    try:
        # Extract and validate request parameters
        api_type = event.get('api_type', 'generic')
        payload = event.get('payload', {})
        target_url = event.get('target_url')
        
        # Log request details for debugging
        logger.debug(f"API Type: {api_type}")
        logger.debug(f"Target URL: {target_url}")
        logger.debug(f"Payload size: {len(str(payload))} characters")
        
        # Validate API type
        if api_type not in SUPPORTED_API_TYPES and api_type != 'generic':
            logger.warning(f"Unsupported API type: {api_type}, using generic transformation")
            api_type = 'generic'
        
        # Transform based on API type
        start_time = datetime.now(timezone.utc)
        
        if api_type == 'erp':
            transformed_data = transform_erp_request(payload)
            logger.info("Applied ERP transformation")
        elif api_type == 'crm':
            transformed_data = transform_crm_request(payload)
            logger.info("Applied CRM transformation")
        elif api_type == 'inventory':
            transformed_data = transform_inventory_request(payload)
            logger.info("Applied inventory transformation")
        else:
            transformed_data = transform_generic_request(payload)
            logger.info("Applied generic transformation")
        
        processing_time = (datetime.now(timezone.utc) - start_time).total_seconds()
        
        # Generate mock response for demonstration
        # In production, this would make actual HTTP requests to enterprise APIs
        mock_response = generate_mock_response(api_type, payload, transformed_data)
        
        # Prepare success response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'api_type': api_type,
                'data': mock_response,
                'transformed_data': transformed_data,
                'processing_time_seconds': round(processing_time, 3),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'status_code': 200
            }, default=str)
        }
        
        logger.info(f"Transformation completed successfully in {processing_time:.3f}s")
        return response
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return create_error_response(400, f"Validation error: {str(e)}")
        
    except KeyError as e:
        logger.error(f"Missing required field: {str(e)}")
        return create_error_response(400, f"Missing required field: {str(e)}")
        
    except Exception as e:
        logger.error(f"Unexpected error during transformation: {str(e)}", exc_info=True)
        return create_error_response(500, f"Internal transformation error: {str(e)}")


def transform_erp_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform requests for ERP (Enterprise Resource Planning) system format.
    
    ERP systems typically require structured transaction data with metadata
    for audit trails and compliance tracking.
    
    Args:
        payload: Raw request payload
        
    Returns:
        Transformed data in ERP format
    """
    logger.debug("Transforming request for ERP system")
    
    # Extract and validate ERP-specific fields
    transaction_id = payload.get('id', f"erp-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}")
    
    transformed = {
        'transaction_id': transaction_id,
        'transaction_type': payload.get('type', 'query'),
        'data': payload.get('data', {}),
        'metadata': {
            'source': 'agentcore_gateway',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'version': '1.0',
            'transformation_type': 'erp',
            'original_timestamp': payload.get('timestamp')
        },
        'validation': {
            'schema_version': '2024.1',
            'compliance_flags': ['SOX', 'GDPR'] if payload.get('data', {}).get('amount') else ['GDPR']
        }
    }
    
    # Add financial validation for ERP transactions
    if 'amount' in payload.get('data', {}):
        transformed['financial_data'] = {
            'amount': float(payload['data']['amount']),
            'currency': payload.get('data', {}).get('currency', 'USD'),
            'account_code': payload.get('data', {}).get('account_code', 'AUTO'),
            'cost_center': payload.get('data', {}).get('cost_center', 'DEFAULT')
        }
    
    logger.debug(f"ERP transformation completed: {len(str(transformed))} characters")
    return transformed


def transform_crm_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform requests for CRM (Customer Relationship Management) system format.
    
    CRM systems focus on customer entity management with relationship
    tracking and interaction history.
    
    Args:
        payload: Raw request payload
        
    Returns:
        Transformed data in CRM format
    """
    logger.debug("Transforming request for CRM system")
    
    # Extract and validate CRM-specific fields
    entity_id = payload.get('id', f"crm-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}")
    
    transformed = {
        'entity_id': entity_id,
        'operation': payload.get('action', 'read'),
        'entity_type': payload.get('entity', 'contact'),
        'attributes': payload.get('data', {}),
        'source_system': 'ai_agent',
        'interaction_data': {
            'channel': 'api',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'session_id': payload.get('session_id', f"session-{entity_id}"),
            'user_agent': 'AgentCore Gateway v1.0'
        },
        'privacy_settings': {
            'data_retention_days': 2555,  # 7 years for business compliance
            'anonymization_eligible': True,
            'consent_required': bool(payload.get('data', {}).get('email'))
        }
    }
    
    # Add customer-specific transformations
    if 'email' in payload.get('data', {}):
        transformed['contact_info'] = {
            'email': payload['data']['email'].lower().strip(),
            'email_verified': False,
            'communication_preferences': {
                'email_opt_in': True,
                'sms_opt_in': False,
                'marketing_opt_in': False
            }
        }
    
    if 'phone' in payload.get('data', {}):
        transformed.setdefault('contact_info', {})['phone'] = {
            'number': str(payload['data']['phone']).strip(),
            'verified': False,
            'type': 'mobile'  # default assumption
        }
    
    logger.debug(f"CRM transformation completed: {len(str(transformed))} characters")
    return transformed


def transform_inventory_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform requests for Inventory Management system format.
    
    Inventory systems require detailed item tracking with quantities,
    locations, and movement history.
    
    Args:
        payload: Raw request payload
        
    Returns:
        Transformed data in inventory format
    """
    logger.debug("Transforming request for inventory system")
    
    # Extract and validate inventory-specific fields
    transaction_id = payload.get('id', f"inv-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}")
    
    transformed = {
        'transaction_id': transaction_id,
        'operation_type': payload.get('type', 'inquiry'),
        'item_data': payload.get('data', {}),
        'inventory_metadata': {
            'source_system': 'agentcore_gateway',
            'processing_timestamp': datetime.now(timezone.utc).isoformat(),
            'batch_id': f"batch-{datetime.now(timezone.utc).strftime('%Y%m%d')}",
            'priority': payload.get('priority', 'normal')
        },
        'tracking_info': {
            'trace_id': f"trace-{transaction_id}",
            'workflow_version': '1.0',
            'audit_required': True
        }
    }
    
    # Add inventory-specific fields
    if 'quantity' in payload.get('data', {}):
        transformed['quantity_info'] = {
            'requested_quantity': float(payload['data']['quantity']),
            'unit_of_measure': payload.get('data', {}).get('unit', 'each'),
            'location_code': payload.get('data', {}).get('location', 'MAIN'),
            'lot_tracking_required': payload.get('data', {}).get('lot_tracked', False)
        }
    
    if 'item_id' in payload.get('data', {}):
        transformed['item_identification'] = {
            'item_id': payload['data']['item_id'],
            'sku': payload.get('data', {}).get('sku', payload['data']['item_id']),
            'barcode': payload.get('data', {}).get('barcode'),
            'description': payload.get('data', {}).get('description', 'Unknown Item')
        }
    
    logger.debug(f"Inventory transformation completed: {len(str(transformed))} characters")
    return transformed


def transform_generic_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Transform requests using generic format for unknown or custom systems.
    
    Generic transformation maintains original structure while adding
    standard metadata and validation information.
    
    Args:
        payload: Raw request payload
        
    Returns:
        Transformed data in generic format
    """
    logger.debug("Transforming request using generic format")
    
    transformed = {
        'request_id': payload.get('id', f"gen-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"),
        'original_payload': payload,
        'transformation_metadata': {
            'type': 'generic',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'source': 'agentcore_gateway',
            'version': '1.0'
        },
        'processing_flags': {
            'requires_validation': True,
            'supports_retry': True,
            'cacheable': False
        }
    }
    
    # Preserve important fields at top level
    for field in ['type', 'action', 'entity', 'data']:
        if field in payload:
            transformed[field] = payload[field]
    
    logger.debug(f"Generic transformation completed: {len(str(transformed))} characters")
    return transformed


def generate_mock_response(api_type: str, original_payload: Dict[str, Any], 
                          transformed_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate a mock response from the target enterprise system.
    
    In production, this function would be replaced with actual HTTP
    requests to enterprise APIs using the transformed data.
    
    Args:
        api_type: Type of API being called
        original_payload: Original request payload
        transformed_data: Transformed request data
        
    Returns:
        Mock response simulating enterprise system response
    """
    base_response = {
        'success': True,
        'transaction_id': transformed_data.get('transaction_id', 
                                             transformed_data.get('entity_id',
                                             transformed_data.get('request_id', 'unknown'))),
        'processed_data': {
            'records_affected': 1,
            'processing_status': 'completed',
            'validation_passed': True
        },
        'status': 'completed',
        'response_time_ms': 150 + (len(str(transformed_data)) // 100) * 10  # Simulate variable response time
    }
    
    # Add system-specific response fields
    if api_type == 'erp':
        base_response.update({
            'financial_summary': {
                'amount_processed': transformed_data.get('financial_data', {}).get('amount', 0),
                'account_balance': 15000.00,  # Mock balance
                'transaction_fee': 2.50
            },
            'compliance_status': {
                'audit_trail_created': True,
                'regulatory_flags': ['reviewed'],
                'approval_required': transformed_data.get('financial_data', {}).get('amount', 0) > 10000
            }
        })
    
    elif api_type == 'crm':
        base_response.update({
            'customer_summary': {
                'profile_updated': True,
                'interaction_logged': True,
                'next_follow_up': (datetime.now(timezone.utc).replace(hour=9, minute=0, second=0) + 
                                 timedelta(days=7)).isoformat()
            },
            'data_quality': {
                'completeness_score': 0.85,
                'duplicate_check_passed': True,
                'enrichment_applied': True
            }
        })
    
    elif api_type == 'inventory':
        base_response.update({
            'inventory_status': {
                'current_stock': 150,  # Mock stock level
                'reserved_quantity': 25,
                'available_quantity': 125,
                'reorder_point': 50
            },
            'location_info': {
                'primary_location': 'MAIN-A-01-B',
                'alternate_locations': ['MAIN-B-02-A', 'OVERFLOW-C-01'],
                'last_movement': (datetime.now(timezone.utc) - 
                                timedelta(hours=3)).isoformat()
            }
        })
    
    return base_response


def create_error_response(status_code: int, error_message: str) -> Dict[str, Any]:
    """
    Create a standardized error response.
    
    Args:
        status_code: HTTP status code
        error_message: Error description
        
    Returns:
        Standardized error response dictionary
    """
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'success': False,
            'error': {
                'code': status_code,
                'message': error_message,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'type': 'transformation_error'
            }
        })
    }


# Additional utility functions for enhanced functionality
def validate_payload(payload: Dict[str, Any], api_type: str) -> bool:
    """
    Validate payload structure for specific API types.
    
    Args:
        payload: Request payload to validate
        api_type: Type of API for validation rules
        
    Returns:
        True if payload is valid, False otherwise
    """
    if not isinstance(payload, dict):
        return False
    
    # Basic validation - all API types need an ID
    if 'id' not in payload:
        logger.warning("Payload missing required 'id' field")
        return False
    
    # API-specific validation
    if api_type == 'erp' and 'data' in payload:
        # ERP requires numeric amounts to be valid numbers
        if 'amount' in payload['data']:
            try:
                float(payload['data']['amount'])
            except (ValueError, TypeError):
                logger.warning("ERP payload contains invalid amount")
                return False
    
    elif api_type == 'crm' and 'data' in payload:
        # CRM requires valid email format if provided
        if 'email' in payload['data']:
            email = payload['data']['email']
            if not isinstance(email, str) or '@' not in email:
                logger.warning("CRM payload contains invalid email")
                return False
    
    return True