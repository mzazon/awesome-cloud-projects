import json
import boto3
import os
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Query Handler for CQRS Read Operations
    Serves read requests from optimized read models with multiple query patterns
    """
    try:
        # Parse query from API Gateway or direct invocation
        query = json.loads(event['body']) if 'body' in event else event
        query_type = query.get('queryType')
        
        if not query_type:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'queryType is required'})
            }
        
        # Route to appropriate query handler
        if query_type == 'GetUserProfile':
            result = get_user_profile(query.get('userId'))
        elif query_type == 'GetUserByEmail':
            result = get_user_by_email(query.get('email'))
        elif query_type == 'GetOrdersByUser':
            result = get_orders_by_user(query.get('userId'))
        elif query_type == 'GetOrdersByStatus':
            result = get_orders_by_status(query.get('status'))
        elif query_type == 'GetOrderDetails':
            result = get_order_details(query.get('orderId'))
        elif query_type == 'SearchUsers':
            result = search_users(query.get('searchTerm'), query.get('limit', 10))
        elif query_type == 'GetRecentOrders':
            result = get_recent_orders(query.get('limit', 10))
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': f'Unknown query type: {query_type}'})
            }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'queryType': query_type,
                'result': result,
                'timestamp': boto3.Session().region_name  # Using a simple timestamp alternative
            }, default=decimal_encoder)
        }
        
    except Exception as e:
        print(f"Error processing query: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }

def get_user_profile(user_id):
    """Get user profile by user ID"""
    if not user_id:
        raise ValueError("userId is required")
    
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.get_item(Key={'UserId': user_id})
    return response.get('Item')

def get_user_by_email(email):
    """Get user profile by email using GSI"""
    if not email:
        raise ValueError("email is required")
    
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Email-index',
        KeyConditionExpression=Key('Email').eq(email)
    )
    return response['Items'][0] if response['Items'] else None

def get_orders_by_user(user_id):
    """Get all orders for a specific user using GSI"""
    if not user_id:
        raise ValueError("userId is required")
    
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='UserId-index',
        KeyConditionExpression=Key('UserId').eq(user_id)
    )
    return response['Items']

def get_orders_by_status(status):
    """Get all orders with a specific status using GSI"""
    if not status:
        raise ValueError("status is required")
    
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Status-index',
        KeyConditionExpression=Key('Status').eq(status)
    )
    return response['Items']

def get_order_details(order_id):
    """Get order details by order ID"""
    if not order_id:
        raise ValueError("orderId is required")
    
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.get_item(Key={'OrderId': order_id})
    return response.get('Item')

def search_users(search_term, limit=10):
    """
    Search users by name or email (simple implementation using scan)
    Note: In production, consider using Amazon OpenSearch for full-text search
    """
    if not search_term:
        raise ValueError("searchTerm is required")
    
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    
    # Simple scan-based search (not optimal for large datasets)
    response = table.scan(
        FilterExpression="contains(#name, :term) OR contains(Email, :term)",
        ExpressionAttributeNames={'#name': 'Name'},
        ExpressionAttributeValues={':term': search_term},
        Limit=limit
    )
    return response['Items']

def get_recent_orders(limit=10):
    """
    Get recent orders (simple implementation using scan)
    Note: In production, consider adding a CreatedAt GSI for efficient time-based queries
    """
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    
    # Simple scan to get recent orders (not optimal for large datasets)
    response = table.scan(
        Limit=limit
    )
    
    # Sort by CreatedAt in memory (not optimal for large datasets)
    items = response['Items']
    items.sort(key=lambda x: x.get('CreatedAt', ''), reverse=True)
    
    return items[:limit]

def decimal_encoder(obj):
    """Convert Decimal objects to float for JSON serialization"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")