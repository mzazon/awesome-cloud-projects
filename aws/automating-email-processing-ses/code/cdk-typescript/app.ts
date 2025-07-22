#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as ses from 'aws-cdk-lib/aws-ses';
import * as sesActions from 'aws-cdk-lib/aws-ses-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for Serverless Email Processing System
 * 
 * This stack creates a complete serverless email processing system using:
 * - Amazon SES for email receiving and sending
 * - AWS Lambda for intelligent email processing
 * - Amazon S3 for email storage
 * - Amazon SNS for notifications
 */
export class ServerlessEmailProcessingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Stack parameters for customization
    const domainName = new cdk.CfnParameter(this, 'DomainName', {
      type: 'String',
      description: 'Domain name for email receiving (must be verified in SES)',
      default: 'example.com',
    });

    const notificationEmail = new cdk.CfnParameter(this, 'NotificationEmail', {
      type: 'String',
      description: 'Email address for SNS notifications',
      default: 'admin@example.com',
    });

    const environment = new cdk.CfnParameter(this, 'Environment', {
      type: 'String',
      description: 'Environment name for resource naming',
      default: 'dev',
      allowedValues: ['dev', 'staging', 'prod'],
    });

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Fn.select(0, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', this.stackId))));

    // S3 Bucket for email storage
    const emailBucket = new s3.Bucket(this, 'EmailBucket', {
      bucketName: `email-processing-${environment.valueAsString}-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldEmails',
          enabled: true,
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // SNS Topic for notifications
    const notificationTopic = new sns.Topic(this, 'EmailNotificationTopic', {
      topicName: `email-notifications-${environment.valueAsString}-${uniqueSuffix}`,
      displayName: 'Email Processing Notifications',
    });

    // Subscribe email to SNS topic
    notificationTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail.valueAsString)
    );

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'EmailProcessorLogGroup', {
      logGroupName: `/aws/lambda/email-processor-${environment.valueAsString}-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM Role for Lambda function
    const lambdaRole = new iam.Role(this, 'EmailProcessorRole', {
      roleName: `EmailProcessorRole-${environment.valueAsString}-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        EmailProcessorPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for email storage
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [emailBucket.arnForObjects('*')],
            }),
            // SES permissions for sending emails
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ses:SendEmail',
                'ses:SendRawEmail',
              ],
              resources: ['*'],
            }),
            // SNS permissions for notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Lambda function for email processing
    const emailProcessorFunction = new lambda.Function(this, 'EmailProcessorFunction', {
      functionName: `email-processor-${environment.valueAsString}-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      logGroup: logGroup,
      environment: {
        BUCKET_NAME: emailBucket.bucketName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
        FROM_EMAIL: `noreply@${domainName.valueAsString}`,
        ENVIRONMENT: environment.valueAsString,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import email
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
ses = boto3.client('ses')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing SES email events.
    Supports both S3-stored emails and direct SES events.
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Handle SES event
        if 'Records' in event and event['Records']:
            record = event['Records'][0]
            
            if 'ses' in record:
                # Direct SES event
                ses_event = record['ses']
                message_id = ses_event['mail']['messageId']
                receipt = ses_event['receipt']
                
                # Get email from S3 if stored there
                bucket_name = os.environ.get('BUCKET_NAME')
                
                try:
                    # Get email object from S3
                    s3_key = f"emails/{message_id}"
                    response = s3.get_object(Bucket=bucket_name, Key=s3_key)
                    raw_email = response['Body'].read()
                    
                    # Parse email
                    email_message = email.message_from_bytes(raw_email)
                    
                    # Extract email details
                    sender = email_message.get('From', 'Unknown')
                    subject = email_message.get('Subject', 'No Subject')
                    recipient = receipt['recipients'][0] if receipt['recipients'] else 'Unknown'
                    
                    logger.info(f"Processing email from {sender} with subject: {subject}")
                    
                    # Process email based on subject or content
                    if 'support' in subject.lower():
                        process_support_email(sender, subject, email_message)
                    elif 'invoice' in subject.lower():
                        process_invoice_email(sender, subject, email_message)
                    else:
                        process_general_email(sender, subject, email_message)
                    
                    # Send notification
                    notify_processing_complete(message_id, sender, subject)
                    
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'message': 'Email processed successfully',
                            'messageId': message_id,
                            'sender': sender,
                            'subject': subject
                        })
                    }
                    
                except Exception as e:
                    logger.error(f"Error processing email {message_id}: {str(e)}")
                    
                    # Send error notification
                    sns.publish(
                        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
                        Subject="Email Processing Error",
                        Message=f"Failed to process email {message_id}: {str(e)}"
                    )
                    
                    return {
                        'statusCode': 500,
                        'body': json.dumps({
                            'error': str(e),
                            'messageId': message_id
                        })
                    }
        
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid event format'})
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Unexpected error: {str(e)}'})
        }

def process_support_email(sender, subject, email_message):
    """Process support-related emails with automated ticket creation."""
    logger.info(f"Processing support email from {sender}")
    
    # Generate ticket ID
    ticket_id = f"TICKET-{hash(sender) % 10000:04d}"
    
    # Send auto-reply
    reply_subject = f"Re: {subject} - Ticket #{ticket_id} Created"
    reply_body = f"""
Thank you for contacting our support team.

Your support ticket has been created with the following details:
- Ticket ID: {ticket_id}
- Subject: {subject}
- Status: Open

Our support team will respond within 24 hours during business hours.

For urgent issues, please call our support hotline.

Best regards,
Customer Support Team
    """
    
    send_reply(sender, reply_subject, reply_body)
    
    # Notify support team via SNS
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject=f"New Support Ticket #{ticket_id}",
        Message=f"""
New support ticket created:

Ticket ID: {ticket_id}
From: {sender}
Subject: {subject}
Priority: Normal

Please check the email processing system for full details.

Support Dashboard: https://console.aws.amazon.com/ses/
        """
    )
    
    logger.info(f"Support ticket {ticket_id} created for {sender}")

def process_invoice_email(sender, subject, email_message):
    """Process invoice-related emails with accounts payable workflow."""
    logger.info(f"Processing invoice email from {sender}")
    
    # Generate invoice reference
    invoice_ref = f"INV-{hash(sender) % 10000:04d}"
    
    # Send confirmation
    reply_subject = f"Invoice Received - Reference {invoice_ref}"
    reply_body = f"""
We have received your invoice submission.

Invoice Details:
- Reference Number: {invoice_ref}
- Subject: {subject}
- Received: {os.environ.get('ENVIRONMENT', 'system')}
- Processing Time: 5-7 business days

Your invoice will be reviewed by our accounts payable team and processed according to our payment terms.

You will receive a confirmation email once payment has been processed.

If you have any questions, please reference your invoice number {invoice_ref} in all correspondence.

Best regards,
Accounts Payable Team
    """
    
    send_reply(sender, reply_subject, reply_body)
    
    # Notify accounts payable team
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject=f"New Invoice Submission - {invoice_ref}",
        Message=f"""
New invoice received for processing:

Reference: {invoice_ref}
From: {sender}
Subject: {subject}

Please review the invoice in the email processing system.

AP Dashboard: https://console.aws.amazon.com/ses/
        """
    )
    
    logger.info(f"Invoice {invoice_ref} logged for {sender}")

