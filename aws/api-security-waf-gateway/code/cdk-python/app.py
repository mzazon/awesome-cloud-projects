#!/usr/bin/env python3
"""
CDK Python Application for API Security with WAF and Gateway

This application creates a comprehensive API security solution using AWS WAF integrated
with Amazon API Gateway, providing defense-in-depth protection through rate limiting,
IP-based restrictions, request inspection rules, and geographic blocking.

Architecture:
- AWS WAF Web ACL with multiple protection rules
- API Gateway REST API with mock integration
- CloudWatch logging for WAF traffic analysis
- Rate limiting and geographic blocking capabilities
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_wafv2 as wafv2,
    aws_apigateway as apigateway,
    aws_logs as logs,
    aws_iam as iam,
    CfnOutput,
    Duration,
    RemovalPolicy
)
from constructs import Construct
from typing import List


class ApiSecurityStack(Stack):
    """
    CDK Stack for implementing API security with AWS WAF and API Gateway.
    
    This stack creates:
    - CloudWatch Log Group for WAF logging
    - AWS WAF Web ACL with rate limiting and geo-blocking rules
    - API Gateway REST API with test endpoint
    - WAF association with API Gateway
    - CloudWatch monitoring and logging configuration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters for customization
        self.rate_limit = 1000  # Requests per 5-minute window
        self.blocked_countries = ["CN", "RU", "KP"]  # Countries to block
        
        # Create CloudWatch Log Group for WAF logging
        self.waf_log_group = self._create_waf_log_group()
        
        # Create AWS WAF Web ACL with security rules
        self.web_acl = self._create_waf_web_acl()
        
        # Create API Gateway REST API
        self.api = self._create_api_gateway()
        
        # Associate WAF with API Gateway
        self._associate_waf_with_api()
        
        # Enable WAF logging
        self._enable_waf_logging()
        
        # Create outputs for reference
        self._create_outputs()

    def _create_waf_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for WAF traffic logging.
        
        Returns:
            logs.LogGroup: The created log group for WAF logs
        """
        log_group = logs.LogGroup(
            self, "WAFLogGroup",
            log_group_name=f"/aws/waf/api-security-acl-{self.stack_name.lower()}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_waf_web_acl(self) -> wafv2.CfnWebACL:
        """
        Create AWS WAF Web ACL with comprehensive security rules.
        
        Returns:
            wafv2.CfnWebACL: The created Web ACL with security rules
        """
        # Create rate limiting rule
        rate_limit_rule = wafv2.CfnWebACL.RuleProperty(
            name="RateLimitRule",
            priority=1,
            statement=wafv2.CfnWebACL.StatementProperty(
                rate_based_statement=wafv2.CfnWebACL.RateBasedStatementProperty(
                    limit=self.rate_limit,
                    aggregate_key_type="IP"
                )
            ),
            action=wafv2.CfnWebACL.RuleActionProperty(
                block={}
            ),
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="RateLimitRule"
            )
        )

        # Create geographic blocking rule
        geo_block_rule = wafv2.CfnWebACL.RuleProperty(
            name="GeoBlockRule",
            priority=2,
            statement=wafv2.CfnWebACL.StatementProperty(
                geo_match_statement=wafv2.CfnWebACL.GeoMatchStatementProperty(
                    country_codes=self.blocked_countries
                )
            ),
            action=wafv2.CfnWebACL.RuleActionProperty(
                block={}
            ),
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="GeoBlockRule"
            )
        )

        # Create Web ACL with rules
        web_acl = wafv2.CfnWebACL(
            self, "ApiSecurityWebACL",
            name=f"api-security-acl-{self.stack_name.lower()}",
            scope="REGIONAL",
            default_action=wafv2.CfnWebACL.DefaultActionProperty(
                allow={}
            ),
            description="Web ACL for API Gateway protection with rate limiting and geo-blocking",
            rules=[rate_limit_rule, geo_block_rule],
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="ApiSecurityWebACL"
            )
        )

        return web_acl

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway REST API with test endpoint.
        
        Returns:
            apigateway.RestApi: The created API Gateway REST API
        """
        # Create the REST API
        api = apigateway.RestApi(
            self, "ProtectedApi",
            rest_api_name=f"protected-api-{self.stack_name.lower()}",
            description="Test API protected by AWS WAF",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            )
        )

        # Create test resource
        test_resource = api.root.add_resource("test")

        # Create mock integration for the test endpoint
        mock_integration = apigateway.MockIntegration(
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_templates={
                        "application/json": '{"message": "Hello from protected API!", "timestamp": "$context.requestTime", "sourceIp": "$context.identity.sourceIp"}'
                    }
                )
            ],
            request_templates={
                "application/json": '{"statusCode": 200}'
            }
        )

        # Add GET method to test resource
        test_resource.add_method(
            "GET",
            mock_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ]
        )

        return api

    def _associate_waf_with_api(self) -> None:
        """
        Associate the WAF Web ACL with the API Gateway stage.
        """
        # Create WAF association with API Gateway
        wafv2.CfnWebACLAssociation(
            self, "WAFApiAssociation",
            resource_arn=f"arn:aws:apigateway:{self.region}::/restapis/{self.api.rest_api_id}/stages/{self.api.deployment_stage.stage_name}",
            web_acl_arn=self.web_acl.attr_arn
        )

    def _enable_waf_logging(self) -> None:
        """
        Enable WAF logging to CloudWatch.
        """
        # Create logging configuration for WAF
        wafv2.CfnLoggingConfiguration(
            self, "WAFLoggingConfig",
            resource_arn=self.web_acl.attr_arn,
            log_destination_configs=[self.waf_log_group.log_group_arn]
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self, "ApiEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL",
            export_name=f"{self.stack_name}-ApiEndpoint"
        )

        CfnOutput(
            self, "TestEndpoint",
            value=f"{self.api.url}test",
            description="Test endpoint URL for validation",
            export_name=f"{self.stack_name}-TestEndpoint"
        )

        CfnOutput(
            self, "WebACLId",
            value=self.web_acl.attr_id,
            description="WAF Web ACL ID",
            export_name=f"{self.stack_name}-WebACLId"
        )

        CfnOutput(
            self, "WebACLArn",
            value=self.web_acl.attr_arn,
            description="WAF Web ACL ARN",
            export_name=f"{self.stack_name}-WebACLArn"
        )

        CfnOutput(
            self, "LogGroupName",
            value=self.waf_log_group.log_group_name,
            description="CloudWatch Log Group for WAF logs",
            export_name=f"{self.stack_name}-LogGroupName"
        )


class ApiSecurityApp(cdk.App):
    """
    CDK Application for API Security with WAF and API Gateway.
    """

    def __init__(self):
        super().__init__()

        # Create the main stack
        ApiSecurityStack(
            self, "ApiSecurityStack",
            description="API Security with WAF and Gateway",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


# Main entry point
if __name__ == "__main__":
    app = ApiSecurityApp()
    app.synth()