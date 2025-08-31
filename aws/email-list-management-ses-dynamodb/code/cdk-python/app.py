#!/usr/bin/env python3
"""
Email List Management System CDK Application

This CDK application creates a serverless email list management system using:
- Amazon DynamoDB for subscriber storage
- AWS Lambda functions for business logic
- Amazon SES for email delivery
- IAM roles with least privilege access

The system provides complete CRUD operations for email subscribers and
automated newsletter delivery capabilities.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput
)
from aws_cdk import aws_dynamodb as dynamodb
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_iam as iam
from aws_cdk import aws_ses as ses
from constructs import Construct
import os


class EmailListManagementStack(Stack):
    """
    CDK Stack for Email List Management System
    
    Creates all necessary AWS resources for a complete email list management
    solution including DynamoDB table, Lambda functions, and IAM roles.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters for customization
        sender_email = self.node.try_get_context("sender_email") or "your-email@example.com"
        
        # Create DynamoDB table for subscriber management
        self.subscribers_table = self._create_subscribers_table()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.subscribe_function = self._create_subscribe_function()
        self.unsubscribe_function = self._create_unsubscribe_function()
        self.newsletter_function = self._create_newsletter_function(sender_email)
        self.list_function = self._create_list_subscribers_function()
        
        # Create outputs for easy reference
        self._create_outputs()

    def _create_subscribers_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing subscriber information.
        
        The table uses email as the partition key for fast lookups and
        includes a GSI for querying by subscription status.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "SubscribersTable",
            table_name=f"email-subscribers-{self.account}-{self.region}",
            partition_key=dynamodb.Attribute(
                name="email",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # For development/testing
            point_in_time_recovery=True,
            table_class=dynamodb.TableClass.STANDARD,
            tags={
                "Purpose": "EmailListManagement",
                "Environment": "Development"
            }
        )
        
        # Add Global Secondary Index for querying by status
        table.add_global_secondary_index(
            index_name="StatusIndex",
            partition_key=dynamodb.Attribute(
                name="status",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        return table

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with necessary permissions.
        
        Follows least privilege principle by granting only required permissions
        for DynamoDB operations, SES email sending, and CloudWatch logging.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self, "EmailListLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Email List Management Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add DynamoDB permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan",
                "dynamodb:Query"
            ],
            resources=[
                self.subscribers_table.table_arn,
                f"{self.subscribers_table.table_arn}/index/*"
            ]
        ))
        
        # Add SES permissions for email sending
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ses:SendEmail",
                "ses:SendRawEmail",
                "ses:GetIdentityVerificationAttributes"
            ],
            resources=["*"]  # SES requires wildcard for email sending
        ))
        
        return role

    def _create_subscribe_function(self) -> lambda_.Function:
        """
        Create Lambda function for handling new subscriber registrations.
        
        This function validates email addresses, prevents duplicates, and
        stores subscriber information in DynamoDB with proper error handling.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        function = lambda_.Function(
            self, "SubscribeFunction",
            function_name=f"email-subscribe-{self.account}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_subscribe_function_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.subscribers_table.table_name
            },
            description="Handles new email subscriber registrations with validation and duplicate prevention"
        )
        
        return function

    def _create_unsubscribe_function(self) -> lambda_.Function:
        """
        Create Lambda function for handling subscriber removal requests.
        
        This function updates subscriber status to inactive while maintaining
        historical data for compliance and analytics purposes.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        function = lambda_.Function(
            self, "UnsubscribeFunction",
            function_name=f"email-unsubscribe-{self.account}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_unsubscribe_function_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.subscribers_table.table_name
            },
            description="Handles subscriber unsubscribe requests by updating status to inactive"
        )
        
        return function

    def _create_newsletter_function(self, sender_email: str) -> lambda_.Function:
        """
        Create Lambda function for sending newsletters to subscribers.
        
        This function retrieves active subscribers and sends personalized
        emails using Amazon SES with proper error handling and delivery tracking.
        
        Args:
            sender_email (str): The verified sender email address
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        function = lambda_.Function(
            self, "NewsletterFunction",
            function_name=f"email-newsletter-{self.account}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_newsletter_function_code()),
            timeout=Duration.minutes(5),  # Longer timeout for bulk email operations
            memory_size=512,
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.subscribers_table.table_name,
                "SENDER_EMAIL": sender_email
            },
            description="Sends newsletters to active subscribers with personalization and delivery tracking"
        )
        
        return function

    def _create_list_subscribers_function(self) -> lambda_.Function:
        """
        Create Lambda function for listing all subscribers.
        
        This read-only function provides administrative capabilities to view
        subscriber information with pagination support for large lists.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        function = lambda_.Function(
            self, "ListSubscribersFunction",
            function_name=f"email-list-subscribers-{self.account}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_list_function_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.subscribers_table.table_name
            },
            description="Lists all subscribers with pagination support for administrative purposes"
        )
        
        return function

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for easy reference to created resources."""
        CfnOutput(
            self, "SubscribersTableName",
            value=self.subscribers_table.table_name,
            description="Name of the DynamoDB table storing subscriber information"
        )
        
        CfnOutput(
            self, "SubscribersTableArn",
            value=self.subscribers_table.table_arn,
            description="ARN of the DynamoDB table storing subscriber information"
        )
        
        CfnOutput(
            self, "SubscribeFunctionName",
            value=self.subscribe_function.function_name,
            description="Name of the Lambda function handling subscription requests"
        )
        
        CfnOutput(
            self, "UnsubscribeFunctionName",
            value=self.unsubscribe_function.function_name,
            description="Name of the Lambda function handling unsubscribe requests"
        )
        
        CfnOutput(
            self, "NewsletterFunctionName",
            value=self.newsletter_function.function_name,
            description="Name of the Lambda function for sending newsletters"
        )
        
        CfnOutput(
            self, "ListSubscribersFunctionName",
            value=self.list_function.function_name,
            description="Name of the Lambda function for listing subscribers"
        )
        
        CfnOutput(
            self, "LambdaRoleArn",
            value=self.lambda_role.role_arn,
            description="ARN of the IAM role used by Lambda functions"
        )

    def _get_subscribe_function_code(self) -> str:
        """Return the Python code for the subscribe Lambda function."""
        return '''
import json
import boto3
import datetime
import os
import re
from botocore.exceptions import ClientError
from typing import Dict, Any

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def validate_email(email: str) -> bool:
    """Validate email address format using regex."""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle new email subscriber registrations.
    
    Args:
        event: Lambda event containing subscription request
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Extract and validate email
        email = body.get('email', '').lower().strip()
        name = body.get('name', 'Subscriber').strip()
        
        # Validate required fields
        if not email:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Email address is required'})
            }
        
        if not validate_email(email):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Invalid email address format'})
            }
        
        if not name or len(name) > 100:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Valid name is required (max 100 characters)'})
            }
        
        # Store subscriber in DynamoDB
        current_time = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        response = table.put_item(
            Item={
                'email': email,
                'name': name,
                'subscribed_date': current_time,
                'status': 'active',
                'source': body.get('source', 'direct'),
                'preferences': body.get('preferences', {})
            },
            ConditionExpression='attribute_not_exists(email)'
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': f'Successfully subscribed {email}',
                'email': email,
                'name': name,
                'subscribed_date': current_time
            })
        }
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            return {
                'statusCode': 409,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Email address already subscribed'})
            }
        
        print(f"DynamoDB error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Database error occurred'})
        }
        
    except json.JSONDecodeError as e:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
        
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
'''

    def _get_unsubscribe_function_code(self) -> str:
        """Return the Python code for the unsubscribe Lambda function."""
        return '''
import json
import boto3
import datetime
import os
from botocore.exceptions import ClientError
from typing import Dict, Any

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle subscriber unsubscribe requests.
    
    Args:
        event: Lambda event containing unsubscribe request
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Extract email
        email = body.get('email', '').lower().strip()
        reason = body.get('reason', 'user_request')
        
        if not email:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Email address is required'})
            }
        
        # Update subscriber status to inactive
        current_time = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        response = table.update_item(
            Key={'email': email},
            UpdateExpression='SET #status = :status, unsubscribed_date = :date, unsubscribe_reason = :reason',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': 'inactive',
                ':date': current_time,
                ':reason': reason
            },
            ConditionExpression='attribute_exists(email) AND #status = :active_status',
            ExpressionAttributeValues={
                **{':status': 'inactive', ':date': current_time, ':reason': reason},
                ':active_status': 'active'
            },
            ReturnValues='ALL_NEW'
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': f'Successfully unsubscribed {email}',
                'email': email,
                'unsubscribed_date': current_time
            })
        }
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Email not found or already unsubscribed'})
            }
        
        print(f"DynamoDB error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Database error occurred'})
        }
        
    except json.JSONDecodeError as e:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
        
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
'''

    def _get_newsletter_function_code(self) -> str:
        """Return the Python code for the newsletter Lambda function."""
        return '''
import json
import boto3
import os
import datetime
from botocore.exceptions import ClientError
from typing import Dict, Any, List

dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def get_active_subscribers() -> List[Dict[str, Any]]:
    """
    Retrieve all active subscribers with pagination support.
    
    Returns:
        List of active subscriber records
    """
    subscribers = []
    
    try:
        # Use GSI to query by status for better performance
        response = table.query(
            IndexName='StatusIndex',
            KeyConditionExpression='#status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'active'}
        )
        
        subscribers.extend(response['Items'])
        
        # Handle pagination
        while 'LastEvaluatedKey' in response:
            response = table.query(
                IndexName='StatusIndex',
                KeyConditionExpression='#status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': 'active'},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            subscribers.extend(response['Items'])
            
    except ClientError as e:
        print(f"Error querying subscribers: {str(e)}")
        # Fallback to scan if GSI query fails
        response = table.scan(
            FilterExpression='#status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'active'}
        )
        subscribers.extend(response['Items'])
        
        while 'LastEvaluatedKey' in response:
            response = table.scan(
                FilterExpression='#status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': 'active'},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            subscribers.extend(response['Items'])
    
    return subscribers

def send_email_to_subscriber(subscriber: Dict[str, Any], subject: str, message: str, sender_email: str) -> bool:
    """
    Send personalized email to a single subscriber.
    
    Args:
        subscriber: Subscriber information
        subject: Email subject
        message: Email message content
        sender_email: Verified sender email address
        
    Returns:
        True if email sent successfully, False otherwise
    """
    try:
        # Create personalized content
        personalized_message = f"Hello {subscriber.get('name', 'Subscriber')},\\n\\n{message}\\n\\nBest regards,\\nYour Newsletter Team"
        
        html_message = f"""
        <html>
        <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background-color: #f8f9fa; padding: 20px; border-radius: 8px;">
                <h2 style="color: #333; margin-bottom: 20px;">Hello {subscriber.get('name', 'Subscriber')},</h2>
                <div style="background-color: white; padding: 20px; border-radius: 6px; margin-bottom: 20px;">
                    <p style="color: #555; line-height: 1.6; margin-bottom: 16px;">{message}</p>
                </div>
                <p style="color: #666; font-size: 14px; margin-bottom: 10px;">Best regards,<br>Your Newsletter Team</p>
                <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
                <p style="color: #999; font-size: 12px; text-align: center;">
                    You received this email because you subscribed to our newsletter.
                    <br>If you no longer wish to receive these emails, please contact us to unsubscribe.
                </p>
            </div>
        </body>
        </html>
        """
        
        ses.send_email(
            Source=sender_email,
            Destination={'ToAddresses': [subscriber['email']]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {
                    'Text': {
                        'Data': personalized_message,
                        'Charset': 'UTF-8'
                    },
                    'Html': {
                        'Data': html_message,
                        'Charset': 'UTF-8'
                    }
                }
            },
            Tags=[
                {'Name': 'Purpose', 'Value': 'Newsletter'},
                {'Name': 'Subscriber', 'Value': subscriber['email']}
            ]
        )
        
        return True
        
    except ClientError as e:
        print(f"Failed to send email to {subscriber['email']}: {str(e)}")
        return False

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Send newsletter to all active subscribers.
    
    Args:
        event: Lambda event containing newsletter content
        context: Lambda context object
        
    Returns:
        Dict containing status code and delivery results
    """
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Extract newsletter content with defaults
        subject = body.get('subject', 'Newsletter Update')
        message = body.get('message', 'Thank you for subscribing to our newsletter!')
        sender_email = os.environ.get('SENDER_EMAIL')
        
        if not sender_email:
            return {
                'statusCode': 500,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Sender email not configured'})
            }
        
        if not subject.strip() or not message.strip():
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Subject and message are required'})
            }
        
        # Get all active subscribers
        subscribers = get_active_subscribers()
        
        if not subscribers:
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'message': 'No active subscribers found',
                    'sent_count': 0,
                    'failed_count': 0,
                    'total_subscribers': 0
                })
            }
        
        # Send emails to all subscribers
        sent_count = 0
        failed_count = 0
        failed_emails = []
        
        for subscriber in subscribers:
            if send_email_to_subscriber(subscriber, subject, message, sender_email):
                sent_count += 1
            else:
                failed_count += 1
                failed_emails.append(subscriber['email'])
        
        # Return detailed results
        result = {
            'message': f'Newsletter delivery completed',
            'sent_count': sent_count,
            'failed_count': failed_count,
            'total_subscribers': len(subscribers),
            'success_rate': f"{(sent_count / len(subscribers) * 100):.1f}%" if subscribers else "0%",
            'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
        }
        
        if failed_emails:
            result['failed_emails'] = failed_emails[:10]  # Limit for response size
            if len(failed_emails) > 10:
                result['additional_failures'] = len(failed_emails) - 10
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(result)
        }
        
    except json.JSONDecodeError as e:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
        
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
'''

    def _get_list_function_code(self) -> str:
        """Return the Python code for the list subscribers Lambda function."""
        return '''
