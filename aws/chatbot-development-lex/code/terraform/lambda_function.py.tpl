import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Environment variables
ORDERS_TABLE = os.environ.get('ORDERS_TABLE', '${orders_table_name}')
PRODUCTS_BUCKET = os.environ.get('PRODUCTS_BUCKET', '${products_bucket_name}')

def lambda_handler(event, context):
    """
    Main Lambda handler for Amazon Lex bot fulfillment.
    Processes different intents and returns appropriate responses.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        intent_name = event['sessionState']['intent']['name']
        
        if intent_name == 'ProductInformation':
            return handle_product_information(event)
        elif intent_name == 'OrderStatus':
            return handle_order_status(event)
        elif intent_name == 'SupportRequest':
            return handle_support_request(event)
        else:
            return close_intent(event, "I'm sorry, I don't understand that request. Please try asking about products, order status, or request support.")
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return close_intent(event, "I'm experiencing technical difficulties. Please try again later or contact support.")

def handle_product_information(event):
    """
    Handle product information requests.
    Extracts product type from slots and provides relevant information.
    """
    slots = event['sessionState']['intent']['slots']
    product_type = None
    
    if 'ProductType' in slots and slots['ProductType'] and 'value' in slots['ProductType']:
        product_type = slots['ProductType']['value']['interpretedValue']
    
    if not product_type:
        return elicit_slot(event, 'ProductType', 
                          "What type of product are you interested in? We have electronics, clothing, and books.")
    
    # Product information lookup (simulated)
    product_info = {
        'electronics': "Our electronics include smartphones, laptops, tablets, and smart home devices. Prices range from $50 to $2000. We carry top brands like Apple, Samsung, and Sony.",
        'clothing': "Our clothing collection features casual wear, formal attire, and seasonal items. Sizes range from XS to XXL. We offer free returns within 30 days.",
        'books': "Our book selection includes fiction, non-fiction, textbooks, and educational materials. Most books are priced between $10-30. We offer both physical and digital formats."
    }
    
    response_text = product_info.get(product_type.lower(), 
                                   f"I don't have specific information about {product_type}. Please try electronics, clothing, or books, or contact our support team for more details.")
    
    return close_intent(event, response_text)

def handle_order_status(event):
    """
    Handle order status inquiries.
    Queries DynamoDB table for order information.
    """
    slots = event['sessionState']['intent']['slots']
    order_id = None
    
    if 'OrderNumber' in slots and slots['OrderNumber'] and 'value' in slots['OrderNumber']:
        order_id = slots['OrderNumber']['value']['interpretedValue']
    
    if not order_id:
        return elicit_slot(event, 'OrderNumber', 
                          "Please provide your order number so I can check the status for you.")
    
    # Query DynamoDB for order status
    try:
        table = dynamodb.Table(ORDERS_TABLE)
        response = table.get_item(Key={'OrderId': order_id})
        
        if 'Item' in response:
            order = response['Item']
            status = order.get('Status', 'Unknown')
            estimated_delivery = order.get('EstimatedDelivery', '')
            
            status_text = f"Order {order_id} is currently {status}."
            if estimated_delivery:
                status_text += f" Estimated delivery: {estimated_delivery}."
            
            # Add additional helpful information based on status
            if status.lower() == 'shipped':
                status_text += " You should receive a tracking number via email shortly."
            elif status.lower() == 'processing':
                status_text += " We're preparing your order for shipment."
        else:
            status_text = f"I couldn't find an order with number {order_id}. Please check the order number and try again, or contact support if you need assistance."
            
    except Exception as e:
        logger.error(f"Error querying DynamoDB: {str(e)}")
        status_text = "I'm having trouble accessing order information right now. Please try again in a few minutes or contact our support team."
    
    return close_intent(event, status_text)

def handle_support_request(event):
    """
    Handle support requests by providing escalation information.
    """
    response_text = ("I'll help you get connected with human support. You have several options:\n\n"
                    "• Email: support@company.com\n"
                    "• Phone: 1-800-SUPPORT (available 24/7)\n"
                    "• Live chat: Available on our website\n\n"
                    "A support representative will assist you promptly. Is there anything else I can help you with in the meantime?")
    
    return close_intent(event, response_text)

def elicit_slot(event, slot_name, message):
    """
    Request a specific slot value from the user.
    """
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_name
            },
            'intent': event['sessionState']['intent'],
            'originatingRequestId': event.get('requestAttributes', {}).get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event, message):
    """
    Close the intent with a final response message.
    """
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': 'Fulfilled'
            },
            'originatingRequestId': event.get('requestAttributes', {}).get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }