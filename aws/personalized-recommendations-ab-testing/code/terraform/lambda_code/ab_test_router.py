import json
import boto3
import hashlib
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    A/B Test Router Lambda Function
    
    Routes users to different recommendation algorithm variants
    using consistent hashing for stable assignments.
    """
    try:
        # Parse request body if it's a string (API Gateway format)
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event
        
        user_id = body.get('user_id')
        test_name = body.get('test_name', 'default_recommendation_test')
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'user_id is required'})
            }
        
        # Get or assign A/B test variant
        variant = get_or_assign_variant(user_id, test_name)
        
        # Get recommendation model configuration for variant
        model_config = get_model_config(variant)
        
        # Invoke recommendation engine with variant configuration
        recommendation_response = get_recommendations(user_id, model_config, body)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'user_id': user_id,
                'test_name': test_name,
                'variant': variant,
                'model_config': model_config,
                'recommendations': recommendation_response
            })
        }
        
    except Exception as e:
        print(f"Error in A/B test router: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def get_or_assign_variant(user_id, test_name):
    """Get existing variant assignment or create new one using consistent hashing"""
    table = dynamodb.Table(os.environ['AB_ASSIGNMENTS_TABLE'])
    
    try:
        # Check if user already has assignment
        response = table.get_item(
            Key={'UserId': user_id, 'TestName': test_name}
        )
        
        if 'Item' in response:
            return response['Item']['Variant']
        
    except Exception as e:
        print(f"Error checking existing assignment: {str(e)}")
    
    # Assign new variant using consistent hashing
    variant = assign_variant(user_id, test_name)
    
    # Store assignment
    try:
        table.put_item(
            Item={
                'UserId': user_id,
                'TestName': test_name,
                'Variant': variant,
                'AssignmentTimestamp': int(datetime.now().timestamp())
            }
        )
    except Exception as e:
        print(f"Error storing assignment: {str(e)}")
    
    return variant

def assign_variant(user_id, test_name):
    """Assign variant using consistent hashing for stable distribution"""
    # Use consistent hashing for stable assignment
    hash_input = f"{user_id}-{test_name}".encode('utf-8')
    hash_value = int(hashlib.md5(hash_input).hexdigest(), 16)
    
    # Define test configuration 
    variants = {
        'variant_a': 0.33,  # User-Personalization
        'variant_b': 0.33,  # Similar-Items
        'variant_c': 0.34   # Popularity-Count
    }
    
    # Determine variant based on hash
    normalized_hash = (hash_value % 10000) / 10000.0
    
    cumulative = 0
    for variant, probability in variants.items():
        cumulative += probability
        if normalized_hash <= cumulative:
            return variant
    
    return 'variant_a'  # Fallback

def get_model_config(variant):
    """Get model configuration for the assigned variant"""
    configs = {
        'variant_a': {
            'recipe': 'aws-user-personalization',
            'campaign_arn': os.environ.get('CAMPAIGN_A_ARN'),
            'description': 'User-Personalization Algorithm'
        },
        'variant_b': {
            'recipe': 'aws-sims',
            'campaign_arn': os.environ.get('CAMPAIGN_B_ARN'),
            'description': 'Item-to-Item Similarity Algorithm'
        },
        'variant_c': {
            'recipe': 'aws-popularity-count',
            'campaign_arn': os.environ.get('CAMPAIGN_C_ARN'),
            'description': 'Popularity-Based Algorithm'
        }
    }
    
    return configs.get(variant, configs['variant_a'])

def get_recommendations(user_id, model_config, request_body):
    """Get recommendations by invoking the recommendation engine"""
    lambda_client = boto3.client('lambda')
    
    try:
        # Prepare payload for recommendation engine
        payload = {
            'user_id': user_id,
            'model_config': model_config,
            'num_results': request_body.get('num_results', 10),
            'context': request_body.get('context', {})
        }
        
        # Invoke recommendation engine Lambda
        response = lambda_client.invoke(
            FunctionName=os.environ.get('RECOMMENDATION_ENGINE_FUNCTION', 'recommendation-engine'),
            InvocationType='RequestResponse',
            Payload=json.dumps(payload)
        )
        
        # Parse response
        response_payload = json.loads(response['Payload'].read())
        
        if response_payload.get('statusCode') == 200:
            body = json.loads(response_payload.get('body', '{}'))
            return body.get('recommendations', [])
        else:
            print(f"Recommendation engine error: {response_payload}")
            return []
            
    except Exception as e:
        print(f"Error calling recommendation engine: {str(e)}")
        return []