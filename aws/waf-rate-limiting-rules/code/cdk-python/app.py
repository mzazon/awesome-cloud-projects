#!/usr/bin/env python3
"""
AWS CDK Python application for Web Application Firewall with Rate Limiting Rules.

This CDK application deploys a comprehensive AWS WAF solution that includes:
- Web ACL with rate limiting rules
- IP reputation protection using AWS managed rule groups
- CloudWatch monitoring and dashboards
- WAF logging to CloudWatch Logs

The solution provides application-layer security for web applications by:
- Blocking excessive requests from single IP addresses (rate limiting)
- Filtering traffic from known malicious IP addresses
- Providing comprehensive monitoring and alerting capabilities
- Enabling detailed security logging for compliance and analysis
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from aws_cdk import aws_wafv2 as wafv2

from constructs import Construct


class WafRateLimitingStack(Stack):
    """
    CDK Stack for AWS WAF with rate limiting and security rules.
    
    This stack creates a comprehensive WAF solution including:
    - Web ACL with multiple security rules
    - Rate limiting to prevent DDoS attacks
    - IP reputation filtering using AWS managed rules
    - CloudWatch monitoring and alerting
    - Detailed security logging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        rate_limit: Optional[int] = None,
        log_retention_days: Optional[int] = None,
        **kwargs
    ) -> None:
        """
        Initialize the WAF Rate Limiting Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            rate_limit: Request rate limit per IP (default: 2000 requests per 5 minutes)
            log_retention_days: CloudWatch log retention in days (default: 30 days)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters with defaults
        self.rate_limit = rate_limit or 2000
        self.log_retention_days = log_retention_days or 30

        # Create CloudWatch log group for WAF logs
        self.log_group = self._create_log_group()

        # Create the main Web ACL with security rules
        self.web_acl = self._create_web_acl()

        # Enable WAF logging
        self._configure_waf_logging()

        # Create CloudWatch dashboard for monitoring
        self.dashboard = self._create_monitoring_dashboard()

        # Create CloudWatch alarms for security monitoring
        self._create_security_alarms()

        # Output important resource information
        self._create_outputs()

        # Apply common tags to all resources
        self._apply_tags()

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for WAF security logs.
        
        Returns:
            CloudWatch LogGroup for WAF logs
        """
        log_group = logs.LogGroup(
            self,
            "WafSecurityLogs",
            log_group_name="/aws/wafv2/security-logs",
            retention=logs.RetentionDays(self.log_retention_days),
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_web_acl(self) -> wafv2.CfnWebACL:
        """
        Create the main Web ACL with comprehensive security rules.
        
        Returns:
            AWS WAF Web ACL with rate limiting and IP reputation rules
        """
        # Define rate limiting rule
        rate_limit_rule = wafv2.CfnWebACL.RuleProperty(
            name="RateLimitRule",
            priority=1,
            statement=wafv2.CfnWebACL.StatementProperty(
                rate_based_statement=wafv2.CfnWebACL.RateBasedStatementProperty(
                    limit=self.rate_limit,
                    aggregate_key_type="IP",
                )
            ),
            action=wafv2.CfnWebACL.RuleActionProperty(
                block={}
            ),
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="RateLimitRule",
            ),
        )

        # Define IP reputation rule using AWS managed rule group
        ip_reputation_rule = wafv2.CfnWebACL.RuleProperty(
            name="IPReputationRule",
            priority=2,
            statement=wafv2.CfnWebACL.StatementProperty(
                managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                    vendor_name="AWS",
                    name="AWSManagedRulesAmazonIpReputationList",
                )
            ),
            action=wafv2.CfnWebACL.RuleActionProperty(
                block={}
            ),
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="IPReputationRule",
            ),
            override_action=wafv2.CfnWebACL.OverrideActionProperty(
                none={}
            ),
        )

        # Create the Web ACL
        web_acl = wafv2.CfnWebACL(
            self,
            "WafWebACL",
            scope="CLOUDFRONT",
            default_action=wafv2.CfnWebACL.DefaultActionProperty(
                allow={}
            ),
            rules=[rate_limit_rule, ip_reputation_rule],
            description="Web ACL for rate limiting and IP reputation filtering",
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="WafWebACL",
            ),
        )

        return web_acl

    def _configure_waf_logging(self) -> None:
        """
        Configure WAF logging to CloudWatch Logs.
        
        This enables comprehensive security logging for compliance,
        monitoring, and incident response purposes.
        """
        wafv2.CfnLoggingConfiguration(
            self,
            "WafLoggingConfig",
            resource_arn=self.web_acl.attr_arn,
            log_destination_configs=[self.log_group.log_group_arn],
            redacted_fields=[
                wafv2.CfnLoggingConfiguration.FieldToMatchProperty(
                    single_header=wafv2.CfnLoggingConfiguration.SingleHeaderProperty(
                        name="authorization"
                    )
                )
            ],
        )

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for WAF security monitoring.
        
        Returns:
            CloudWatch Dashboard with key WAF metrics
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "WafSecurityDashboard",
            dashboard_name=f"WAF-Security-Dashboard-{self.stack_name}",
        )

        # Allowed vs Blocked Requests widget
        allowed_blocked_widget = cloudwatch.GraphWidget(
            title="WAF Allowed vs Blocked Requests",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/WAFV2",
                    metric_name="AllowedRequests",
                    dimensions_map={
                        "WebACL": self.web_acl.attr_name,
                        "Region": "CloudFront",
                        "Rule": "ALL",
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/WAFV2",
                    metric_name="BlockedRequests",
                    dimensions_map={
                        "WebACL": self.web_acl.attr_name,
                        "Region": "CloudFront",
                        "Rule": "ALL",
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )

        # Blocked Requests by Rule widget
        blocked_by_rule_widget = cloudwatch.GraphWidget(
            title="Blocked Requests by Rule",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/WAFV2",
                    metric_name="BlockedRequests",
                    dimensions_map={
                        "WebACL": self.web_acl.attr_name,
                        "Region": "CloudFront",
                        "Rule": "RateLimitRule",
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="Rate Limit Rule",
                ),
                cloudwatch.Metric(
                    namespace="AWS/WAFV2",
                    metric_name="BlockedRequests",
                    dimensions_map={
                        "WebACL": self.web_acl.attr_name,
                        "Region": "CloudFront",
                        "Rule": "IPReputationRule",
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="IP Reputation Rule",
                ),
            ],
            width=12,
            height=6,
        )

        # Rate Limit Rule specific metrics
        rate_limit_widget = cloudwatch.GraphWidget(
            title="Rate Limiting Activity",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/WAFV2",
                    metric_name="BlockedRequests",
                    dimensions_map={
                        "WebACL": self.web_acl.attr_name,
                        "Region": "CloudFront",
                        "Rule": "RateLimitRule",
                    },
                    statistic="Sum",
                    period=Duration.minutes(1),
                    label="Blocked by Rate Limit",
                ),
            ],
            width=12,
            height=6,
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            allowed_blocked_widget,
            blocked_by_rule_widget,
            rate_limit_widget,
        )

        return dashboard

    def _create_security_alarms(self) -> None:
        """
        Create CloudWatch alarms for security monitoring and alerting.
        
        These alarms help detect potential security incidents and
        ensure rapid response to threats.
        """
        # Alarm for high number of blocked requests (potential attack)
        cloudwatch.Alarm(
            self,
            "HighBlockedRequestsAlarm",
            alarm_name=f"WAF-HighBlockedRequests-{self.stack_name}",
            alarm_description="Alarm when WAF blocks an unusually high number of requests",
            metric=cloudwatch.Metric(
                namespace="AWS/WAFV2",
                metric_name="BlockedRequests",
                dimensions_map={
                    "WebACL": self.web_acl.attr_name,
                    "Region": "CloudFront",
                    "Rule": "ALL",
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Alarm for rate limiting activations
        cloudwatch.Alarm(
            self,
            "RateLimitActivationAlarm",
            alarm_name=f"WAF-RateLimitActivation-{self.stack_name}",
            alarm_description="Alarm when rate limiting rule blocks requests",
            metric=cloudwatch.Metric(
                namespace="AWS/WAFV2",
                metric_name="BlockedRequests",
                dimensions_map={
                    "WebACL": self.web_acl.attr_name,
                    "Region": "CloudFront",
                    "Rule": "RateLimitRule",
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "WebAclArn",
            value=self.web_acl.attr_arn,
            description="ARN of the WAF Web ACL",
            export_name=f"{self.stack_name}-WebAclArn",
        )

        CfnOutput(
            self,
            "WebAclId",
            value=self.web_acl.attr_id,
            description="ID of the WAF Web ACL",
            export_name=f"{self.stack_name}-WebAclId",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group for WAF logs",
            export_name=f"{self.stack_name}-LogGroupName",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name=f"{self.stack_name}-DashboardUrl",
        )

        CfnOutput(
            self,
            "RateLimit",
            value=str(self.rate_limit),
            description="Rate limit threshold (requests per 5 minutes)",
            export_name=f"{self.stack_name}-RateLimit",
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all resources in the stack."""
        Tags.of(self).add("Project", "WAF-RateLimiting")
        Tags.of(self).add("Environment", self.node.try_get_context("environment") or "development")
        Tags.of(self).add("Owner", "SecurityTeam")
        Tags.of(self).add("CostCenter", "Security")


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get configuration from context or environment variables
    rate_limit = app.node.try_get_context("rateLimit") or int(os.environ.get("RATE_LIMIT", "2000"))
    log_retention_days = app.node.try_get_context("logRetentionDays") or int(os.environ.get("LOG_RETENTION_DAYS", "30"))
    environment = app.node.try_get_context("environment") or os.environ.get("ENVIRONMENT", "development")

    # Create the stack
    WafRateLimitingStack(
        app,
        f"WafRateLimitingStack-{environment}",
        rate_limit=rate_limit,
        log_retention_days=log_retention_days,
        description="AWS WAF with rate limiting rules and comprehensive security monitoring",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
    )

    app.synth()


if __name__ == "__main__":
    main()