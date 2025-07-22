#!/usr/bin/env python3
"""
AWS CDK Python Application for Mobile Push Notifications with Pinpoint
Recipe: Pinpoint Mobile Push Notifications

This CDK application creates the infrastructure for a mobile push notification
system using AWS End User Messaging Push (formerly Amazon Pinpoint) with
support for both iOS (APNs) and Android (FCM) platforms.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_pinpoint as pinpoint,
    aws_iam as iam,
    aws_kinesis as kinesis,
    aws_cloudwatch as cloudwatch,
    Duration,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct
from typing import Dict, Any, Optional


class MobilePushNotificationStack(Stack):
    """
    CDK Stack for Mobile Push Notifications with Pinpoint
    
    This stack creates:
    - Pinpoint Application for mobile engagement
    - IAM roles for Pinpoint service
    - Kinesis stream for event analytics
    - CloudWatch alarms for monitoring
    - Sample endpoints and segments for testing
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str,
        app_name: str = "ecommerce-mobile-app",
        enable_event_streaming: bool = True,
        enable_monitoring: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Mobile Push Notification Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            app_name: Name for the Pinpoint application
            enable_event_streaming: Whether to enable event streaming to Kinesis
            enable_monitoring: Whether to create CloudWatch alarms
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.app_name = app_name
        self.enable_event_streaming = enable_event_streaming
        self.enable_monitoring = enable_monitoring

        # Create IAM role for Pinpoint service
        self.pinpoint_service_role = self._create_pinpoint_service_role()

        # Create Pinpoint application
        self.pinpoint_app = self._create_pinpoint_application()

        # Create event streaming infrastructure (optional)
        if self.enable_event_streaming:
            self.kinesis_stream = self._create_kinesis_stream()
            self._configure_event_streaming()

        # Create CloudWatch monitoring (optional)
        if self.enable_monitoring:
            self._create_cloudwatch_alarms()

        # Create sample endpoints for testing
        self._create_sample_endpoints()

        # Create user segment for targeting
        self.user_segment = self._create_user_segment()

        # Create push notification template
        self.push_template = self._create_push_template()

        # Output important values
        self._create_outputs()

    def _create_pinpoint_service_role(self) -> iam.Role:
        """
        Create IAM role for Pinpoint service with necessary permissions
        
        Returns:
            IAM Role for Pinpoint service
        """
        role = iam.Role(
            self,
            "PinpointServiceRole",
            assumed_by=iam.ServicePrincipal("pinpoint.amazonaws.com"),
            description="IAM role for Pinpoint service to access required AWS services",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonPinpointServiceRole"
                )
            ],
        )

        # Add additional permissions for Kinesis streaming if enabled
        if self.enable_event_streaming:
            role.add_to_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "kinesis:PutRecord",
                        "kinesis:PutRecords",
                        "kinesis:DescribeStream",
                    ],
                    resources=[f"arn:aws:kinesis:{self.region}:{self.account}:stream/pinpoint-events-*"],
                )
            )

        return role

    def _create_pinpoint_application(self) -> pinpoint.CfnApp:
        """
        Create Pinpoint application for mobile engagement
        
        Returns:
            Pinpoint Application construct
        """
        app = pinpoint.CfnApp(
            self,
            "PinpointApp",
            name=self.app_name,
            tags={
                "Purpose": "Mobile Push Notifications",
                "Environment": "Development",
                "Recipe": "mobile-push-notifications-pinpoint",
            },
        )

        return app

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis stream for Pinpoint event analytics
        
        Returns:
            Kinesis Stream for event data
        """
        stream = kinesis.Stream(
            self,
            "PinpointEventsStream",
            stream_name=f"pinpoint-events-{self.app_name}",
            shard_count=1,
            retention_period=Duration.days(7),
            removal_policy=RemovalPolicy.DESTROY,
        )

        return stream

    def _configure_event_streaming(self) -> None:
        """Configure Pinpoint event streaming to Kinesis"""
        if hasattr(self, 'kinesis_stream'):
            pinpoint.CfnEventStream(
                self,
                "PinpointEventStream",
                application_id=self.pinpoint_app.ref,
                destination_stream_arn=self.kinesis_stream.stream_arn,
                role_arn=self.pinpoint_service_role.role_arn,
            )

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring push notification performance"""
        
        # Alarm for push notification failures
        cloudwatch.Alarm(
            self,
            "PushNotificationFailures",
            alarm_name=f"PinpointPushFailures-{self.app_name}",
            alarm_description="Alert when push notification failures exceed threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/Pinpoint",
                metric_name="DirectSendMessagePermanentFailure",
                dimensions_map={"ApplicationId": self.pinpoint_app.ref},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Alarm for delivery rate
        cloudwatch.Alarm(
            self,
            "PushDeliveryRate",
            alarm_name=f"PinpointDeliveryRate-{self.app_name}",
            alarm_description="Alert when delivery rate falls below 90%",
            metric=cloudwatch.Metric(
                namespace="AWS/Pinpoint",
                metric_name="DirectSendMessageDeliveryRate",
                dimensions_map={"ApplicationId": self.pinpoint_app.ref},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=0.9,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_sample_endpoints(self) -> None:
        """Create sample endpoints for testing push notifications"""
        
        # iOS endpoint
        pinpoint.CfnApplicationSettings(
            self,
            "iOSEndpoint",
            application_id=self.pinpoint_app.ref,
            campaign_hook={
                "lambda_function_name": "pinpoint-campaign-hook",
                "mode": "DELIVERY",
            } if False else None,  # Disabled by default
        )

        # Note: Actual endpoints are typically created by the mobile application
        # This is a placeholder to show the structure

    def _create_user_segment(self) -> pinpoint.CfnSegment:
        """
        Create user segment for targeted campaigns
        
        Returns:
            Pinpoint Segment for high-value customers
        """
        segment = pinpoint.CfnSegment(
            self,
            "HighValueCustomersSegment",
            application_id=self.pinpoint_app.ref,
            name="high-value-customers",
            dimensions={
                "UserAttributes": {
                    "PurchaseHistory": {
                        "AttributeType": "INCLUSIVE",
                        "Values": ["high-value"],
                    }
                },
                "Demographic": {
                    "Platform": {
                        "DimensionType": "INCLUSIVE",
                        "Values": ["iOS", "Android"],
                    }
                },
            },
        )

        return segment

    def _create_push_template(self) -> pinpoint.CfnPushTemplate:
        """
        Create reusable push notification template
        
        Returns:
            Pinpoint Push Template
        """
        template = pinpoint.CfnPushTemplate(
            self,
            "FlashSaleTemplate",
            template_name="flash-sale-template",
            template_description="Template for flash sale notifications",
            adm={
                "action": "OPEN_APP",
                "body": "Don't miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
                "title": "🔥 Flash Sale Alert",
                "sound": "default",
            },
            apns={
                "action": "OPEN_APP",
                "body": "Don't miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
                "title": "🔥 Flash Sale Alert",
                "sound": "default",
            },
            gcm={
                "action": "OPEN_APP",
                "body": "Don't miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
                "title": "🔥 Flash Sale Alert",
                "sound": "default",
            },
            default={
                "action": "OPEN_APP",
                "body": "Don't miss out! Exclusive flash sale ends in 2 hours!",
                "title": "🔥 Flash Sale Alert",
            },
            tags={
                "Purpose": "Marketing",
                "Campaign": "Flash Sale",
                "Template": "Reusable",
            },
        )

        return template

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers"""
        
        CfnOutput(
            self,
            "PinpointApplicationId",
            value=self.pinpoint_app.ref,
            description="Pinpoint Application ID for mobile push notifications",
            export_name=f"{self.stack_name}-PinpointAppId",
        )

        CfnOutput(
            self,
            "PinpointApplicationName",
            value=self.app_name,
            description="Pinpoint Application Name",
            export_name=f"{self.stack_name}-PinpointAppName",
        )

        CfnOutput(
            self,
            "ServiceRoleArn",
            value=self.pinpoint_service_role.role_arn,
            description="IAM Role ARN for Pinpoint service",
            export_name=f"{self.stack_name}-ServiceRoleArn",
        )

        if self.enable_event_streaming and hasattr(self, 'kinesis_stream'):
            CfnOutput(
                self,
                "EventStreamArn",
                value=self.kinesis_stream.stream_arn,
                description="Kinesis Stream ARN for Pinpoint events",
                export_name=f"{self.stack_name}-EventStreamArn",
            )

        CfnOutput(
            self,
            "UserSegmentId",
            value=self.user_segment.ref,
            description="User Segment ID for high-value customers",
            export_name=f"{self.stack_name}-UserSegmentId",
        )

        CfnOutput(
            self,
            "PushTemplateName",
            value=self.push_template.template_name,
            description="Push notification template name",
            export_name=f"{self.stack_name}-PushTemplateName",
        )


class MobilePushNotificationApp(cdk.App):
    """
    CDK Application for Mobile Push Notifications
    
    This application creates the complete infrastructure needed for mobile
    push notifications using AWS End User Messaging Push (Pinpoint).
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from CDK context or environment
        app_name = self.node.try_get_context("app_name") or "ecommerce-mobile-app"
        environment = self.node.try_get_context("environment") or "development"
        enable_event_streaming = self.node.try_get_context("enable_event_streaming") != False
        enable_monitoring = self.node.try_get_context("enable_monitoring") != False

        # Create the stack
        MobilePushNotificationStack(
            self,
            f"MobilePushNotificationStack-{environment}",
            app_name=f"{app_name}-{environment}",
            enable_event_streaming=enable_event_streaming,
            enable_monitoring=enable_monitoring,
            description="Infrastructure for mobile push notifications with AWS Pinpoint",
            tags={
                "Recipe": "mobile-push-notifications-pinpoint",
                "Environment": environment,
                "Purpose": "Mobile Engagement",
            },
        )


def main() -> None:
    """Main entry point for the CDK application"""
    app = MobilePushNotificationApp()
    app.synth()


if __name__ == "__main__":
    main()