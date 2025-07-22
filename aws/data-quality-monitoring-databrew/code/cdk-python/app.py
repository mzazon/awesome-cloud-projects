#!/usr/bin/env python3
"""
AWS CDK Python Application for Data Quality Monitoring with AWS Glue DataBrew

This application creates a comprehensive data quality monitoring solution using:
- AWS Glue DataBrew for data profiling and quality validation
- S3 buckets for data storage and results
- IAM roles and policies for secure access
- EventBridge for event-driven automation
- SNS for alerting on quality issues
- Lambda functions for processing quality results
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_databrew as databrew,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct


class DataQualityMonitoringStack(Stack):
    """
    Stack for AWS Glue DataBrew data quality monitoring solution.
    
    This stack creates all necessary resources for automated data quality
    monitoring including DataBrew resources, S3 storage, IAM roles,
    EventBridge rules, and SNS notifications.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the DataQualityMonitoringStack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for quality alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.notification_email = notification_email or "admin@example.com"
        
        # Generate unique suffix for resource names
        self.unique_suffix = self.node.addr[-8:].lower()
        
        # Create core infrastructure
        self._create_s3_resources()
        self._create_iam_resources()
        self._create_sample_data()
        self._create_databrew_resources()
        self._create_monitoring_resources()
        self._create_lambda_functions()
        self._create_event_automation()
        
        # Create outputs
        self._create_outputs()

    def _create_s3_resources(self) -> None:
        """Create S3 buckets for data storage and results."""
        # Primary data bucket for raw data and results
        self.data_bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"databrew-quality-monitoring-{self.unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ProfileResultsLifecycle",
                    prefix="profile-results/",
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

        # Lambda deployment bucket for function code
        self.lambda_bucket = s3.Bucket(
            self,
            "LambdaBucket",
            bucket_name=f"databrew-lambda-code-{self.unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_iam_resources(self) -> None:
        """Create IAM roles and policies for DataBrew and Lambda."""
        # DataBrew service role
        self.databrew_role = iam.Role(
            self,
            "DataBrewServiceRole",
            role_name=f"DataBrewServiceRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("databrew.amazonaws.com"),
            description="Service role for AWS Glue DataBrew operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueDataBrewServiceRole"
                ),
            ],
        )

        # Add custom policy for S3 access
        self.databrew_role.add_to_policy(
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

        # Lambda execution role
        self.lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"DataBrewLambdaRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for DataBrew quality processing Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

        # Add permissions for SNS publishing
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=["*"],
            )
        )

        # Add permissions for S3 access
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:PutObject"],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )

    def _create_sample_data(self) -> None:
        """Create sample customer data for testing."""
        # Sample CSV data with quality issues for testing
        sample_data = """customer_id,name,email,age,registration_date,account_balance
1,John Smith,john.smith@example.com,25,2023-01-15,1500.00
2,Jane Doe,jane.doe@example.com,32,2023-02-20,2300.50
3,Bob Johnson,,28,2023-03-10,750.25
4,Alice Brown,alice.brown@example.com,45,2023-04-05,3200.75
5,Charlie Wilson,charlie.wilson@example.com,-5,2023-05-12,1800.00
6,Diana Lee,diana.lee@example.com,67,invalid-date,2500.00
7,Frank Miller,frank.miller@example.com,33,2023-07-18,
8,Grace Taylor,grace.taylor@example.com,29,2023-08-25,1200.50
9,Henry Davis,henry.davis@example.com,41,2023-09-30,1750.25
10,Ivy Chen,ivy.chen@example.com,38,2023-10-15,2100.00
11,Jack Wilson,invalid-email,30,2023-11-01,1900.00
12,Kate Brown,kate.brown@example.com,150,2023-11-15,2200.00
13,Leo Garcia,leo.garcia@example.com,35,2023-12-01,-500.00
14,Mia Johnson,mia.johnson@example.com,28,2023-12-15,1600.75
15,Noah Lee,noah.lee@example.com,42,2023-12-30,2800.25"""

        # Deploy sample data to S3
        self.sample_data_deployment = s3_deployment.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3_deployment.Source.data(
                    "raw-data/customer_data.csv",
                    sample_data,
                )
            ],
            destination_bucket=self.data_bucket,
            destination_key_prefix="raw-data/",
            retain_on_delete=False,
        )

    def _create_databrew_resources(self) -> None:
        """Create AWS Glue DataBrew resources."""
        # Create DataBrew dataset
        self.dataset = databrew.CfnDataset(
            self,
            "CustomerDataset",
            name=f"customer-data-{self.unique_suffix}",
            input=databrew.CfnDataset.InputProperty(
                s3_input_definition=databrew.CfnDataset.S3LocationProperty(
                    bucket=self.data_bucket.bucket_name,
                    key="raw-data/",
                )
            ),
            format="CSV",
            format_options=databrew.CfnDataset.FormatOptionsProperty(
                csv=databrew.CfnDataset.CsvOptionsProperty(
                    delimiter=",",
                    header_row=True,
                )
            ),
        )

        # Create data quality ruleset
        self.ruleset = databrew.CfnRuleset(
            self,
            "DataQualityRuleset",
            name=f"customer-quality-rules-{self.unique_suffix}",
            target_arn=f"arn:aws:databrew:{self.region}:{self.account}:dataset/{self.dataset.name}",
            rules=[
                databrew.CfnRuleset.RuleProperty(
                    name="customer_id_not_null",
                    check_expression="COLUMN_COMPLETENESS(customer_id) > 0.95",
                    disabled=False,
                ),
                databrew.CfnRuleset.RuleProperty(
                    name="email_format_valid",
                    check_expression='COLUMN_DATA_TYPE(email) = "STRING" AND COLUMN_MATCHES_REGEX(email, "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$") > 0.8',
                    disabled=False,
                ),
                databrew.CfnRuleset.RuleProperty(
                    name="age_range_valid",
                    check_expression="COLUMN_MIN(age) >= 0 AND COLUMN_MAX(age) <= 120",
                    disabled=False,
                ),
                databrew.CfnRuleset.RuleProperty(
                    name="balance_positive",
                    check_expression="COLUMN_MIN(account_balance) >= 0",
                    disabled=False,
                ),
                databrew.CfnRuleset.RuleProperty(
                    name="registration_date_valid",
                    check_expression='COLUMN_DATA_TYPE(registration_date) = "DATE"',
                    disabled=False,
                ),
            ],
        )

        # Create profile job
        self.profile_job = databrew.CfnJob(
            self,
            "ProfileJob",
            name=f"customer-profile-job-{self.unique_suffix}",
            type="PROFILE",
            role_arn=self.databrew_role.role_arn,
            dataset_name=self.dataset.name,
            output_location=databrew.CfnJob.OutputLocationProperty(
                bucket=self.data_bucket.bucket_name,
                key="profile-results/",
            ),
            job_sample=databrew.CfnJob.JobSampleProperty(
                mode="FULL_DATASET",
            ),
            profile_configuration=databrew.CfnJob.ProfileConfigurationProperty(
                dataset_statistics_configuration=databrew.CfnJob.StatisticsConfigurationProperty(
                    included_statistics=["ALL"]
                ),
                profile_columns=[
                    databrew.CfnJob.ColumnSelectorProperty(
                        name="*",
                        regex=".*",
                    )
                ],
            ),
            validation_configurations=[
                databrew.CfnJob.ValidationConfigurationProperty(
                    ruleset_arn=f"arn:aws:databrew:{self.region}:{self.account}:ruleset/{self.ruleset.name}",
                    validation_mode="CHECK_ALL",
                )
            ],
        )

        # Add dependency to ensure dataset exists before profile job
        self.profile_job.add_dependency(self.dataset)
        self.profile_job.add_dependency(self.ruleset)

    def _create_monitoring_resources(self) -> None:
        """Create SNS topic and subscriptions for monitoring."""
        # SNS topic for data quality alerts
        self.quality_alerts_topic = sns.Topic(
            self,
            "QualityAlertsTopic",
            topic_name=f"data-quality-alerts-{self.unique_suffix}",
            display_name="Data Quality Alerts",
            description="Notifications for data quality validation results",
        )

        # Add email subscription
        self.quality_alerts_topic.add_subscription(
            subscriptions.EmailSubscription(self.notification_email)
        )

        # SNS topic for job completion notifications
        self.job_completion_topic = sns.Topic(
            self,
            "JobCompletionTopic",
            topic_name=f"databrew-job-completion-{self.unique_suffix}",
            display_name="DataBrew Job Completion",
            description="Notifications for DataBrew job completion",
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for processing quality results."""
        # Lambda function for processing quality validation results
        self.quality_processor = lambda_.Function(
            self,
            "QualityResultProcessor",
            function_name=f"databrew-quality-processor-{self.unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Process DataBrew quality validation results",
            environment={
                "QUALITY_ALERTS_TOPIC_ARN": self.quality_alerts_topic.topic_arn,
                "JOB_COMPLETION_TOPIC_ARN": self.job_completion_topic.topic_arn,
                "DATA_BUCKET_NAME": self.data_bucket.bucket_name,
            },
            code=lambda_.Code.from_inline(self._get_lambda_code()),
        )

        # Grant permissions to publish to SNS topics
        self.quality_alerts_topic.grant_publish(self.quality_processor)
        self.job_completion_topic.grant_publish(self.quality_processor)

    def _create_event_automation(self) -> None:
        """Create EventBridge rules for automation."""
        # EventBridge rule for DataBrew validation failures
        self.validation_failure_rule = events.Rule(
            self,
            "ValidationFailureRule",
            rule_name=f"databrew-validation-failure-{self.unique_suffix}",
            description="Trigger alerts on DataBrew validation failures",
            event_pattern=events.EventPattern(
                source=["aws.databrew"],
                detail_type=["DataBrew Ruleset Validation Result"],
                detail={
                    "validationState": ["FAILED"],
                },
            ),
        )

        # Add Lambda target for processing failures
        self.validation_failure_rule.add_target(
            targets.LambdaFunction(
                self.quality_processor,
                event=events.RuleTargetInput.from_object({
                    "eventType": "ValidationFailure",
                    "source": events.EventField.from_path("$.source"),
                    "detail": events.EventField.from_path("$.detail"),
                }),
            )
        )

        # EventBridge rule for DataBrew job completion
        self.job_completion_rule = events.Rule(
            self,
            "JobCompletionRule",
            rule_name=f"databrew-job-completion-{self.unique_suffix}",
            description="Trigger processing on DataBrew job completion",
            event_pattern=events.EventPattern(
                source=["aws.databrew"],
                detail_type=["DataBrew Job State Change"],
                detail={
                    "state": ["SUCCEEDED", "FAILED"],
                },
            ),
        )

        # Add Lambda target for job completion processing
        self.job_completion_rule.add_target(
            targets.LambdaFunction(
                self.quality_processor,
                event=events.RuleTargetInput.from_object({
                    "eventType": "JobCompletion",
                    "source": events.EventField.from_path("$.source"),
                    "detail": events.EventField.from_path("$.detail"),
                }),
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        cdk.CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for data storage and results",
        )

        cdk.CfnOutput(
            self,
            "DatasetName",
            value=self.dataset.name,
            description="DataBrew dataset name",
        )

        cdk.CfnOutput(
            self,
            "ProfileJobName",
            value=self.profile_job.name,
            description="DataBrew profile job name",
        )

        cdk.CfnOutput(
            self,
            "RulesetName",
            value=self.ruleset.name,
            description="DataBrew ruleset name",
        )

        cdk.CfnOutput(
            self,
            "QualityAlertsTopicArn",
            value=self.quality_alerts_topic.topic_arn,
            description="SNS topic ARN for quality alerts",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.quality_processor.function_arn,
            description="Lambda function ARN for quality processing",
        )

    def _get_lambda_code(self) -> str:
        """Get Lambda function code for processing quality results."""
        return """
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Process DataBrew quality validation results and job completion events.
    
    Args:
        event: EventBridge event containing DataBrew information
        context: Lambda context object
        
    Returns:
        Response dictionary with processing status
    \"\"\"
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    # Initialize AWS clients
    sns = boto3.client('sns')
    s3 = boto3.client('s3')
    
    # Environment variables
    quality_topic_arn = os.environ['QUALITY_ALERTS_TOPIC_ARN']
    completion_topic_arn = os.environ['JOB_COMPLETION_TOPIC_ARN']
    bucket_name = os.environ['DATA_BUCKET_NAME']
    
    try:
        event_type = event.get('eventType', 'Unknown')
        
        if event_type == 'ValidationFailure':
            return handle_validation_failure(event, sns, quality_topic_arn)
        elif event_type == 'JobCompletion':
            return handle_job_completion(event, sns, s3, completion_topic_arn, bucket_name)
        else:
            print(f"Unknown event type: {event_type}")
            return {"statusCode": 200, "body": "Event processed"}
            
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {"statusCode": 500, "body": f"Error: {str(e)}"}

def handle_validation_failure(event: Dict[str, Any], sns, topic_arn: str) -> Dict[str, Any]:
    \"\"\"Handle DataBrew validation failure events.\"\"\"
    detail = event.get('detail', {})
    
    # Extract validation details
    dataset_name = detail.get('datasetName', 'Unknown')
    ruleset_name = detail.get('rulesetName', 'Unknown')
    validation_state = detail.get('validationState', 'Unknown')
    report_location = detail.get('validationReportLocation', 'Not available')
    
    # Create alert message
    message = f\"\"\"
🚨 DATA QUALITY VALIDATION FAILED 🚨

Dataset: {dataset_name}
Ruleset: {ruleset_name}
Status: {validation_state}
Report Location: {report_location}
Timestamp: {datetime.now().isoformat()}

Please review the validation report for detailed failure information.
\"\"\"
    
    # Publish to SNS
    response = sns.publish(
        TopicArn=topic_arn,
        Subject=f"Data Quality Alert: {dataset_name}",
        Message=message
    )
    
    print(f"Published validation failure alert: {response['MessageId']}")
    
    return {
        "statusCode": 200,
        "body": "Validation failure alert sent"
    }

def handle_job_completion(event: Dict[str, Any], sns, s3, topic_arn: str, bucket_name: str) -> Dict[str, Any]:
    \"\"\"Handle DataBrew job completion events.\"\"\"
    detail = event.get('detail', {})
    
    # Extract job details
    job_name = detail.get('jobName', 'Unknown')
    job_state = detail.get('state', 'Unknown')
    job_type = detail.get('jobType', 'Unknown')
    
    # Create completion message
    status_emoji = "✅" if job_state == "SUCCEEDED" else "❌"
    message = f\"\"\"
{status_emoji} DATABREW JOB COMPLETED {status_emoji}

Job Name: {job_name}
Job Type: {job_type}
Status: {job_state}
Timestamp: {datetime.now().isoformat()}

Job execution has completed. Check the results in S3 bucket: {bucket_name}
\"\"\"
    
    # Publish to SNS
    response = sns.publish(
        TopicArn=topic_arn,
        Subject=f"DataBrew Job {job_state}: {job_name}",
        Message=message
    )
    
    print(f"Published job completion notification: {response['MessageId']}")
    
    return {
        "statusCode": 200,
        "body": "Job completion notification sent"
    }
"""


class DataQualityMonitoringApp(cdk.App):
    """CDK Application for Data Quality Monitoring."""

    def __init__(self):
        super().__init__()

        # Get notification email from environment or use default
        notification_email = os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")
        
        # Create the stack
        DataQualityMonitoringStack(
            self,
            "DataQualityMonitoringStack",
            notification_email=notification_email,
            description="AWS Glue DataBrew data quality monitoring solution",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


if __name__ == "__main__":
    app = DataQualityMonitoringApp()
    app.synth()