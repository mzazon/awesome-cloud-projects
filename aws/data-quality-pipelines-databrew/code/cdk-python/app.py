#!/usr/bin/env python3
"""
CDK Python application for AWS Glue DataBrew Data Quality Pipeline

This application creates an automated data quality pipeline using:
- AWS Glue DataBrew for data profiling and validation
- Amazon EventBridge for event-driven automation
- AWS Lambda for processing validation results
- Amazon S3 for data storage and reports

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_databrew as databrew,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    CfnOutput,
    Tags,
)
from constructs import Construct


class DataQualityPipelineStack(Stack):
    """
    CDK Stack for automated data quality pipeline using AWS Glue DataBrew.
    
    This stack creates:
    - S3 buckets for data storage and quality reports
    - IAM roles for DataBrew and Lambda
    - DataBrew dataset, ruleset, and profile job
    - Lambda function for event processing
    - EventBridge rules for automation
    - SNS topic for notifications
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment: str = "dev",
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the DataQualityPipelineStack.
        
        Args:
            scope: The CDK app scope
            construct_id: Unique identifier for this stack
            environment: Environment name (dev, staging, prod)
            notification_email: Email address for quality alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.environment = environment
        self.notification_email = notification_email

        # Create S3 buckets
        self.data_bucket = self._create_data_bucket()
        
        # Create IAM roles
        self.databrew_role = self._create_databrew_role()
        self.lambda_role = self._create_lambda_role()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create Lambda function for event processing
        self.event_processor = self._create_event_processor()
        
        # Create EventBridge rule
        self.event_rule = self._create_event_rule()
        
        # Create DataBrew resources
        self.dataset = self._create_dataset()
        self.ruleset = self._create_ruleset()
        self.profile_job = self._create_profile_job()
        
        # Add stack outputs
        self._create_outputs()
        
        # Add common tags
        self._add_common_tags()

    def _create_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for data storage and quality reports."""
        bucket = s3.Bucket(
            self,
            "DataQualityBucket",
            bucket_name=f"data-quality-pipeline-{self.environment}-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="QualityReportsArchive",
                    prefix="quality-reports/",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                    expiration=Duration.days(365),
                ),
            ],
        )
        
        # Add bucket notification configuration for EventBridge
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3.NotificationConfig(
                event_name="DataQualityReportCreated",
                filter_prefix="quality-reports/",
            ),
        )
        
        return bucket

    def _create_databrew_role(self) -> iam.Role:
        """Create IAM role for AWS Glue DataBrew operations."""
        role = iam.Role(
            self,
            "DataBrewServiceRole",
            role_name=f"DataBrewServiceRole-{self.environment}-{self.region}",
            assumed_by=iam.ServicePrincipal("databrew.amazonaws.com"),
            description="IAM role for AWS Glue DataBrew service operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueDataBrewServiceRole"
                ),
            ],
        )
        
        # Add inline policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda event processing function."""
        role = iam.Role(
            self,
            "DataQualityLambdaRole",
            role_name=f"DataQualityLambdaRole-{self.environment}-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for data quality event processing Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add inline policies for SNS and S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish",
                    "s3:GetObject",
                    "s3:PutObject",
                    "databrew:DescribeJob",
                    "databrew:DescribeJobRun",
                ],
                resources=[
                    self.notification_topic.topic_arn if hasattr(self, 'notification_topic') else "*",
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                    f"arn:aws:databrew:{self.region}:{self.account}:job/*",
                ],
            )
        )
        
        return role

    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for data quality notifications."""
        topic = sns.Topic(
            self,
            "DataQualityNotificationTopic",
            topic_name=f"DataQualityAlerts-{self.environment}",
            display_name="Data Quality Pipeline Notifications",
            description="SNS topic for data quality validation alerts and notifications",
        )
        
        # Add email subscription if provided
        if self.notification_email:
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )
        
        return topic

    def _create_event_processor(self) -> lambda_.Function:
        """Create Lambda function for processing DataBrew validation events."""
        # Create log group with retention
        log_group = logs.LogGroup(
            self,
            "DataQualityProcessorLogGroup",
            log_group_name=f"/aws/lambda/DataQualityProcessor-{self.environment}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        function = lambda_.Function(
            self,
            "DataQualityProcessor",
            function_name=f"DataQualityProcessor-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Processes DataBrew validation events and triggers remediation actions",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "S3_BUCKET_NAME": self.data_bucket.bucket_name,
                "ENVIRONMENT": self.environment,
            },
            log_group=log_group,
        )
        
        return function

    def _create_event_rule(self) -> events.Rule:
        """Create EventBridge rule for DataBrew validation events."""
        rule = events.Rule(
            self,
            "DataBrewValidationRule",
            rule_name=f"DataBrewValidationRule-{self.environment}",
            description="Routes DataBrew validation events to Lambda for processing",
            event_pattern=events.EventPattern(
                source=["aws.databrew"],
                detail_type=["DataBrew Job State Change"],
                detail={
                    "state": ["SUCCEEDED", "FAILED"],
                    "jobType": ["PROFILE"],
                },
            ),
            enabled=True,
        )
        
        # Add Lambda target
        rule.add_target(
            events_targets.LambdaFunction(
                self.event_processor,
                retry_attempts=2,
                max_event_age=Duration.hours(4),
            )
        )
        
        return rule

    def _create_dataset(self) -> databrew.CfnDataset:
        """Create DataBrew dataset for data quality analysis."""
        dataset = databrew.CfnDataset(
            self,
            "CustomerDataset",
            name=f"customer-data-{self.environment}",
            input=databrew.CfnDataset.InputProperty(
                s3_input_definition=databrew.CfnDataset.S3LocationProperty(
                    bucket=self.data_bucket.bucket_name,
                    key="raw-data/customer-data.csv",
                )
            ),
            format="CSV",
            format_options=databrew.CfnDataset.FormatOptionsProperty(
                csv=databrew.CfnDataset.CsvOptionsProperty(
                    delimiter=",",
                    header_row=True,
                )
            ),
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Purpose", value="DataQuality"),
            ],
        )
        
        return dataset

    def _create_ruleset(self) -> databrew.CfnRuleset:
        """Create DataBrew ruleset for data quality validation."""
        ruleset = databrew.CfnRuleset(
            self,
            "CustomerQualityRuleset",
            name=f"customer-quality-rules-{self.environment}",
            target_arn=f"arn:aws:databrew:{self.region}:{self.account}:dataset/{self.dataset.name}",
            rules=[
                databrew.CfnRuleset.RuleProperty(
                    name="EmailFormatValidation",
                    check_expression=":col1 matches \"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$\"",
                    substitution_map={
                        ":col1": "`email`",
                    },
                    threshold=databrew.CfnRuleset.ThresholdProperty(
                        value=90.0,
                        type="GREATER_THAN_OR_EQUAL",
                        unit="PERCENTAGE",
                    ),
                ),
                databrew.CfnRuleset.RuleProperty(
                    name="AgeRangeValidation",
                    check_expression=":col1 between :val1 and :val2",
                    substitution_map={
                        ":col1": "`age`",
                        ":val1": "0",
                        ":val2": "120",
                    },
                    threshold=databrew.CfnRuleset.ThresholdProperty(
                        value=95.0,
                        type="GREATER_THAN_OR_EQUAL",
                        unit="PERCENTAGE",
                    ),
                ),
                databrew.CfnRuleset.RuleProperty(
                    name="PurchaseAmountNotNull",
                    check_expression=":col1 is not null",
                    substitution_map={
                        ":col1": "`purchase_amount`",
                    },
                    threshold=databrew.CfnRuleset.ThresholdProperty(
                        value=90.0,
                        type="GREATER_THAN_OR_EQUAL",
                        unit="PERCENTAGE",
                    ),
                ),
            ],
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Purpose", value="DataQuality"),
            ],
        )
        
        return ruleset

    def _create_profile_job(self) -> databrew.CfnJob:
        """Create DataBrew profile job for data quality assessment."""
        profile_job = databrew.CfnJob(
            self,
            "QualityAssessmentJob",
            name=f"quality-assessment-job-{self.environment}",
            type="PROFILE",
            dataset_name=self.dataset.name,
            role_arn=self.databrew_role.role_arn,
            output_location=databrew.CfnJob.OutputLocationProperty(
                bucket=self.data_bucket.bucket_name,
                key="quality-reports/",
            ),
            validation_configurations=[
                databrew.CfnJob.ValidationConfigurationProperty(
                    ruleset_arn=f"arn:aws:databrew:{self.region}:{self.account}:ruleset/{self.ruleset.name}",
                    validation_mode="CHECK_ALL",
                )
            ],
            job_sample=databrew.CfnJob.JobSampleProperty(
                mode="FULL_DATASET",
            ),
            profile_configuration=databrew.CfnJob.ProfileConfigurationProperty(
                dataset_statistics_configuration=databrew.CfnJob.StatisticsConfigurationProperty(
                    included_statistics=[
                        "COMPLETENESS",
                        "VALIDITY",
                        "UNIQUENESS",
                        "CORRELATION",
                    ]
                ),
                profile_columns=[
                    databrew.CfnJob.ColumnSelectorProperty(
                        regex=".*",
                    )
                ],
            ),
            max_capacity=5,
            timeout=120,
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment),
                cdk.CfnTag(key="Purpose", value="DataQuality"),
            ],
        )
        
        return profile_job

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for event processing."""
        return """
import json
import boto3
import os
from datetime import datetime, timezone
from typing import Dict, Any, Optional
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    '''
    Process DataBrew validation events and trigger remediation actions.
    
    This function handles DataBrew job state changes and validation results,
    sending notifications and initiating remediation workflows as needed.
    '''
    logger.info(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Extract event details
        detail = event.get('detail', {})
        job_name = detail.get('jobName', 'Unknown')
        job_type = detail.get('jobType', 'Unknown')
        state = detail.get('state', 'Unknown')
        
        # Initialize AWS clients
        sns = boto3.client('sns')
        s3 = boto3.client('s3')
        databrew = boto3.client('databrew')
        
        # Get environment variables
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        environment = os.environ.get('ENVIRONMENT', 'unknown')
        
        logger.info(f"Processing {job_type} job '{job_name}' with state '{state}'")
        
        if job_type == 'PROFILE' and state in ['SUCCEEDED', 'FAILED']:
            # Get detailed job information
            try:
                job_details = databrew.describe_job(Name=job_name)
                validation_configs = job_details.get('ValidationConfigurations', [])
                
                if state == 'SUCCEEDED' and validation_configs:
                    # Check validation results
                    validation_results = _check_validation_results(
                        databrew, job_name, detail.get('jobRunId')
                    )
                    
                    if validation_results.get('has_failures', False):
                        _send_quality_alert(
                            sns, topic_arn, job_name, validation_results, environment
                        )
                        _quarantine_failed_data(s3, bucket_name, job_name)
                    else:
                        _send_success_notification(
                            sns, topic_arn, job_name, validation_results, environment
                        )
                        
                elif state == 'FAILED':
                    _send_job_failure_alert(sns, topic_arn, job_name, detail, environment)
                    
            except Exception as e:
                logger.error(f"Error processing job details: {str(e)}")
                raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {job_type} job {job_name}',
                'state': state,
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }

def _check_validation_results(databrew, job_name: str, run_id: Optional[str]) -> Dict[str, Any]:
    '''Check validation results from DataBrew profile job.'''
    try:
        # Get job run details
        if run_id:
            run_details = databrew.describe_job_run(Name=job_name, RunId=run_id)
            validation_results = run_details.get('ValidationConfigurations', [])
            
            has_failures = any(
                result.get('ValidationMode') == 'CHECK_ALL' 
                for result in validation_results
            )
            
            return {
                'has_failures': has_failures,
                'validation_configs': validation_results,
                'run_id': run_id
            }
    except Exception as e:
        logger.error(f"Error checking validation results: {str(e)}")
        return {'has_failures': False, 'error': str(e)}

def _send_quality_alert(sns, topic_arn: str, job_name: str, results: Dict[str, Any], environment: str):
    '''Send SNS notification for data quality failures.'''
    if not topic_arn:
        logger.warning("No SNS topic ARN configured")
        return
        
    message = f'''
Data Quality Alert - Validation Failed

Environment: {environment}
Job: {job_name}
Run ID: {results.get('run_id', 'Unknown')}
Timestamp: {datetime.now(timezone.utc).isoformat()}

Validation failures detected in the dataset. Please review the quality report
and investigate source data issues.

Action Required: 
1. Review the data quality report in S3
2. Check source data for anomalies
3. Implement data cleansing if needed
4. Re-run the profile job after remediation

This is an automated alert from the Data Quality Pipeline.
'''
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject=f'Data Quality Alert - {environment}',
            Message=message
        )
        logger.info(f"Quality alert sent for job {job_name}")
    except Exception as e:
        logger.error(f"Failed to send quality alert: {str(e)}")

def _send_success_notification(sns, topic_arn: str, job_name: str, results: Dict[str, Any], environment: str):
    '''Send SNS notification for successful validation.'''
    if not topic_arn:
        return
        
    message = f'''
Data Quality Success - Validation Passed

Environment: {environment}
Job: {job_name}
Run ID: {results.get('run_id', 'Unknown')}
Timestamp: {datetime.now(timezone.utc).isoformat()}

All data quality validations passed successfully.
Data is ready for downstream processing.

This is an automated notification from the Data Quality Pipeline.
'''
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject=f'Data Quality Success - {environment}',
            Message=message
        )
        logger.info(f"Success notification sent for job {job_name}")
    except Exception as e:
        logger.error(f"Failed to send success notification: {str(e)}")

def _send_job_failure_alert(sns, topic_arn: str, job_name: str, detail: Dict[str, Any], environment: str):
    '''Send SNS notification for job execution failures.'''
    if not topic_arn:
        return
        
    message = f'''
Data Quality Job Failure Alert

Environment: {environment}
Job: {job_name}
State: {detail.get('state', 'Unknown')}
Timestamp: {datetime.now(timezone.utc).isoformat()}

The DataBrew profile job failed to execute. Please check the job configuration
and logs for detailed error information.

This is an automated alert from the Data Quality Pipeline.
'''
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject=f'DataBrew Job Failure - {environment}',
            Message=message
        )
        logger.info(f"Job failure alert sent for job {job_name}")
    except Exception as e:
        logger.error(f"Failed to send job failure alert: {str(e)}")

def _quarantine_failed_data(s3, bucket_name: str, job_name: str):
    '''Move failed data to quarantine location.'''
    try:
        # This is a placeholder for data quarantine logic
        # In production, you would implement specific quarantine rules
        # based on your data governance requirements
        
        quarantine_key = f"quarantine/{job_name}/{datetime.now(timezone.utc).strftime('%Y-%m-%d-%H-%M-%S')}"
        logger.info(f"Data quarantine initiated for job {job_name} at {quarantine_key}")
        
        # Example: Copy failed data to quarantine location
        # s3.copy_object(
        #     CopySource={'Bucket': bucket_name, 'Key': 'raw-data/'},
        #     Bucket=bucket_name,
        #     Key=quarantine_key
        # )
        
    except Exception as e:
        logger.error(f"Failed to quarantine data: {str(e)}")
"""

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the stack."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for data storage",
            export_name=f"DataQualityPipeline-{self.environment}-DataBucket",
        )
        
        CfnOutput(
            self,
            "DatasetName",
            value=self.dataset.name,
            description="Name of the DataBrew dataset",
            export_name=f"DataQualityPipeline-{self.environment}-Dataset",
        )
        
        CfnOutput(
            self,
            "RulesetName",
            value=self.ruleset.name,
            description="Name of the DataBrew ruleset",
            export_name=f"DataQualityPipeline-{self.environment}-Ruleset",
        )
        
        CfnOutput(
            self,
            "ProfileJobName",
            value=self.profile_job.name,
            description="Name of the DataBrew profile job",
            export_name=f"DataQualityPipeline-{self.environment}-ProfileJob",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.event_processor.function_name,
            description="Name of the Lambda function for event processing",
            export_name=f"DataQualityPipeline-{self.environment}-Lambda",
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
            export_name=f"DataQualityPipeline-{self.environment}-SNSTopic",
        )

    def _add_common_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "DataQualityPipeline")
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("CostCenter", "DataEngineering")
        Tags.of(self).add("CreatedBy", "CDK-Python")


class DataQualityPipelineApp(cdk.App):
    """CDK Application for Data Quality Pipeline."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        environment = self.node.try_get_context("environment") or "dev"
        notification_email = self.node.try_get_context("notification_email")
        
        # Create the stack
        DataQualityPipelineStack(
            self,
            f"DataQualityPipeline-{environment}",
            environment=environment,
            notification_email=notification_email,
            description=f"Automated data quality pipeline using AWS Glue DataBrew - {environment}",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION"),
            ),
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = DataQualityPipelineApp()
    app.synth()


if __name__ == "__main__":
    main()