import json
import boto3
import os
from decimal import Decimal
from botocore.exceptions import ClientError
from typing import Dict, Any, List

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def decimal_default(obj):
    """JSON serializer for Decimal objects."""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

def get_subscribers_with_pagination(status_filter: str = None, limit: int = None, last_key: Dict = None) -> Dict[str, Any]:
    """
    Get subscribers with optional filtering and pagination.
    
    Args:
        status_filter: Optional status to filter by ('active', 'inactive')
        limit: Maximum number of items to return
        last_key: Last evaluated key for pagination
        
    Returns:
        Dict containing subscribers and pagination info
    """
    scan_kwargs = {}
    
    # Add status filter if specified
    if status_filter:
        scan_kwargs['FilterExpression'] = '#status = :status'
        scan_kwargs['ExpressionAttributeNames'] = {'#status': 'status'}
        scan_kwargs['ExpressionAttributeValues'] = {':status': status_filter}
    
    # Add pagination parameters
    if limit:
        scan_kwargs['Limit'] = limit
    
    if last_key:
        scan_kwargs['ExclusiveStartKey'] = last_key
    
    # Perform scan operation
    response = table.scan(**scan_kwargs)
    
    return {
        'Items': response.get('Items', []),
        'LastEvaluatedKey': response.get('LastEvaluatedKey'),
        'Count': response.get('Count', 0),
        'ScannedCount': response.get('ScannedCount', 0)
    }

