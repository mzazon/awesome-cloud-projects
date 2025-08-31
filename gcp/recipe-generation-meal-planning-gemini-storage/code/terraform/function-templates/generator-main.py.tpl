import json
import os
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
from datetime import datetime

# Initialize Vertex AI with project from environment
aiplatform.init(project="${project_id}", location=os.environ.get('VERTEX_LOCATION', 'us-central1'))

@functions_framework.http
def generate_recipe(request):
    """Generate personalized recipes using Vertex AI Gemini models"""
    try:
        # Set CORS headers for web application compatibility
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)

        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return json.dumps({'error': 'Invalid JSON'}), 400, {'Content-Type': 'application/json'}
        
        ingredients = request_json.get('ingredients', [])
        dietary_restrictions = request_json.get('dietary_restrictions', [])
        skill_level = request_json.get('skill_level', 'beginner')
        cuisine_type = request_json.get('cuisine_type', 'any')
        
        if not ingredients:
            return json.dumps({'error': 'Ingredients list required'}), 400, {'Content-Type': 'application/json'}
        
        # Create comprehensive Gemini prompt for recipe generation
        prompt = f"""
        Create a detailed recipe using these ingredients: {', '.join(ingredients)}
        
        Requirements:
        - Dietary restrictions: {', '.join(dietary_restrictions) if dietary_restrictions else 'None'}
        - Cooking skill level: {skill_level}
        - Cuisine preference: {cuisine_type}
        
        Please provide:
        1. Recipe title
        2. Preparation time and cooking time
        3. Ingredient list with quantities
        4. Step-by-step instructions
        5. Nutritional highlights
        6. Serving suggestions
        
        Format as JSON with fields: title, prep_time, cook_time, ingredients_with_quantities, instructions, nutrition_info, serving_suggestions
        """
        
        # Generate content using the specified Gemini model
        model = aiplatform.generative_models.GenerativeModel('${model_name}')
        response = model.generate_content(prompt)
        
        # Parse and store recipe with metadata
        recipe_data = {
            'id': f"recipe-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            'generated_at': datetime.now().isoformat(),
            'input_ingredients': ingredients,
            'dietary_restrictions': dietary_restrictions,
            'skill_level': skill_level,
            'cuisine_type': cuisine_type,
            'ai_response': response.text,
            'model_used': '${model_name}',
            'project_id': '${project_id}'
        }
        
        # Store in Cloud Storage with structured path
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
        blob = bucket.blob(f"recipes/{recipe_data['id']}.json")
        blob.upload_from_string(json.dumps(recipe_data, indent=2))
        
        response_data = {
            'success': True,
            'recipe_id': recipe_data['id'],
            'recipe': recipe_data
        }
        
        return json.dumps(response_data), 200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        }
        
    except Exception as e:
        error_response = {'error': str(e), 'timestamp': datetime.now().isoformat()}
        return json.dumps(error_response), 500, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        }