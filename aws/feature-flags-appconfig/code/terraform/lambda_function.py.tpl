import json
import urllib.request
import urllib.error
import os

def lambda_handler(event, context):
    """
    Lambda function that demonstrates feature flag integration with AWS AppConfig.
    
    This function retrieves feature flags from AppConfig using the Lambda extension
    and demonstrates how to use them in business logic with proper error handling
    and fallback behavior.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        dict: Response with feature flag states and business logic results
    """
    
    # AppConfig Lambda extension endpoint - uses environment variables
    # injected by Terraform template
    appconfig_url = f"http://localhost:2772/applications/${app_id}/environments/${env_id}/configurations/${profile_id}"
    
    try:
        # Retrieve feature flags from AppConfig via Lambda extension
        request = urllib.request.Request(appconfig_url)
        with urllib.request.urlopen(request, timeout=10) as response:
            config_data = json.loads(response.read().decode())
        
        # Extract feature flags and attributes from configuration
        flags = config_data.get('flags', {})
        attributes = config_data.get('attributes', {})
        
        # Initialize response structure
        result = {
            'message': 'Feature flag demo response',
            'timestamp': context.aws_request_id,
            'features': {},
            'configuration_source': 'appconfig'
        }
        
        # Business Logic: New Checkout Flow Feature
        # Demonstrates conditional feature enabling with attribute-based configuration
        if flags.get('new-checkout-flow', {}).get('enabled', False):
            rollout_percentage = attributes.get('rollout-percentage', {}).get('number', 0)
            target_audience = attributes.get('target-audience', {}).get('string', 'all-users')
            
            result['features']['checkout'] = {
                'enabled': True,
                'type': 'new-flow',
                'rollout_percentage': rollout_percentage,
                'target_audience': target_audience,
                'description': 'Enhanced checkout experience with improved UX'
            }
        else:
            result['features']['checkout'] = {
                'enabled': False,
                'type': 'legacy-flow',
                'description': 'Standard checkout flow'
            }
        
        # Business Logic: Enhanced Search Feature
        # Shows how to use feature flags with algorithm selection and caching configuration
        if flags.get('enhanced-search', {}).get('enabled', False):
            search_algorithm = attributes.get('search-algorithm', {}).get('string', 'basic')
            cache_ttl = attributes.get('cache-ttl', {}).get('number', 300)
            
            result['features']['search'] = {
                'enabled': True,
                'algorithm': search_algorithm,
                'cache_ttl': cache_ttl,
                'description': f'Enhanced search using {search_algorithm} with {cache_ttl}s cache'
            }
        else:
            result['features']['search'] = {
                'enabled': False,
                'algorithm': 'basic',
                'description': 'Basic search functionality'
            }
        
        # Business Logic: Premium Features
        # Demonstrates feature lists and premium feature enablement
        if flags.get('premium-features', {}).get('enabled', False):
            feature_list = attributes.get('feature-list', {}).get('string', '')
            features_array = feature_list.split(',') if feature_list else []
            
            result['features']['premium'] = {
                'enabled': True,
                'features': features_array,
                'count': len(features_array),
                'description': f'Premium features enabled: {", ".join(features_array)}'
            }
        else:
            result['features']['premium'] = {
                'enabled': False,
                'features': [],
                'count': 0,
                'description': 'Premium features not available'
            }
        
        # Add configuration metadata for debugging
        result['configuration_metadata'] = {
            'version': config_data.get('version', 'unknown'),
            'flags_count': len(flags),
            'attributes_count': len(attributes)
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Feature-Flags-Source': 'appconfig'
            },
            'body': json.dumps(result, indent=2, default=str)
        }
        
    except urllib.error.HTTPError as e:
        error_msg = f"HTTP Error retrieving feature flags: {e.code} - {e.reason}"
        print(error_msg)
        return create_fallback_response(error_msg, context.aws_request_id)
        
    except urllib.error.URLError as e:
        error_msg = f"URL Error retrieving feature flags: {str(e)}"
        print(error_msg)
        return create_fallback_response(error_msg, context.aws_request_id)
        
    except json.JSONDecodeError as e:
        error_msg = f"JSON decode error: {str(e)}"
        print(error_msg)
        return create_fallback_response(error_msg, context.aws_request_id)
        
    except Exception as e:
        error_msg = f"Unexpected error retrieving feature flags: {str(e)}"
        print(error_msg)
        return create_fallback_response(error_msg, context.aws_request_id)

def create_fallback_response(error_msg, request_id):
    """
    Creates a fallback response when feature flag retrieval fails.
    
    This function demonstrates graceful degradation by returning safe default
    feature states when AppConfig is unavailable, ensuring application
    continues to function even during configuration service outages.
    
    Args:
        error_msg (str): Error message describing the failure
        request_id (str): AWS request ID for correlation
        
    Returns:
        dict: Lambda response with default feature flag states
    """
    
    fallback_config = {
        'message': 'Using default configuration due to AppConfig service error',
        'timestamp': request_id,
        'error': error_msg,
        'configuration_source': 'fallback',
        'features': {
            'checkout': {
                'enabled': False,
                'type': 'legacy-flow',
                'description': 'Fallback to legacy checkout (safe default)'
            },
            'search': {
                'enabled': False,
                'algorithm': 'basic',
                'description': 'Fallback to basic search (safe default)'
            },
            'premium': {
                'enabled': False,
                'features': [],
                'count': 0,
                'description': 'Premium features disabled (safe default)'
            }
        },
        'fallback_reason': 'AppConfig service unavailable or configuration error'
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Feature-Flags-Source': 'fallback',
            'X-Feature-Flags-Error': 'true'
        },
        'body': json.dumps(fallback_config, indent=2, default=str)
    }