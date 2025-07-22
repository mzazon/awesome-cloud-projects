#!/usr/bin/env python3
"""
CDK Python application for Website Uptime Monitoring with Route 53 Health Checks.

This application creates:
- Route 53 health check for website monitoring
- CloudWatch alarm for health check failures
- SNS topic for email notifications
- CloudWatch dashboard for visualization
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Tags,
    aws_route53 as route53,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)
from constructs import Construct


class WebsiteUptimeMonitoringStack(Stack):
    """
    CDK Stack for Website Uptime Monitoring with Route 53 Health Checks.
    
    This stack creates a comprehensive uptime monitoring solution using:
    - Route 53 health checks for global monitoring
    - CloudWatch alarms for automated alerting
    - SNS for email notifications
    - CloudWatch dashboard for visualization
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        website_url: str,
        monitor_email: str,
        health_check_interval: int = 30,
        failure_threshold: int = 3,
        **kwargs
    ) -> None:
        """
        Initialize the Website Uptime Monitoring Stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            website_url: The website URL to monitor (e.g., https://example.com)
            monitor_email: Email address for notifications
            health_check_interval: Health check interval in seconds (30 or 10)
            failure_threshold: Number of consecutive failures before marking unhealthy
            **kwargs: Additional arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Parse the website URL to extract components
        website_parts = self._parse_website_url(website_url)
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic(monitor_email)
        
        # Create Route 53 health check
        self.health_check = self._create_health_check(
            website_parts, health_check_interval, failure_threshold
        )
        
        # Create CloudWatch alarm
        self.alarm = self._create_cloudwatch_alarm()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_dashboard()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs
        self._create_outputs(website_url, monitor_email)

    def _parse_website_url(self, website_url: str) -> Dict[str, Any]:
        """
        Parse website URL into components needed for health check.
        
        Args:
            website_url: The complete website URL
            
        Returns:
            Dictionary containing domain, path, port, and protocol
        """
        # Simple URL parsing - in production, consider using urllib.parse
        if website_url.startswith("https://"):
            protocol = "HTTPS"
            port = 443
            domain_and_path = website_url[8:]  # Remove https://
        elif website_url.startswith("http://"):
            protocol = "HTTP"
            port = 80
            domain_and_path = website_url[7:]  # Remove http://
        else:
            # Default to HTTPS if no protocol specified
            protocol = "HTTPS"
            port = 443
            domain_and_path = website_url

        # Split domain and path
        if "/" in domain_and_path:
            domain, path = domain_and_path.split("/", 1)
            path = "/" + path
        else:
            domain = domain_and_path
            path = "/"

        return {
            "domain": domain,
            "path": path,
            "port": port,
            "protocol": protocol
        }

    def _create_notification_topic(self, monitor_email: str) -> sns.Topic:
        """
        Create SNS topic for email notifications.
        
        Args:
            monitor_email: Email address for notifications
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self,
            "UptimeAlertsTopic",
            display_name="Website Uptime Alerts",
            topic_name=f"website-uptime-alerts-{self.node.addr[:8]}"
        )

        # Add email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(monitor_email)
        )

        return topic

    def _create_health_check(
        self,
        website_parts: Dict[str, Any],
        interval: int,
        failure_threshold: int
    ) -> route53.CfnHealthCheck:
        """
        Create Route 53 health check.
        
        Args:
            website_parts: Parsed website URL components
            interval: Health check interval in seconds
            failure_threshold: Number of failures before marking unhealthy
            
        Returns:
            Route 53 CfnHealthCheck construct
        """
        # Create health check configuration
        health_check_config = route53.CfnHealthCheck.HealthCheckConfigProperty(
            type=website_parts["protocol"],
            fully_qualified_domain_name=website_parts["domain"],
            resource_path=website_parts["path"],
            port=website_parts["port"],
            request_interval=interval,
            failure_threshold=failure_threshold,
            measure_latency=True,
            enable_sni=True if website_parts["protocol"] == "HTTPS" else False
        )

        # Create the health check
        health_check = route53.CfnHealthCheck(
            self,
            "WebsiteHealthCheck",
            type=website_parts["protocol"],
            health_check_config=health_check_config,
            health_check_tags=[
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Name",
                    value=f"website-uptime-{self.node.addr[:8]}"
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Purpose",
                    value="UptimeMonitoring"
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Environment",
                    value="Production"
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Owner",
                    value="DevOps"
                )
            ]
        )

        return health_check

    def _create_cloudwatch_alarm(self) -> cloudwatch.Alarm:
        """
        Create CloudWatch alarm for health check failures.
        
        Returns:
            CloudWatch Alarm construct
        """
        # Create metric for health check status
        health_check_metric = cloudwatch.Metric(
            namespace="AWS/Route53",
            metric_name="HealthCheckStatus",
            dimensions_map={
                "HealthCheckId": self.health_check.attr_health_check_id
            },
            statistic="Minimum",
            period=cdk.Duration.minutes(1)
        )

        # Create alarm
        alarm = cloudwatch.Alarm(
            self,
            "WebsiteDownAlarm",
            alarm_name=f"website-down-{self.node.addr[:8]}",
            alarm_description="Alert when website is down",
            metric=health_check_metric,
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        # Add SNS action for both alarm and OK states
        alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        alarm.add_ok_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

        return alarm

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for visualization.
        
        Returns:
            CloudWatch Dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "UptimeDashboard",
            dashboard_name=f"website-uptime-dashboard-{self.node.addr[:8]}"
        )

        # Health status widget
        health_status_widget = cloudwatch.GraphWidget(
            title="Website Health Status",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Route53",
                    metric_name="HealthCheckStatus",
                    dimensions_map={
                        "HealthCheckId": self.health_check.attr_health_check_id
                    },
                    statistic="Average",
                    period=cdk.Duration.minutes(5)
                )
            ],
            left_y_axis=cloudwatch.YAxisProps(min=0, max=1)
        )

        # Health percentage widget
        health_percentage_widget = cloudwatch.GraphWidget(
            title="Health Check Percentage",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Route53",
                    metric_name="HealthCheckPercentHealthy",
                    dimensions_map={
                        "HealthCheckId": self.health_check.attr_health_check_id
                    },
                    statistic="Average",
                    period=cdk.Duration.minutes(5)
                )
            ],
            left_y_axis=cloudwatch.YAxisProps(min=0, max=100)
        )

        # Connection time widget (if latency is enabled)
        connection_time_widget = cloudwatch.GraphWidget(
            title="Connection Time (ms)",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Route53",
                    metric_name="ConnectionTime",
                    dimensions_map={
                        "HealthCheckId": self.health_check.attr_health_check_id
                    },
                    statistic="Average",
                    period=cdk.Duration.minutes(5)
                )
            ]
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            health_status_widget,
            health_percentage_widget
        )
        dashboard.add_widgets(connection_time_widget)

        return dashboard

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", "WebsiteUptimeMonitoring")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "DevOps")
        Tags.of(self).add("Purpose", "UptimeMonitoring")

    def _create_outputs(self, website_url: str, monitor_email: str) -> None:
        """
        Create CloudFormation outputs.
        
        Args:
            website_url: The monitored website URL
            monitor_email: Email address for notifications
        """
        CfnOutput(
            self,
            "HealthCheckId",
            value=self.health_check.attr_health_check_id,
            description="Route 53 Health Check ID",
            export_name=f"{self.stack_name}-HealthCheckId"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS Topic ARN for notifications",
            export_name=f"{self.stack_name}-SNSTopicArn"
        )

        CfnOutput(
            self,
            "AlarmName",
            value=self.alarm.alarm_name,
            description="CloudWatch Alarm Name",
            export_name=f"{self.stack_name}-AlarmName"
        )

        CfnOutput(
            self,
            "DashboardName",
            value=self.dashboard.dashboard_name,
            description="CloudWatch Dashboard Name",
            export_name=f"{self.stack_name}-DashboardName"
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL"
        )

        CfnOutput(
            self,
            "MonitoredWebsite",
            value=website_url,
            description="Website being monitored"
        )

        CfnOutput(
            self,
            "NotificationEmail",
            value=monitor_email,
            description="Email address for notifications"
        )


class WebsiteUptimeMonitoringApp(cdk.App):
    """CDK Application for Website Uptime Monitoring."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        website_url = os.environ.get("WEBSITE_URL", "https://httpbin.org/status/200")
        monitor_email = os.environ.get("MONITOR_EMAIL", "admin@example.com")
        
        # Optional configuration
        health_check_interval = int(os.environ.get("HEALTH_CHECK_INTERVAL", "30"))
        failure_threshold = int(os.environ.get("FAILURE_THRESHOLD", "3"))

        # Create the stack
        WebsiteUptimeMonitoringStack(
            self,
            "WebsiteUptimeMonitoringStack",
            website_url=website_url,
            monitor_email=monitor_email,
            health_check_interval=health_check_interval,
            failure_threshold=failure_threshold,
            description="Website Uptime Monitoring with Route 53 Health Checks"
        )


# Create and synthesize the application
if __name__ == "__main__":
    app = WebsiteUptimeMonitoringApp()
    app.synth()