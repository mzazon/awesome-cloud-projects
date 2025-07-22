#!/usr/bin/env python3
"""
CDK Python Application for Content Caching Strategies with CloudFront and ElastiCache

This application demonstrates a multi-tier caching architecture combining CloudFront 
for global content distribution with ElastiCache for application-level data caching.
The architecture includes Lambda functions, API Gateway, and S3 for a complete 
content delivery solution.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_elasticache as elasticache,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class ContentCachingStack(Stack):
    """
    A CDK Stack that implements a multi-tier caching strategy using CloudFront and ElastiCache.
    
    This stack creates:
    - S3 bucket for static content storage
    - ElastiCache Redis cluster for application-level caching
    - Lambda function for API logic with cache integration
    - API Gateway for RESTful endpoints
    - CloudFront distribution for global content delivery
    - CloudWatch monitoring and alarms
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = cdk.Names.unique_id(self)[:8].lower()

        # Get default VPC for ElastiCache deployment
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)

        # Create S3 bucket for static content
        self.content_bucket = self._create_content_bucket(unique_suffix)

        # Create ElastiCache Redis cluster
        self.cache_cluster = self._create_elasticache_cluster(vpc, unique_suffix)

        # Create Lambda function for API logic
        self.api_function = self._create_lambda_function(vpc, unique_suffix)

        # Create API Gateway
        self.api_gateway = self._create_api_gateway(unique_suffix)

        # Create CloudFront distribution
        self.distribution = self._create_cloudfront_distribution(unique_suffix)

        # Create monitoring resources
        self._create_monitoring_resources(unique_suffix)

        # Deploy sample content to S3
        self._deploy_sample_content()

        # Create stack outputs
        self._create_outputs()

    def _create_content_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for static content storage with CloudFront integration.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "ContentBucket",
            bucket_name=f"cache-demo-content-{unique_suffix}",
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,  # Access controlled via CloudFront OAC
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
        )

        # Add bucket policy for CloudFront access (will be updated after distribution creation)
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/*"
                    }
                }
            )
        )

        return bucket

    def _create_elasticache_cluster(self, vpc: ec2.IVpc, unique_suffix: str) -> elasticache.CfnCacheCluster:
        """
        Create ElastiCache Redis cluster for application-level caching.
        
        Args:
            vpc: VPC for cluster deployment
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            ElastiCache cluster construct
        """
        # Create security group for ElastiCache
        cache_security_group = ec2.SecurityGroup(
            self,
            "CacheSecurityGroup",
            vpc=vpc,
            description="Security group for ElastiCache Redis cluster",
            allow_all_outbound=False,
        )

        # Allow inbound Redis traffic from Lambda functions
        cache_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),  # Will be restricted to Lambda security group
            connection=ec2.Port.tcp(6379),
            description="Redis port access from Lambda functions",
        )

        # Create subnet group for ElastiCache
        subnet_group = elasticache.CfnSubnetGroup(
            self,
            "CacheSubnetGroup",
            description="Subnet group for ElastiCache cluster",
            subnet_ids=[subnet.subnet_id for subnet in vpc.private_subnets],
            cache_subnet_group_name=f"cache-demo-subnet-group-{unique_suffix}",
        )

        # Create ElastiCache Redis cluster
        cache_cluster = elasticache.CfnCacheCluster(
            self,
            "CacheCluster",
            cache_cluster_id=f"demo-cache-{unique_suffix}",
            cache_node_type="cache.t3.micro",
            engine="redis",
            num_cache_nodes=1,
            cache_subnet_group_name=subnet_group.cache_subnet_group_name,
            vpc_security_group_ids=[cache_security_group.security_group_id],
            port=6379,
        )

        cache_cluster.add_dependency(subnet_group)

        return cache_cluster

    def _create_lambda_function(self, vpc: ec2.IVpc, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for API logic with ElastiCache integration.
        
        Args:
            vpc: VPC for function deployment
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            Lambda function construct
        """
        # Create security group for Lambda
        lambda_security_group = ec2.SecurityGroup(
            self,
            "LambdaSecurityGroup",
            vpc=vpc,
            description="Security group for Lambda functions",
            allow_all_outbound=True,
        )

        # Create Lambda function
        function = _lambda.Function(
            self,
            "ApiFunction",
            function_name=f"cache-demo-api-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            security_groups=[lambda_security_group],
            environment={
                "REDIS_ENDPOINT": self.cache_cluster.attr_cache_nodes_0_endpoint_address,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Add Redis dependency to Lambda layer
        redis_layer = _lambda.LayerVersion(
            self,
            "RedisLayer",
            code=_lambda.Code.from_asset("lambda-layer"),  # Assumes redis layer is pre-built
            compatible_runtimes=[_lambda.Runtime.PYTHON_3_9],
            description="Redis client library for Python",
        )

        return function

    def _create_api_gateway(self, unique_suffix: str) -> apigateway.RestApi:
        """
        Create API Gateway for RESTful endpoints.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            API Gateway construct
        """
        api = apigateway.RestApi(
            self,
            "CacheApi",
            rest_api_name=f"cache-demo-api-{unique_suffix}",
            description="API for content caching demonstration",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization"],
            ),
        )

        # Create API resources and methods
        api_resource = api.root.add_resource("api")
        data_resource = api_resource.add_resource("data")

        # Add Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.api_function,
            request_templates={"application/json": '{ "statusCode": "200" }'},
        )

        data_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Cache-Control": True,
                        "method.response.header.Content-Type": True,
                    },
                )
            ],
        )

        return api

    def _create_cloudfront_distribution(self, unique_suffix: str) -> cloudfront.Distribution:
        """
        Create CloudFront distribution for global content delivery.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            CloudFront distribution construct
        """
        # Create Origin Access Control for S3
        oac = cloudfront.S3OriginAccessControl(
            self,
            "OAC",
            signing_behavior=cloudfront.SigningBehavior.ALWAYS,
            signing_protocol=cloudfront.SigningProtocol.SIGV4,
            origin_access_control_name=f"S3-OAC-{unique_suffix}",
        )

        # Create S3 origin
        s3_origin = origins.S3StaticWebsiteOrigin(
            self.content_bucket,
            origin_access_control=oac,
        )

        # Create API Gateway origin
        api_origin = origins.RestApiOrigin(self.api_gateway)

        # Create cache policies
        api_cache_policy = cloudfront.CachePolicy(
            self,
            "ApiCachePolicy",
            cache_policy_name=f"APIResponseCaching-{unique_suffix}",
            comment="Cache policy for API responses",
            default_ttl=Duration.seconds(60),
            max_ttl=Duration.seconds(300),
            min_ttl=Duration.seconds(0),
            cookie_behavior=cloudfront.CacheCookieBehavior.none(),
            header_behavior=cloudfront.CacheHeaderBehavior.none(),
            query_string_behavior=cloudfront.CacheQueryStringBehavior.all(),
            enable_accept_encoding_gzip=True,
            enable_accept_encoding_brotli=True,
        )

        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "Distribution",
            comment=f"Multi-tier caching demo - {unique_suffix}",
            default_behavior=cloudfront.BehaviorOptions(
                origin=s3_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
            ),
            additional_behaviors={
                "/api/*": cloudfront.BehaviorOptions(
                    origin=api_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=api_cache_policy,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                    compress=True,
                )
            },
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            enable_logging=True,
        )

        return distribution

    def _create_monitoring_resources(self, unique_suffix: str) -> None:
        """
        Create CloudWatch monitoring and alarms.
        
        Args:
            unique_suffix: Unique identifier for resource naming
        """
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "CacheLogGroup",
            log_group_name=f"/aws/cloudfront/cache-demo-{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudWatch alarm for cache hit ratio
        cache_hit_alarm = cloudwatch.Alarm(
            self,
            "CacheHitRatioAlarm",
            alarm_name=f"CloudFront-CacheHitRatio-Low-{unique_suffix}",
            alarm_description="Alert when CloudFront cache hit ratio is low",
            metric=cloudfront.Metric.cache_hit_rate(
                distribution_id=self.distribution.distribution_id,
                statistic=cloudwatch.Stats.AVERAGE,
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
        )

        # Create alarm for Lambda errors
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"Lambda-Errors-{unique_suffix}",
            alarm_description="Alert when Lambda function has errors",
            metric=self.api_function.metric_errors(
                statistic=cloudwatch.Stats.SUM,
                period=Duration.minutes(5),
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
        )

    def _deploy_sample_content(self) -> None:
        """Deploy sample HTML content to S3 bucket."""
        s3_deployment.BucketDeployment(
            self,
            "SampleContent",
            sources=[s3_deployment.Source.data("index.html", self._get_sample_html())],
            destination_bucket=self.content_bucket,
            retain_on_delete=False,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "S3BucketName",
            value=self.content_bucket.bucket_name,
            description="Name of the S3 bucket for static content",
        )

        CfnOutput(
            self,
            "ElastiCacheEndpoint",
            value=self.cache_cluster.attr_cache_nodes_0_endpoint_address,
            description="ElastiCache Redis cluster endpoint",
        )

        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api_gateway.url,
            description="API Gateway endpoint URL",
        )

        CfnOutput(
            self,
            "CloudFrontDomainName",
            value=self.distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
        )

        CfnOutput(
            self,
            "CloudFrontUrl",
            value=f"https://{self.distribution.distribution_domain_name}",
            description="CloudFront distribution URL",
        )

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for cache integration.
        
        Returns:
            Lambda function code as string
        """
        return '''
import json
import redis
import time
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function that implements cache-aside pattern with ElastiCache Redis.
    
    This function checks ElastiCache first for requested data, falling back to
    database queries only when cache misses occur. It demonstrates intelligent
    caching behavior with appropriate TTL values and error handling.
    """
    # ElastiCache endpoint from environment variable
    redis_endpoint = os.environ.get('REDIS_ENDPOINT', 'localhost')
    
    try:
        # Connect to Redis with connection pooling
        r = redis.Redis(
            host=redis_endpoint, 
            port=6379, 
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True,
            health_check_interval=30
        )
        
        # Test connection
        r.ping()
        
        # Check if data exists in cache
        cache_key = "demo_data"
        cached_data = r.get(cache_key)
        
        if cached_data:
            # Return cached data
            data = json.loads(cached_data)
            data['cache_hit'] = True
            data['source'] = 'ElastiCache'
            response_time = '< 1ms'
        else:
            # Simulate database query
            time.sleep(0.1)  # Simulate DB query time
            
            # Generate fresh data
            data = {
                'timestamp': datetime.now().isoformat(),
                'message': 'Hello from Lambda with ElastiCache!',
                'query_time': '100ms',
                'cache_hit': False,
                'source': 'Database (simulated)',
                'data_freshness': 'Fresh from origin'
            }
            
            # Cache the data for 5 minutes (300 seconds)
            r.setex(cache_key, 300, json.dumps(data))
            response_time = '100ms'
        
        # Add performance metrics
        data['response_time'] = response_time
        data['lambda_request_id'] = context.aws_request_id
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'public, max-age=60',  # CloudFront caching
                'X-Cache-Status': 'HIT' if data['cache_hit'] else 'MISS',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps(data, indent=2)
        }
        
    except redis.ConnectionError as e:
        # Handle Redis connection errors gracefully
        fallback_data = {
            'timestamp': datetime.now().isoformat(),
            'message': 'Fallback response - Redis unavailable',
            'cache_hit': False,
            'source': 'Lambda fallback',
            'error': 'Redis connection failed',
            'lambda_request_id': context.aws_request_id
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache',
                'X-Cache-Status': 'ERROR',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(fallback_data)
        }
        
    except Exception as e:
        # Handle unexpected errors
        error_response = {
            'error': str(e),
            'message': 'Unexpected error occurred',
            'lambda_request_id': context.aws_request_id,
            'timestamp': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(error_response)
        }
'''

    def _get_sample_html(self) -> str:
        """
        Get sample HTML content for S3 deployment.
        
        Returns:
            HTML content as string
        """
        return '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Tier Caching Demo</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 40px; 
            background-color: #f5f5f5;
            line-height: 1.6;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .api-result { 
            background: #f8f9fa; 
            padding: 20px; 
            margin: 20px 0; 
            border-radius: 5px;
            border-left: 4px solid #007bff;
            white-space: pre-wrap;
            font-family: 'Courier New', monospace;
            font-size: 14px;
        }
        .loading {
            color: #6c757d;
            font-style: italic;
        }
        .cache-hit {
            border-left-color: #28a745;
            background-color: #d4edda;
        }
        .cache-miss {
            border-left-color: #ffc107;
            background-color: #fff3cd;
        }
        .error {
            border-left-color: #dc3545;
            background-color: #f8d7da;
        }
        button {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            margin: 10px 5px 10px 0;
        }
        button:hover {
            background: #0056b3;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .metric-card {
            background: #e9ecef;
            padding: 15px;
            border-radius: 5px;
            text-align: center;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            color: #007bff;
        }
        .metric-label {
            font-size: 12px;
            color: #6c757d;
            text-transform: uppercase;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Multi-Tier Caching Demo</h1>
        <p>This demonstration showcases a comprehensive caching strategy using:</p>
        <ul>
            <li><strong>CloudFront</strong> - Global edge caching for reduced latency</li>
            <li><strong>ElastiCache Redis</strong> - Application-level data caching</li>
            <li><strong>Lambda</strong> - Serverless API with intelligent cache management</li>
            <li><strong>API Gateway</strong> - RESTful endpoint with caching headers</li>
        </ul>
        
        <div class="metrics">
            <div class="metric-card">
                <div class="metric-value" id="total-requests">0</div>
                <div class="metric-label">Total Requests</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" id="cache-hits">0</div>
                <div class="metric-label">Cache Hits</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" id="cache-ratio">0%</div>
                <div class="metric-label">Hit Ratio</div>
            </div>
        </div>

        <button onclick="fetchData()">🔄 Fetch API Data</button>
        <button onclick="clearStats()">📊 Clear Statistics</button>
        
        <div id="api-result" class="api-result loading">
            Click "Fetch API Data" to test the caching architecture...
        </div>
    </div>

    <script>
        let totalRequests = 0;
        let cacheHits = 0;

        function updateMetrics() {
            document.getElementById('total-requests').textContent = totalRequests;
            document.getElementById('cache-hits').textContent = cacheHits;
            const ratio = totalRequests > 0 ? Math.round((cacheHits / totalRequests) * 100) : 0;
            document.getElementById('cache-ratio').textContent = ratio + '%';
        }

        function clearStats() {
            totalRequests = 0;
            cacheHits = 0;
            updateMetrics();
        }

        async function fetchData() {
            const resultDiv = document.getElementById('api-result');
            resultDiv.textContent = 'Loading data from API...';
            resultDiv.className = 'api-result loading';
            
            try {
                const startTime = performance.now();
                const response = await fetch('/api/data');
                const endTime = performance.now();
                const data = await response.json();
                
                // Update statistics
                totalRequests++;
                if (data.cache_hit) {
                    cacheHits++;
                    resultDiv.className = 'api-result cache-hit';
                } else {
                    resultDiv.className = 'api-result cache-miss';
                }
                
                // Display results with timing information
                const timing = `Client-side timing: ${Math.round(endTime - startTime)}ms`;
                const cacheStatus = response.headers.get('X-Cache-Status') || 'Unknown';
                
                resultDiv.textContent = 
                    `📊 API Response Data:\\n\\n${JSON.stringify(data, null, 2)}\\n\\n` +
                    `⚡ ${timing}\\n` +
                    `🏷️  Cache Status: ${cacheStatus}\\n` +
                    `🌐 CloudFront: ${response.headers.get('Via') ? 'HIT' : 'Direct'}`;
                
                updateMetrics();
                
            } catch (error) {
                resultDiv.className = 'api-result error';
                resultDiv.textContent = `❌ Error fetching data: ${error.message}`;
            }
        }

        // Initialize metrics
        updateMetrics();
        
        // Auto-fetch data on page load after a short delay
        setTimeout(fetchData, 1000);
    </script>
</body>
</html>'''


app = cdk.App()

# Create the main stack
ContentCachingStack(
    app,
    "ContentCachingStack",
    description="Multi-tier caching strategy with CloudFront and ElastiCache",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    ),
)

app.synth()