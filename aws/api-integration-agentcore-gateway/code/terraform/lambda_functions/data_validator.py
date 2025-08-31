"""
Data Validator Lambda Function
==============================
Enterprise-grade data validation function that implements comprehensive 
validation rules to protect downstream systems from malformed requests 
while providing detailed feedback to AI agents about data requirements.

This validation engine supports multiple validation types for different 
business domains including financial, customer, and standard data validation.

Author: AWS Recipe - Enterprise API Integration with AgentCore Gateway
Version: 1.0
"""

import json
import re
import os
import logging
from typing import Dict, Any, List, Union, Optional
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

# Configure logging
log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
logging.basicConfig(
    level=getattr(logging, log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Validation configuration constants
MAX_STRING_LENGTH = 1000
MAX_AMOUNT = 1000000
MIN_AMOUNT = 0
SUPPORTED_CURRENCIES = ['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY']
VALIDATION_TYPES = ['standard', 'financial', 'customer', 'inventory', 'compliance']

# Regular expression patterns for validation
EMAIL_PATTERN = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
PHONE_PATTERN = re.compile(r'^\+?[\d\s\-\(\)\.]{10,}$')
CURRENCY_CODE_PATTERN = re.compile(r'^[A-Z]{3}$')
ACCOUNT_CODE_PATTERN = re.compile(r'^[A-Z0-9\-]{3,20}$')


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    AWS Lambda handler for data validation requests.
    
    This function validates API request data according to enterprise rules,
    implementing comprehensive validation that protects downstream systems
    from invalid data while providing detailed feedback.
    
    Args:
        event: Lambda event containing validation parameters
        context: Lambda context object
        
    Returns:
        Dictionary with validation results, errors, and sanitized data
    """
    logger.info(f"Processing data validation request: {json.dumps(event, default=str)}")
    
    try:
        # Extract validation parameters
        data = event.get('data', {})
        validation_type = event.get('validation_type', 'standard')
        strict_mode = event.get('strict_mode', False)
        
        # Log validation details
        logger.debug(f"Validation type: {validation_type}")
        logger.debug(f"Strict mode: {strict_mode}")
        logger.debug(f"Data size: {len(str(data))} characters")
        
        # Validate the validation type itself
        if validation_type not in VALIDATION_TYPES:
            logger.warning(f"Unknown validation type '{validation_type}', using 'standard'")
            validation_type = 'standard'
        
        # Perform validation based on type
        start_time = datetime.now(timezone.utc)
        validation_result = validate_data(data, validation_type, strict_mode)
        processing_time = (datetime.now(timezone.utc) - start_time).total_seconds()
        
        # Enhance validation result with metadata
        validation_result.update({
            'validation_type': validation_type,
            'strict_mode': strict_mode,
            'processing_time_seconds': round(processing_time, 3),
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'validator_version': '1.0'
        })
        
        # Create response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'valid': validation_result['is_valid'],
                'errors': validation_result['errors'],
                'warnings': validation_result.get('warnings', []),
                'sanitized_data': validation_result['sanitized_data'],
                'validation_metadata': {
                    'type': validation_type,
                    'strict_mode': strict_mode,
                    'processing_time': processing_time,
                    'timestamp': validation_result['timestamp'],
                    'rules_applied': validation_result.get('rules_applied', [])
                }
            }, default=str)
        }
        
        # Log results
        status = "PASSED" if validation_result['is_valid'] else "FAILED"
        error_count = len(validation_result['errors'])
        warning_count = len(validation_result.get('warnings', []))
        
        logger.info(f"Validation {status}: {error_count} errors, {warning_count} warnings in {processing_time:.3f}s")
        
        return response
        
    except ValueError as e:
        logger.error(f"Validation configuration error: {str(e)}")
        return create_error_response(400, f"Validation configuration error: {str(e)}")
        
    except Exception as e:
        logger.error(f"Unexpected error during validation: {str(e)}", exc_info=True)
        return create_error_response(500, f"Internal validation error: {str(e)}")


def validate_data(data: Dict[str, Any], validation_type: str, strict_mode: bool = False) -> Dict[str, Any]:
    """
    Perform comprehensive data validation based on type and mode.
    
    Args:
        data: Data to validate
        validation_type: Type of validation to apply
        strict_mode: Whether to apply strict validation rules
        
    Returns:
        Dictionary containing validation results
    """
    logger.debug(f"Performing {validation_type} validation (strict: {strict_mode})")
    
    errors = []
    warnings = []
    sanitized_data = {}
    rules_applied = []
    
    try:
        # Apply validation based on type
        if validation_type == 'standard':
            errors.extend(validate_required_fields(data))
            errors.extend(validate_data_types(data))
            warnings.extend(validate_string_lengths(data))
            sanitized_data = sanitize_standard_data(data)
            rules_applied.extend(['required_fields', 'data_types', 'string_lengths'])
            
        elif validation_type == 'financial':
            errors.extend(validate_required_fields(data, ['id', 'type']))
            errors.extend(validate_financial_data(data, strict_mode))
            warnings.extend(validate_financial_warnings(data))
            sanitized_data = sanitize_financial_data(data)
            rules_applied.extend(['required_fields', 'financial_data', 'currency_validation'])
            
        elif validation_type == 'customer':
            errors.extend(validate_required_fields(data, ['id', 'type']))
            errors.extend(validate_customer_data(data, strict_mode))
            warnings.extend(validate_customer_warnings(data))
            sanitized_data = sanitize_customer_data(data)
            rules_applied.extend(['required_fields', 'customer_data', 'privacy_compliance'])
            
        elif validation_type == 'inventory':
            errors.extend(validate_required_fields(data, ['id', 'type']))
            errors.extend(validate_inventory_data(data, strict_mode))
            warnings.extend(validate_inventory_warnings(data))
            sanitized_data = sanitize_inventory_data(data)
            rules_applied.extend(['required_fields', 'inventory_data', 'quantity_validation'])
            
        elif validation_type == 'compliance':
            errors.extend(validate_compliance_data(data, strict_mode))
            warnings.extend(validate_compliance_warnings(data))
            sanitized_data = sanitize_compliance_data(data)
            rules_applied.extend(['compliance_fields', 'regulatory_validation', 'audit_requirements'])
        
        # Apply additional strict mode validations
        if strict_mode:
            errors.extend(validate_strict_mode_rules(data, validation_type))
            rules_applied.append('strict_mode_rules')
        
        # Final data integrity check
        integrity_errors = validate_data_integrity(sanitized_data)
        errors.extend(integrity_errors)
        
        if integrity_errors:
            rules_applied.append('data_integrity_check')
        
    except Exception as e:
        logger.error(f"Error during {validation_type} validation: {str(e)}")
        errors.append(f"Validation processing error: {str(e)}")
    
    return {
        'is_valid': len(errors) == 0,
        'errors': errors,
        'warnings': warnings,
        'sanitized_data': sanitized_data,
        'rules_applied': rules_applied
    }


def validate_required_fields(data: Dict[str, Any], required_fields: List[str] = None) -> List[str]:
    """
    Validate required field presence and basic structure.
    
    Args:
        data: Data to validate
        required_fields: List of required field names
        
    Returns:
        List of validation errors
    """
    if required_fields is None:
        required_fields = ['id', 'type', 'data']
    
    errors = []
    
    for field in required_fields:
        if field not in data:
            errors.append(f"Required field '{field}' is missing")
        elif data[field] is None:
            errors.append(f"Required field '{field}' cannot be null")
        elif isinstance(data[field], str) and not data[field].strip():
            errors.append(f"Required field '{field}' cannot be empty")
    
    return errors


def validate_data_types(data: Dict[str, Any]) -> List[str]:
    """
    Validate data type constraints for common fields.
    
    Args:
        data: Data to validate
        
    Returns:
        List of validation errors
    """
    errors = []
    
    # Validate ID field
    if 'id' in data and not isinstance(data['id'], (str, int)):
        errors.append("Field 'id' must be a string or integer")
    
    # Validate type field
    if 'type' in data and not isinstance(data['type'], str):
        errors.append("Field 'type' must be a string")
    
    # Validate data field structure
    if 'data' in data and not isinstance(data['data'], dict):
        errors.append("Field 'data' must be an object/dictionary")
    
    # Validate timestamp format if provided
    if 'timestamp' in data:
        try:
            datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            errors.append("Field 'timestamp' must be a valid ISO format timestamp")
    
    return errors


def validate_string_lengths(data: Dict[str, Any]) -> List[str]:
    """
    Validate string length constraints and provide warnings.
    
    Args:
        data: Data to validate
        
    Returns:
        List of validation warnings
    """
    warnings = []
    
    def check_string_field(obj: Any, path: str = ""):
        if isinstance(obj, dict):
            for key, value in obj.items():
                new_path = f"{path}.{key}" if path else key
                check_string_field(value, new_path)
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                check_string_field(item, f"{path}[{i}]")
        elif isinstance(obj, str):
            if len(obj) > MAX_STRING_LENGTH:
                warnings.append(f"String field '{path}' exceeds maximum length of {MAX_STRING_LENGTH} characters")
            elif len(obj) > MAX_STRING_LENGTH * 0.8:
                warnings.append(f"String field '{path}' is approaching maximum length limit")
    
    check_string_field(data)
    return warnings


def validate_financial_data(data: Dict[str, Any], strict_mode: bool = False) -> List[str]:
    """
    Validate financial-specific data with enhanced rules.
    
    Args:
        data: Data to validate
        strict_mode: Whether to apply strict financial validation
        
    Returns:
        List of validation errors
    """
    errors = []
    financial_data = data.get('data', {})
    
    # Validate amount field
    if 'amount' in financial_data:
        try:
            amount = Decimal(str(financial_data['amount']))
            if amount < MIN_AMOUNT:
                errors.append(f"Amount cannot be negative (minimum: {MIN_AMOUNT})")
            elif amount > MAX_AMOUNT:
                errors.append(f"Amount exceeds maximum limit of {MAX_AMOUNT}")
            
            # Strict mode: additional precision validation
            if strict_mode:
                if amount.as_tuple().exponent < -2:
                    errors.append("Amount precision cannot exceed 2 decimal places in strict mode")
                
        except (ValueError, TypeError, InvalidOperation):
            errors.append("Amount must be a valid number")
    
    # Validate currency code
    if 'currency' in financial_data:
        currency = financial_data['currency']
        if not isinstance(currency, str):
            errors.append("Currency must be a string")
        elif not CURRENCY_CODE_PATTERN.match(currency):
            errors.append("Currency must be a valid 3-letter currency code")
        elif currency not in SUPPORTED_CURRENCIES:
            errors.append(f"Currency '{currency}' is not supported. Supported: {', '.join(SUPPORTED_CURRENCIES)}")
    
    # Validate account code format
    if 'account_code' in financial_data:
        account_code = financial_data['account_code']
        if account_code and not ACCOUNT_CODE_PATTERN.match(str(account_code)):
            errors.append("Account code must be 3-20 characters with letters, numbers, and hyphens only")
    
    # Strict mode: require additional financial fields
    if strict_mode:
        required_financial_fields = ['amount', 'currency', 'account_code']
        for field in required_financial_fields:
            if field not in financial_data:
                errors.append(f"Strict mode requires financial field '{field}'")
    
    return errors


def validate_financial_warnings(data: Dict[str, Any]) -> List[str]:
    """
    Generate warnings for financial data validation.
    
    Args:
        data: Data to validate
        
    Returns:
        List of validation warnings
    """
    warnings = []
    financial_data = data.get('data', {})
    
    # Large amount warning
    if 'amount' in financial_data:
        try:
            amount = float(financial_data['amount'])
            if amount > 50000:
                warnings.append(f"Large transaction amount detected: {amount}")
            if amount > 100000:
                warnings.append("Transaction may require additional approval due to amount")
        except (ValueError, TypeError):
            pass  # Error will be caught in main validation
    
    # Missing recommended fields
    recommended_fields = ['currency', 'description', 'account_code']
    for field in recommended_fields:
        if field not in financial_data:
            warnings.append(f"Recommended financial field '{field}' is missing")
    
    return warnings


def validate_customer_data(data: Dict[str, Any], strict_mode: bool = False) -> List[str]:
    """
    Validate customer-specific data with privacy and compliance rules.
    
    Args:
        data: Data to validate
        strict_mode: Whether to apply strict customer validation
        
    Returns:
        List of validation errors
    """
    errors = []
    customer_data = data.get('data', {})
    
    # Validate email format
    if 'email' in customer_data:
        email = customer_data['email']
        if not isinstance(email, str):
            errors.append("Email must be a string")
        elif not EMAIL_PATTERN.match(email):
            errors.append("Invalid email format")
        elif len(email) > 254:  # RFC 5321 limit
            errors.append("Email address too long (maximum 254 characters)")
    
    # Validate phone number format
    if 'phone' in customer_data:
        phone = str(customer_data['phone']).strip()
        if not PHONE_PATTERN.match(phone):
            errors.append("Invalid phone number format")
        elif len(phone.replace(' ', '').replace('-', '').replace('(', '').replace(')', '').replace('+', '')) < 10:
            errors.append("Phone number too short (minimum 10 digits)")
    
    # Validate name fields
    for name_field in ['first_name', 'last_name', 'full_name']:
        if name_field in customer_data:
            name = customer_data[name_field]
            if not isinstance(name, str):
                errors.append(f"Field '{name_field}' must be a string")
            elif len(name.strip()) < 1:
                errors.append(f"Field '{name_field}' cannot be empty")
            elif len(name) > 100:
                errors.append(f"Field '{name_field}' too long (maximum 100 characters)")
            elif re.search(r'[0-9]', name):
                errors.append(f"Field '{name_field}' should not contain numbers")
    
    # Validate age/birthdate
    if 'age' in customer_data:
        try:
            age = int(customer_data['age'])
            if age < 0 or age > 150:
                errors.append("Age must be between 0 and 150")
        except (ValueError, TypeError):
            errors.append("Age must be a valid integer")
    
    if 'birthdate' in customer_data:
        try:
            birthdate = datetime.fromisoformat(customer_data['birthdate'].replace('Z', '+00:00'))
            today = datetime.now(timezone.utc)
            if birthdate > today:
                errors.append("Birthdate cannot be in the future")
            elif (today - birthdate).days > 150 * 365:
                errors.append("Birthdate indicates age over 150 years")
        except (ValueError, AttributeError):
            errors.append("Birthdate must be a valid ISO format date")
    
    # Strict mode: additional validations
    if strict_mode:
        required_customer_fields = ['email', 'first_name', 'last_name']
        for field in required_customer_fields:
            if field not in customer_data:
                errors.append(f"Strict mode requires customer field '{field}'")
        
        # Privacy compliance checks
        if 'consent_given' not in customer_data:
            errors.append("Strict mode requires explicit consent documentation")
    
    return errors


def validate_customer_warnings(data: Dict[str, Any]) -> List[str]:
    """
    Generate warnings for customer data validation.
    
    Args:
        data: Data to validate
        
    Returns:
        List of validation warnings
    """
    warnings = []
    customer_data = data.get('data', {})
    
    # Privacy and compliance warnings
    if 'email' in customer_data and 'consent_given' not in customer_data:
        warnings.append("Email provided without explicit consent documentation")
    
    if 'phone' in customer_data and 'sms_consent' not in customer_data:
        warnings.append("Phone number provided without SMS consent documentation")
    
    # Data quality warnings
    recommended_fields = ['first_name', 'last_name', 'email']
    missing_recommended = [f for f in recommended_fields if f not in customer_data]
    if missing_recommended:
        warnings.append(f"Missing recommended customer fields: {', '.join(missing_recommended)}")
    
    return warnings


def validate_inventory_data(data: Dict[str, Any], strict_mode: bool = False) -> List[str]:
    """
    Validate inventory-specific data with quantity and location rules.
    
    Args:
        data: Data to validate
        strict_mode: Whether to apply strict inventory validation
        
    Returns:
        List of validation errors
    """
    errors = []
    inventory_data = data.get('data', {})
    
    # Validate quantity
    if 'quantity' in inventory_data:
        try:
            quantity = float(inventory_data['quantity'])
            if quantity < 0:
                errors.append("Quantity cannot be negative")
            elif quantity > 1000000:
                errors.append("Quantity exceeds maximum limit")
        except (ValueError, TypeError):
            errors.append("Quantity must be a valid number")
    
    # Validate item_id format
    if 'item_id' in inventory_data:
        item_id = inventory_data['item_id']
        if not isinstance(item_id, str):
            errors.append("Item ID must be a string")
        elif len(item_id.strip()) == 0:
            errors.append("Item ID cannot be empty")
        elif len(item_id) > 50:
            errors.append("Item ID too long (maximum 50 characters)")
    
    # Validate location code
    if 'location' in inventory_data:
        location = inventory_data['location']
        if not isinstance(location, str):
            errors.append("Location must be a string")
        elif not re.match(r'^[A-Z0-9\-]{2,20}$', location):
            errors.append("Location must be 2-20 characters with uppercase letters, numbers, and hyphens")
    
    # Validate unit of measure
    if 'unit' in inventory_data:
        unit = inventory_data['unit']
        valid_units = ['each', 'kg', 'g', 'lb', 'oz', 'm', 'cm', 'in', 'l', 'ml', 'gal']
        if unit not in valid_units:
            errors.append(f"Unit must be one of: {', '.join(valid_units)}")
    
    # Strict mode validations
    if strict_mode:
        required_inventory_fields = ['item_id', 'quantity', 'location', 'unit']
        for field in required_inventory_fields:
            if field not in inventory_data:
                errors.append(f"Strict mode requires inventory field '{field}'")
    
    return errors


def validate_inventory_warnings(data: Dict[str, Any]) -> List[str]:
    """
    Generate warnings for inventory data validation.
    
    Args:
        data: Data to validate
        
    Returns:
        List of validation warnings
    """
    warnings = []
    inventory_data = data.get('data', {})
    
    # Large quantity warning
    if 'quantity' in inventory_data:
        try:
            quantity = float(inventory_data['quantity'])
            if quantity > 10000:
                warnings.append(f"Large quantity detected: {quantity}")
        except (ValueError, TypeError):
            pass
    
    # Missing recommended fields
    recommended_fields = ['item_id', 'description', 'location', 'unit']
    missing_recommended = [f for f in recommended_fields if f not in inventory_data]
    if missing_recommended:
        warnings.append(f"Missing recommended inventory fields: {', '.join(missing_recommended)}")
    
    return warnings


def validate_compliance_data(data: Dict[str, Any], strict_mode: bool = False) -> List[str]:
    """
    Validate compliance and regulatory data requirements.
    
    Args:
        data: Data to validate
        strict_mode: Whether to apply strict compliance validation
        
    Returns:
        List of validation errors
    """
    errors = []
    
    # Audit trail requirements
    if 'audit_trail' not in data and strict_mode:
        errors.append("Strict compliance mode requires audit trail information")
    
    # Data retention validation
    if 'retention_policy' in data:
        retention = data['retention_policy']
        if not isinstance(retention, dict):
            errors.append("Retention policy must be an object")
        elif 'retention_days' in retention:
            try:
                days = int(retention['retention_days'])
                if days < 1 or days > 2555:  # 7 years max
                    errors.append("Retention days must be between 1 and 2555")
            except (ValueError, TypeError):
                errors.append("Retention days must be a valid integer")
    
    return errors


def validate_compliance_warnings(data: Dict[str, Any]) -> List[str]:
    """
    Generate warnings for compliance data validation.
    
    Args:
        data: Data to validate
        
    Returns:
        List of validation warnings
    """
    warnings = []
    
    # Compliance recommendations
    if 'privacy_policy_version' not in data:
        warnings.append("Privacy policy version not specified")
    
    if 'data_classification' not in data:
        warnings.append("Data classification not specified")
    
    return warnings


def validate_strict_mode_rules(data: Dict[str, Any], validation_type: str) -> List[str]:
    """
    Apply additional validation rules for strict mode.
    
    Args:
        data: Data to validate
        validation_type: Type of validation being performed
        
    Returns:
        List of validation errors
    """
    errors = []
    
    # Require explicit versioning in strict mode
    if 'schema_version' not in data:
        errors.append("Strict mode requires explicit schema version")
    
    # Require request tracing
    if 'trace_id' not in data and 'request_id' not in data:
        errors.append("Strict mode requires request tracing (trace_id or request_id)")
    
    # Additional validation based on type
    if validation_type == 'financial':
        if 'regulatory_compliance' not in data:
            errors.append("Strict financial mode requires regulatory compliance documentation")
    
    elif validation_type == 'customer':
        if 'privacy_consent' not in data:
            errors.append("Strict customer mode requires explicit privacy consent")
    
    return errors


def validate_data_integrity(data: Dict[str, Any]) -> List[str]:
    """
    Perform final data integrity validation.
    
    Args:
        data: Sanitized data to validate
        
    Returns:
        List of validation errors
    """
    errors = []
    
    # Check for circular references
    try:
        json.dumps(data)
    except (ValueError, TypeError) as e:
        errors.append(f"Data integrity error: {str(e)}")
    
    # Validate data size limits
    data_size = len(json.dumps(data, default=str))
    if data_size > 1048576:  # 1MB limit
        errors.append(f"Data size {data_size} bytes exceeds 1MB limit")
    
    return errors


# Sanitization functions
def sanitize_standard_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize standard data by trimming strings and basic cleanup."""
    return sanitize_data_recursive(data)


def sanitize_financial_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize financial data with precision handling."""
    sanitized = sanitize_data_recursive(data)
    
    # Handle financial precision
    if 'data' in sanitized and 'amount' in sanitized['data']:
        try:
            amount = Decimal(str(sanitized['data']['amount']))
            sanitized['data']['amount'] = float(amount.quantize(Decimal('0.01')))
        except (ValueError, TypeError, InvalidOperation):
            pass  # Leave as-is if conversion fails
    
    return sanitized


def sanitize_customer_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize customer data with privacy considerations."""
    sanitized = sanitize_data_recursive(data)
    
    # Normalize email to lowercase
    if 'data' in sanitized and 'email' in sanitized['data']:
        sanitized['data']['email'] = sanitized['data']['email'].lower().strip()
    
    # Standardize phone number format
    if 'data' in sanitized and 'phone' in sanitized['data']:
        phone = re.sub(r'[^\d+]', '', str(sanitized['data']['phone']))
        sanitized['data']['phone'] = phone
    
    return sanitized


def sanitize_inventory_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize inventory data with quantity precision."""
    sanitized = sanitize_data_recursive(data)
    
    # Standardize location codes to uppercase
    if 'data' in sanitized and 'location' in sanitized['data']:
        sanitized['data']['location'] = sanitized['data']['location'].upper().strip()
    
    return sanitized


def sanitize_compliance_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize compliance data with audit trail preservation."""
    sanitized = sanitize_data_recursive(data)
    
    # Add sanitization timestamp
    sanitized['sanitization_timestamp'] = datetime.now(timezone.utc).isoformat()
    
    return sanitized


def sanitize_data_recursive(obj: Any) -> Any:
    """
    Recursively sanitize data by trimming strings and cleaning values.
    
    Args:
        obj: Object to sanitize
        
    Returns:
        Sanitized object
    """
    if isinstance(obj, dict):
        return {key: sanitize_data_recursive(value) for key, value in obj.items()}
    elif isinstance(obj, list):
        return [sanitize_data_recursive(item) for item in obj]
    elif isinstance(obj, str):
        return obj.strip()
    else:
        return obj


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
            'valid': False,
            'errors': [error_message],
            'validation_metadata': {
                'error_type': 'validation_system_error',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'status_code': status_code
            }
        })
    }