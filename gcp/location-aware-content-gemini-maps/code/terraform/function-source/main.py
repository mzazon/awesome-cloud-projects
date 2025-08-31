import os
import json
from datetime import datetime
from google import genai
from google.genai import types
from google.cloud import storage
from flask import jsonify

# Initialize Vertex AI client with Maps grounding support
client = genai.Client(
    vertexai=True,
    project=os.environ.get('GCP_PROJECT'),
    location='us-central1'
)

# Initialize Cloud Storage client
storage_client = storage.Client()

def generate_location_content(request):
    """Generate location-aware content using Gemini with Maps grounding."""
    
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json()
        location = request_json.get('location', '')
        content_type = request_json.get('content_type', 'marketing')
        audience = request_json.get('audience', 'general')
        
        if not location:
            return jsonify({'error': 'Location parameter required'}), 400
        
        # Construct prompt based on content type
        prompts = {
            'marketing': f"""Create compelling marketing copy for {location}. 
                        Include specific local attractions, dining options, and unique 
                        features that make this location special. Target audience: {audience}.
                        Use factual information about real places and businesses.""",
            
            'travel': f"""Write a detailed travel guide for {location}. 
                      Include must-see attractions, local restaurants, transportation 
                      options, and insider tips. Make it engaging and informative 
                      with specific place names and details.""",
            
            'business': f"""Create professional business content about {location} 
                        including market opportunities, local demographics, key 
                        attractions, and business environment. Include specific 
                        venues and establishments."""
        }
        
        prompt = prompts.get(content_type, prompts['marketing'])
        
        # Configure Maps grounding tool
        maps_tool = types.Tool(
            google_maps=types.GoogleMaps(
                auth_config={}  # Uses default authentication
            )
        )
        
        # Generate content with Maps grounding
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
            tools=[maps_tool],
            config=types.GenerateContentConfig(
                temperature=0.7,
                max_output_tokens=1000,
                top_p=0.8
            )
        )
        
        generated_content = response.text
        
        # Extract grounding information if available
        grounding_info = []
        if hasattr(response, 'grounding_metadata') and response.grounding_metadata:
            metadata = response.grounding_metadata
            if hasattr(metadata, 'grounding_chunks') and metadata.grounding_chunks:
                for chunk in metadata.grounding_chunks:
                    if hasattr(chunk, 'web') and chunk.web:
                        grounding_info.append({
                            'title': getattr(chunk.web, 'title', 'Unknown'),
                            'uri': getattr(chunk.web, 'uri', ''),
                            'domain': getattr(chunk.web, 'domain', '')
                        })
        
        # Save generated content to Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            bucket = storage_client.bucket(bucket_name)
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"content/{content_type}_{location.replace(' ', '_')}_{timestamp}.json"
            
            content_data = {
                'location': location,
                'content_type': content_type,
                'audience': audience,
                'generated_content': generated_content,
                'grounding_sources': grounding_info,
                'timestamp': timestamp,
                'model': 'gemini-2.5-flash'
            }
            
            blob = bucket.blob(filename)
            blob.upload_from_string(
                json.dumps(content_data, indent=2),
                content_type='application/json'
            )
        
        return jsonify({
            'content': generated_content,
            'location': location,
            'content_type': content_type,
            'grounding_sources': grounding_info,
            'timestamp': timestamp
        }), 200, headers
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500, headers