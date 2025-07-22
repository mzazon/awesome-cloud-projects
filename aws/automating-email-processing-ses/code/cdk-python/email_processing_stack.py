"""
AWS CDK Stack for Serverless Email Processing System

This stack creates a complete serverless email processing solution including:
- S3 bucket for email storage
- Lambda function for email processing logic
- SES receipt rule set and rules for email routing
- SNS topic for notifications
- IAM roles and policies with least privilege access
"""

from typing import List
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_ses as ses,
    CfnOutput
)
from constructs import Construct


class EmailProcessingStack(Stack):
    """
    CDK Stack for deploying serverless email processing infrastructure.
    
    This stack creates all necessary AWS resources for automated email processing
    including storage, compute, notifications, and email routing configuration.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        domain_name: str,
        notification_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the Email Processing Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            domain_name: Domain name for email receiving
            notification_email: Email address for SNS notifications
            **kwargs: Additional keyword arguments for Stack
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.domain_name = domain_name
        self.notification_email = notification_email
        
        # Create core infrastructure components
        self.email_bucket = self._create_email_storage_bucket()
        self.notification_topic = self._create_notification_topic()
        self.lambda_role = self._create_lambda_execution_role()
        self.email_processor = self._create_email_processing_function()
        self.receipt_rule_set = self._create_ses_receipt_rules()
        
        # Create stack outputs
        self._create_outputs()

    def _create_email_storage_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing received emails.
        
        Returns:
            S3 Bucket configured for email storage with appropriate security settings
        """
        bucket = s3.Bucket(
            self,
            "EmailStorageBucket",
            bucket_name=f"email-processing-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="EmailArchiving",
                    enabled=True,
                    expiration=Duration.days(365),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        # Add bucket policy for SES access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowSESPuts",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("ses.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/emails/*"],
                conditions={
                    "StringEquals": {
                        "aws:Referer": self.account
                    }
                }
            )
        )
        
        return bucket

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for email processing notifications.
        
        Returns:
            SNS Topic configured for email notifications
        """
        topic = sns.Topic(
            self,
            "EmailNotificationTopic",
            topic_name="email-processing-notifications",
            display_name="Email Processing Notifications",
            fifo=False
        )
        
        # Subscribe the notification email address
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )
        
        return topic

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege access.
        
        Returns:
            IAM Role with appropriate permissions for email processing
        """
        role = iam.Role(
            self,
            "EmailProcessorRole",
            role_name=f"EmailProcessorRole-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for email processing Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom inline policy for specific permissions
        role.add_to_policy(
            iam.PolicyStatement(
                sid="S3EmailAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject"
                ],
                resources=[f"{self.email_bucket.bucket_arn}/*"]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                sid="SESEmailSending",
                effect=iam.Effect.ALLOW,
                actions=[
                    "ses:SendEmail",
                    "ses:SendRawEmail"
                ],
                resources=["*"]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                sid="SNSPublishing",
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn]
            )
        )
        
        return role

    def _create_email_processing_function(self) -> _lambda.Function:
        """
        Create Lambda function for processing emails.
        
        Returns:
            Lambda Function configured for email processing
        """
        function = _lambda.Function(
            self,
            "EmailProcessorFunction",
            function_name="email-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="email_processor.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "BUCKET_NAME": self.email_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "FROM_EMAIL": f"noreply@{self.domain_name}",
                "DOMAIN_NAME": self.domain_name
            },
            description="Processes incoming emails and sends automated responses"
        )
        
        # Grant SES permission to invoke this function
        function.add_permission(
            "SESInvokePermission",
            principal=iam.ServicePrincipal("ses.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_account=self.account
        )
        
        return function

    def _create_ses_receipt_rules(self) -> ses.CfnReceiptRuleSet:
        """
        Create SES receipt rule set and rules for email processing.
        
        Returns:
            SES Receipt Rule Set configured for email routing
        """
        # Create receipt rule set
        rule_set = ses.CfnReceiptRuleSet(
            self,
            "EmailReceiptRuleSet",
            rule_set_name=f"EmailProcessingRuleSet-{self.region}"
        )
        
        # Create receipt rule for email processing
        receipt_rule = ses.CfnReceiptRule(
            self,
            "EmailProcessingRule",
            rule_set_name=rule_set.rule_set_name,
            rule={
                "name": f"EmailProcessingRule-{self.region}",
                "enabled": True,
                "tlsPolicy": "Optional",
                "recipients": [
                    f"support@{self.domain_name}",
                    f"invoices@{self.domain_name}",
                    f"general@{self.domain_name}"
                ],
                "actions": [
                    {
                        "s3Action": {
                            "bucketName": self.email_bucket.bucket_name,
                            "objectKeyPrefix": "emails/"
                        }
                    },
                    {
                        "lambdaAction": {
                            "functionArn": self.email_processor.function_arn,
                            "invocationType": "Event"
                        }
                    }
                ]
            }
        )
        
        # Add dependency to ensure rule set exists before rule
        receipt_rule.add_dependency(rule_set)
        
        return rule_set

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for email processing.
        
        Returns:
            String containing the complete Lambda function code
        """
        return '''
import json
import boto3
import email
import os
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
ses = boto3.client('ses')
sns = boto3.client('sns')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing SES email events.
    
    Args:
        event: SES event containing email information
        context: Lambda context object
        
    Returns:
        Dictionary with status code and response message
    """
    try:
        logger.info(f"Processing email event: {json.dumps(event)}")
        
        # Parse SES event
        ses_event = event['Records'][0]['ses']
        message_id = ses_event['mail']['messageId']
        receipt = ses_event['receipt']
        
        # Get email from S3
        bucket_name = os.environ.get('BUCKET_NAME')
        s3_key = f"emails/{message_id}"
        
        logger.info(f"Retrieving email from S3: {bucket_name}/{s3_key}")
        
        # Get email object from S3
        response = s3.get_object(Bucket=bucket_name, Key=s3_key)
        raw_email = response['Body'].read()
        
        # Parse email
        email_message = email.message_from_bytes(raw_email)
        
        # Extract email details
        sender = email_message.get('From', 'Unknown')
        subject = email_message.get('Subject', 'No Subject')
        recipient = receipt['recipients'][0] if receipt['recipients'] else 'Unknown'
        
        logger.info(f"Processing email from {sender} with subject: {subject}")
        
        # Process email based on recipient and subject
        if 'support@' in recipient or 'support' in subject.lower():
            process_support_email(sender, subject, email_message, message_id)
        elif 'invoices@' in recipient or 'invoice' in subject.lower():
            process_invoice_email(sender, subject, email_message, message_id)
        else:
            process_general_email(sender, subject, email_message, message_id)
        
        # Send processing notification
        notify_processing_complete(message_id, sender, subject, recipient)
        
        logger.info(f"Successfully processed email {message_id}")
        return {'statusCode': 200, 'body': 'Email processed successfully'}
        
    except Exception as e:
        logger.error(f"Error processing email: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}


def process_support_email(sender: str, subject: str, email_message: email.message.EmailMessage, message_id: str) -> None:
    """Process support-related emails with automated ticket creation."""
    logger.info(f"Processing support email from {sender}")
    
    # Generate ticket ID
    ticket_id = f"TICKET-{hash(sender + message_id) % 100000:05d}"
    
    # Send auto-reply
    reply_subject = f"Re: {subject} - Support Ticket #{ticket_id} Created"
    reply_body = f"""
Thank you for contacting our support team.

Your support ticket has been created with the following details:
- Ticket ID: {ticket_id}
- Subject: {subject}
- Status: Open

Our team will review your request and respond within 24 hours during business days.

For urgent issues, please call our support hotline.

Best regards,
Customer Support Team
    """
    
    send_reply(sender, reply_subject, reply_body)
    
    # Notify support team via SNS
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject=f"🎫 New Support Ticket: {ticket_id}",
        Message=f"""
New Support Ticket Created:

Ticket ID: {ticket_id}
From: {sender}
Subject: {subject}
Priority: Normal

Please check the email processing system for full details.

Action Required: Assign ticket to appropriate team member.
        """
    )


def process_invoice_email(sender: str, subject: str, email_message: email.message.EmailMessage, message_id: str) -> None:
    """Process invoice-related emails with automated confirmation."""
    logger.info(f"Processing invoice email from {sender}")
    
    # Generate invoice reference
    invoice_ref = f"INV-{hash(sender + message_id) % 100000:05d}"
    
    # Send confirmation
    reply_subject = f"Invoice Received - Reference: {invoice_ref}"
    reply_body = f"""
We have received your invoice and it has been logged in our system.

Invoice Details:
- Reference Number: {invoice_ref}
- Subject: {subject}
- Received: {email.utils.formatdate()}

Processing Information:
- Your invoice will be processed within 5-7 business days
- Payment will be issued according to our standard terms
- You will receive confirmation when payment is processed

If you have any questions about this invoice, please reference number {invoice_ref} in all communications.

Best regards,
Accounts Payable Team
    """
    
    send_reply(sender, reply_subject, reply_body)
    
    # Notify accounting team
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject=f"💰 New Invoice Received: {invoice_ref}",
        Message=f"""
New Invoice Received:

Reference: {invoice_ref}
From: {sender}
Subject: {subject}

Action Required: Review and process invoice according to company procedures.
        """
    )


