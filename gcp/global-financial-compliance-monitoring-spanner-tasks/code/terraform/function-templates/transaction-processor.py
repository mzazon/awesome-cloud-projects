import json
import uuid
from datetime import datetime
from google.cloud import spanner
from google.cloud import tasks_v2
from google.cloud import pubsub_v1
import functions_framework

# Initialize clients
spanner_client = spanner.Client()
tasks_client = tasks_v2.CloudTasksClient()
publisher = pubsub_v1.PublisherClient()

# Configuration from Terraform template variables
SPANNER_INSTANCE = "${spanner_instance}"
SPANNER_DATABASE = "${spanner_database}"
PROJECT_ID = "${project_id}"
TOPIC_NAME = "${topic_name}"

@functions_framework.http
def process_transaction(request):
    """Process financial transaction and trigger compliance checks"""
    
    try:
        # Handle CORS preflight requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Set CORS headers for actual request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return json.dumps({'error': 'Invalid JSON in request body'}), 400, headers
        
        # Generate transaction ID
        transaction_id = str(uuid.uuid4())
        
        # Validate transaction data
        validation_error = validate_transaction_data(request_json)
        if validation_error:
            return json.dumps({'error': validation_error}), 400, headers
        
        # Connect to Spanner database
        instance = spanner_client.instance(SPANNER_INSTANCE)
        database = instance.database(SPANNER_DATABASE)
        
        # Insert transaction into database
        with database.batch() as batch:
            batch.insert(
                table='transactions',
                columns=['transaction_id', 'account_id', 'amount', 'currency',
                        'source_country', 'destination_country', 'transaction_type',
                        'timestamp', 'compliance_status', 'created_at', 'updated_at'],
                values=[(
                    transaction_id,
                    request_json['account_id'],
                    request_json['amount'],
                    request_json['currency'],
                    request_json['source_country'],
                    request_json['destination_country'],
                    request_json['transaction_type'],
                    spanner.COMMIT_TIMESTAMP,
                    'PENDING',
                    spanner.COMMIT_TIMESTAMP,
                    spanner.COMMIT_TIMESTAMP
                )]
            )
        
        # Trigger compliance check
        trigger_compliance_check(transaction_id, request_json)
        
        response = {
            'transaction_id': transaction_id,
            'status': 'pending_compliance',
            'message': 'Transaction submitted for compliance processing',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return json.dumps(response), 200, headers
        
    except Exception as e:
        error_response = {
            'error': 'Internal server error',
            'message': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }
        return json.dumps(error_response), 500, headers

def validate_transaction_data(data):
    """Validate required transaction fields"""
    required_fields = [
        'account_id', 'amount', 'currency', 'source_country',
        'destination_country', 'transaction_type'
    ]
    
    for field in required_fields:
        if field not in data:
            return f"Missing required field: {field}"
    
    # Validate data types and formats
    try:
        amount = float(data['amount'])
        if amount <= 0:
            return "Amount must be greater than 0"
    except (ValueError, TypeError):
        return "Amount must be a valid number"
    
    if len(data['currency']) != 3:
        return "Currency must be a 3-letter code (e.g., USD)"
    
    if len(data['source_country']) != 2 or len(data['destination_country']) != 2:
        return "Country codes must be 2-letter ISO codes (e.g., US)"
    
    if not data['account_id'].strip():
        return "Account ID cannot be empty"
    
    if not data['transaction_type'].strip():
        return "Transaction type cannot be empty"
    
    return None

def trigger_compliance_check(transaction_id, transaction_data):
    """Trigger compliance check via Pub/Sub"""
    try:
        topic_path = publisher.topic_path(PROJECT_ID, TOPIC_NAME)
        
        message_data = {
            'transaction_id': transaction_id,
            'transaction_data': transaction_data,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Publish message to trigger compliance processing
        future = publisher.publish(
            topic_path, 
            json.dumps(message_data).encode('utf-8'),
            source='transaction-processor',
            event_type='transaction.created'
        )
        
        # Wait for the publish to complete
        message_id = future.result()
        
        print(f"Published compliance check message {message_id} for transaction {transaction_id}")
        
    except Exception as e:
        print(f"Error publishing compliance check message: {str(e)}")
        raise