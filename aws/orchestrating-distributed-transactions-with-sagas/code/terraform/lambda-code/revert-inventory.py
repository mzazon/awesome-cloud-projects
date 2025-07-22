import json
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        product_id = event['productId']
        quantity = int(event['quantity'])
        
        # Release reserved inventory
        table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET reserved = reserved - :qty',
            ExpressionAttributeValues={':qty': quantity}
        )
        
        return {
            'statusCode': 200,
            'status': 'INVENTORY_REVERTED',
            'productId': product_id,
            'quantity': quantity,
            'message': 'Inventory reservation reverted'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'REVERT_FAILED',
            'error': str(e)
        }