import json
import os
from google.cloud import storage
import functions_framework
from datetime import datetime

@functions_framework.http
def retrieve_recipes(request):
    """Retrieve and search stored recipes with filtering capabilities"""
    try:
        # Set CORS headers for web application compatibility
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)

        # Parse query parameters for flexible search
        args = request.args
        recipe_id = args.get('recipe_id')
        ingredient_filter = args.get('ingredient')
        cuisine_filter = args.get('cuisine')
        skill_filter = args.get('skill_level')
        limit = int(args.get('limit', 10))
        
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
        
        # If specific recipe requested, return it directly
        if recipe_id:
            blob = bucket.blob(f"recipes/{recipe_id}.json")
            if blob.exists():
                recipe_data = json.loads(blob.download_as_text())
                response_data = {'recipe': recipe_data}
                return json.dumps(response_data), 200, {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                }
            else:
                error_response = {'error': 'Recipe not found', 'recipe_id': recipe_id}
                return json.dumps(error_response), 404, {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                }
        
        # List all recipes with filtering capabilities
        recipes = []
        total_scanned = 0
        blobs = bucket.list_blobs(prefix="recipes/")
        
        for blob in blobs:
            if blob.name.endswith('.json'):
                total_scanned += 1
                try:
                    recipe_data = json.loads(blob.download_as_text())
                    
                    # Apply filters based on request parameters
                    include_recipe = True
                    
                    # Filter by ingredient
                    if ingredient_filter:
                        ingredients_text = ' '.join(recipe_data.get('input_ingredients', []))
                        if ingredient_filter.lower() not in ingredients_text.lower():
                            include_recipe = False
                    
                    # Filter by cuisine type
                    if cuisine_filter:
                        if cuisine_filter.lower() != recipe_data.get('cuisine_type', '').lower():
                            include_recipe = False
                    
                    # Filter by skill level
                    if skill_filter:
                        if skill_filter.lower() != recipe_data.get('skill_level', '').lower():
                            include_recipe = False
                    
                    if include_recipe:
                        # Return summarized recipe information for list view
                        recipe_summary = {
                            'id': recipe_data.get('id'),
                            'generated_at': recipe_data.get('generated_at'),
                            'ingredients': recipe_data.get('input_ingredients'),
                            'cuisine_type': recipe_data.get('cuisine_type'),
                            'skill_level': recipe_data.get('skill_level'),
                            'dietary_restrictions': recipe_data.get('dietary_restrictions', []),
                            'model_used': recipe_data.get('model_used', 'unknown')
                        }
                        
                        # Try to extract recipe title from AI response if available
                        try:
                            ai_response = recipe_data.get('ai_response', '')
                            if ai_response:
                                # Simple extraction - look for JSON in response
                                if '{' in ai_response and '}' in ai_response:
                                    start = ai_response.find('{')
                                    end = ai_response.rfind('}') + 1
                                    ai_json = json.loads(ai_response[start:end])
                                    recipe_summary['title'] = ai_json.get('title', 'Generated Recipe')
                                else:
                                    recipe_summary['title'] = 'Generated Recipe'
                            else:
                                recipe_summary['title'] = 'Generated Recipe'
                        except:
                            recipe_summary['title'] = 'Generated Recipe'
                        
                        recipes.append(recipe_summary)
                        
                        if len(recipes) >= limit:
                            break
                
                except Exception as e:
                    # Skip malformed recipes gracefully but log the error
                    print(f"Error processing recipe {blob.name}: {str(e)}")
                    continue
        
        response_data = {
            'recipes': recipes,
            'total_found': len(recipes),
            'total_scanned': total_scanned,
            'filters_applied': {
                'ingredient': ingredient_filter,
                'cuisine': cuisine_filter,
                'skill_level': skill_filter
            },
            'timestamp': datetime.now().isoformat()
        }
        
        return json.dumps(response_data), 200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        }
        
    except Exception as e:
        error_response = {
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }
        return json.dumps(error_response), 500, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        }