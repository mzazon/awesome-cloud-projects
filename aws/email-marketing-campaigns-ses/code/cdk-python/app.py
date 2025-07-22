#!/usr/bin/env python3
"""
CDK Python Application for Email Marketing Campaigns with Amazon SES

This application creates a complete email marketing infrastructure including:
- Amazon SES email identities and templates
- S3 bucket for subscriber lists and templates
- SNS topic for email event notifications
- CloudWatch dashboard and alarms for monitoring
- Configuration set for email tracking
- Lambda function for bounce handling
- EventBridge rule for campaign automation
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ses as ses,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_logs as logs,
    RemovalPolicy,
    Duration,
    CfnParameter,
    CfnOutput,
)
from constructs import Construct
import json


class EmailMarketingStack(Stack):
    """
    CDK Stack for Email Marketing Campaigns with Amazon SES
    
    This stack creates all necessary resources for a complete email marketing
    solution including sender identity verification, email templates, event
    tracking, analytics, and automated bounce handling.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        sender_email = CfnParameter(
            self,
            "SenderEmail",
            type="String",
            description="Email address to use as sender (must be verified)",
            default="marketing@yourdomain.com",
        )

        sender_domain = CfnParameter(
            self,
            "SenderDomain",
            type="String",
            description="Domain to verify for sending emails",
            default="yourdomain.com",
        )

        notification_email = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address to receive bounce/complaint notifications",
            default="admin@yourdomain.com",
        )

        # Create S3 bucket for subscriber lists and email templates
        email_bucket = s3.Bucket(
            self,
            "EmailMarketingBucket",
            bucket_name=f"email-marketing-{self.account}-{self.region}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create folders in S3 bucket
        s3.CfnObject(
            self,
            "SubscribersFolder",
            bucket=email_bucket.bucket_name,
            key="subscribers/",
            content_type="application/x-directory",
        )

        s3.CfnObject(
            self,
            "SuppressionFolder",
            bucket=email_bucket.bucket_name,
            key="suppression/",
            content_type="application/x-directory",
        )

        # Create SNS topic for email event notifications
        email_events_topic = sns.Topic(
            self,
            "EmailEventsTopic",
            display_name="Email Marketing Events",
            topic_name=f"email-events-{self.account}",
        )

        # Subscribe email endpoint to SNS topic
        email_events_topic.add_subscription(
            sns_subscriptions.EmailSubscription(notification_email.value_as_string)
        )

        # Create SES domain identity
        domain_identity = ses.EmailIdentity(
            self,
            "DomainIdentity",
            identity=ses.Identity.domain(sender_domain.value_as_string),
            dkim_signing=True,
            dkim_identity=ses.DkimIdentity.byod_dkim(
                private_key_selector="ses",
                public_key_selector="ses",
                private_key=None,  # Will be generated
            ),
        )

        # Create SES email identity
        email_identity = ses.EmailIdentity(
            self,
            "EmailIdentity",
            identity=ses.Identity.email(sender_email.value_as_string),
        )

        # Create SES configuration set
        config_set = ses.ConfigurationSet(
            self,
            "EmailConfigurationSet",
            configuration_set_name=f"marketing-campaigns-{self.account}",
            delivery_options=ses.DeliveryOptions(tls_policy=ses.TlsPolicy.REQUIRE),
            reputation_options=ses.ReputationOptions(reputation_metrics_enabled=True),
            sending_options=ses.SendingOptions(sending_enabled=True),
            suppression_options=ses.SuppressionOptions(
                suppressed_reasons=[
                    ses.SuppressionReasons.BOUNCE,
                    ses.SuppressionReasons.COMPLAINT,
                ]
            ),
        )

        # Add CloudWatch event destination to configuration set
        config_set.add_event_destination(
            "CloudWatchDestination",
            destination=ses.EventDestination.cloud_watch_destination(
                default_dimensions={
                    "MessageTag": "campaign",
                    "ConfigurationSet": config_set.configuration_set_name,
                }
            ),
            events=[
                ses.EmailSendingEvent.SEND,
                ses.EmailSendingEvent.BOUNCE,
                ses.EmailSendingEvent.COMPLAINT,
                ses.EmailSendingEvent.DELIVERY,
                ses.EmailSendingEvent.OPEN,
                ses.EmailSendingEvent.CLICK,
                ses.EmailSendingEvent.RENDERING_FAILURE,
                ses.EmailSendingEvent.DELIVERY_DELAY,
            ],
        )

        # Add SNS event destination to configuration set
        config_set.add_event_destination(
            "SNSDestination",
            destination=ses.EventDestination.sns_destination(email_events_topic),
            events=[
                ses.EmailSendingEvent.BOUNCE,
                ses.EmailSendingEvent.COMPLAINT,
                ses.EmailSendingEvent.DELIVERY,
                ses.EmailSendingEvent.SEND,
            ],
        )

        # Create email templates
        welcome_template = ses.CfnTemplate(
            self,
            "WelcomeTemplate",
            template_name="welcome-campaign",
            template_data=ses.CfnTemplate.TemplateProperty(
                subject_part="Welcome to Our Community, {{name}}!",
                html_part="""
                <html>
                <body>
                    <h2>Welcome {{name}}!</h2>
                    <p>Thank you for joining our community. We are excited to have you aboard!</p>
                    <p>As a welcome gift, use code <strong>WELCOME10</strong> for 10% off your first purchase.</p>
                    <p>Best regards,<br/>The Marketing Team</p>
                    <p><a href="{{unsubscribe_url}}">Unsubscribe</a></p>
                </body>
                </html>
                """,
                text_part="""
                Welcome {{name}}!
                
                Thank you for joining our community. We are excited to have you aboard!
                
                As a welcome gift, use code WELCOME10 for 10% off your first purchase.
                
                Best regards,
                The Marketing Team
                
                Unsubscribe: {{unsubscribe_url}}
                """,
            ),
        )

        promotion_template = ses.CfnTemplate(
            self,
            "PromotionTemplate",
            template_name="product-promotion",
            template_data=ses.CfnTemplate.TemplateProperty(
                subject_part="Exclusive Offer: {{discount}}% Off {{product_name}}",
                html_part="""
                <html>
                <body>
                    <h2>Special Offer for {{name}}!</h2>
                    <p>Get {{discount}}% off our popular {{product_name}}!</p>
                    <p>Limited time offer - expires {{expiry_date}}</p>
                    <p>
                        <a href="{{product_url}}" style="background-color: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">
                            Shop Now
                        </a>
                    </p>
                    <p>Best regards,<br/>The Marketing Team</p>
                    <p><a href="{{unsubscribe_url}}">Unsubscribe</a></p>
                </body>
                </html>
                """,
                text_part="""
                Special Offer for {{name}}!
                
                Get {{discount}}% off our popular {{product_name}}!
                
                Limited time offer - expires {{expiry_date}}
                
                Shop Now: {{product_url}}
                
                Best regards,
                The Marketing Team
                
                Unsubscribe: {{unsubscribe_url}}
                """,
            ),
        )

        # Create Lambda function for bounce handling
        bounce_handler_function = lambda_.Function(
            self,
            "BounceHandlerFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(
                """
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''
    Handle bounce and complaint events from SES via SNS
    '''
    ses_client = boto3.client('sesv2')
    s3_client = boto3.client('s3')
    
    try:
        # Process SNS records
        for record in event['Records']:
            message = json.loads(record['Sns']['Message'])
            
            # Handle bounce events
            if message['eventType'] == 'bounce':
                bounced_email = message['mail']['destination'][0]
                bounce_type = message['bounce']['bounceType']
                
                # Add permanent bounces to suppression list
                if bounce_type == 'Permanent':
                    ses_client.put_suppressed_destination(
                        EmailAddress=bounced_email,
                        Reason='BOUNCE'
                    )
                    logger.info(f"Added {bounced_email} to suppression list due to permanent bounce")
                
            # Handle complaint events
            elif message['eventType'] == 'complaint':
                complained_email = message['mail']['destination'][0]
                
                # Add complaints to suppression list
                ses_client.put_suppressed_destination(
                    EmailAddress=complained_email,
                    Reason='COMPLAINT'
                )
                logger.info(f"Added {complained_email} to suppression list due to complaint")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed email events')
        }
        
    except Exception as e:
        logger.error(f"Error processing email events: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing events: {str(e)}')
        }
"""
            ),
            timeout=Duration.seconds(60),
            memory_size=128,
            environment={
                "BUCKET_NAME": email_bucket.bucket_name,
                "TOPIC_ARN": email_events_topic.topic_arn,
            },
        )

        # Grant permissions to Lambda function
        bounce_handler_function.add_to_role_policy(
            iam.PolicyStatement(
                actions=[
                    "ses:PutSuppressedDestination",
                    "ses:GetSuppressedDestination",
                    "sesv2:PutSuppressedDestination",
                    "sesv2:GetSuppressedDestination",
                ],
                resources=["*"],
            )
        )

        email_bucket.grant_read_write(bounce_handler_function)

        # Subscribe Lambda function to SNS topic
        email_events_topic.add_subscription(
            sns_subscriptions.LambdaSubscription(bounce_handler_function)
        )

        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "EmailMarketingDashboard",
            dashboard_name="EmailMarketingDashboard",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Email Sending Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/SES",
                                metric_name="Send",
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SES",
                                metric_name="Bounce",
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SES",
                                metric_name="Complaint",
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SES",
                                metric_name="Delivery",
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        period=Duration.minutes(5),
                        width=12,
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Bounce Rate",
                        metrics=[
                            cloudwatch.MathExpression(
                                expression="bounce/send*100",
                                using_metrics={
                                    "bounce": cloudwatch.Metric(
                                        namespace="AWS/SES",
                                        metric_name="Bounce",
                                        statistic="Sum",
                                        period=Duration.hours(1),
                                    ),
                                    "send": cloudwatch.Metric(
                                        namespace="AWS/SES",
                                        metric_name="Send",
                                        statistic="Sum",
                                        period=Duration.hours(1),
                                    ),
                                },
                                label="Bounce Rate (%)",
                            )
                        ],
                        width=6,
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Complaint Rate",
                        metrics=[
                            cloudwatch.MathExpression(
                                expression="complaint/send*100",
                                using_metrics={
                                    "complaint": cloudwatch.Metric(
                                        namespace="AWS/SES",
                                        metric_name="Complaint",
                                        statistic="Sum",
                                        period=Duration.hours(1),
                                    ),
                                    "send": cloudwatch.Metric(
                                        namespace="AWS/SES",
                                        metric_name="Send",
                                        statistic="Sum",
                                        period=Duration.hours(1),
                                    ),
                                },
                                label="Complaint Rate (%)",
                            )
                        ],
                        width=6,
                    ),
                ],
            ],
        )

        # Create CloudWatch alarms
        high_bounce_alarm = cloudwatch.Alarm(
            self,
            "HighBounceRateAlarm",
            alarm_name="HighBounceRate",
            alarm_description="Alert when bounce rate exceeds 5%",
            metric=cloudwatch.Metric(
                namespace="AWS/SES",
                metric_name="Bounce",
                statistic="Sum",
                period=Duration.hours(1),
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        high_bounce_alarm.add_alarm_action(
            cloudwatch.SnsAction(email_events_topic)
        )

        high_complaint_alarm = cloudwatch.Alarm(
            self,
            "HighComplaintRateAlarm",
            alarm_name="HighComplaintRate",
            alarm_description="Alert when complaint rate exceeds 0.1%",
            metric=cloudwatch.Metric(
                namespace="AWS/SES",
                metric_name="Complaint",
                statistic="Sum",
                period=Duration.hours(1),
            ),
            threshold=0.1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        high_complaint_alarm.add_alarm_action(
            cloudwatch.SnsAction(email_events_topic)
        )

        # Create EventBridge rule for campaign automation
        campaign_automation_rule = events.Rule(
            self,
            "CampaignAutomationRule",
            rule_name="WeeklyEmailCampaign",
            description="Trigger weekly email campaigns",
            schedule=events.Schedule.rate(Duration.days(7)),
        )

        # Create Lambda function for campaign automation
        campaign_automation_function = lambda_.Function(
            self,
            "CampaignAutomationFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(
                """
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''
    Automated campaign execution function
    '''
    ses_client = boto3.client('sesv2')
    s3_client = boto3.client('s3')
    
    try:
        # This is a placeholder for automated campaign logic
        # In production, this would:
        # 1. Fetch subscriber list from S3
        # 2. Segment subscribers based on preferences
        # 3. Send personalized emails using SES templates
        # 4. Log campaign metrics
        
        logger.info("Campaign automation triggered")
        
        # Example: Log automation event
        automation_log = {
            'timestamp': datetime.now().isoformat(),
            'event': 'campaign_automation_triggered',
            'status': 'success'
        }
        
        logger.info(f"Automation log: {json.dumps(automation_log)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Campaign automation completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in campaign automation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Campaign automation error: {str(e)}')
        }
"""
            ),
            timeout=Duration.seconds(300),
            memory_size=256,
            environment={
                "BUCKET_NAME": email_bucket.bucket_name,
                "CONFIG_SET_NAME": config_set.configuration_set_name,
                "SENDER_EMAIL": sender_email.value_as_string,
            },
        )

        # Grant permissions to campaign automation function
        campaign_automation_function.add_to_role_policy(
            iam.PolicyStatement(
                actions=[
                    "ses:SendEmail",
                    "ses:SendBulkEmail",
                    "ses:SendTemplatedEmail",
                    "ses:SendBulkTemplatedEmail",
                    "sesv2:SendEmail",
                    "sesv2:SendBulkEmail",
                ],
                resources=["*"],
            )
        )

        email_bucket.grant_read_write(campaign_automation_function)

        # Add Lambda function as EventBridge target
        campaign_automation_rule.add_target(
            events_targets.LambdaFunction(campaign_automation_function)
        )

        # Create sample subscriber list and upload to S3
        sample_subscribers = [
            {
                "email": "subscriber1@example.com",
                "name": "John Doe",
                "segment": "new_customers",
                "preferences": ["electronics", "books"],
            },
            {
                "email": "subscriber2@example.com",
                "name": "Jane Smith",
                "segment": "loyal_customers",
                "preferences": ["fashion", "home"],
            },
            {
                "email": "subscriber3@example.com",
                "name": "Bob Johnson",
                "segment": "new_customers",
                "preferences": ["sports", "electronics"],
            },
        ]

        # Upload sample subscriber list to S3
        s3.CfnObject(
            self,
            "SampleSubscribers",
            bucket=email_bucket.bucket_name,
            key="subscribers/subscribers.json",
            content_type="application/json",
            body=json.dumps(sample_subscribers, indent=2),
        )

        # Outputs
        CfnOutput(
            self,
            "S3BucketName",
            value=email_bucket.bucket_name,
            description="S3 bucket for email templates and subscriber lists",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=email_events_topic.topic_arn,
            description="SNS topic ARN for email event notifications",
        )

        CfnOutput(
            self,
            "ConfigurationSetName",
            value=config_set.configuration_set_name,
            description="SES configuration set name for email tracking",
        )

        CfnOutput(
            self,
            "BounceHandlerFunctionArn",
            value=bounce_handler_function.function_arn,
            description="Lambda function ARN for bounce handling",
        )

        CfnOutput(
            self,
            "CampaignAutomationFunctionArn",
            value=campaign_automation_function.function_arn,
            description="Lambda function ARN for campaign automation",
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=EmailMarketingDashboard",
            description="CloudWatch dashboard URL for email marketing metrics",
        )

        CfnOutput(
            self,
            "DomainVerificationInstructions",
            value=f"Add DKIM records to DNS for {sender_domain.value_as_string} to complete domain verification",
            description="Domain verification instructions",
        )


# CDK App
app = cdk.App()

# Create the email marketing stack
EmailMarketingStack(
    app,
    "EmailMarketingStack",
    description="Email Marketing Campaigns with Amazon SES - CDK Python",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

app.synth()