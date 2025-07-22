import json
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        product_id = event['productId']
        quantity_needed = int(event['quantity'])
        
        # Get current inventory
        response = table.get_item(Key={'productId': product_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'status': 'INVENTORY_NOT_FOUND',
                'message': 'Product not found in inventory'
            }
        
        item = response['Item']
        available_quantity = int(item['quantity']) - int(item.get('reserved', 0))
        
        if available_quantity < quantity_needed:
            return {
                'statusCode': 400,
                'status': 'INSUFFICIENT_INVENTORY',
                'message': f'Only {available_quantity} items available'
            }
        
        # Reserve inventory
        table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET reserved = reserved + :qty',
            ExpressionAttributeValues={':qty': quantity_needed}
        )
        
        return {
            'statusCode': 200,
            'status': 'INVENTORY_RESERVED',
            'productId': product_id,
            'quantity': quantity_needed,
            'message': 'Inventory reserved successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'INVENTORY_FAILED',
            'error': str(e)
        }