def process_general_email(sender: str, subject: str, email_message: email.message.EmailMessage, message_id: str) -> None:
    """Process general emails with standard acknowledgment."""
    logger.info(f"Processing general email from {sender}")
    
    # Send general acknowledgment
    reply_subject = f"Re: {subject} - Message Received"
    reply_body = f"""
Thank you for your email.

We have received your message and will review it promptly. If your message requires a response, we will get back to you within 2-3 business days.

For urgent matters, please contact us directly through our customer service channels.

Message Details:
- Subject: {subject}
- Received: {email.utils.formatdate()}

Best regards,
Customer Service Team
    """
    
    send_reply(sender, reply_subject, reply_body)


def send_reply(to_email: str, subject: str, body: str) -> None:
    """Send automated reply via SES."""
    try:
        from_email = os.environ.get('FROM_EMAIL', f'noreply@{os.environ.get("DOMAIN_NAME", "example.com")}')
        
        logger.info(f"Sending reply to {to_email}")
        
        ses.send_email(
            Source=from_email,
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {'Text': {'Data': body, 'Charset': 'UTF-8'}}
            }
        )
        
        logger.info(f"Reply sent successfully to {to_email}")
        
    except Exception as e:
        logger.error(f"Error sending reply to {to_email}: {str(e)}")


