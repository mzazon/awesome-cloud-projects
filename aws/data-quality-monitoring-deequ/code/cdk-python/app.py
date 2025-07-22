#!/usr/bin/env python3
"""
Real-time Data Quality Monitoring with Deequ on EMR - CDK Python Application

This CDK application deploys a comprehensive data quality monitoring solution using
Amazon Deequ on EMR with integrated CloudWatch monitoring and SNS alerting.

Architecture:
- S3 bucket for data storage and logs
- EMR cluster with Deequ for data quality analysis
- CloudWatch dashboard for metrics visualization
- SNS topic for quality alerts
- IAM roles with least privilege access
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_emr as emr,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subs,
    aws_cloudwatch as cloudwatch,
    aws_ec2 as ec2,
    aws_s3_deployment as s3_deployment,
)
from constructs import Construct
import json
from typing import Optional


class DataQualityMonitoringStack(Stack):
    """
    CDK Stack for Real-time Data Quality Monitoring with Deequ on EMR.
    
    This stack creates all the necessary infrastructure for a production-ready
    data quality monitoring solution using Amazon Deequ on EMR.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        cluster_name: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Data Quality Monitoring Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            cluster_name: Optional custom name for the EMR cluster
            notification_email: Email address for quality alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Default values
        self.cluster_name = cluster_name or f"deequ-quality-monitor-{unique_suffix}"
        self.notification_email = notification_email

        # Create core infrastructure
        self._create_s3_bucket()
        self._create_iam_roles()
        self._create_sns_topic()
        self._create_vpc()
        self._create_emr_cluster()
        self._create_cloudwatch_dashboard()
        self._deploy_scripts()
        self._create_outputs()

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for data storage, logs, and scripts."""
        self.data_bucket = s3.Bucket(
            self,
            "DataQualityBucket",
            bucket_name=f"deequ-data-quality-{self.node.addr[-8:].lower()}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    prefix="logs/",
                    expiration=Duration.days(90),
                    enabled=True
                ),
                s3.LifecycleRule(
                    id="ArchiveQualityReports",
                    prefix="quality-reports/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    enabled=True
                )
            ]
        )

        # Create folder structure
        for folder in ["raw-data/", "quality-reports/", "logs/", "scripts/"]:
            s3_deployment.BucketDeployment(
                self,
                f"Create{folder.replace('/', '').replace('-', '').title()}Folder",
                sources=[s3_deployment.Source.data(folder, "")],
                destination_bucket=self.data_bucket,
                destination_key_prefix=folder,
                retain_on_delete=False
            )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for EMR service and EC2 instances."""
        # EMR Service Role
        self.emr_service_role = iam.Role(
            self,
            "EMRServiceRole",
            role_name=f"EMR_DefaultRole_{self.node.addr[-8:]}",
            assumed_by=iam.ServicePrincipal("elasticmapreduce.amazonaws.com"),
            description="Service role for EMR cluster management",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonElasticMapReduceRole"
                )
            ]
        )

        # EMR EC2 Instance Role
        self.emr_ec2_role = iam.Role(
            self,
            "EMRInstanceRole",
            role_name=f"EMR_EC2_DefaultRole_{self.node.addr[-8:]}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Instance role for EMR EC2 instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonElasticMapReduceforEC2Role"
                )
            ]
        )

        # Add additional permissions for data quality monitoring
        self.emr_ec2_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )

        self.emr_ec2_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )

        self.emr_ec2_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish"
                ],
                resources=[f"arn:aws:sns:{self.region}:{self.account}:*"]
            )
        )

        # Create instance profile
        self.emr_instance_profile = iam.CfnInstanceProfile(
            self,
            "EMRInstanceProfile",
            instance_profile_name=f"EMR_EC2_DefaultRole_{self.node.addr[-8:]}",
            roles=[self.emr_ec2_role.role_name]
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for data quality alerts."""
        self.sns_topic = sns.Topic(
            self,
            "DataQualityAlerts",
            topic_name=f"data-quality-alerts-{self.node.addr[-8:].lower()}",
            display_name="Data Quality Monitoring Alerts",
            description="SNS topic for data quality monitoring alerts and notifications"
        )

        # Add email subscription if provided
        if self.notification_email:
            self.sns_topic.add_subscription(
                sns_subs.EmailSubscription(self.notification_email)
            )

        # Add CloudWatch Logs subscription for audit trail
        self.sns_topic.add_subscription(
            sns_subs.SqsSubscription(
                queue=None,  # Will create default queue
                raw_message_delivery=False
            )
        )

    def _create_vpc(self) -> None:
        """Create VPC for EMR cluster (uses default VPC if available)."""
        # For simplicity, use default VPC
        # In production, consider creating a custom VPC with proper subnets
        self.vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
        
        # Get default subnet
        self.subnet = self.vpc.public_subnets[0]

    def _create_emr_cluster(self) -> None:
        """Create EMR cluster with Deequ bootstrap action."""
        # Create bootstrap script content
        bootstrap_script_content = '''#!/bin/bash

# Download and install Deequ JAR
sudo mkdir -p /usr/lib/spark/jars
sudo wget -O /usr/lib/spark/jars/deequ-2.0.4-spark-3.4.jar \
    https://repo1.maven.org/maven2/com/amazon/deequ/deequ/2.0.4-spark-3.4/deequ-2.0.4-spark-3.4.jar

# Install required Python packages
sudo pip3 install boto3 pyarrow pandas numpy pydeequ

# Create directories for custom scripts
sudo mkdir -p /opt/deequ-scripts
sudo chmod 755 /opt/deequ-scripts

echo "Deequ installation completed successfully"
'''

        # Deploy bootstrap script to S3
        s3_deployment.BucketDeployment(
            self,
            "DeployBootstrapScript",
            sources=[s3_deployment.Source.data("install-deequ.sh", bootstrap_script_content)],
            destination_bucket=self.data_bucket,
            destination_key_prefix="scripts/",
            retain_on_delete=False
        )

        # EMR Cluster Configuration
        self.emr_cluster = emr.CfnCluster(
            self,
            "EMRCluster",
            name=self.cluster_name,
            release_label="emr-6.15.0",
            applications=[
                emr.CfnCluster.ApplicationProperty(name="Spark"),
                emr.CfnCluster.ApplicationProperty(name="Hadoop"),
                emr.CfnCluster.ApplicationProperty(name="Hive")
            ],
            instances=emr.CfnCluster.JobFlowInstancesConfigProperty(
                master_instance_group=emr.CfnCluster.InstanceGroupConfigProperty(
                    instance_count=1,
                    instance_type="m5.xlarge",
                    name="Master"
                ),
                core_instance_group=emr.CfnCluster.InstanceGroupConfigProperty(
                    instance_count=2,
                    instance_type="m5.xlarge",
                    name="Core"
                ),
                ec2_subnet_id=self.subnet.subnet_id,
                keep_job_flow_alive_when_no_steps=True,
                termination_protected=False
            ),
            service_role=self.emr_service_role.role_arn,
            job_flow_role=self.emr_instance_profile.instance_profile_name,
            log_uri=f"s3://{self.data_bucket.bucket_name}/logs/",
            bootstrap_actions=[
                emr.CfnCluster.BootstrapActionConfigProperty(
                    name="InstallDeequ",
                    script_bootstrap_action=emr.CfnCluster.ScriptBootstrapActionConfigProperty(
                        path=f"s3://{self.data_bucket.bucket_name}/scripts/install-deequ.sh"
                    )
                )
            ],
            configurations=[
                emr.CfnCluster.ConfigurationProperty(
                    classification="spark-defaults",
                    configuration_properties={
                        "spark.sql.adaptive.enabled": "true",
                        "spark.sql.adaptive.coalescePartitions.enabled": "true",
                        "spark.serializer": "org.apache.spark.serializer.KryoSerializer",
                        "spark.sql.adaptive.skewJoin.enabled": "true",
                        "spark.sql.adaptive.localShuffleReader.enabled": "true"
                    }
                ),
                emr.CfnCluster.ConfigurationProperty(
                    classification="spark-env",
                    configurations=[
                        emr.CfnCluster.ConfigurationProperty(
                            classification="export",
                            configuration_properties={
                                "PYSPARK_PYTHON": "/usr/bin/python3",
                                "PYSPARK_DRIVER_PYTHON": "/usr/bin/python3"
                            }
                        )
                    ]
                )
            ],
            visible_to_all_users=True,
            tags=[
                cdk.CfnTag(key="Name", value=self.cluster_name),
                cdk.CfnTag(key="Purpose", value="DataQualityMonitoring"),
                cdk.CfnTag(key="Environment", value="Development")
            ]
        )

        # Add dependency on IAM roles
        self.emr_cluster.add_dependency(self.emr_instance_profile)

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for data quality metrics."""
        self.dashboard = cloudwatch.Dashboard(
            self,
            "DataQualityDashboard",
            dashboard_name="DeeQuDataQualityMonitoring",
            period_override=cloudwatch.PeriodOverride.INHERIT,
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Data Quality Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Size",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Completeness_customer_id_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Completeness_email_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Completeness_income_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6
                    ),
                    cloudwatch.GraphWidget(
                        title="Data Distribution Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Uniqueness_customer_id_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Mean_age_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="StandardDeviation_age_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Latest Data Quality Score",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Completeness_customer_id_",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            )
                        ],
                        width=6,
                        height=3
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Records Processed",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="DataQuality/Deequ",
                                metric_name="Size",
                                dimensions_map={"DataSource": self.data_bucket.bucket_name},
                                statistic="Average"
                            )
                        ],
                        width=6,
                        height=3
                    )
                ]
            ]
        )

    def _deploy_scripts(self) -> None:
        """Deploy data quality monitoring scripts to S3."""
        # Data quality monitoring Python script
        monitoring_script_content = '''import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, lit
import boto3
import json
from datetime import datetime

# Initialize Spark session with Deequ
spark = SparkSession.builder \\
    .appName("DeeQuDataQualityMonitor") \\
    .config("spark.jars.packages", "com.amazon.deequ:deequ:2.0.4-spark-3.4") \\
    .getOrCreate()

# Import Deequ classes
from pydeequ.analyzers import *
from pydeequ.checks import *
from pydeequ.verification import *
from pydeequ.suggestions import *

def publish_metrics_to_cloudwatch(metrics, bucket_name):
    """Publish data quality metrics to CloudWatch"""
    cloudwatch = boto3.client('cloudwatch')
    
    for metric_name, metric_value in metrics.items():
        cloudwatch.put_metric_data(
            Namespace='DataQuality/Deequ',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': metric_value,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DataSource',
                            'Value': bucket_name
                        }
                    ]
                }
            ]
        )

def send_alert_if_needed(verification_result, sns_topic_arn):
    """Send SNS alert if data quality issues are found"""
    failed_checks = []
    
    for check_result in verification_result.checkResults:
        if check_result.status != CheckStatus.Success:
            failed_checks.append({
                'check': str(check_result.check),
                'status': str(check_result.status),
                'constraint': str(check_result.constraint)
            })
    
    if failed_checks:
        sns = boto3.client('sns')
        message = {
            'timestamp': datetime.now().isoformat(),
            'alert_type': 'DATA_QUALITY_FAILURE',
            'failed_checks': failed_checks,
            'total_failed_checks': len(failed_checks)
        }
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(message, indent=2),
            Subject='Data Quality Alert - Issues Detected'
        )

def main():
    # Get parameters
    if len(sys.argv) != 4:
        print("Usage: deequ-quality-monitor.py <s3_bucket> <data_path> <sns_topic_arn>")
        sys.exit(1)
    
    s3_bucket = sys.argv[1]
    data_path = sys.argv[2]
    sns_topic_arn = sys.argv[3]
    
    # Read data
    df = spark.read.option("header", "true").option("inferSchema", "true").csv(data_path)
    
    print(f"Processing {df.count()} records from {data_path}")
    
    # Define data quality checks
    verification_result = VerificationSuite(spark) \\
        .onData(df) \\
        .addCheck(
            Check(spark, CheckLevel.Error, "Customer Data Quality Checks")
            .hasSize(lambda x: x > 0)  # Non-empty dataset
            .isComplete("customer_id")  # No null customer IDs
            .isUnique("customer_id")   # Unique customer IDs
            .isComplete("email")       # No null emails
            .containsEmail("email")    # Valid email format
            .isNonNegative("age")      # Age must be non-negative
            .isContainedIn("region", ["US", "EU", "APAC"])  # Valid regions
            .hasCompleteness("income", lambda x: x > 0.9)  # At least 90% income data
        ) \\
        .run()
    
    # Run analysis for detailed metrics
    analysis_result = AnalysisRunner(spark) \\
        .onData(df) \\
        .addAnalyzer(Size()) \\
        .addAnalyzer(Completeness("customer_id")) \\
        .addAnalyzer(Completeness("email")) \\
        .addAnalyzer(Completeness("income")) \\
        .addAnalyzer(Uniqueness("customer_id")) \\
        .addAnalyzer(Mean("age")) \\
        .addAnalyzer(StandardDeviation("age")) \\
        .addAnalyzer(CountDistinct("region")) \\
        .run()
    
    # Extract metrics
    metrics = {}
    for analyzer_name, analyzer_result in analysis_result.analyzerContext.metricMap.items():
        if analyzer_result.value.isSuccess():
            metric_name = str(analyzer_name).replace(":", "_").replace("(", "_").replace(")", "_")
            metrics[metric_name] = analyzer_result.value.get()
    
    # Publish metrics to CloudWatch
    publish_metrics_to_cloudwatch(metrics, s3_bucket)
    
    # Send alerts if needed
    send_alert_if_needed(verification_result, sns_topic_arn)
    
    # Save detailed results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Save verification results
    verification_df = VerificationResult.checkResultsAsDataFrame(spark, verification_result)
    verification_df.write.mode("overwrite").json(f"s3://{s3_bucket}/quality-reports/verification_{timestamp}")
    
    # Save analysis results
    analysis_df = AnalysisResult.successMetricsAsDataFrame(spark, analysis_result)
    analysis_df.write.mode("overwrite").json(f"s3://{s3_bucket}/quality-reports/analysis_{timestamp}")
    
    print("✅ Data quality monitoring completed successfully")
    print(f"Metrics published to CloudWatch namespace: DataQuality/Deequ")
    print(f"Reports saved to: s3://{s3_bucket}/quality-reports/")
    
    # Print summary
    print("\\n=== VERIFICATION RESULTS ===")
    verification_df.show(truncate=False)
    
    print("\\n=== ANALYSIS RESULTS ===")
    analysis_df.show(truncate=False)

if __name__ == "__main__":
    main()
'''

        # Deploy monitoring script
        s3_deployment.BucketDeployment(
            self,
            "DeployMonitoringScript",
            sources=[s3_deployment.Source.data("deequ-quality-monitor.py", monitoring_script_content)],
            destination_bucket=self.data_bucket,
            destination_key_prefix="scripts/",
            retain_on_delete=False
        )

        # Sample data generation script
        sample_data_script = '''import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta

# Generate sample customer data with intentional quality issues
np.random.seed(42)
num_records = 10000

# Create base dataset
data = {
    'customer_id': range(1, num_records + 1),
    'email': [f'user{i}@example.com' for i in range(1, num_records + 1)],
    'age': np.random.randint(18, 80, num_records),
    'income': np.random.normal(50000, 20000, num_records),
    'region': np.random.choice(['US', 'EU', 'APAC'], num_records),
    'signup_date': [datetime.now() - timedelta(days=random.randint(1, 365)) 
                   for _ in range(num_records)]
}

# Introduce quality issues
# 1. Missing values in income
missing_indices = np.random.choice(num_records, size=int(num_records * 0.05), replace=False)
for idx in missing_indices:
    data['income'][idx] = None

# 2. Invalid email formats
invalid_email_indices = np.random.choice(num_records, size=int(num_records * 0.02), replace=False)
for idx in invalid_email_indices:
    data['email'][idx] = f'invalid-email-{idx}'

# 3. Negative ages
negative_age_indices = np.random.choice(num_records, size=int(num_records * 0.01), replace=False)
for idx in negative_age_indices:
    data['age'][idx] = -abs(data['age'][idx])

# 4. Duplicate customer IDs
duplicate_indices = np.random.choice(num_records, size=int(num_records * 0.03), replace=False)
for idx in duplicate_indices:
    data['customer_id'][idx] = data['customer_id'][idx - 1]

# Convert to DataFrame and save
df = pd.DataFrame(data)
df.to_csv('/tmp/sample_customer_data.csv', index=False)
print(f"Generated {len(df)} customer records with quality issues")
'''

        # Deploy sample data script
        s3_deployment.BucketDeployment(
            self,
            "DeploySampleDataScript",
            sources=[s3_deployment.Source.data("generate-sample-data.py", sample_data_script)],
            destination_bucket=self.data_bucket,
            destination_key_prefix="scripts/",
            retain_on_delete=False
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "S3BucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for data storage and logs",
            export_name=f"{self.stack_name}-S3BucketName"
        )

        CfnOutput(
            self,
            "EMRClusterID",
            value=self.emr_cluster.ref,
            description="EMR cluster ID for data processing",
            export_name=f"{self.stack_name}-EMRClusterID"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for data quality alerts",
            export_name=f"{self.stack_name}-SNSTopicArn"
        )

        CfnOutput(
            self,
            "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=DeeQuDataQualityMonitoring",
            description="CloudWatch dashboard URL for data quality metrics",
            export_name=f"{self.stack_name}-DashboardURL"
        )

        CfnOutput(
            self,
            "EMRClusterName",
            value=self.cluster_name,
            description="EMR cluster name",
            export_name=f"{self.stack_name}-EMRClusterName"
        )


class DataQualityMonitoringApp(cdk.App):
    """CDK Application for Data Quality Monitoring solution."""

    def __init__(self) -> None:
        super().__init__()

        # Get context values
        cluster_name = self.node.try_get_context("cluster_name")
        notification_email = self.node.try_get_context("notification_email")
        environment_name = self.node.try_get_context("environment") or "dev"

        # Create the stack
        DataQualityMonitoringStack(
            self,
            f"DataQualityMonitoring-{environment_name}",
            cluster_name=cluster_name,
            notification_email=notification_email,
            env=Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region") or "us-east-1"
            ),
            description="Real-time Data Quality Monitoring with Deequ on EMR - CDK Python Stack",
            tags={
                "Project": "DataQualityMonitoring",
                "Environment": environment_name,
                "Owner": "DataEngineering",
                "CostCenter": "Analytics",
                "ManagedBy": "CDK"
            }
        )


# Create the CDK application
app = DataQualityMonitoringApp()

# Synthesize the CloudFormation template
app.synth()