def process_general_email(sender, subject, email_message):
    """Process general emails with standard acknowledgment."""
    logger.info(f"Processing general email from {sender}")
    
    # Send general acknowledgment
    reply_subject = f"Re: {subject}"
    reply_body = f"""
Thank you for your email.

We have received your message and will review it accordingly. If your inquiry requires a response, our team will get back to you within 2-3 business days.

For urgent matters, please contact us directly:
- Support: Create a support ticket by including 'Support' in your subject line
- Billing: Include 'Invoice' in your subject line for faster processing

Subject: {subject}
Environment: {os.environ.get('ENVIRONMENT', 'production')}

Best regards,
Customer Service Team
    """
    
    send_reply(sender, reply_subject, reply_body)
    
    logger.info(f"General email processed for {sender}")

def send_reply(to_email, subject, body):
    """Send automated reply via SES with error handling."""
    try:
        from_email = os.environ.get('FROM_EMAIL', 'noreply@example.com')
        
        logger.info(f"Sending reply to {to_email} with subject: {subject}")
        
        response = ses.send_email(
            Source=from_email,
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {'Text': {'Data': body, 'Charset': 'UTF-8'}}
            }
        )
        
        logger.info(f"Reply sent successfully. MessageId: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Error sending reply to {to_email}: {str(e)}")
        
        # Send error notification
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject="Email Reply Failed",
            Message=f"Failed to send reply to {to_email}: {str(e)}"
        )

