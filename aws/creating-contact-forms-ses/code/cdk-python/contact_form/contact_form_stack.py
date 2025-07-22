"""
Contact Form CDK Stack

This module defines the AWS CDK stack for deploying a serverless contact form backend.
The stack includes:
- Lambda function for processing contact form submissions
- API Gateway REST API for HTTP endpoints
- IAM roles and policies with least privilege access
- CloudWatch logs for monitoring and debugging
"""

from typing import Any, Optional
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_apigateway as apigw,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class ContactFormStack(Stack):
    """
    CDK Stack for Contact Form backend infrastructure.
    
    This stack deploys a complete serverless contact form solution including:
    - Lambda function for form processing and email sending
    - API Gateway REST API with CORS configuration
    - IAM roles with minimal required permissions
    - CloudWatch logging for observability
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        ses_from_email: Optional[str] = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Contact Form stack.
        
        Args:
            scope: CDK app or parent construct
            construct_id: Unique identifier for this stack
            ses_from_email: SES verified email address for sending emails
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Configuration - allow override via context or parameter
        self.ses_from_email = (
            ses_from_email or
            self.node.try_get_context("ses_from_email") or
            "noreply@example.com"
        )
        
        # Create IAM role for Lambda function
        lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda function for contact form processing
        contact_form_lambda = self._create_lambda_function(lambda_role)
        
        # Create API Gateway REST API
        api = self._create_api_gateway(contact_form_lambda)
        
        # Create CloudFormation outputs
        self._create_outputs(api, contact_form_lambda)

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with necessary permissions.
        
        Returns:
            IAM role with permissions for Lambda execution, SES, and CloudWatch logs
        """
        role = iam.Role(
            self,
            "ContactFormLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Contact Form Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add SES permissions
        ses_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ses:SendEmail",
                "ses:SendRawEmail",
                "ses:GetSendQuota",
                "ses:GetSendStatistics",
            ],
            resources=[
                f"arn:aws:ses:{self.region}:{self.account}:identity/*",
            ],
        )
        
        role.add_to_policy(ses_policy)
        
        return role

    def _create_lambda_function(self, execution_role: iam.Role) -> _lambda.Function:
        """
        Create Lambda function for processing contact form submissions.
        
        Args:
            execution_role: IAM role for Lambda execution
            
        Returns:
            Configured Lambda function
        """
        # Create CloudWatch log group with retention policy
        log_group = logs.LogGroup(
            self,
            "ContactFormLambdaLogGroup",
            log_group_name=f"/aws/lambda/contact-form-processor",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Lambda function code
        lambda_code = _lambda.Code.from_inline('''
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle contact form submission from API Gateway.
    
    Args:
        event: API Gateway event containing form data
        context: Lambda context object
        
    Returns:
        HTTP response with CORS headers
    """
    try:
        # Log the incoming request for debugging
        logger.info(f"Received contact form submission: {json.dumps(event, default=str)}")
        
        # Parse request body
        if 'body' not in event or not event['body']:
            return create_response(400, {'error': 'Request body is required'})
            
        body = json.loads(event['body'])
        
        # Validate required fields
        required_fields = ['name', 'email', 'message']
        missing_fields = [field for field in required_fields if not body.get(field)]
        
        if missing_fields:
            return create_response(400, {
                'error': f'Missing required fields: {", ".join(missing_fields)}'
            })
        
        # Extract form data
        name = body.get('name', '').strip()
        email = body.get('email', '').strip()
        subject = body.get('subject', 'Contact Form Submission').strip()
        message = body.get('message', '').strip()
        
        # Basic validation
        if len(name) < 1 or len(name) > 100:
            return create_response(400, {'error': 'Name must be between 1 and 100 characters'})
            
        if len(message) < 1 or len(message) > 2000:
            return create_response(400, {'error': 'Message must be between 1 and 2000 characters'})
        
        # Send email via SES
        result = send_contact_email(name, email, subject, message)
        
        if result['success']:
            logger.info(f"Email sent successfully with MessageId: {result.get('message_id')}")
            return create_response(200, {
                'message': 'Thank you for your message. We will get back to you soon!',
                'messageId': result.get('message_id')
            })
        else:
            logger.error(f"Failed to send email: {result.get('error')}")
            return create_response(500, {'error': 'Failed to send email. Please try again later.'})
            
    except json.JSONDecodeError:
        logger.error("Invalid JSON in request body")
        return create_response(400, {'error': 'Invalid JSON format'})
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_response(500, {'error': 'Internal server error'})

def send_contact_email(name: str, email: str, subject: str, message: str) -> Dict[str, Any]:
    """
    Send contact form email using Amazon SES.
    
    Args:
        name: Contact person's name
        email: Contact person's email
        subject: Email subject line
        message: Email message content
        
    Returns:
        Dict with success status and message ID or error
    """
    try:
        ses_client = boto3.client('ses')
        from_email = os.environ.get('SES_FROM_EMAIL', 'noreply@example.com')
        
        # Format email content
        timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
        
        email_body = f"""
New Contact Form Submission

Submitted: {timestamp}
Name: {name}
Email: {email}
Subject: {subject}

Message:
{message}

---
This email was automatically generated from your website contact form.
        """.strip()
        
        # Send email
        response = ses_client.send_email(
            Source=from_email,
            Destination={
                'ToAddresses': [from_email]  # Send to same address (you can configure this)
            },
            Message={
                'Subject': {
                    'Data': f'Contact Form: {subject}',
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': email_body,
                        'Charset': 'UTF-8'
                    }
                }
            },
            ReplyToAddresses=[email]  # Allow replying directly to the sender
        )
        
        return {
            'success': True,
            'message_id': response['MessageId']
        }
        
    except Exception as e:
        logger.error(f"SES error: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def create_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create HTTP response with CORS headers.
    
    Args:
        status_code: HTTP status code
        body: Response body dictionary
        
    Returns:
        API Gateway response format
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token',
            'Access-Control-Max-Age': '86400'
        },
        'body': json.dumps(body)
    }
        ''')

        function = _lambda.Function(
            self,
            "ContactFormFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_code,
            role=execution_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "SES_FROM_EMAIL": self.ses_from_email,
                "LOG_LEVEL": "INFO",
            },
            log_group=log_group,
            description="Processes contact form submissions and sends emails via SES",
        )

        return function

    def _create_api_gateway(self, lambda_function: _lambda.Function) -> apigw.RestApi:
        """
        Create API Gateway REST API with CORS configuration.
        
        Args:
            lambda_function: Lambda function to integrate with API Gateway
            
        Returns:
            Configured REST API
        """
        # Create CloudWatch log group for API Gateway
        api_log_group = logs.LogGroup(
            self,
            "ContactFormApiLogGroup",
            log_group_name=f"/aws/apigateway/contact-form-api",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create REST API
        api = apigw.RestApi(
            self,
            "ContactFormApi",
            rest_api_name="Contact Form API",
            description="REST API for contact form submissions",
            default_cors_preflight_options={
                "allow_origins": apigw.Cors.ALL_ORIGINS,
                "allow_methods": ["POST", "OPTIONS"],
                "allow_headers": [
                    "Content-Type", 
                    "X-Amz-Date", 
                    "Authorization", 
                    "X-Api-Key",
                    "X-Amz-Security-Token"
                ],
                "max_age": Duration.hours(1),
            },
            deploy_options={
                "stage_name": "prod",
                "description": "Production stage for contact form API",
                "throttle_settings": {
                    "rate_limit": 100,
                    "burst_limit": 200,
                },
                "access_log_destination": apigw.LogGroupLogDestination(api_log_group),
                "access_log_format": apigw.AccessLogFormat.json_with_standard_fields(
                    caller=True,
                    http_method=True,
                    ip=True,
                    protocol=True,
                    request_time=True,
                    resource_path=True,
                    response_length=True,
                    status=True,
                    user=True,
                ),
            },
            endpoint_configuration={
                "types": [apigw.EndpointType.REGIONAL]
            },
        )

        # Create Lambda integration
        lambda_integration = apigw.LambdaIntegration(
            lambda_function,
            proxy=True,
            allow_test_invoke=True,
        )

        # Add /contact resource and POST method
        contact_resource = api.root.add_resource("contact")
        contact_resource.add_method(
            "POST",
            lambda_integration,
            method_responses=[{
                "status_code": "200",
                "response_parameters": {
                    "method.response.header.Access-Control-Allow-Origin": True,
                },
            }],
        )

        return api

    def _create_outputs(self, api: apigw.RestApi, lambda_function: _lambda.Function) -> None:
        """
        Create CloudFormation outputs for important resources.
        
        Args:
            api: API Gateway REST API
            lambda_function: Lambda function
        """
        CfnOutput(
            self,
            "ApiEndpoint",
            value=f"{api.url}contact",
            description="Contact Form API endpoint URL",
            export_name=f"{self.stack_name}-ApiEndpoint",
        )

        CfnOutput(
            self,
            "ApiGatewayId",
            value=api.rest_api_id,
            description="API Gateway REST API ID",
            export_name=f"{self.stack_name}-ApiGatewayId",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=lambda_function.function_name,
            description="Lambda function name",
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=lambda_function.function_arn,
            description="Lambda function ARN",
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )

        CfnOutput(
            self,
            "SESFromEmail",
            value=self.ses_from_email,
            description="SES sender email address (must be verified)",
            export_name=f"{self.stack_name}-SESFromEmail",
        )