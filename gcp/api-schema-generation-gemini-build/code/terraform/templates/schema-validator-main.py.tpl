import json
import jsonschema
import re
import os
from typing import Dict, List, Any
from google.cloud import storage
import functions_framework

@functions_framework.http
def validate_schema(request):
    """Validate OpenAPI schema compliance and best practices"""
    
    try:
        # Download schema from Cloud Storage
        client = storage.Client()
        bucket_name = request.args.get('bucket') or request.get_json().get('bucket_name') if request.get_json() else None
        
        if not bucket_name:
            bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
        
        if not bucket_name:
            return {'valid': False, 'errors': ['Bucket name is required']}, 400
        
        bucket = client.bucket(bucket_name)
        blob = bucket.blob('openapi-schema.json')
        
        if not blob.exists():
            return {'valid': False, 'errors': ['Schema file not found']}, 404
        
        schema_content = blob.download_as_text()
        schema = json.loads(schema_content)
        
        # Comprehensive validation results
        validation_results = {
            'valid': True,
            'errors': [],
            'warnings': [],
            'best_practices': [],
            'statistics': {}
        }
        
        # Required field validation
        required_fields = ['openapi', 'info', 'paths']
        for field in required_fields:
            if field not in schema:
                validation_results['valid'] = False
                validation_results['errors'].append(f"Missing required field: {field}")
        
        # OpenAPI version validation
        openapi_version = schema.get('openapi', '')
        if not openapi_version.startswith('3.'):
            validation_results['valid'] = False
            validation_results['errors'].append(f"Unsupported OpenAPI version: {openapi_version}")
        else:
            validation_results['warnings'].append(f"Using OpenAPI {openapi_version} specification")
        
        # Info section validation
        info = schema.get('info', {})
        if not info.get('title'):
            validation_results['errors'].append("Missing API title in info section")
        if not info.get('version'):
            validation_results['errors'].append("Missing API version in info section")
        
        # Paths validation
        paths = schema.get('paths', {})
        if not paths:
            validation_results['warnings'].append("No API paths defined")
        else:
            validation_results['statistics']['endpoint_count'] = len(paths)
            
            # Validate HTTP methods and responses
            for path, methods in paths.items():
                for method, details in methods.items():
                    if method.upper() not in ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']:
                        continue
                        
                    if 'responses' not in details:
                        validation_results['warnings'].append(f"Missing responses for {method.upper()} {path}")
                    else:
                        responses = details['responses']
                        if '200' not in responses and method.upper() == 'GET':
                            validation_results['warnings'].append(f"GET {path} should have a 200 response")
                        if '201' not in responses and method.upper() == 'POST':
                            validation_results['warnings'].append(f"POST {path} should have a 201 response")
        
        # Components validation
        components = schema.get('components', {})
        schemas = components.get('schemas', {})
        validation_results['statistics']['schema_count'] = len(schemas)
        
        # Best practices checks
        if 'servers' in schema:
            validation_results['best_practices'].append("✓ Server definitions included")
        else:
            validation_results['warnings'].append("Consider adding server definitions")
        
        if info.get('description'):
            validation_results['best_practices'].append("✓ API description provided")
        else:
            validation_results['warnings'].append("Consider adding API description")
        
        if components:
            validation_results['best_practices'].append("✓ Reusable components defined")
        
        # Security validation
        if 'security' in schema or any('security' in details for details in paths.values()):
            validation_results['best_practices'].append("✓ Security definitions included")
        else:
            validation_results['warnings'].append("Consider adding security definitions")
        
        # Final validation status
        if validation_results['errors']:
            validation_results['valid'] = False
        
        return validation_results
        
    except json.JSONDecodeError as e:
        return {'valid': False, 'errors': [f'Invalid JSON: {str(e)}']}, 400
    except Exception as e:
        return {'valid': False, 'errors': [f'Validation error: {str(e)}']}, 500