def notify_processing_complete(message_id, sender, subject):
    """Send processing completion notification via SNS."""
    try:
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject="Email Processed Successfully",
            Message=f"""
Email processing completed:

Message ID: {message_id}
From: {sender}
Subject: {subject}
Environment: {os.environ.get('ENVIRONMENT', 'unknown')}
Timestamp: {json.dumps(context.aws_request_id if 'context' in globals() else 'unknown')}

Processing completed successfully.
            """
        )
        
        logger.info(f"Processing notification sent for message {message_id}")
        
    except Exception as e:
        logger.error(f"Error sending processing notification: {str(e)}")
      `),
    });

    // Grant SES permission to invoke Lambda function
    emailProcessorFunction.addPermission('SESInvokePermission', {
      principal: new iam.ServicePrincipal('ses.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceAccount: this.account,
    });

    // SES Receipt Rule Set
    const ruleSetName = `EmailProcessingRuleSet-${environment.valueAsString}-${uniqueSuffix}`;
    const receiptRuleSet = new ses.ReceiptRuleSet(this, 'EmailReceiptRuleSet', {
      receiptRuleSetName: ruleSetName,
    });

    // SES Receipt Rule for email processing
    const receiptRule = new ses.ReceiptRule(this, 'EmailProcessingRule', {
      ruleSet: receiptRuleSet,
      ruleName: `EmailProcessingRule-${environment.valueAsString}-${uniqueSuffix}`,
      enabled: true,
      recipients: [
        `support@${domainName.valueAsString}`,
        `invoices@${domainName.valueAsString}`,
        `contact@${domainName.valueAsString}`,
      ],
      actions: [
        // Store email in S3
        new sesActions.S3({
          bucket: emailBucket,
          objectKeyPrefix: 'emails/',
        }),
        // Invoke Lambda function
        new sesActions.Lambda({
          function: emailProcessorFunction,
          invocationType: sesActions.LambdaInvocationType.EVENT,
        }),
      ],
    });

    // Outputs for reference and testing
    new cdk.CfnOutput(this, 'EmailBucketName', {
      value: emailBucket.bucketName,
      description: 'S3 bucket name for email storage',
      exportName: `${this.stackName}-EmailBucketName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: emailProcessorFunction.functionName,
      description: 'Lambda function name for email processing',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: emailProcessorFunction.functionArn,
      description: 'Lambda function ARN for email processing',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic ARN for email notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'SESRuleSetName', {
      value: receiptRuleSet.receiptRuleSetName!,
      description: 'SES receipt rule set name',
      exportName: `${this.stackName}-SESRuleSetName`,
    });

    new cdk.CfnOutput(this, 'EmailRecipients', {
      value: `support@${domainName.valueAsString}, invoices@${domainName.valueAsString}, contact@${domainName.valueAsString}`,
      description: 'Email addresses configured for processing',
      exportName: `${this.stackName}-EmailRecipients`,
    });

    new cdk.CfnOutput(this, 'MXRecordValue', {
      value: `10 inbound-smtp.${this.region}.amazonaws.com`,
      description: 'MX record value to add to your DNS (Priority: 10)',
      exportName: `${this.stackName}-MXRecordValue`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ServerlessEmailProcessing');
    cdk.Tags.of(this).add('Environment', environment.valueAsString);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// CDK App
const app = new cdk.App();

// Get environment from context or use default
const environment = app.node.tryGetContext('environment') || 'dev';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

// Create stack
new ServerlessEmailProcessingStack(app, `ServerlessEmailProcessingStack-${environment}`, {
  env: {
    account: account,
    region: region,
  },
  description: 'Serverless Email Processing System with SES and Lambda',
  tags: {
    Project: 'ServerlessEmailProcessing',
    Environment: environment,
    Owner: 'CDK',
  },
});

app.synth();