def get_subscriber_statistics(subscribers: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Calculate statistics about subscribers.
    
    Args:
        subscribers: List of subscriber records
        
    Returns:
        Dict containing subscriber statistics
    """
    stats = {
        'total_subscribers': len(subscribers),
        'active_subscribers': 0,
        'inactive_subscribers': 0,
        'subscribers_by_source': {},
        'recent_subscriptions': 0  # Last 30 days
    }
    
    from datetime import datetime, timezone, timedelta
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    
    for subscriber in subscribers:
        # Count by status
        status = subscriber.get('status', 'unknown')
        if status == 'active':
            stats['active_subscribers'] += 1
        elif status == 'inactive':
            stats['inactive_subscribers'] += 1
        
        # Count by source
        source = subscriber.get('source', 'unknown')
        stats['subscribers_by_source'][source] = stats['subscribers_by_source'].get(source, 0) + 1
        
        # Count recent subscriptions
        subscribed_date_str = subscriber.get('subscribed_date', '')
        if subscribed_date_str:
            try:
                subscribed_date = datetime.fromisoformat(subscribed_date_str.replace('Z', '+00:00'))
                if subscribed_date > thirty_days_ago:
                    stats['recent_subscriptions'] += 1
            except (ValueError, TypeError):
                pass  # Skip invalid dates
    
    return stats

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    List subscribers with optional filtering and pagination.
    
    Args:
        event: Lambda event containing query parameters
        context: Lambda context object
        
    Returns:
        Dict containing subscriber list and metadata
    """
    try:
        # Parse query parameters from event
        query_params = event.get('queryStringParameters') or {}
        
        # Extract parameters with defaults
        status_filter = query_params.get('status')  # 'active', 'inactive', or None for all
        limit = query_params.get('limit')
        last_key_str = query_params.get('lastKey')
        include_stats = query_params.get('includeStats', 'false').lower() == 'true'
        
        # Validate and convert limit
        if limit:
            try:
                limit = int(limit)
                if limit <= 0 or limit > 1000:  # Reasonable limits
                    limit = 100
            except ValueError:
                limit = 100
        
        # Parse last key for pagination
        last_key = None
        if last_key_str:
            try:
                last_key = json.loads(last_key_str)
            except json.JSONDecodeError:
                pass  # Invalid last key, ignore
        
        # Validate status filter
        if status_filter and status_filter not in ['active', 'inactive']:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Invalid status filter. Use "active" or "inactive"'})
            }
        
        # Get subscribers with pagination
        result = get_subscribers_with_pagination(status_filter, limit, last_key)
        subscribers = result['Items']
        
        # Convert Decimal types for JSON serialization
        for subscriber in subscribers:
            for key, value in subscriber.items():
                if isinstance(value, Decimal):
                    subscriber[key] = float(value)
        
        # Build response
        response_data = {
            'subscribers': subscribers,
            'count': result['Count'],
            'scanned_count': result['ScannedCount']
        }
        
        # Add pagination info if there are more results
        if result['LastEvaluatedKey']:
            response_data['lastEvaluatedKey'] = result['LastEvaluatedKey']
            response_data['hasMore'] = True
        else:
            response_data['hasMore'] = False
        
        # Add statistics if requested
        if include_stats:
            # For stats, we need all subscribers, not just the current page
            if not status_filter and not limit and not last_key:
                # We already have all subscribers
                all_subscribers = subscribers
            else:
                # Get all subscribers for stats calculation
                all_result = get_subscribers_with_pagination()
                all_subscribers = all_result['Items']
            
            response_data['statistics'] = get_subscriber_statistics(all_subscribers)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',  # For web access
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps(response_data, default=decimal_default)
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Database error occurred'})
        }
        
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
'''


def main():
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get deployment environment from context or use defaults
    env = Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create the email list management stack
    EmailListManagementStack(
        app, 
        "EmailListManagementStack",
        env=env,
        description="Email List Management System using SES, DynamoDB, and Lambda"
    )
    
    # Add tags to all resources in the app
    cdk.Tags.of(app).add("Project", "EmailListManagement")
    cdk.Tags.of(app).add("Environment", "Development")
    cdk.Tags.of(app).add("ManagedBy", "CDK")
    
    app.synth()


if __name__ == "__main__":
    main()