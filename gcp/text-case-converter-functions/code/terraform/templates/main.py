import functions_framework
import json
import re

@functions_framework.http
def ${function_name}(request):
    """HTTP Cloud Function for text case conversion.
    
    Accepts POST requests with JSON payload containing:
    - text: string to convert
    - case_type: target case format
    
    Returns JSON response with converted text.
    """
    
    # Set CORS headers for cross-origin requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight OPTIONS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Only accept POST requests
    if request.method != 'POST':
        return (json.dumps({'error': 'Method not allowed'}), 405, headers)
    
    try:
        # Parse JSON request body
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON'}), 400, headers)
        
        text = request_json.get('text', '')
        case_type = request_json.get('case_type', '').lower()
        
        if not text:
            return (json.dumps({'error': 'Text field is required'}), 400, headers)
        
        if not case_type:
            return (json.dumps({'error': 'case_type field is required'}), 400, headers)
        
        # Perform case conversion
        converted_text = convert_case(text, case_type)
        
        if converted_text is None:
            return (json.dumps({'error': f'Unsupported case type: {case_type}'}), 400, headers)
        
        # Return successful response
        response = {
            'original': text,
            'case_type': case_type,
            'converted': converted_text
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        # Log error and return generic error message
        print(f"Error processing request: {str(e)}")
        return (json.dumps({'error': 'Internal server error'}), 500, headers)

def convert_case(text, case_type):
    """Convert text to specified case format."""
    
    case_handlers = {
        'upper': lambda t: t.upper(),
        'uppercase': lambda t: t.upper(),
        'lower': lambda t: t.lower(),
        'lowercase': lambda t: t.lower(),
        'title': lambda t: t.title(),
        'titlecase': lambda t: t.title(),
        'capitalize': lambda t: t.capitalize(),
        'camel': lambda t: to_camel_case(t),
        'camelcase': lambda t: to_camel_case(t),
        'pascal': lambda t: to_pascal_case(t),
        'pascalcase': lambda t: to_pascal_case(t),
        'snake': lambda t: to_snake_case(t),
        'snakecase': lambda t: to_snake_case(t),
        'kebab': lambda t: to_kebab_case(t),
        'kebabcase': lambda t: to_kebab_case(t)
    }
    
    return case_handlers.get(case_type, lambda t: None)(text)

def to_camel_case(text):
    """Convert text to camelCase."""
    # Split on whitespace and non-alphanumeric characters
    words = re.split(r'[^a-zA-Z0-9]', text)
    # Filter empty strings and convert
    words = [word for word in words if word]
    if not words:
        return text
    
    result = words[0].lower()
    for word in words[1:]:
        result += word.capitalize()
    return result

def to_pascal_case(text):
    """Convert text to PascalCase."""
    words = re.split(r'[^a-zA-Z0-9]', text)
    words = [word for word in words if word]
    return ''.join(word.capitalize() for word in words)

def to_snake_case(text):
    """Convert text to snake_case."""
    # Handle camelCase and PascalCase
    s1 = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', text)
    # Handle sequences of uppercase letters
    s2 = re.sub('([a-z0-9])([A-Z])', r'\1_\2', s1)
    # Replace whitespace and non-alphanumeric with underscores
    s3 = re.sub(r'[^a-zA-Z0-9]', '_', s2)
    # Remove duplicate underscores and convert to lowercase
    return re.sub(r'_+', '_', s3).strip('_').lower()

def to_kebab_case(text):
    """Convert text to kebab-case."""
    # Similar to snake_case but with hyphens
    s1 = re.sub('(.)([A-Z][a-z]+)', r'\1-\2', text)
    s2 = re.sub('([a-z0-9])([A-Z])', r'\1-\2', s1)
    s3 = re.sub(r'[^a-zA-Z0-9]', '-', s2)
    return re.sub(r'-+', '-', s3).strip('-').lower()