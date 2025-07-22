import json
import random
import datetime
import logging
import os
import time

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Payment Service Lambda Function
    
    Handles payment processing and authorization for the microservices workflow.
    Processes payments with business rules for credit evaluation and error simulation.
    
    Args:
        event: Lambda event containing orderData and userData
        context: Lambda context object
        
    Returns:
        dict: Payment result including transactionId, amount, status, and method
        
    Raises:
        Exception: When payment is declined or processing fails
    """
    
    logger.info(f"Payment Service invoked with event: {json.dumps(event)}")
    
    try:
        # Extract order and user data from event
        order_data = event.get('orderData', {})
        user_data = event.get('userData', {})
        
        # Parse data if it's JSON strings from Step Functions
        if isinstance(order_data, str):
            order_data = json.loads(order_data)
        if isinstance(user_data, str):
            user_data = json.loads(user_data)
        
        # Extract payment details
        order_total = order_data.get('total', 0)
        credit_score = user_data.get('creditScore', 600)
        user_id = user_data.get('userId')
        
        logger.info(f"Processing payment for user {user_id}, amount: ${order_total}, credit score: {credit_score}")
        
        # Validate payment amount
        if order_total <= 0:
            error_msg = "Invalid payment amount"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        # Business rule: Decline high-value orders for low credit scores
        if order_total > 1000 and credit_score < 650:
            error_msg = "Payment declined: Insufficient credit rating for high-value purchase"
            logger.warning(f"Payment declined for user {user_id}: amount ${order_total}, credit score {credit_score}")
            raise Exception(error_msg)
        
        # Business rule: Additional validation for very high amounts
        if order_total > 5000 and credit_score < 750:
            error_msg = "Payment declined: Premium credit rating required for high-value purchases"
            logger.warning(f"Payment declined for user {user_id}: amount ${order_total}, credit score {credit_score}")
            raise Exception(error_msg)
        
        # Simulate payment processing time
        processing_time = random.uniform(0.5, 2.0)
        time.sleep(processing_time)
        
        # Simulate random payment failures (10% failure rate)
        if random.random() < 0.1:
            error_msg = "Payment gateway timeout - please retry"
            logger.warning(f"Simulated payment gateway timeout for user {user_id}")
            raise Exception(error_msg)
        
        # Simulate network errors (5% failure rate)
        if random.random() < 0.05:
            error_msg = "Payment network unavailable - please try again later"
            logger.warning(f"Simulated network error for user {user_id}")
            raise Exception(error_msg)
        
        # Generate transaction ID
        transaction_id = f"txn_{random.randint(100000, 999999)}_{int(time.time())}"
        
        # Determine payment method based on amount
        if order_total < 100:
            payment_method = "debit_card"
        elif order_total < 500:
            payment_method = "credit_card"
        else:
            payment_method = "premium_credit_card"
        
        # Calculate processing fee
        processing_fee = round(order_total * 0.029 + 0.30, 2)  # Typical credit card fee
        
        # Create payment result
        payment_result = {
            'transactionId': transaction_id,
            'amount': order_total,
            'processingFee': processing_fee,
            'netAmount': round(order_total - processing_fee, 2),
            'status': 'authorized',
            'method': payment_method,
            'authCode': f"AUTH{random.randint(100000, 999999)}",
            'processedAt': datetime.datetime.utcnow().isoformat(),
            'processingTime': round(processing_time, 2),
            'currency': 'USD',
            'riskScore': 'low' if credit_score > 700 else 'medium' if credit_score > 650 else 'high'
        }
        
        logger.info(f"Payment authorized successfully: {transaction_id}, Amount: ${order_total}")
        logger.debug(f"Payment details: {json.dumps(payment_result)}")
        
        # Return successful response
        response = {
            'statusCode': 200,
            'body': json.dumps(payment_result),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
        logger.info("Payment Service completed successfully")
        return response
        
    except Exception as e:
        error_msg = f"Payment Service error: {str(e)}"
        logger.error(error_msg)
        
        # Return error response
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': error_msg,
                'amount': event.get('orderData', {}).get('total'),
                'userId': event.get('userData', {}).get('userId'),
                'failedAt': datetime.datetime.utcnow().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }