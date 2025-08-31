#!/usr/bin/env python3
"""
CDK Python application for Website Monitoring with CloudWatch Synthetics.

This application creates a complete website monitoring solution using:
- CloudWatch Synthetics canary for automated testing
- S3 bucket for storing canary artifacts
- CloudWatch alarms for failure detection
- SNS topic for notifications
- CloudWatch dashboard for visualization

Author: Recipe Generator v1.3
Last Updated: 2025-07-12
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_iam as iam,
    aws_synthetics as synthetics,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)
from constructs import Construct


class WebsiteMonitoringStack(Stack):
    """
    CDK Stack for Website Monitoring with CloudWatch Synthetics.
    
    This stack creates a comprehensive website monitoring solution that:
    - Monitors website availability and performance using synthetic canaries
    - Stores monitoring artifacts in S3 with lifecycle management
    - Provides automated alerting through CloudWatch alarms and SNS
    - Creates a dashboard for visualizing monitoring metrics
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        website_url: str = "https://example.com",
        notification_email: str = "admin@example.com",
        canary_name: str = "website-monitor",
        monitoring_frequency: int = 5,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Website Monitoring Stack.
        
        Args:
            scope: CDK app scope
            construct_id: Unique identifier for this stack
            website_url: URL to monitor (default: https://example.com)
            notification_email: Email for alert notifications
            canary_name: Name for the synthetics canary
            monitoring_frequency: Monitoring frequency in minutes (default: 5)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = cdk.Names.unique_id(self)[:6].lower()
        
        # Store configuration parameters
        self.website_url = website_url
        self.notification_email = notification_email
        self.canary_name = f"{canary_name}-{unique_suffix}"
        self.monitoring_frequency = monitoring_frequency

        # Create resources
        self.artifacts_bucket = self._create_artifacts_bucket(unique_suffix)
        self.canary_role = self._create_canary_execution_role(unique_suffix)
        self.synthetics_canary = self._create_synthetics_canary()
        self.sns_topic = self._create_sns_topic(unique_suffix)
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()
        self.monitoring_dashboard = self._create_monitoring_dashboard(unique_suffix)

        # Create stack outputs
        self._create_outputs()

    def _create_artifacts_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing canary artifacts.
        
        The bucket includes versioning, lifecycle management, and proper
        security configurations for storing synthetic monitoring artifacts.
        
        Args:
            unique_suffix: Unique identifier for bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "SyntheticsArtifactsBucket",
            bucket_name=f"synthetics-artifacts-{unique_suffix}",
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="SyntheticsArtifactRetention",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ],
                    expiration=Duration.days(90)
                )
            ],
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
        )

        # Add tags for resource management
        cdk.Tags.of(bucket).add("Purpose", "SyntheticsMonitoring")
        cdk.Tags.of(bucket).add("Environment", "Production")
        cdk.Tags.of(bucket).add("CreatedBy", "CDKPython")

        return bucket

    def _create_canary_execution_role(self, unique_suffix: str) -> iam.Role:
        """
        Create IAM role for Synthetics canary execution.
        
        The role provides necessary permissions for canary execution while
        following the principle of least privilege.
        
        Args:
            unique_suffix: Unique identifier for role naming
            
        Returns:
            IAM Role construct
        """
        canary_role = iam.Role(
            self,
            "SyntheticsCanaryExecutionRole",
            role_name=f"SyntheticsCanaryRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for CloudWatch Synthetics canary",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchSyntheticsExecutionRolePolicy"
                )
            ]
        )

        # Grant additional permissions for S3 artifact storage
        self.artifacts_bucket.grant_read_write(canary_role)

        # Add tags for resource management
        cdk.Tags.of(canary_role).add("Purpose", "SyntheticsExecution")
        cdk.Tags.of(canary_role).add("Environment", "Production")

        return canary_role

    def _create_synthetics_canary(self) -> synthetics.Canary:
        """
        Create CloudWatch Synthetics canary for website monitoring.
        
        The canary runs automated tests against the target website using
        Puppeteer browser automation to simulate real user interactions.
        
        Returns:
            CloudWatch Synthetics Canary construct
        """
        # Define the canary script for website monitoring
        canary_script = '''
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const checkWebsite = async function () {
    let page = await synthetics.getPage();
    
    // Navigate to website with performance monitoring
    const response = await synthetics.executeStepFunction('loadHomepage', async function () {
        return await page.goto(synthetics.getConfiguration().getUrl(), {
            waitUntil: 'networkidle0',
            timeout: 30000
        });
    });
    
    // Verify successful response
    if (response.status() < 200 || response.status() > 299) {
        throw new Error(`Failed to load page: ${response.status()}`);
    }
    
    // Check for critical page elements
    await synthetics.executeStepFunction('verifyPageElements', async function () {
        await page.waitForSelector('body', { timeout: 10000 });
        
        // Verify page title exists
        const title = await page.title();
        if (!title || title.length === 0) {
            throw new Error('Page title is missing');
        }
        
        log.info(`Page title: ${title}`);
        
        // Check for JavaScript errors
        const errors = await page.evaluate(() => {
            return window.console.errors || [];
        });
        
        if (errors.length > 0) {
            log.warn(`JavaScript errors detected: ${errors.length}`);
        }
    });
    
    // Capture performance metrics
    await synthetics.executeStepFunction('captureMetrics', async function () {
        const metrics = await page.evaluate(() => {
            const navigation = performance.getEntriesByType('navigation')[0];
            return {
                loadTime: navigation.loadEventEnd - navigation.loadEventStart,
                domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
                responseTime: navigation.responseEnd - navigation.requestStart
            };
        });
        
        // Log custom metrics
        log.info(`Load time: ${metrics.loadTime}ms`);
        log.info(`DOM content loaded: ${metrics.domContentLoaded}ms`);
        log.info(`Response time: ${metrics.responseTime}ms`);
        
        // Set custom CloudWatch metrics
        await synthetics.addUserAgentMetric('LoadTime', metrics.loadTime, 'Milliseconds');
        await synthetics.addUserAgentMetric('ResponseTime', metrics.responseTime, 'Milliseconds');
    });
};

exports.handler = async () => {
    return await synthetics.executeStep('checkWebsite', checkWebsite);
};
        '''

        canary = synthetics.Canary(
            self,
            "WebsiteMonitoringCanary",
            canary_name=self.canary_name,
            runtime=synthetics.Runtime.SYNTHETICS_NODEJS_PUPPETEER_10_0,
            test=synthetics.Test.custom(
                code=synthetics.Code.from_inline(canary_script),
                handler="index.handler"
            ),
            schedule=synthetics.Schedule.rate(Duration.minutes(self.monitoring_frequency)),
            environment_variables={
                "URL": self.website_url
            },
            role=self.canary_role,
            artifacts_bucket_location=synthetics.ArtifactsBucketLocation.from_bucket(
                bucket=self.artifacts_bucket,
                prefix="canary-artifacts"
            ),
            timeout=Duration.seconds(60),
            memory_size=960,
            success_retention_period=Duration.days(31),
            failure_retention_period=Duration.days(31),
            start_after_creation=True
        )

        # Add tags for resource management
        cdk.Tags.of(canary).add("Purpose", "WebsiteMonitoring")
        cdk.Tags.of(canary).add("Environment", "Production")
        cdk.Tags.of(canary).add("MonitoredURL", self.website_url)

        return canary

    def _create_sns_topic(self, unique_suffix: str) -> sns.Topic:
        """
        Create SNS topic for monitoring notifications.
        
        The topic provides a centralized notification mechanism for
        monitoring alerts and can support multiple subscription types.
        
        Args:
            unique_suffix: Unique identifier for topic naming
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self,
            "SyntheticsAlertsTopic",
            topic_name=f"synthetics-alerts-{unique_suffix}",
            display_name="Website Monitoring Alerts",
            description="Notifications for website monitoring alerts and failures"
        )

        # Add email subscription for notifications
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )

        # Add tags for resource management
        cdk.Tags.of(topic).add("Purpose", "MonitoringAlerts")
        cdk.Tags.of(topic).add("Environment", "Production")

        return topic

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for monitoring website health.
        
        Creates alarms for both availability failures and performance
        degradation to provide comprehensive monitoring coverage.
        
        Returns:
            Dictionary of CloudWatch Alarm constructs
        """
        alarms = {}

        # Create alarm for canary failures
        failure_alarm = cloudwatch.Alarm(
            self,
            "CanaryFailureAlarm",
            alarm_name=f"{self.canary_name}-FailureAlarm",
            alarm_description="Alert when website monitoring canary fails",
            metric=cloudwatch.Metric(
                namespace="CloudWatchSynthetics",
                metric_name="SuccessPercent",
                dimensions_map={"CanaryName": self.canary_name},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=90,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        # Add SNS notification to failure alarm
        failure_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )

        alarms["failure"] = failure_alarm

        # Create alarm for high response times
        response_time_alarm = cloudwatch.Alarm(
            self,
            "CanaryResponseTimeAlarm",
            alarm_name=f"{self.canary_name}-ResponseTimeAlarm",
            alarm_description="Alert when website response time is high",
            metric=cloudwatch.Metric(
                namespace="CloudWatchSynthetics",
                metric_name="Duration",
                dimensions_map={"CanaryName": self.canary_name},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=10000,  # 10 seconds in milliseconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS notification to response time alarm
        response_time_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )

        alarms["response_time"] = response_time_alarm

        return alarms

    def _create_monitoring_dashboard(self, unique_suffix: str) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring visualization.
        
        The dashboard provides comprehensive visibility into website
        performance trends and monitoring metrics.
        
        Args:
            unique_suffix: Unique identifier for dashboard naming
            
        Returns:
            CloudWatch Dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "WebsiteMonitoringDashboard",
            dashboard_name=f"Website-Monitoring-{unique_suffix}",
            widgets=[
                [
                    # Success rate and duration metrics
                    cloudwatch.GraphWidget(
                        title="Website Monitoring Overview",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="CloudWatchSynthetics",
                                metric_name="SuccessPercent",
                                dimensions_map={"CanaryName": self.canary_name},
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Success Rate (%)"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="CloudWatchSynthetics",
                                metric_name="Duration",
                                dimensions_map={"CanaryName": self.canary_name},
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Duration (ms)"
                            )
                        ],
                        left_y_axis=cloudwatch.YAxisProps(min=0, max=100),
                        right_y_axis=cloudwatch.YAxisProps(min=0)
                    ),
                    
                    # Test results (passed/failed)
                    cloudwatch.GraphWidget(
                        title="Test Results",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="CloudWatchSynthetics",
                                metric_name="Failed",
                                dimensions_map={"CanaryName": self.canary_name},
                                statistic="Sum",
                                period=Duration.minutes(5),
                                label="Failed Tests",
                                color=cloudwatch.Color.RED
                            ),
                            cloudwatch.Metric(
                                namespace="CloudWatchSynthetics",
                                metric_name="Passed",
                                dimensions_map={"CanaryName": self.canary_name},
                                statistic="Sum",
                                period=Duration.minutes(5),
                                label="Passed Tests",
                                color=cloudwatch.Color.GREEN
                            )
                        ],
                        left_y_axis=cloudwatch.YAxisProps(min=0)
                    )
                ]
            ]
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "CanaryName",
            value=self.synthetics_canary.canary_name,
            description="Name of the CloudWatch Synthetics canary"
        )

        CfnOutput(
            self,
            "ArtifactsBucketName",
            value=self.artifacts_bucket.bucket_name,
            description="S3 bucket name for canary artifacts"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for monitoring notifications"
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.monitoring_dashboard.dashboard_name}",
            description="URL to the CloudWatch monitoring dashboard"
        )

        CfnOutput(
            self,
            "MonitoredWebsiteURL",
            value=self.website_url,
            description="Website URL being monitored"
        )


# Import the missing CloudWatch actions module
from aws_cdk import aws_cloudwatch_actions as cloudwatch_actions


def main() -> None:
    """
    Main application entry point.
    
    Creates the CDK application and deploys the website monitoring stack
    with configuration from environment variables or defaults.
    """
    app = cdk.App()

    # Get configuration from context or environment variables
    website_url = app.node.try_get_context("websiteUrl") or os.environ.get("WEBSITE_URL", "https://example.com")
    notification_email = app.node.try_get_context("notificationEmail") or os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")
    canary_name = app.node.try_get_context("canaryName") or os.environ.get("CANARY_NAME", "website-monitor")
    monitoring_frequency = int(app.node.try_get_context("monitoringFrequency") or os.environ.get("MONITORING_FREQUENCY", "5"))

    # Create the monitoring stack
    WebsiteMonitoringStack(
        app,
        "WebsiteMonitoringStack",
        website_url=website_url,
        notification_email=notification_email,
        canary_name=canary_name,
        monitoring_frequency=monitoring_frequency,
        description="Website monitoring solution using CloudWatch Synthetics",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
    )

    # Add application-level tags
    cdk.Tags.of(app).add("Project", "WebsiteMonitoring")
    cdk.Tags.of(app).add("Framework", "CDKPython")
    cdk.Tags.of(app).add("RecipeVersion", "1.1")

    app.synth()


if __name__ == "__main__":
    main()