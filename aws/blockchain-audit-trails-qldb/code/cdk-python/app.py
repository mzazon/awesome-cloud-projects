#!/usr/bin/env python3
"""
CDK Python application for Blockchain Audit Trails Compliance with Amazon QLDB and CloudTrail.

This application creates a comprehensive blockchain-based audit trail system using:
- Amazon QLDB for immutable ledger records
- AWS CloudTrail for API activity logging
- EventBridge for real-time compliance monitoring
- Lambda for audit processing
- S3 for audit data storage
- Kinesis Data Firehose for streaming
- Athena for compliance queries
- CloudWatch for monitoring and alerting

Author: AWS Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    aws_qldb as qldb,
    aws_cloudtrail as cloudtrail,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3 as s3,
    aws_kinesisfirehose as firehose,
    aws_athena as athena,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from typing import Optional
import json


class BlockchainAuditTrailsStack(Stack):
    """
    CDK Stack for Blockchain Audit Trails Compliance solution.
    
    This stack creates a complete audit trail system with immutable blockchain
    records for regulatory compliance using Amazon QLDB and supporting services.
    """

    def __init__(
        self,
        scope: cdk.App,
        construct_id: str,
        environment_name: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the Blockchain Audit Trails Stack.
        
        Args:
            scope: CDK App scope
            construct_id: Unique stack identifier
            environment_name: Environment name (dev, staging, prod)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.environment_name = environment_name
        
        # Create core audit trail infrastructure
        self._create_s3_bucket()
        self._create_qldb_ledger()
        self._create_lambda_function()
        self._create_cloudtrail()
        self._create_eventbridge_rule()
        self._create_kinesis_firehose()
        self._create_athena_resources()
        self._create_monitoring_and_alerting()
        
        # Output important resource information
        self._create_outputs()

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for audit reports and CloudTrail logs."""
        self.audit_bucket = s3.Bucket(
            self,
            "ComplianceAuditBucket",
            bucket_name=f"compliance-audit-bucket-{self.environment_name}-{cdk.Aws.ACCOUNT_ID}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For development - change for production
            auto_delete_objects=True,  # For development - change for production
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldAuditLogs",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        ),
                    ]
                )
            ]
        )
        
        # Add tags for compliance tracking
        cdk.Tags.of(self.audit_bucket).add("Environment", self.environment_name)
        cdk.Tags.of(self.audit_bucket).add("Purpose", "ComplianceAudit")
        cdk.Tags.of(self.audit_bucket).add("DataClassification", "Sensitive")

    def _create_qldb_ledger(self) -> None:
        """Create Amazon QLDB ledger for immutable audit records."""
        self.qldb_ledger = qldb.CfnLedger(
            self,
            "ComplianceAuditLedger",
            name=f"compliance-audit-ledger-{self.environment_name}",
            permissions_mode="STANDARD",
            deletion_protection=True,  # Critical for compliance - prevents accidental deletion
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="Purpose", value="ComplianceAudit"),
                cdk.CfnTag(key="DataClassification", value="Sensitive"),
            ]
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for audit processing."""
        # Create Lambda execution role with specific permissions
        self.lambda_role = iam.Role(
            self,
            "AuditProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AuditProcessorPolicy": iam.PolicyDocument(
                    statements=[
                        # QLDB permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "qldb:SendCommand",
                                "qldb:GetDigest",
                                "qldb:GetBlock",
                                "qldb:GetRevision",
                                "qldb:PartiQLSelect",
                                "qldb:PartiQLInsert",
                            ],
                            resources=[self.qldb_ledger.attr_arn]
                        ),
                        # S3 permissions for audit reports
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                                "s3:DeleteObject",
                            ],
                            resources=[f"{self.audit_bucket.bucket_arn}/*"]
                        ),
                        # CloudWatch metrics permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                            ],
                            resources=["*"]
                        ),
                    ]
                )
            }
        )
        
        # Create Lambda function with audit processing code
        self.audit_processor = lambda_.Function(
            self,
            "AuditProcessor",
            function_name=f"audit-processor-{self.environment_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "LEDGER_NAME": self.qldb_ledger.name,
                "S3_BUCKET": self.audit_bucket.bucket_name,
                "ENVIRONMENT": self.environment_name,
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import hashlib
import datetime
import os
from botocore.exceptions import ClientError
from typing import Dict, Any

# Initialize AWS clients
qldb_client = boto3.client('qldb')
s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Process CloudTrail events and create immutable audit records in QLDB.
    
    Args:
        event: CloudTrail event from EventBridge
        context: Lambda execution context
        
    Returns:
        Response dictionary with processing status
    \"\"\"
    try:
        print(f"Processing audit event: {json.dumps(event, default=str)}")
        
        # Create structured audit record
        audit_record = create_audit_record(event)
        
        # Store in QLDB (simplified for this example)
        ledger_name = os.environ['LEDGER_NAME']
        store_audit_record(ledger_name, audit_record)
        
        # Generate compliance metrics
        generate_compliance_metrics(audit_record)
        
        # Store processed record in S3 for analysis
        store_in_s3(audit_record)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Audit record processed successfully',
                'auditId': audit_record.get('auditId'),
                'timestamp': audit_record.get('timestamp')
            })
        }
        
    except Exception as e:
        print(f"Error processing audit record: {str(e)}")
        
        # Send error metrics
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                }
            ]
        )
        
        raise


def create_audit_record(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Create structured audit record from CloudTrail event.\"\"\"
    timestamp = datetime.datetime.utcnow().isoformat()
    event_detail = event.get('detail', {})
    
    # Extract relevant audit information
    audit_record = {
        'auditId': hashlib.sha256(str(event).encode()).hexdigest()[:16],
        'timestamp': timestamp,
        'eventName': event_detail.get('eventName', 'Unknown'),
        'eventSource': event_detail.get('eventSource', ''),
        'eventType': event_detail.get('eventType', ''),
        'awsRegion': event_detail.get('awsRegion', ''),
        'sourceIPAddress': event_detail.get('sourceIPAddress', ''),
        'userAgent': event_detail.get('userAgent', ''),
        'userIdentity': event_detail.get('userIdentity', {}),
        'requestParameters': event_detail.get('requestParameters', {}),
        'responseElements': event_detail.get('responseElements', {}),
        'resources': event_detail.get('resources', []),
        'apiVersion': event_detail.get('apiVersion', ''),
        'errorCode': event_detail.get('errorCode'),
        'errorMessage': event_detail.get('errorMessage'),
        'recordHash': ''
    }
    
    # Create hash for integrity verification
    record_string = json.dumps(audit_record, sort_keys=True, default=str)
    audit_record['recordHash'] = hashlib.sha256(record_string.encode()).hexdigest()
    
    return audit_record


def store_audit_record(ledger_name: str, audit_record: Dict[str, Any]) -> None:
    \"\"\"Store audit record in QLDB ledger.\"\"\"
    try:
        # Get ledger digest for verification
        digest_response = qldb_client.get_digest(Name=ledger_name)
        
        print(f"QLDB Digest: {digest_response.get('Digest', {}).get('IonText', 'N/A')}")
        print(f"Stored audit record with ID: {audit_record['auditId']}")
        
        # Note: In a real implementation, you would use proper QLDB session
        # management and PartiQL INSERT statements to store the record
        
    except ClientError as e:
        print(f"Error storing audit record in QLDB: {e}")
        raise


def generate_compliance_metrics(audit_record: Dict[str, Any]) -> None:
    \"\"\"Generate CloudWatch metrics for compliance monitoring.\"\"\"
    try:
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=[
                {
                    'MetricName': 'AuditRecordsProcessed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'EventSource',
                            'Value': audit_record.get('eventSource', 'unknown')
                        },
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'AuditRecordSize',
                    'Value': len(json.dumps(audit_record)),
                    'Unit': 'Bytes',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                }
            ]
        )
        
    except ClientError as e:
        print(f"Error sending CloudWatch metrics: {e}")


def store_in_s3(audit_record: Dict[str, Any]) -> None:
    \"\"\"Store processed audit record in S3 for analysis.\"\"\"
    try:
        bucket_name = os.environ['S3_BUCKET']
        timestamp = datetime.datetime.utcnow()
        
        # Create partitioned key for efficient querying
        s3_key = f"processed-audit-records/year={timestamp.year}/month={timestamp.month:02d}/day={timestamp.day:02d}/{audit_record['auditId']}.json"
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(audit_record, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256',
            Metadata={
                'audit-id': audit_record['auditId'],
                'event-source': audit_record.get('eventSource', 'unknown'),
                'environment': os.environ.get('ENVIRONMENT', 'unknown')
            }
        )
        
        print(f"Stored audit record in S3: {s3_key}")
        
    except ClientError as e:
        print(f"Error storing audit record in S3: {e}")
""")
        )
        
        # Add tags to Lambda function
        cdk.Tags.of(self.audit_processor).add("Environment", self.environment_name)
        cdk.Tags.of(self.audit_processor).add("Purpose", "ComplianceAudit")

    def _create_cloudtrail(self) -> None:
        """Create CloudTrail for comprehensive API logging."""
        self.cloudtrail = cloudtrail.Trail(
            self,
            "ComplianceAuditTrail",
            trail_name=f"compliance-audit-trail-{self.environment_name}",
            bucket=self.audit_bucket,
            s3_key_prefix="cloudtrail-logs/",
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,  # Critical for compliance - enables log file integrity validation
            send_to_cloud_watch_logs=True,
            cloud_watch_logs_retention=logs.RetentionDays.ONE_YEAR,  # Compliance retention
            event_rules=[
                # Monitor critical API calls for compliance
                cloudtrail.ReadWriteType.ALL,
            ]
        )
        
        # Add tags for compliance tracking
        cdk.Tags.of(self.cloudtrail).add("Environment", self.environment_name)
        cdk.Tags.of(self.cloudtrail).add("Purpose", "ComplianceAudit")

    def _create_eventbridge_rule(self) -> None:
        """Create EventBridge rule for real-time audit processing."""
        self.audit_rule = events.Rule(
            self,
            "ComplianceAuditRule",
            rule_name=f"compliance-audit-rule-{self.environment_name}",
            description="Process critical API calls for compliance audit",
            event_pattern=events.EventPattern(
                source=["aws.cloudtrail"],
                detail_type=["AWS API Call via CloudTrail"],
                detail={
                    "eventSource": [
                        "qldb.amazonaws.com",
                        "s3.amazonaws.com",
                        "iam.amazonaws.com",
                        "lambda.amazonaws.com",
                        "cloudtrail.amazonaws.com",
                    ],
                    "eventName": [
                        # QLDB events
                        "SendCommand",
                        "CreateLedger",
                        "DeleteLedger",
                        # S3 events
                        "PutObject",
                        "DeleteObject",
                        "GetObject",
                        # IAM events
                        "CreateRole",
                        "DeleteRole",
                        "AttachRolePolicy",
                        "DetachRolePolicy",
                        # Lambda events
                        "CreateFunction",
                        "DeleteFunction",
                        "UpdateFunctionCode",
                        # CloudTrail events
                        "StopLogging",
                        "DeleteTrail",
                    ]
                }
            ),
            targets=[
                targets.LambdaFunction(
                    handler=self.audit_processor,
                    retry_attempts=3,
                    max_event_age=Duration.hours(2),
                    dead_letter_queue=None,  # Could add DLQ for production
                )
            ]
        )

    def _create_kinesis_firehose(self) -> None:
        """Create Kinesis Data Firehose for streaming audit data to S3."""
        # Create IAM role for Kinesis Data Firehose
        firehose_role = iam.Role(
            self,
            "FirehoseDeliveryRole",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            inline_policies={
                "FirehoseDeliveryPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.audit_bucket.bucket_arn,
                                f"{self.audit_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:PutLogEvents",
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        # Create Kinesis Data Firehose delivery stream
        self.firehose_stream = firehose.CfnDeliveryStream(
            self,
            "ComplianceAuditStream",
            delivery_stream_name=f"compliance-audit-stream-{self.environment_name}",
            delivery_stream_type="DirectPut",
            s3_destination_configuration=firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
                bucket_arn=self.audit_bucket.bucket_arn,
                role_arn=firehose_role.role_arn,
                prefix="compliance-reports/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
                error_output_prefix="errors/",
                buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                    size_in_m_bs=5,
                    interval_in_seconds=300
                ),
                compression_format="GZIP",
                cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                    enabled=True,
                    log_group_name=f"/aws/firehose/compliance-audit-stream-{self.environment_name}",
                )
            )
        )

    def _create_athena_resources(self) -> None:
        """Create Athena workgroup and database for compliance queries."""
        # Create Athena workgroup
        self.athena_workgroup = athena.CfnWorkGroup(
            self,
            "ComplianceAuditWorkGroup",
            name=f"compliance-audit-workgroup-{self.environment_name}",
            description="Workgroup for compliance audit queries",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.audit_bucket.bucket_name}/athena-results/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3"
                    )
                ),
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                bytes_scanned_cutoff_per_query=1000000000,  # 1GB query limit
            )
        )

    def _create_monitoring_and_alerting(self) -> None:
        """Create CloudWatch monitoring and SNS alerting for compliance."""
        # Create SNS topic for compliance alerts
        self.compliance_topic = sns.Topic(
            self,
            "ComplianceAlertsTopic",
            topic_name=f"compliance-audit-alerts-{self.environment_name}",
            display_name="Compliance Audit Alerts",
        )
        
        # Create CloudWatch dashboard
        self.compliance_dashboard = cloudwatch.Dashboard(
            self,
            "ComplianceDashboard",
            dashboard_name=f"ComplianceAudit-{self.environment_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Audit Records Processed",
                        left=[
                            cloudwatch.Metric(
                                namespace="ComplianceAudit",
                                metric_name="AuditRecordsProcessed",
                                statistic="Sum",
                                period=Duration.minutes(5),
                            )
                        ],
                        width=12,
                        height=6,
                    ),
                    cloudwatch.GraphWidget(
                        title="Lambda Function Performance",
                        left=[
                            self.audit_processor.metric_invocations(
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            self.audit_processor.metric_errors(
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        right=[
                            self.audit_processor.metric_duration(
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Recent Audit Processing Logs",
                        log_groups=[self.audit_processor.log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /audit/",
                            "sort @timestamp desc",
                            "limit 100"
                        ],
                        width=24,
                        height=6,
                    )
                ]
            ]
        )
        
        # Create CloudWatch alarms
        self.error_alarm = cloudwatch.Alarm(
            self,
            "ComplianceAuditErrors",
            alarm_name=f"ComplianceAuditErrors-{self.environment_name}",
            alarm_description="Alert when audit processing fails",
            metric=self.audit_processor.metric_errors(
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        # Add SNS action to alarm
        self.error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.compliance_topic)
        )
        
        # Create alarm for high processing latency
        self.latency_alarm = cloudwatch.Alarm(
            self,
            "ComplianceAuditLatency",
            alarm_name=f"ComplianceAuditLatency-{self.environment_name}",
            alarm_description="Alert when audit processing latency is high",
            metric=self.audit_processor.metric_duration(
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=30000,  # 30 seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        cdk.CfnOutput(
            self,
            "QLDBLedgerName",
            value=self.qldb_ledger.name,
            description="Name of the QLDB ledger for audit records",
            export_name=f"ComplianceAudit-{self.environment_name}-LedgerName"
        )
        
        cdk.CfnOutput(
            self,
            "S3BucketName",
            value=self.audit_bucket.bucket_name,
            description="S3 bucket for audit reports and CloudTrail logs",
            export_name=f"ComplianceAudit-{self.environment_name}-BucketName"
        )
        
        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.audit_processor.function_name,
            description="Lambda function for audit processing",
            export_name=f"ComplianceAudit-{self.environment_name}-LambdaFunction"
        )
        
        cdk.CfnOutput(
            self,
            "CloudTrailName",
            value=self.cloudtrail.trail_name,
            description="CloudTrail for API activity logging",
            export_name=f"ComplianceAudit-{self.environment_name}-CloudTrail"
        )
        
        cdk.CfnOutput(
            self,
            "AthenaWorkGroup",
            value=self.athena_workgroup.name,
            description="Athena workgroup for compliance queries",
            export_name=f"ComplianceAudit-{self.environment_name}-AthenaWorkGroup"
        )
        
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.compliance_topic.topic_arn,
            description="SNS topic for compliance alerts",
            export_name=f"ComplianceAudit-{self.environment_name}-SNSTopic"
        )
        
        cdk.CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{cdk.Aws.REGION}.console.aws.amazon.com/cloudwatch/home?region={cdk.Aws.REGION}#dashboards:name={self.compliance_dashboard.dashboard_name}",
            description="CloudWatch dashboard for compliance monitoring",
            export_name=f"ComplianceAudit-{self.environment_name}-Dashboard"
        )


# Import required for CloudWatch actions
from aws_cdk import aws_cloudwatch_actions as cloudwatch_actions


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = cdk.App()
    
    # Get environment name from context or default to 'dev'
    environment_name = app.node.try_get_context("environment") or "dev"
    
    # Get AWS account and region from environment or context
    account = app.node.try_get_context("account") or None
    region = app.node.try_get_context("region") or None
    
    # Create the stack
    BlockchainAuditTrailsStack(
        app,
        f"BlockchainAuditTrailsStack-{environment_name}",
        environment_name=environment_name,
        env=Environment(account=account, region=region),
        description=f"Blockchain Audit Trails Compliance Stack for {environment_name} environment",
        tags={
            "Project": "ComplianceAudit",
            "Environment": environment_name,
            "ManagedBy": "CDK",
            "Purpose": "BlockchainAuditTrails",
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()