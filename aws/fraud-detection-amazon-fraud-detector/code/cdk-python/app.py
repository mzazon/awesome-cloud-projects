#!/usr/bin/env python3
"""
Real-Time Fraud Detection with Amazon Fraud Detector CDK Application

This CDK application deploys a comprehensive fraud detection platform using Amazon Fraud Detector,
combining advanced machine learning models with sophisticated rule engines for real-time
transaction analysis and fraud prevention.

Architecture includes:
- Amazon Fraud Detector with Transaction Fraud Insights model
- Kinesis Data Streams for real-time transaction processing
- Lambda functions for event enrichment and fraud scoring
- DynamoDB for decision logging and audit trails
- SNS for fraud alert notifications
- CloudWatch for monitoring and dashboards

Author: AWS CDK Team
Version: 1.0.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_s3 as s3,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_lambda_event_sources as event_sources,
)
from constructs import Construct


class FraudDetectorStack(Stack):
    """
    Main stack for the Real-Time Fraud Detection platform.
    
    This stack creates all necessary infrastructure components for a production-ready
    fraud detection system using Amazon Fraud Detector.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        fraud_detector_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the Fraud Detection Stack.
        
        Args:
            scope: The CDK app or parent construct
            construct_id: Unique identifier for this stack
            fraud_detector_email: Email address for fraud alert notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        random_suffix = self.node.try_get_context("random_suffix") or "dev"
        
        # Store configuration parameters
        self.fraud_detector_email = fraud_detector_email
        self.random_suffix = random_suffix
        
        # Create foundational infrastructure
        self._create_storage_resources()
        self._create_streaming_resources()
        self._create_iam_roles()
        self._create_database_resources()
        self._create_notification_resources()
        self._create_lambda_functions()
        self._create_monitoring_resources()
        
        # Output important resource information
        self._create_outputs()

    def _create_storage_resources(self) -> None:
        """Create S3 bucket for training data and model artifacts."""
        self.fraud_bucket = s3.Bucket(
            self,
            "FraudDetectionBucket",
            bucket_name=f"fraud-detection-platform-{self.random_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldVersions",
                    enabled=True,
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=cdk.Duration.days(30)
                        ),
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=cdk.Duration.days(90)
                        )
                    ],
                    noncurrent_version_expiration=cdk.Duration.days(365)
                )
            ]
        )

    def _create_streaming_resources(self) -> None:
        """Create Kinesis Data Stream for real-time transaction processing."""
        self.kinesis_stream = kinesis.Stream(
            self,
            "TransactionStream",
            stream_name=f"fraud-transaction-stream-{self.random_suffix}",
            shard_count=3,
            retention_period=Duration.days(7),
            encryption=kinesis.StreamEncryption.KMS
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Fraud Detector and Lambda functions."""
        # Fraud Detector service role
        self.fraud_detector_role = iam.Role(
            self,
            "FraudDetectorRole",
            role_name=f"FraudDetectorEnhancedRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("frauddetector.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonFraudDetectorFullAccessPolicy"
                )
            ],
            inline_policies={
                "FraudDetectorS3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:ListBucket",
                                "s3:PutObject"
                            ],
                            resources=[
                                self.fraud_bucket.bucket_arn,
                                f"{self.fraud_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                )
            }
        )

        # Lambda execution role for fraud detection processing
        self.lambda_role = iam.Role(
            self,
            "FraudDetectionLambdaRole",
            role_name=f"FraudDetectionLambdaRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaKinesisExecutionRole"
                )
            ]
        )

    def _create_database_resources(self) -> None:
        """Create DynamoDB table for fraud decision logging."""
        self.decisions_table = dynamodb.Table(
            self,
            "FraudDecisionsTable",
            table_name=f"fraud-decisions-{self.random_suffix}",
            partition_key=dynamodb.Attribute(
                name="transaction_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=100,
            write_capacity=100,
            removal_policy=RemovalPolicy.DESTROY,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            global_secondary_indexes=[
                dynamodb.GlobalSecondaryIndex(
                    index_name="customer-index",
                    partition_key=dynamodb.Attribute(
                        name="customer_id",
                        type=dynamodb.AttributeType.STRING
                    ),
                    read_capacity=50,
                    write_capacity=50,
                    projection_type=dynamodb.ProjectionType.ALL
                )
            ],
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

    def _create_notification_resources(self) -> None:
        """Create SNS topic for fraud alerts."""
        self.fraud_alerts_topic = sns.Topic(
            self,
            "FraudAlertsTask",
            topic_name=f"fraud-detection-alerts-{self.random_suffix}",
            display_name="Fraud Detection Alerts"
        )

        # Subscribe email to fraud alerts
        self.fraud_alerts_topic.add_subscription(
            subscriptions.EmailSubscription(self.fraud_detector_email)
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for event processing and fraud detection."""
        # Event enrichment Lambda function
        self.event_enrichment_function = lambda_.Function(
            self,
            "EventEnrichmentFunction",
            function_name=f"event-enrichment-processor-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="event_enrichment.lambda_handler",
            code=lambda_.Code.from_inline(self._get_event_enrichment_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "DECISIONS_TABLE": self.decisions_table.table_name,
                "FRAUD_PROCESSOR_FUNCTION": f"fraud-detection-processor-{self.random_suffix}"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Fraud detection processor Lambda function
        self.fraud_detection_function = lambda_.Function(
            self,
            "FraudDetectionFunction",
            function_name=f"fraud-detection-processor-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="fraud_detection.lambda_handler",
            code=lambda_.Code.from_inline(self._get_fraud_detection_code()),
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "DETECTOR_NAME": f"realtime-fraud-detector-{self.random_suffix}",
                "EVENT_TYPE_NAME": f"transaction-fraud-detection-{self.random_suffix}",
                "ENTITY_TYPE_NAME": f"customer-entity-{self.random_suffix}",
                "DECISIONS_TABLE": self.decisions_table.table_name,
                "SNS_TOPIC_ARN": self.fraud_alerts_topic.topic_arn,
                "MODEL_NAME": f"transaction-fraud-insights-{self.random_suffix}"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Grant necessary permissions
        self._grant_lambda_permissions()

        # Create event source mapping for Kinesis
        self.event_enrichment_function.add_event_source(
            event_sources.KinesisEventSource(
                stream=self.kinesis_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=10,
                max_batching_window=Duration.seconds(5)
            )
        )

    def _grant_lambda_permissions(self) -> None:
        """Grant necessary permissions to Lambda functions."""
        # Grant DynamoDB permissions
        self.decisions_table.grant_read_write_data(self.event_enrichment_function)
        self.decisions_table.grant_read_write_data(self.fraud_detection_function)

        # Grant SNS permissions
        self.fraud_alerts_topic.grant_publish(self.fraud_detection_function)

        # Grant Lambda invoke permissions
        self.fraud_detection_function.grant_invoke(self.event_enrichment_function)

        # Grant Fraud Detector permissions
        self.fraud_detection_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "frauddetector:GetEventPrediction",
                    "frauddetector:GetDetectors",
                    "frauddetector:GetModels",
                    "frauddetector:GetRules"
                ],
                resources=["*"]
            )
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch dashboard and alarms for monitoring."""
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "FraudDetectionDashboard",
            dashboard_name=f"FraudDetectionPlatform-{self.random_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.fraud_detection_function.metric_invocations(),
                            self.fraud_detection_function.metric_errors(),
                            self.fraud_detection_function.metric_duration()
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Kinesis Stream Metrics",
                        left=[
                            self.kinesis_stream.metric_incoming_records(),
                            self.kinesis_stream.metric_outgoing_records()
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="DynamoDB Metrics",
                        left=[
                            self.decisions_table.metric_consumed_read_capacity_units(),
                            self.decisions_table.metric_consumed_write_capacity_units()
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

        # Create alarms for critical metrics
        self._create_alarms()

    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        # Lambda error rate alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"FraudDetection-LambdaErrors-{self.random_suffix}",
            alarm_description="High error rate in fraud detection Lambda functions",
            metric=self.fraud_detection_function.metric_errors(),
            threshold=5,
            evaluation_periods=2,
            datapoints_to_alarm=1
        )

        # Lambda duration alarm
        lambda_duration_alarm = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            alarm_name=f"FraudDetection-LambdaDuration-{self.random_suffix}",
            alarm_description="High duration in fraud detection Lambda functions",
            metric=self.fraud_detection_function.metric_duration(),
            threshold=25000,  # 25 seconds
            evaluation_periods=3,
            datapoints_to_alarm=2
        )

        # DynamoDB throttle alarm
        dynamodb_throttle_alarm = cloudwatch.Alarm(
            self,
            "DynamoDBThrottleAlarm",
            alarm_name=f"FraudDetection-DynamoDBThrottles-{self.random_suffix}",
            alarm_description="DynamoDB throttling detected",
            metric=self.decisions_table.metric_throttled_requests(),
            threshold=1,
            evaluation_periods=1,
            datapoints_to_alarm=1
        )

        # Add alarms to SNS topic
        lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.fraud_alerts_topic)
        )
        lambda_duration_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.fraud_alerts_topic)
        )
        dynamodb_throttle_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.fraud_alerts_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        cdk.CfnOutput(
            self,
            "FraudBucketName",
            value=self.fraud_bucket.bucket_name,
            description="S3 bucket for fraud detection training data"
        )

        cdk.CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Kinesis stream for transaction processing"
        )

        cdk.CfnOutput(
            self,
            "DecisionsTableName",
            value=self.decisions_table.table_name,
            description="DynamoDB table for fraud decisions"
        )

        cdk.CfnOutput(
            self,
            "FraudAlertsTopicArn",
            value=self.fraud_alerts_topic.topic_arn,
            description="SNS topic for fraud alerts"
        )

        cdk.CfnOutput(
            self,
            "FraudDetectorRoleArn",
            value=self.fraud_detector_role.role_arn,
            description="IAM role for Amazon Fraud Detector"
        )

        cdk.CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL"
        )

    def _get_event_enrichment_code(self) -> str:
        """Get the Lambda function code for event enrichment."""
        return '''
import json
import boto3
import base64
from datetime import datetime
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

lambda_client = boto3.client('lambda')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Enriches incoming transaction events with behavioral features
    and forwards them to the fraud detection processor.
    """
    try:
        processed_records = 0
        
        for record in event['Records']:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            transaction_data = json.loads(payload)
            
            # Enrich transaction data
            enriched_data = enrich_transaction_data(transaction_data)
            
            # Forward to fraud detection processor
            forward_to_fraud_detection(enriched_data)
            
            processed_records += 1
        
        logger.info(f"Successfully processed {processed_records} records")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed {processed_records} records')
        }
        
    except Exception as e:
        logger.error(f"Error processing records: {str(e)}")
        raise

def enrich_transaction_data(transaction_data):
    """Add behavioral and historical features to transaction data."""
    customer_id = transaction_data.get('customer_id', 'unknown')
    current_time = datetime.now()
    
    # Add enrichment features
    transaction_data['transaction_frequency'] = get_transaction_frequency(customer_id)
    transaction_data['velocity_score'] = calculate_velocity_score(customer_id)
    transaction_data['processing_timestamp'] = current_time.isoformat()
    
    return transaction_data

def get_transaction_frequency(customer_id):
    """Calculate number of transactions in last 24 hours."""
    # Simplified implementation - in production, query DynamoDB
    return 1

def calculate_velocity_score(customer_id):
    """Calculate velocity-based risk score."""
    # Simplified implementation - in production, use historical data
    return 0.1

def forward_to_fraud_detection(enriched_data):
    """Forward enriched data to fraud detection processor."""
    try:
        lambda_client.invoke(
            FunctionName=os.environ['FRAUD_PROCESSOR_FUNCTION'],
            InvocationType='Event',
            Payload=json.dumps(enriched_data)
        )
    except Exception as e:
        logger.error(f"Error forwarding to fraud processor: {str(e)}")
        raise
        '''

    def _get_fraud_detection_code(self) -> str:
        """Get the Lambda function code for fraud detection processing."""
        return '''
import json
import boto3
import logging
import os
import uuid
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Process fraud detection for enriched transaction data.
    """
    try:
        # Extract transaction data
        transaction_data = event
        
        # Generate unique event ID
        event_id = f"txn_{uuid.uuid4().hex[:16]}"
        
        # Prepare variables for fraud detection
        variables = prepare_fraud_variables(transaction_data)
        
        # Get fraud prediction
        fraud_response = get_fraud_prediction(event_id, variables)
        
        # Process and log decision
        decision = process_fraud_decision(transaction_data, fraud_response)
        
        # Send alerts if necessary
        if decision['risk_level'] in ['HIGH', 'CRITICAL']:
            send_fraud_alert(decision)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'transaction_id': transaction_data.get('transaction_id'),
                'decision': decision['action'],
                'risk_score': decision['risk_score'],
                'risk_level': decision['risk_level']
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing fraud detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def prepare_fraud_variables(transaction_data):
    """Prepare variables for fraud detection API call."""
    return {
        'customer_id': transaction_data.get('customer_id', 'unknown'),
        'email_address': transaction_data.get('email_address', 'unknown'),
        'ip_address': transaction_data.get('ip_address', 'unknown'),
        'customer_name': transaction_data.get('customer_name', 'unknown'),
        'phone_number': transaction_data.get('phone_number', 'unknown'),
        'billing_address': transaction_data.get('billing_address', 'unknown'),
        'billing_city': transaction_data.get('billing_city', 'unknown'),
        'billing_state': transaction_data.get('billing_state', 'unknown'),
        'billing_zip': transaction_data.get('billing_zip', 'unknown'),
        'shipping_address': transaction_data.get('shipping_address', 'unknown'),
        'shipping_city': transaction_data.get('shipping_city', 'unknown'),
        'shipping_state': transaction_data.get('shipping_state', 'unknown'),
        'shipping_zip': transaction_data.get('shipping_zip', 'unknown'),
        'payment_method': transaction_data.get('payment_method', 'unknown'),
        'card_bin': transaction_data.get('card_bin', 'unknown'),
        'order_price': str(transaction_data.get('order_price', 0.0)),
        'product_category': transaction_data.get('product_category', 'unknown'),
        'transaction_amount': str(transaction_data.get('transaction_amount', 0.0)),
        'currency': transaction_data.get('currency', 'USD'),
        'merchant_category': transaction_data.get('merchant_category', 'unknown')
    }

def get_fraud_prediction(event_id, variables):
    """Get fraud prediction from Amazon Fraud Detector."""
    return frauddetector.get_event_prediction(
        detectorId=os.environ['DETECTOR_NAME'],
        eventId=event_id,
        eventTypeName=os.environ['EVENT_TYPE_NAME'],
        entities=[{
            'entityType': os.environ['ENTITY_TYPE_NAME'],
            'entityId': variables['customer_id']
        }],
        eventTimestamp=datetime.now().isoformat(),
        eventVariables=variables
    )

def process_fraud_decision(transaction_data, fraud_response):
    """Process fraud detection response and make decision."""
    # Extract model scores and outcomes
    model_scores = fraud_response.get('modelScores', [])
    rule_results = fraud_response.get('ruleResults', [])
    
    # Determine primary outcome
    primary_outcome = None
    if rule_results:
        primary_outcome = rule_results[0]['outcomes'][0] if rule_results[0]['outcomes'] else None
    
    # Calculate risk score
    risk_score = 0
    if model_scores:
        risk_score = model_scores[0]['scores'].get('TRANSACTION_FRAUD_INSIGHTS', 0)
    
    # Determine risk level
    risk_level = determine_risk_level(risk_score, primary_outcome)
    
    # Create decision record
    decision = {
        'transaction_id': transaction_data.get('transaction_id'),
        'customer_id': transaction_data.get('customer_id'),
        'timestamp': datetime.now().isoformat(),
        'risk_score': risk_score,
        'risk_level': risk_level,
        'action': primary_outcome or 'approve_transaction',
        'model_scores': model_scores,
        'rule_results': rule_results,
        'processing_time': datetime.now().isoformat()
    }
    
    # Log decision to DynamoDB
    log_decision(decision)
    
    return decision

def determine_risk_level(risk_score, outcome):
    """Determine risk level based on score and outcome."""
    if outcome == 'immediate_block' or risk_score > 900:
        return 'CRITICAL'
    elif outcome == 'manual_review' or risk_score > 600:
        return 'HIGH'
    elif outcome == 'challenge_authentication' or risk_score > 400:
        return 'MEDIUM'
    else:
        return 'LOW'

def log_decision(decision):
    """Log fraud decision to DynamoDB."""
    table = dynamodb.Table(os.environ['DECISIONS_TABLE'])
    
    table.put_item(
        Item={
            'transaction_id': decision['transaction_id'],
            'timestamp': int(datetime.now().timestamp()),
            'customer_id': decision['customer_id'],
            'risk_score': decision['risk_score'],
            'risk_level': decision['risk_level'],
            'action': decision['action'],
            'processing_time': decision['processing_time']
        }
    )

def send_fraud_alert(decision):
    """Send fraud alert for high-risk transactions."""
    message = {
        'alert_type': 'HIGH_RISK_TRANSACTION',
        'transaction_id': decision['transaction_id'],
        'customer_id': decision['customer_id'],
        'risk_score': decision['risk_score'],
        'risk_level': decision['risk_level'],
        'action': decision['action'],
        'timestamp': decision['timestamp']
    }
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Message=json.dumps(message),
        Subject=f"High Risk Transaction Alert - {decision['risk_level']}"
    )
        '''


class FraudDetectionApp(cdk.App):
    """Main CDK application for fraud detection platform."""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from context
        fraud_detector_email = self.node.try_get_context("fraud_detector_email")
        if not fraud_detector_email:
            fraud_detector_email = "fraud-alerts@example.com"
        
        # Create the main stack
        FraudDetectorStack(
            self,
            "FraudDetectorStack",
            fraud_detector_email=fraud_detector_email,
            description="Real-Time Fraud Detection with Amazon Fraud Detector",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
            )
        )


def main():
    """Main entry point for the CDK application."""
    app = FraudDetectionApp()
    app.synth()


if __name__ == "__main__":
    main()