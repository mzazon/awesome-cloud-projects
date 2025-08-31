import json
import colorsys
import hashlib
from datetime import datetime
from google.cloud import storage
import functions_framework

def hex_to_hsl(hex_color):
    """Convert hex color to HSL values"""
    hex_color = hex_color.lstrip('#')
    r, g, b = tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))
    r, g, b = r/255.0, g/255.0, b/255.0
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s * 100, l * 100

def hsl_to_hex(h, s, l):
    """Convert HSL values to hex color"""
    h, s, l = h/360.0, s/100.0, l/100.0
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

def generate_palette(base_color):
    """Generate harmonious color palette from base color"""
    h, s, l = hex_to_hsl(base_color)
    
    # Generate complementary and analogous colors
    palette = {
        'base': base_color,
        'complementary': hsl_to_hex((h + 180) % 360, s, l),
        'analogous_1': hsl_to_hex((h + 30) % 360, s, l),
        'analogous_2': hsl_to_hex((h - 30) % 360, s, l),
        'triadic_1': hsl_to_hex((h + 120) % 360, s, l),
        'triadic_2': hsl_to_hex((h + 240) % 360, s, l),
        'light_variant': hsl_to_hex(h, s, min(100, l + 20)),
        'dark_variant': hsl_to_hex(h, s, max(0, l - 20))
    }
    
    return palette

@functions_framework.http
def generate_color_palette(request):
    """HTTP Cloud Function for color palette generation"""
    
    # Handle CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json or 'base_color' not in request_json:
            return (json.dumps({"error": "Missing base_color parameter"}), 400, headers)
        
        base_color = request_json['base_color']
        
        # Validate hex color format
        if not base_color.startswith('#') or len(base_color) != 7:
            return (json.dumps({"error": "Invalid hex color format. Use #RRGGBB"}), 400, headers)
        
        # Validate hex characters
        try:
            int(base_color[1:], 16)
        except ValueError:
            return (json.dumps({"error": "Invalid hex color format. Use #RRGGBB"}), 400, headers)
        
        # Generate color palette
        palette = generate_palette(base_color)
        
        # Create palette metadata
        palette_id = hashlib.md5(base_color.encode()).hexdigest()[:8]
        palette_data = {
            'id': palette_id,
            'base_color': base_color,
            'colors': palette,
            'created_at': datetime.utcnow().isoformat(),
            'palette_type': 'harmonious'
        }
        
        # Store palette in Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket('${bucket_name}')
        blob = bucket.blob(f'palettes/{palette_id}.json')
        blob.upload_from_string(
            json.dumps(palette_data, indent=2),
            content_type='application/json'
        )
        
        # Return response with palette and storage URL
        response_data = {
            'success': True,
            'palette': palette_data,
            'storage_url': f'https://storage.googleapis.com/{bucket.name}/{blob.name}'
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        error_response = {'error': f'Internal server error: {str(e)}'}
        return (json.dumps(error_response), 500, headers)