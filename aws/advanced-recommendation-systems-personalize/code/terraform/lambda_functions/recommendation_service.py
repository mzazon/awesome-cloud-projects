import json
import boto3
import os
import logging
from datetime import datetime
import hashlib

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
personalize_runtime = boto3.client('personalize-runtime')
cloudwatch = boto3.client('cloudwatch')

# A/B Testing Configuration
AB_TEST_CONFIG = {
    'user_personalization': 0.4,  # 40% traffic
    'similar_items': 0.2,         # 20% traffic
    'trending_now': 0.2,          # 20% traffic
    'popularity': 0.2             # 20% traffic
}

def get_recommendation_strategy(user_id):
    """Determine recommendation strategy based on A/B testing using consistent hashing"""
    hash_value = int(hashlib.md5(user_id.encode()).hexdigest(), 16) % 100
    cumulative_prob = 0
    
    for strategy, probability in AB_TEST_CONFIG.items():
        cumulative_prob += probability * 100
        if hash_value < cumulative_prob:
            return strategy
    
    return 'user_personalization'  # Default fallback

def get_recommendations(campaign_arn, user_id, num_results=10, filter_arn=None, filter_values=None):
    """Get recommendations from Personalize campaign"""
    try:
        params = {
            'campaignArn': campaign_arn,
            'userId': user_id,
            'numResults': num_results
        }
        
        if filter_arn and filter_values:
            params['filterArn'] = filter_arn
            params['filterValues'] = filter_values
        
        response = personalize_runtime.get_recommendations(**params)
        return response
        
    except Exception as e:
        logger.error(f"Error getting recommendations: {str(e)}")
        return None

def get_similar_items(campaign_arn, item_id, num_results=10):
    """Get similar items recommendations"""
    try:
        response = personalize_runtime.get_recommendations(
            campaignArn=campaign_arn,
            itemId=item_id,
            numResults=num_results
        )
        return response
        
    except Exception as e:
        logger.error(f"Error getting similar items: {str(e)}")
        return None

def send_ab_test_metrics(strategy, user_id, response_time, num_results):
    """Send A/B testing metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='PersonalizeABTest',
            MetricData=[
                {
                    'MetricName': 'RecommendationRequests',
                    'Dimensions': [
                        {'Name': 'Strategy', 'Value': strategy}
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ResponseTime',
                    'Dimensions': [
                        {'Name': 'Strategy', 'Value': strategy}
                    ],
                    'Value': response_time,
                    'Unit': 'Milliseconds'
                },
                {
                    'MetricName': 'NumResults',
                    'Dimensions': [
                        {'Name': 'Strategy', 'Value': strategy}
                    ],
                    'Value': num_results,
                    'Unit': 'Count'
                }
            ]
        )
        logger.info(f"Sent metrics for strategy: {strategy}")
    except Exception as e:
        logger.error(f"Error sending metrics: {str(e)}")

def lambda_handler(event, context):
    """Main Lambda handler for recommendation requests"""
    start_time = datetime.now()
    
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract parameters from different event sources
        if 'pathParameters' in event:
            # API Gateway event
            path_params = event.get('pathParameters') or {}
            query_params = event.get('queryStringParameters') or {}
        else:
            # Direct Lambda invocation
            path_params = event
            query_params = event
        
        user_id = path_params.get('userId')
        item_id = path_params.get('itemId')
        recommendation_type = path_params.get('type', 'personalized')
        
        num_results = int(query_params.get('numResults', 10))
        category = query_params.get('category')
        min_price = query_params.get('minPrice')
        max_price = query_params.get('maxPrice')
        
        logger.info(f"Request parameters - User: {user_id}, Item: {item_id}, Type: {recommendation_type}")
        
        # Determine strategy based on A/B testing
        if recommendation_type == 'personalized' and user_id:
            strategy = get_recommendation_strategy(user_id)
        else:
            strategy = recommendation_type
        
        logger.info(f"Selected strategy: {strategy}")
        
        # Map strategies to campaign ARNs
        campaign_mapping = {
            'user_personalization': os.environ.get('USER_PERSONALIZATION_CAMPAIGN_ARN'),
            'similar_items': os.environ.get('SIMILAR_ITEMS_CAMPAIGN_ARN'),
            'trending_now': os.environ.get('TRENDING_NOW_CAMPAIGN_ARN'),
            'popularity': os.environ.get('POPULARITY_CAMPAIGN_ARN')
        }
        
        campaign_arn = campaign_mapping.get(strategy)
        if not campaign_arn:
            raise ValueError(f"Campaign ARN not configured for strategy: {strategy}")
        
        # Handle different recommendation types
        response = None
        if strategy == 'similar_items' and item_id:
            response = get_similar_items(campaign_arn, item_id, num_results)
        elif user_id:
            # Apply filters if specified
            filter_arn = None
            filter_values = {}
            
            if category:
                filter_arn = os.environ.get('CATEGORY_FILTER_ARN')
                filter_values['$CATEGORY'] = f'"{category}"'
            
            if min_price and max_price:
                filter_arn = os.environ.get('PRICE_FILTER_ARN')
                filter_values['$MIN_PRICE'] = min_price
                filter_values['$MAX_PRICE'] = max_price
            
            response = get_recommendations(
                campaign_arn,
                user_id,
                num_results,
                filter_arn,
                filter_values if filter_values else None
            )
        else:
            raise ValueError("Missing required parameters: userId or itemId")
        
        if not response:
            raise Exception("Failed to get recommendations from Personalize")
        
        # Calculate response time
        response_time = (datetime.now() - start_time).total_seconds() * 1000
        
        # Send A/B testing metrics
        recommendations_count = len(response.get('itemList', []))
        send_ab_test_metrics(strategy, user_id, response_time, recommendations_count)
        
        # Format response
        recommendations = []
        for item in response.get('itemList', []):
            recommendations.append({
                'itemId': item['itemId'],
                'score': round(item.get('score', 0), 4)
            })
        
        result = {
            'userId': user_id,
            'itemId': item_id,
            'strategy': strategy,
            'recommendations': recommendations,
            'responseTime': round(response_time, 2),
            'requestId': context.aws_request_id,
            'filters': {
                'category': category,
                'minPrice': min_price,
                'maxPrice': max_price
            } if any([category, min_price, max_price]) else None
        }
        
        logger.info(f"Returning {len(recommendations)} recommendations using strategy: {strategy}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps(result)
        }
        
    except Exception as e:
        error_message = str(e)
        logger.error(f"Error in recommendation handler: {error_message}")
        
        # Send error metrics
        try:
            cloudwatch.put_metric_data(
                Namespace='PersonalizeABTest',
                MetricData=[
                    {
                        'MetricName': 'Errors',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except:
            pass  # Don't fail if metrics can't be sent
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': error_message,
                'requestId': context.aws_request_id
            })
        }