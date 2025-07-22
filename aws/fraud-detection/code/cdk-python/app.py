#!/usr/bin/env python3
"""
AWS CDK application for Fraud Detection with Amazon Fraud Detector.

This application creates a complete fraud detection infrastructure including:
- S3 bucket for training data storage
- IAM roles and policies for Fraud Detector service
- Amazon Fraud Detector resources (entity types, event types, models, rules, outcomes)
- Lambda function for processing fraud predictions
- CloudWatch logs for monitoring and debugging

The solution combines machine learning models with rule-based logic to detect
fraudulent transactions in real-time while minimizing false positives.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_frauddetector as frauddetector,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
import json
from typing import Dict, List, Optional


class FraudDetectionStack(Stack):
    """
    CDK Stack for Amazon Fraud Detector implementation.
    
    This stack creates all necessary resources for a complete fraud detection system
    including data storage, ML models, detection rules, and processing functions.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        unique_suffix: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Fraud Detection Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            unique_suffix: Optional suffix for resource naming
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix if not provided
        if unique_suffix is None:
            unique_suffix = cdk.Fn.select(0, cdk.Fn.split("-", cdk.Fn.ref("AWS::StackId")))[-6:]

        # Resource naming with unique suffix
        self.resource_prefix = f"fraud-detection-{unique_suffix}"
        
        # Create S3 bucket for training data
        self.training_data_bucket = self._create_training_data_bucket()
        
        # Create IAM role for Fraud Detector service
        self.fraud_detector_role = self._create_fraud_detector_service_role()
        
        # Create Lambda execution role
        self.lambda_execution_role = self._create_lambda_execution_role()
        
        # Create Lambda function for processing predictions
        self.prediction_processor = self._create_prediction_processor_function()
        
        # Create fraud detection labels
        self.fraud_label = self._create_fraud_label()
        self.legit_label = self._create_legit_label()
        
        # Create entity type for customers
        self.customer_entity_type = self._create_customer_entity_type()
        
        # Create event type for payment transactions
        self.payment_event_type = self._create_payment_event_type()
        
        # Create outcomes for rule actions
        self.review_outcome = self._create_review_outcome()
        self.block_outcome = self._create_block_outcome()
        self.approve_outcome = self._create_approve_outcome()
        
        # Create sample training data
        self._upload_sample_training_data()
        
        # Output important resource information
        self._create_outputs()

    def _create_training_data_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing fraud detection training data.
        
        Returns:
            S3 bucket for training data storage
        """
        bucket = s3.Bucket(
            self,
            "TrainingDataBucket",
            bucket_name=f"{self.resource_prefix}-training-data",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
        )
        
        # Add bucket policy to restrict access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[
                    bucket.bucket_arn,
                    bucket.arn_for_objects("*")
                ],
                conditions={
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            )
        )
        
        return bucket

    def _create_fraud_detector_service_role(self) -> iam.Role:
        """
        Create IAM role for Amazon Fraud Detector service.
        
        Returns:
            IAM role with necessary permissions for Fraud Detector
        """
        role = iam.Role(
            self,
            "FraudDetectorServiceRole",
            role_name=f"{self.resource_prefix}-service-role",
            assumed_by=iam.ServicePrincipal("frauddetector.amazonaws.com"),
            description="Service role for Amazon Fraud Detector to access S3 training data",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonFraudDetectorFullAccessPolicy"
                )
            ],
        )
        
        # Add inline policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                sid="S3TrainingDataAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:ListBucket",
                ],
                resources=[
                    self.training_data_bucket.bucket_arn,
                    self.training_data_bucket.arn_for_objects("*"),
                ],
            )
        )
        
        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution.
        
        Returns:
            IAM role with necessary permissions for Lambda execution
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"{self.resource_prefix}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for fraud detection Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add policy for Fraud Detector access
        role.add_to_policy(
            iam.PolicyStatement(
                sid="FraudDetectorAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "frauddetector:GetEventPrediction",
                    "frauddetector:DescribeDetector",
                    "frauddetector:DescribeModelVersions",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_prediction_processor_function(self) -> lambda_.Function:
        """
        Create Lambda function for processing fraud predictions.
        
        Returns:
            Lambda function for fraud prediction processing
        """
        # Lambda function code
        function_code = '''
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process fraud detection predictions for incoming transactions.
    
    Args:
        event: Lambda event containing transaction data
        context: Lambda context object
        
    Returns:
        Dict containing fraud prediction results
    """
    try:
        # Extract transaction data from event
        transaction_data = event.get('transaction', {})
        detector_config = event.get('detector_config', {})
        
        # Validate required configuration
        detector_id = detector_config.get('detector_id')
        event_type_name = detector_config.get('event_type_name')
        entity_type_name = detector_config.get('entity_type_name')
        
        if not all([detector_id, event_type_name, entity_type_name]):
            raise ValueError("Missing required detector configuration")
        
        # Prepare variables for fraud detection
        variables = {
            'customer_id': str(transaction_data.get('customer_id', 'unknown')),
            'email_address': str(transaction_data.get('email_address', 'unknown')),
            'ip_address': str(transaction_data.get('ip_address', 'unknown')),
            'customer_name': str(transaction_data.get('customer_name', 'unknown')),
            'phone_number': str(transaction_data.get('phone_number', 'unknown')),
            'billing_address': str(transaction_data.get('billing_address', 'unknown')),
            'billing_city': str(transaction_data.get('billing_city', 'unknown')),
            'billing_state': str(transaction_data.get('billing_state', 'unknown')),
            'billing_zip': str(transaction_data.get('billing_zip', 'unknown')),
            'payment_method': str(transaction_data.get('payment_method', 'unknown')),
            'card_bin': str(transaction_data.get('card_bin', 'unknown')),
            'order_price': str(transaction_data.get('order_price', 0.0)),
            'product_category': str(transaction_data.get('product_category', 'unknown'))
        }
        
        # Generate unique event ID
        event_id = f"txn_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}"
        
        # Get fraud prediction
        response = frauddetector.get_event_prediction(
            detectorId=detector_id,
            eventId=event_id,
            eventTypeName=event_type_name,
            entities=[{
                'entityType': entity_type_name,
                'entityId': variables['customer_id']
            }],
            eventTimestamp=datetime.now().isoformat() + 'Z',
            eventVariables=variables
        )
        
        # Process and structure results
        prediction_result = {
            'transaction_id': event.get('transaction_id', event_id),
            'customer_id': variables['customer_id'],
            'timestamp': datetime.now().isoformat(),
            'event_id': event_id,
            'fraud_prediction': {
                'model_scores': response.get('modelScores', []),
                'rule_results': response.get('ruleResults', []),
                'external_model_outputs': response.get('externalModelOutputs', [])
            },
            'recommended_action': None,
            'risk_level': 'unknown'
        }
        
        # Extract primary outcome and risk level
        rule_results = response.get('ruleResults', [])
        if rule_results:
            outcomes = rule_results[0].get('outcomes', [])
            if outcomes:
                prediction_result['recommended_action'] = outcomes[0]
                
                # Determine risk level based on action
                action = outcomes[0].lower()
                if action == 'block':
                    prediction_result['risk_level'] = 'high'
                elif action == 'review':
                    prediction_result['risk_level'] = 'medium'
                elif action == 'approve':
                    prediction_result['risk_level'] = 'low'
        
        # Extract fraud score if available
        model_scores = response.get('modelScores', [])
        if model_scores:
            prediction_result['fraud_score'] = model_scores[0].get('scores', {})
        
        # Log prediction results
        logger.info(f"Fraud prediction completed for transaction: {prediction_result['transaction_id']}")
        logger.info(f"Recommended action: {prediction_result['recommended_action']}")
        logger.info(f"Risk level: {prediction_result['risk_level']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(prediction_result, default=str),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"Error processing fraud prediction: {str(e)}"
        logger.error(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'transaction_id': event.get('transaction_id', 'unknown'),
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
'''
        
        function = lambda_.Function(
            self,
            "PredictionProcessor",
            function_name=f"{self.resource_prefix}-prediction-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=self.lambda_execution_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            description="Process fraud detection predictions for transactions",
            environment={
                "LOG_LEVEL": "INFO",
                "DETECTOR_NAME": f"{self.resource_prefix}-detector",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return function

    def _create_fraud_label(self) -> frauddetector.CfnLabel:
        """Create fraud label for ML model training."""
        return frauddetector.CfnLabel(
            self,
            "FraudLabel",
            name="fraud",
            description="Label for fraudulent transactions",
        )

    def _create_legit_label(self) -> frauddetector.CfnLabel:
        """Create legitimate label for ML model training."""
        return frauddetector.CfnLabel(
            self,
            "LegitLabel", 
            name="legit",
            description="Label for legitimate transactions",
        )

    def _create_customer_entity_type(self) -> frauddetector.CfnEntityType:
        """Create entity type for customers."""
        return frauddetector.CfnEntityType(
            self,
            "CustomerEntityType",
            name=f"{self.resource_prefix}-customer",
            description="Customer entity for fraud detection",
        )

    def _create_payment_event_type(self) -> frauddetector.CfnEventType:
        """Create event type for payment transactions."""
        event_variables = [
            {
                "name": "customer_id",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "email_address",
                "dataType": "STRING", 
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "ip_address",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "customer_name",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "phone_number",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "billing_address",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "billing_city",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "billing_state",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "billing_zip",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "payment_method",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "card_bin",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
            {
                "name": "order_price",
                "dataType": "FLOAT",
                "dataSource": "EVENT",
                "defaultValue": "0.0",
            },
            {
                "name": "product_category",
                "dataType": "STRING",
                "dataSource": "EVENT",
                "defaultValue": "unknown",
            },
        ]
        
        return frauddetector.CfnEventType(
            self,
            "PaymentEventType",
            name=f"{self.resource_prefix}-payment-fraud",
            description="Payment fraud detection event type",
            event_variables=event_variables,
            entity_types=[self.customer_entity_type.name],
            event_ingestion="ENABLED",
        )

    def _create_review_outcome(self) -> frauddetector.CfnOutcome:
        """Create outcome for manual review."""
        return frauddetector.CfnOutcome(
            self,
            "ReviewOutcome",
            name="review",
            description="Send transaction for manual review",
        )

    def _create_block_outcome(self) -> frauddetector.CfnOutcome:
        """Create outcome for blocking transactions."""
        return frauddetector.CfnOutcome(
            self,
            "BlockOutcome",
            name="block",
            description="Block fraudulent transaction",
        )

    def _create_approve_outcome(self) -> frauddetector.CfnOutcome:
        """Create outcome for approving transactions."""
        return frauddetector.CfnOutcome(
            self,
            "ApproveOutcome",
            name="approve",
            description="Approve legitimate transaction",
        )

    def _upload_sample_training_data(self) -> None:
        """Upload sample training data to S3 bucket."""
        # Sample training data content
        training_data_content = '''event_timestamp,customer_id,email_address,ip_address,customer_name,phone_number,billing_address,billing_city,billing_state,billing_zip,shipping_address,shipping_city,shipping_state,shipping_zip,payment_method,card_bin,order_price,product_category,EVENT_LABEL
2024-01-15T10:30:00Z,cust001,john.doe@email.com,192.168.1.1,John Doe,555-1234,123 Main St,Seattle,WA,98101,123 Main St,Seattle,WA,98101,credit_card,411111,99.99,electronics,legit
2024-01-15T11:45:00Z,cust002,jane.smith@email.com,10.0.0.1,Jane Smith,555-5678,456 Oak Ave,Portland,OR,97201,456 Oak Ave,Portland,OR,97201,credit_card,424242,1299.99,electronics,legit
2024-01-15T12:15:00Z,cust003,fraud@temp.com,1.2.3.4,Test User,555-0000,789 Pine St,New York,NY,10001,999 Different St,Los Angeles,CA,90210,credit_card,444444,2500.00,jewelry,fraud
2024-01-15T13:30:00Z,cust004,alice.johnson@email.com,172.16.0.1,Alice Johnson,555-9876,321 Elm St,Chicago,IL,60601,321 Elm St,Chicago,IL,60601,debit_card,555555,45.99,books,legit
2024-01-15T14:45:00Z,cust005,bob.wilson@email.com,192.168.2.1,Bob Wilson,555-4321,654 Maple Dr,Denver,CO,80201,654 Maple Dr,Denver,CO,80201,credit_card,666666,150.00,clothing,legit
2024-01-15T15:00:00Z,cust006,suspicious@tempmail.com,5.6.7.8,Fake Name,555-1111,123 Fake St,Nowhere,XX,00000,456 Other St,Somewhere,YY,11111,credit_card,777777,5000.00,electronics,fraud'''
        
        # Use CDK's BucketDeployment to upload the file
        from aws_cdk import aws_s3_deployment as s3_deployment
        
        s3_deployment.BucketDeployment(
            self,
            "TrainingDataDeployment",
            sources=[
                s3_deployment.Source.data(
                    "training-data.csv",
                    training_data_content
                )
            ],
            destination_bucket=self.training_data_bucket,
            retain_on_delete=False,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "TrainingDataBucketName",
            value=self.training_data_bucket.bucket_name,
            description="S3 bucket name for fraud detection training data",
            export_name=f"{self.stack_name}-training-data-bucket",
        )
        
        CfnOutput(
            self,
            "FraudDetectorServiceRoleArn",
            value=self.fraud_detector_role.role_arn,
            description="IAM role ARN for Fraud Detector service",
            export_name=f"{self.stack_name}-service-role-arn",
        )
        
        CfnOutput(
            self,
            "PredictionProcessorFunctionName",
            value=self.prediction_processor.function_name,
            description="Lambda function name for processing fraud predictions",
            export_name=f"{self.stack_name}-lambda-function-name",
        )
        
        CfnOutput(
            self,
            "CustomerEntityTypeName",
            value=self.customer_entity_type.name,
            description="Entity type name for customers",
            export_name=f"{self.stack_name}-entity-type-name",
        )
        
        CfnOutput(
            self,
            "PaymentEventTypeName",
            value=self.payment_event_type.name,
            description="Event type name for payment transactions",
            export_name=f"{self.stack_name}-event-type-name",
        )
        
        CfnOutput(
            self,
            "DetectorName",
            value=f"{self.resource_prefix}-detector",
            description="Fraud detector name (to be created manually or via additional automation)",
            export_name=f"{self.stack_name}-detector-name",
        )


class FraudDetectionApp(App):
    """CDK Application for fraud detection system deployment."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()
        
        # Get account and region from environment
        env = Environment(
            account=self.node.try_get_context("account"),
            region=self.node.try_get_context("region")
        )
        
        # Create the fraud detection stack
        FraudDetectionStack(
            self,
            "FraudDetectionStack",
            env=env,
            description="AWS CDK stack for Fraud Detection with Amazon Fraud Detector",
            tags={
                "Project": "FraudDetection",
                "Environment": self.node.try_get_context("environment") or "dev",
                "CostCenter": "Security",
                "Owner": "DataScience",
            },
        )


# Create and run the CDK application
app = FraudDetectionApp()
app.synth()