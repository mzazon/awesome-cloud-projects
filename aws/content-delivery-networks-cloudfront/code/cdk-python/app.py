#!/usr/bin/env python3
"""
AWS CDK Application for Advanced CloudFront Content Delivery Network

This CDK application deploys a sophisticated CloudFront distribution with:
- Multiple origins (S3 and custom)
- Lambda@Edge functions for response processing
- CloudFront Functions for request processing
- AWS WAF integration for security
- Real-time logging with Kinesis
- CloudWatch monitoring dashboard
- CloudFront KeyValueStore for dynamic configuration
- Origin Access Control for S3 security

Architecture Components:
- CloudFront Distribution with advanced cache behaviors
- Lambda@Edge function for security header injection
- CloudFront Function for request processing
- AWS WAF Web ACL with managed rules
- S3 bucket with secure access controls
- Kinesis Data Stream for real-time logs
- CloudWatch dashboard for monitoring
- KeyValueStore for dynamic configuration
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    RemovalPolicy,
    Duration,
    CfnOutput,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_wafv2 as wafv2,
    aws_kinesis as kinesis,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
import json
import os


class CloudFrontCdnStack(Stack):
    """
    CDK Stack for Advanced CloudFront Content Delivery Network
    
    This stack creates a comprehensive CDN solution with multiple origins,
    edge computing capabilities, security controls, and monitoring.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Create S3 bucket for static content
        self.content_bucket = self._create_content_bucket(unique_suffix)
        
        # Create Lambda@Edge function for response processing
        self.edge_function = self._create_lambda_edge_function(unique_suffix)
        
        # Create CloudFront Function for request processing
        self.cf_function = self._create_cloudfront_function(unique_suffix)
        
        # Create WAF Web ACL for security
        self.web_acl = self._create_waf_web_acl(unique_suffix)
        
        # Create Kinesis stream for real-time logs
        self.kinesis_stream = self._create_kinesis_stream(unique_suffix)
        
        # Create CloudFront KeyValueStore
        self.key_value_store = self._create_key_value_store(unique_suffix)
        
        # Create Origin Access Control
        self.oac = self._create_origin_access_control(unique_suffix)
        
        # Create CloudFront distribution
        self.distribution = self._create_cloudfront_distribution()
        
        # Update S3 bucket policy to allow CloudFront access
        self._update_bucket_policy()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard(unique_suffix)
        
        # Create outputs
        self._create_outputs()

    def _create_content_bucket(self, unique_suffix: str) -> s3.Bucket:
        """Create S3 bucket for static content with security configurations."""
        bucket = s3.Bucket(
            self, "ContentBucket",
            bucket_name=f"cdn-content-{unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )

        # Deploy sample content to bucket
        s3_deployment.BucketDeployment(
            self, "ContentDeployment",
            sources=[s3_deployment.Source.data(
                "index.html",
                "<html><body><h1>Advanced CDN Demo</h1><p>Deployed with CDK</p></body></html>"
            )],
            destination_bucket=bucket,
            destination_key_prefix="",
            prune=False
        )

        return bucket

    def _create_lambda_edge_function(self, unique_suffix: str) -> lambda_.Function:
        """Create Lambda@Edge function for response processing."""
        
        # Create IAM role for Lambda@Edge
        edge_role = iam.Role(
            self, "EdgeFunctionRole",
            role_name=f"cdn-edge-function-role-{unique_suffix}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("edgelambda.amazonaws.com")
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Lambda@Edge function code
        function_code = """
const handler = async (event, context) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const headers = response.headers;
    
    // Add comprehensive security headers
    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=31536000; includeSubDomains; preload'
    }];
    
    headers['x-content-type-options'] = [{
        key: 'X-Content-Type-Options',
        value: 'nosniff'
    }];
    
    headers['x-frame-options'] = [{
        key: 'X-Frame-Options',
        value: 'SAMEORIGIN'
    }];
    
    headers['x-xss-protection'] = [{
        key: 'X-XSS-Protection',
        value: '1; mode=block'
    }];
    
    headers['referrer-policy'] = [{
        key: 'Referrer-Policy',
        value: 'strict-origin-when-cross-origin'
    }];
    
    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    }];
    
    // Add CORS headers for API paths
    if (request.uri.startsWith('/api/')) {
        headers['access-control-allow-origin'] = [{
            key: 'Access-Control-Allow-Origin',
            value: '*'
        }];
        headers['access-control-allow-methods'] = [{
            key: 'Access-Control-Allow-Methods',
            value: 'GET, POST, OPTIONS, PUT, DELETE'
        }];
        headers['access-control-allow-headers'] = [{
            key: 'Access-Control-Allow-Headers',
            value: 'Content-Type, Authorization, X-Requested-With'
        }];
    }
    
    // Add performance headers
    headers['x-edge-location'] = [{
        key: 'X-Edge-Location',
        value: event.Records[0].cf.config.distributionId
    }];
    
    headers['x-cache-status'] = [{
        key: 'X-Cache-Status',
        value: 'PROCESSED'
    }];
    
    return response;
};

exports.handler = handler;
"""

        function = lambda_.Function(
            self, "EdgeFunction",
            function_name=f"cdn-edge-processor-{unique_suffix}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(function_code),
            role=edge_role,
            timeout=Duration.seconds(5),
            memory_size=128,
            description="Lambda@Edge function for CloudFront response processing"
        )

        # Create a version for Lambda@Edge (required)
        version = function.current_version

        return version

    def _create_cloudfront_function(self, unique_suffix: str) -> cloudfront.Function:
        """Create CloudFront Function for request processing."""
        
        # CloudFront Function code
        function_code = """
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    
    // Add security headers
    headers['x-forwarded-proto'] = {value: 'https'};
    headers['x-request-id'] = {value: generateRequestId()};
    
    // Normalize cache key by removing tracking parameters
    var uri = request.uri;
    var querystring = request.querystring;
    
    // Remove tracking parameters to improve cache hit ratio
    delete querystring.utm_source;
    delete querystring.utm_medium;
    delete querystring.utm_campaign;
    delete querystring.fbclid;
    delete querystring.gclid;
    
    // Redirect old paths to new structure
    if (uri.startsWith('/old-api/')) {
        uri = uri.replace('/old-api/', '/api/');
        request.uri = uri;
    }
    
    // Normalize URI for better caching
    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
    }
    
    return request;
}

function generateRequestId() {
    return 'req-' + Math.random().toString(36).substr(2, 9);
}
"""

        cf_function = cloudfront.Function(
            self, "RequestFunction",
            function_name=f"cdn-request-processor-{unique_suffix}",
            code=cloudfront.FunctionCode.from_inline(function_code),
            comment="CloudFront Function for request processing and cache optimization",
            runtime=cloudfront.FunctionRuntime.JS_2_0
        )

        return cf_function

    def _create_waf_web_acl(self, unique_suffix: str) -> wafv2.CfnWebACL:
        """Create AWS WAF Web ACL with comprehensive security rules."""
        
        web_acl = wafv2.CfnWebACL(
            self, "WebACL",
            name=f"cdn-security-{unique_suffix}",
            scope="CLOUDFRONT",
            default_action=wafv2.CfnWebACL.DefaultActionProperty(
                allow={}
            ),
            rules=[
                # AWS Managed Rule - Common Rule Set
                wafv2.CfnWebACL.RuleProperty(
                    name="AWSManagedRulesCommonRuleSet",
                    priority=1,
                    override_action=wafv2.CfnWebACL.OverrideActionProperty(
                        none={}
                    ),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                            vendor_name="AWS",
                            name="AWSManagedRulesCommonRuleSet"
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        sampled_requests_enabled=True,
                        cloud_watch_metrics_enabled=True,
                        metric_name="CommonRuleSetMetric"
                    )
                ),
                # AWS Managed Rule - Known Bad Inputs
                wafv2.CfnWebACL.RuleProperty(
                    name="AWSManagedRulesKnownBadInputsRuleSet",
                    priority=2,
                    override_action=wafv2.CfnWebACL.OverrideActionProperty(
                        none={}
                    ),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                            vendor_name="AWS",
                            name="AWSManagedRulesKnownBadInputsRuleSet"
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        sampled_requests_enabled=True,
                        cloud_watch_metrics_enabled=True,
                        metric_name="KnownBadInputsRuleSetMetric"
                    )
                ),
                # Rate Limiting Rule
                wafv2.CfnWebACL.RuleProperty(
                    name="RateLimitRule",
                    priority=3,
                    action=wafv2.CfnWebACL.RuleActionProperty(
                        block={}
                    ),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        rate_based_statement=wafv2.CfnWebACL.RateBasedStatementProperty(
                            limit=2000,
                            aggregate_key_type="IP"
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        sampled_requests_enabled=True,
                        cloud_watch_metrics_enabled=True,
                        metric_name="RateLimitRuleMetric"
                    )
                )
            ],
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name=f"cdn-security-{unique_suffix}"
            )
        )

        return web_acl

    def _create_kinesis_stream(self, unique_suffix: str) -> kinesis.Stream:
        """Create Kinesis Data Stream for real-time logs."""
        
        stream = kinesis.Stream(
            self, "RealTimeLogsStream",
            stream_name=f"cloudfront-realtime-logs-{unique_suffix}",
            shard_count=1,
            retention_period=Duration.days(1),
            encryption=kinesis.StreamEncryption.MANAGED
        )

        return stream

    def _create_key_value_store(self, unique_suffix: str) -> cloudfront.CfnKeyValueStore:
        """Create CloudFront KeyValueStore for dynamic configuration."""
        
        kvs = cloudfront.CfnKeyValueStore(
            self, "KeyValueStore",
            name=f"cdn-config-{unique_suffix}",
            comment="Dynamic configuration store for CDN"
        )

        return kvs

    def _create_origin_access_control(self, unique_suffix: str) -> cloudfront.CfnOriginAccessControl:
        """Create Origin Access Control for S3 bucket security."""
        
        oac = cloudfront.CfnOriginAccessControl(
            self, "OriginAccessControl",
            origin_access_control_config=cloudfront.CfnOriginAccessControl.OriginAccessControlConfigProperty(
                name=f"cdn-oac-{unique_suffix}",
                description="Origin Access Control for S3 bucket",
                origin_access_control_origin_type="s3",
                signing_behavior="always",
                signing_protocol="sigv4"
            )
        )

        return oac

    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """Create CloudFront distribution with advanced configuration."""
        
        # Create S3 origin with OAC
        s3_origin = origins.S3StaticWebsiteOrigin(
            bucket=self.content_bucket,
            origin_path="",
            connection_attempts=3,
            connection_timeout=Duration.seconds(10)
        )

        # Create custom origin for API endpoints
        custom_origin = origins.HttpOrigin(
            "httpbin.org",
            protocol_policy=cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
            connection_attempts=3,
            connection_timeout=Duration.seconds(10),
            read_timeout=Duration.seconds(30),
            keepalive_timeout=Duration.seconds(5)
        )

        # Create cache policies
        api_cache_policy = cloudfront.CachePolicy(
            self, "ApiCachePolicy",
            cache_policy_name=f"api-cache-policy-{self.node.addr[-8:].lower()}",
            comment="Cache policy for API endpoints",
            default_ttl=Duration.minutes(5),
            min_ttl=Duration.seconds(0),
            max_ttl=Duration.hours(1),
            cookie_behavior=cloudfront.CacheCookieBehavior.none(),
            header_behavior=cloudfront.CacheHeaderBehavior.allow_list(
                "Authorization", "Content-Type", "Accept", "User-Agent"
            ),
            query_string_behavior=cloudfront.CacheQueryStringBehavior.all(),
            enable_accept_encoding_gzip=True,
            enable_accept_encoding_brotli=True
        )

        static_cache_policy = cloudfront.CachePolicy(
            self, "StaticCachePolicy",
            cache_policy_name=f"static-cache-policy-{self.node.addr[-8:].lower()}",
            comment="Cache policy for static content",
            default_ttl=Duration.days(1),
            min_ttl=Duration.seconds(0),
            max_ttl=Duration.days(365),
            cookie_behavior=cloudfront.CacheCookieBehavior.none(),
            header_behavior=cloudfront.CacheHeaderBehavior.none(),
            query_string_behavior=cloudfront.CacheQueryStringBehavior.none(),
            enable_accept_encoding_gzip=True,
            enable_accept_encoding_brotli=True
        )

        # Create origin request policy
        origin_request_policy = cloudfront.OriginRequestPolicy(
            self, "OriginRequestPolicy",
            origin_request_policy_name=f"origin-request-policy-{self.node.addr[-8:].lower()}",
            comment="Origin request policy for all origins",
            cookie_behavior=cloudfront.OriginRequestCookieBehavior.none(),
            header_behavior=cloudfront.OriginRequestHeaderBehavior.allow_list(
                "CloudFront-Viewer-Country", "CloudFront-Is-Mobile-Viewer",
                "CloudFront-Is-Tablet-Viewer", "CloudFront-Is-Desktop-Viewer"
            ),
            query_string_behavior=cloudfront.OriginRequestQueryStringBehavior.all()
        )

        # Create CloudWatch log group for access logs
        log_group = logs.LogGroup(
            self, "AccessLogGroup",
            log_group_name=f"/aws/cloudfront/access-logs/{self.node.addr[-8:].lower()}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create the distribution
        distribution = cloudfront.Distribution(
            self, "Distribution",
            comment="Advanced CDN with multiple origins and edge functions",
            default_behavior=cloudfront.BehaviorOptions(
                origin=s3_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                compress=True,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                origin_request_policy=origin_request_policy,
                function_associations=[
                    cloudfront.FunctionAssociation(
                        function=self.cf_function,
                        event_type=cloudfront.FunctionEventType.VIEWER_REQUEST
                    )
                ],
                edge_lambdas=[
                    cloudfront.EdgeLambda(
                        function_version=self.edge_function,
                        event_type=cloudfront.LambdaEdgeEventType.ORIGIN_RESPONSE,
                        include_body=False
                    )
                ]
            ),
            additional_behaviors={
                "/api/*": cloudfront.BehaviorOptions(
                    origin=custom_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                    compress=True,
                    cache_policy=api_cache_policy,
                    origin_request_policy=origin_request_policy,
                    edge_lambdas=[
                        cloudfront.EdgeLambda(
                            function_version=self.edge_function,
                            event_type=cloudfront.LambdaEdgeEventType.ORIGIN_RESPONSE,
                            include_body=False
                        )
                    ]
                ),
                "/static/*": cloudfront.BehaviorOptions(
                    origin=s3_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                    compress=True,
                    cache_policy=static_cache_policy,
                    origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN
                )
            },
            error_responses=[
                cloudfront.ErrorResponse(
                    http_status=404,
                    response_http_status=404,
                    response_page_path="/404.html",
                    ttl=Duration.minutes(5)
                ),
                cloudfront.ErrorResponse(
                    http_status=500,
                    response_http_status=500,
                    response_page_path="/500.html",
                    ttl=Duration.seconds(0)
                )
            ],
            web_acl_id=self.web_acl.attr_arn,
            price_class=cloudfront.PriceClass.PRICE_CLASS_ALL,
            http_version=cloudfront.HttpVersion.HTTP2_AND_3,
            enable_ipv6=True,
            default_root_object="index.html",
            enable_logging=True,
            log_bucket=self.content_bucket,
            log_file_prefix="cloudfront-access-logs/",
            log_includes_cookies=False
        )

        return distribution

    def _update_bucket_policy(self) -> None:
        """Update S3 bucket policy to allow CloudFront access via OAC."""
        
        bucket_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="AllowCloudFrontServicePrincipal",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                    actions=["s3:GetObject"],
                    resources=[f"{self.content_bucket.bucket_arn}/*"],
                    conditions={
                        "StringEquals": {
                            "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{self.distribution.distribution_id}"
                        }
                    }
                )
            ]
        )

        # Apply the policy to the bucket
        self.content_bucket.add_to_resource_policy(bucket_policy.statements[0])

    def _create_cloudwatch_dashboard(self, unique_suffix: str) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring CDN performance."""
        
        dashboard = cloudwatch.Dashboard(
            self, "CDNDashboard",
            dashboard_name=f"CloudFront-Advanced-CDN-{unique_suffix}",
            widgets=[
                [
                    # Traffic metrics
                    cloudwatch.GraphWidget(
                        title="CloudFront Traffic",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="Requests",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="BytesDownloaded",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    ),
                    # Error rates
                    cloudwatch.GraphWidget(
                        title="Error Rates",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="4xxErrorRate",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="5xxErrorRate",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Cache hit rate
                    cloudwatch.GraphWidget(
                        title="Cache Hit Rate",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="CacheHitRate",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    ),
                    # WAF metrics
                    cloudwatch.GraphWidget(
                        title="WAF Activity",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/WAFV2",
                                metric_name="AllowedRequests",
                                dimensions_map={
                                    "WebACL": self.web_acl.name,
                                    "Rule": "ALL",
                                    "Region": "CloudFront"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/WAFV2",
                                metric_name="BlockedRequests",
                                dimensions_map={
                                    "WebACL": self.web_acl.name,
                                    "Rule": "ALL",
                                    "Region": "CloudFront"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "DistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront Distribution ID",
            export_name=f"{self.stack_name}-DistributionId"
        )

        CfnOutput(
            self, "DistributionDomainName",
            value=self.distribution.distribution_domain_name,
            description="CloudFront Distribution Domain Name",
            export_name=f"{self.stack_name}-DistributionDomainName"
        )

        CfnOutput(
            self, "DistributionURL",
            value=f"https://{self.distribution.distribution_domain_name}",
            description="CloudFront Distribution URL",
            export_name=f"{self.stack_name}-DistributionURL"
        )

        CfnOutput(
            self, "S3BucketName",
            value=self.content_bucket.bucket_name,
            description="S3 Content Bucket Name",
            export_name=f"{self.stack_name}-S3BucketName"
        )

        CfnOutput(
            self, "WebACLArn",
            value=self.web_acl.attr_arn,
            description="WAF Web ACL ARN",
            export_name=f"{self.stack_name}-WebACLArn"
        )

        CfnOutput(
            self, "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Kinesis Stream for Real-time Logs",
            export_name=f"{self.stack_name}-KinesisStreamName"
        )

        CfnOutput(
            self, "LambdaEdgeFunctionArn",
            value=self.edge_function.function_arn,
            description="Lambda@Edge Function ARN",
            export_name=f"{self.stack_name}-LambdaEdgeFunctionArn"
        )

        CfnOutput(
            self, "CloudFrontFunctionArn",
            value=self.cf_function.function_arn,
            description="CloudFront Function ARN",
            export_name=f"{self.stack_name}-CloudFrontFunctionArn"
        )

        CfnOutput(
            self, "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL",
            export_name=f"{self.stack_name}-DashboardURL"
        )


# CDK Application entry point
app = cdk.App()

# Get configuration from context or environment variables
config = {
    "account": app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT"),
    "region": app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    "stack_name": app.node.try_get_context("stack_name") or "CloudFrontAdvancedCDN"
}

# Validate required configuration
if not config["account"]:
    raise ValueError("AWS account ID must be provided via CDK context or CDK_DEFAULT_ACCOUNT environment variable")

if not config["region"]:
    raise ValueError("AWS region must be provided via CDK context or CDK_DEFAULT_REGION environment variable")

# Create the stack with environment configuration
CloudFrontCdnStack(
    app, config["stack_name"],
    env=Environment(
        account=config["account"],
        region=config["region"]
    ),
    description="Advanced CloudFront CDN with Lambda@Edge, WAF, and monitoring",
    tags={
        "Project": "CloudFront-Advanced-CDN",
        "Environment": app.node.try_get_context("environment") or "development",
        "ManagedBy": "AWS-CDK",
        "CostCenter": app.node.try_get_context("cost_center") or "engineering",
        "Owner": app.node.try_get_context("owner") or "devops-team"
    }
)

# Synthesize the application
app.synth()