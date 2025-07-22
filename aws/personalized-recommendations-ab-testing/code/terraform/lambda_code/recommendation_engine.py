import json
import boto3
import os
from datetime import datetime

personalize_runtime = boto3.client('personalize-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Recommendation Engine Lambda Function
    
    Serves personalized recommendations using Amazon Personalize
    with fallback mechanisms and metadata enrichment.
    """
    try:
        # Parse request body if it's a string (API Gateway format)
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event
        
        user_id = body.get('user_id')
        model_config = body.get('model_config', {})
        num_results = body.get('num_results', 10)
        context_data = body.get('context', {})
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'user_id is required'})
            }
        
        try:
            # Get recommendations from Personalize
            recommendations = get_personalize_recommendations(
                user_id, model_config, num_results, context_data
            )
            
            # Enrich recommendations with item metadata
            enriched_recommendations = enrich_recommendations(recommendations)
            
            # Track recommendation request
            track_recommendation_request(user_id, model_config, enriched_recommendations)
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'user_id': user_id,
                    'recommendations': enriched_recommendations,
                    'algorithm': model_config.get('description', 'Unknown'),
                    'timestamp': datetime.now().isoformat()
                })
            }
            
        except Exception as e:
            print(f"Personalize error: {str(e)}")
            # Fallback to popularity-based recommendations
            fallback_recommendations = get_fallback_recommendations(num_results)
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'user_id': user_id,
                    'recommendations': fallback_recommendations,
                    'algorithm': 'Fallback - Popularity Based',
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                })
            }
            
    except Exception as e:
        print(f"General error in recommendation engine: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def get_personalize_recommendations(user_id, model_config, num_results, context_data):
    """Get recommendations from Amazon Personalize"""
    campaign_arn = model_config.get('campaign_arn')
    
    if not campaign_arn:
        raise ValueError("No campaign ARN provided")
    
    # Build request parameters
    request_params = {
        'campaignArn': campaign_arn,
        'userId': user_id,
        'numResults': num_results
    }
    
    # Add context if provided
    if context_data:
        request_params['context'] = context_data
    
    # Get recommendations from Personalize
    response = personalize_runtime.get_recommendations(**request_params)
    
    return response['itemList']

def enrich_recommendations(recommendations):
    """Enrich recommendations with item metadata from DynamoDB"""
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    enriched = []
    for item in recommendations:
        item_id = item['itemId']
        
        try:
            # Get item metadata from DynamoDB
            response = items_table.get_item(Key={'ItemId': item_id})
            
            if 'Item' in response:
                item_data = response['Item']
                enriched.append({
                    'item_id': item_id,
                    'score': float(item.get('score', 0)),
                    'category': item_data.get('Category', 'Unknown'),
                    'price': float(item_data.get('Price', 0)),
                    'brand': item_data.get('Brand', 'Unknown'),
                    'creation_date': item_data.get('CreationDate', '')
                })
            else:
                # Item not found in catalog
                enriched.append({
                    'item_id': item_id,
                    'score': float(item.get('score', 0)),
                    'category': 'Unknown',
                    'price': 0,
                    'brand': 'Unknown',
                    'creation_date': '',
                    'warning': 'Item not found in catalog'
                })
                
        except Exception as e:
            print(f"Error enriching item {item_id}: {str(e)}")
            enriched.append({
                'item_id': item_id,
                'score': float(item.get('score', 0)),
                'error': str(e)
            })
    
    return enriched

def get_fallback_recommendations(num_results):
    """Get fallback recommendations when Personalize is unavailable"""
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    try:
        # Simple scan for items (in production, use a better method like GSI)
        response = items_table.scan(Limit=num_results)
        items = response.get('Items', [])
        
        fallback = []
        for item in items:
            fallback.append({
                'item_id': item['ItemId'],
                'score': 0.5,  # Default score for fallback
                'category': item.get('Category', 'Unknown'),
                'price': float(item.get('Price', 0)),
                'brand': item.get('Brand', 'Unknown'),
                'creation_date': item.get('CreationDate', ''),
                'fallback': True
            })
        
        return fallback
        
    except Exception as e:
        print(f"Error getting fallback recommendations: {str(e)}")
        return []

def track_recommendation_request(user_id, model_config, recommendations):
    """Track recommendation serving for analytics"""
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    try:
        # Calculate TTL (30 days from now)
        ttl_timestamp = int(datetime.now().timestamp()) + (30 * 24 * 60 * 60)
        
        events_table.put_item(
            Item={
                'UserId': user_id,
                'Timestamp': int(datetime.now().timestamp() * 1000),
                'EventType': 'recommendation_served',
                'Algorithm': model_config.get('description', 'Unknown'),
                'ItemCount': len(recommendations),
                'Items': json.dumps([r['item_id'] for r in recommendations]),
                'ExpirationTime': ttl_timestamp  # TTL for automatic cleanup
            }
        )
    except Exception as e:
        print(f"Failed to track recommendation request: {str(e)}")

def get_user_context(user_id):
    """Get user context data for enhanced recommendations"""
    users_table = dynamodb.Table(os.environ.get('USERS_TABLE', 'users'))
    
    try:
        response = users_table.get_item(Key={'UserId': user_id})
        
        if 'Item' in response:
            user_data = response['Item']
            return {
                'age_group': categorize_age(user_data.get('Age', 25)),
                'subscription_type': user_data.get('SubscriptionType', 'free'),
                'gender': user_data.get('Gender', 'unknown')
            }
    except Exception as e:
        print(f"Error getting user context: {str(e)}")
    
    return {}

def categorize_age(age):
    """Categorize age into groups for context"""
    try:
        age = int(age)
        if age < 25:
            return 'young_adult'
        elif age < 35:
            return 'adult'
        elif age < 50:
            return 'middle_aged'
        else:
            return 'senior'
    except:
        return 'unknown'