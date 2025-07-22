import json
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        order_id = event['orderId']
        
        # Update order status to cancelled
        table.update_item(
            Key={'orderId': order_id},
            UpdateExpression='SET #status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'CANCELLED'}
        )
        
        return {
            'statusCode': 200,
            'status': 'ORDER_CANCELLED',
            'orderId': order_id,
            'message': 'Order cancelled successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'CANCELLATION_FAILED',
            'error': str(e)
        }