def notify_processing_complete(message_id: str, sender: str, subject: str, recipient: str) -> None:
    """Send processing notification via SNS."""
    try:
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject="📧 Email Processed Successfully",
            Message=f"""
Email Processing Complete:

Message ID: {message_id}
From: {sender}
To: {recipient}
Subject: {subject}
Processing Time: {email.utils.formatdate()}

The email has been processed and appropriate actions have been taken.
            """
        )
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
'''

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "EmailBucketName",
            value=self.email_bucket.bucket_name,
            description="S3 bucket name for email storage",
            export_name=f"{self.stack_name}-EmailBucket"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.email_processor.function_arn,
            description="Lambda function ARN for email processing",
            export_name=f"{self.stack_name}-LambdaFunction"
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
            export_name=f"{self.stack_name}-SNSTopic"
        )
        
        CfnOutput(
            self,
            "SESRuleSetName",
            value=self.receipt_rule_set.rule_set_name,
            description="SES receipt rule set name",
            export_name=f"{self.stack_name}-SESRuleSet"
        )
        
        CfnOutput(
            self,
            "DomainName",
            value=self.domain_name,
            description="Domain name configured for email receiving",
            export_name=f"{self.stack_name}-Domain"
        )
        
        CfnOutput(
            self,
            "SupportEmail",
            value=f"support@{self.domain_name}",
            description="Support email address",
            export_name=f"{self.stack_name}-SupportEmail"
        )
        
        CfnOutput(
            self,
            "InvoicesEmail", 
            value=f"invoices@{self.domain_name}",
            description="Invoices email address",
            export_name=f"{self.stack_name}-InvoicesEmail"
        )