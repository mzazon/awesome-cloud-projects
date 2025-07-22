import json
import boto3
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table('${connections_table}')

def lambda_handler(event, context):
    """
    WebSocket $disconnect route handler
    Handles WebSocket disconnections and cleans up connection state
    """
    connection_id = event['requestContext']['connectionId']
    
    try:
        # Get connection information before deletion
        response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' in response:
            connection_data = response['Item']
            user_id = connection_data.get('userId', 'unknown')
            room_id = connection_data.get('roomId', 'unknown')
            
            print(f"Disconnecting user {user_id} from room {room_id}")
            
            # Optionally notify room members of disconnection
            # This could be extended to broadcast user left messages
            
        # Remove connection from table
        connections_table.delete_item(
            Key={'connectionId': connection_id}
        )
        
        print(f"Connection removed: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Disconnected successfully'})
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Disconnect failed'})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }