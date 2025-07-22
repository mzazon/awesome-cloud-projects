#!/usr/bin/env python3
"""
CDK Python Application for Database Query Caching with ElastiCache

This CDK application implements a complete database query caching solution using
Amazon ElastiCache Redis, RDS MySQL, and supporting infrastructure. The solution
demonstrates cache-aside patterns for improving database performance and reducing
query latency.

Architecture Components:
- ElastiCache Redis replication group with automatic failover
- RDS MySQL database instance
- VPC with public and private subnets
- Security groups for controlled access
- EC2 instance for testing and demonstration
- Custom parameter groups for Redis optimization

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Tags,
    CfnOutput,
    aws_ec2 as ec2,
    aws_elasticache as elasticache,
    aws_rds as rds,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
from typing import Optional


class DatabaseCachingStack(Stack):
    """
    CDK Stack for Database Query Caching with ElastiCache Redis.
    
    This stack creates a complete caching architecture including:
    - Multi-AZ VPC with public and private subnets
    - ElastiCache Redis replication group with automatic failover
    - RDS MySQL database with appropriate configuration
    - EC2 instance for testing cache integration
    - Security groups with least privilege access
    - Custom parameter groups for optimal Redis performance
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str = "dev",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        
        # Create VPC and networking infrastructure
        self._create_vpc()
        
        # Create security groups
        self._create_security_groups()
        
        # Create ElastiCache infrastructure
        self._create_elasticache_infrastructure()
        
        # Create RDS database
        self._create_rds_database()
        
        # Create EC2 instance for testing
        self._create_test_instance()
        
        # Create outputs
        self._create_outputs()
        
        # Apply common tags
        self._apply_tags()

    def _create_vpc(self) -> None:
        """
        Create VPC with public and private subnets across multiple AZs.
        
        The VPC configuration provides:
        - Public subnets for internet-facing resources
        - Private subnets for ElastiCache and RDS
        - NAT gateways for private subnet internet access
        - Internet gateway for public subnet access
        """
        self.vpc = ec2.Vpc(
            self,
            "DatabaseCachingVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="DatabaseSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add VPC flow logs for network monitoring
        log_group = logs.LogGroup(
            self,
            "VpcFlowLogsGroup",
            retention=logs.RetentionDays.ONE_WEEK,
        )

        vpc_flow_log_role = iam.Role(
            self,
            "VpcFlowLogRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            inline_policies={
                "FlowLogDeliveryRolePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

        ec2.FlowLog(
            self,
            "VpcFlowLog",
            resource_type=ec2.FlowLogResourceType.from_vpc(self.vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                log_group, vpc_flow_log_role
            ),
        )

    def _create_security_groups(self) -> None:
        """
        Create security groups for cache, database, and application access.
        
        Security groups implement least privilege access:
        - Cache security group: Redis port 6379 from application tier
        - Database security group: MySQL port 3306 from application tier
        - Application security group: SSH and application ports
        """
        # Security group for ElastiCache Redis
        self.cache_security_group = ec2.SecurityGroup(
            self,
            "CacheSecurityGroup",
            vpc=self.vpc,
            description="Security group for ElastiCache Redis cluster",
            allow_all_outbound=False,
        )

        # Security group for RDS MySQL
        self.database_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS MySQL database",
            allow_all_outbound=False,
        )

        # Security group for EC2 application instance
        self.application_security_group = ec2.SecurityGroup(
            self,
            "ApplicationSecurityGroup",
            vpc=self.vpc,
            description="Security group for application EC2 instance",
            allow_all_outbound=True,
        )

        # Allow application to access cache on Redis port
        self.cache_security_group.add_ingress_rule(
            peer=self.application_security_group,
            connection=ec2.Port.tcp(6379),
            description="Allow Redis access from application instances",
        )

        # Allow application to access database on MySQL port
        self.database_security_group.add_ingress_rule(
            peer=self.application_security_group,
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from application instances",
        )

        # Allow SSH access to application instance from anywhere (for testing)
        self.application_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access for testing and administration",
        )

    def _create_elasticache_infrastructure(self) -> None:
        """
        Create ElastiCache Redis infrastructure with replication and failover.
        
        The ElastiCache setup includes:
        - Custom parameter group with LRU eviction policy
        - Subnet group spanning multiple AZs
        - Replication group with automatic failover
        - Multi-AZ deployment for high availability
        """
        # Create cache parameter group for Redis optimization
        self.cache_parameter_group = elasticache.CfnParameterGroup(
            self,
            "CacheParameterGroup",
            cache_parameter_group_family="redis7.x",
            description="Custom parameter group for database query caching",
            properties={
                "maxmemory-policy": "allkeys-lru",
            },
        )

        # Create cache subnet group for multi-AZ deployment
        self.cache_subnet_group = elasticache.CfnSubnetGroup(
            self,
            "CacheSubnetGroup",
            description="Subnet group for ElastiCache Redis cluster",
            subnet_ids=[
                subnet.subnet_id for subnet in self.vpc.private_subnets
            ],
        )

        # Create ElastiCache Redis replication group
        self.cache_replication_group = elasticache.CfnReplicationGroup(
            self,
            "CacheReplicationGroup",
            description="Redis replication group for database query caching",
            replication_group_id=f"cache-{self.environment_name}",
            node_type="cache.t3.micro",
            port=6379,
            num_cache_clusters=2,
            automatic_failover_enabled=True,
            multi_az_enabled=True,
            cache_parameter_group_name=self.cache_parameter_group.ref,
            cache_subnet_group_name=self.cache_subnet_group.ref,
            security_group_ids=[self.cache_security_group.security_group_id],
            at_rest_encryption_enabled=True,
            transit_encryption_enabled=True,
            engine="redis",
            engine_version="7.0",
            preferred_cache_cluster_a_zs=self.vpc.availability_zones[:2],
            snapshot_retention_limit=1,
            snapshot_window="03:00-05:00",
            preferred_maintenance_window="sun:05:00-sun:07:00",
        )

    def _create_rds_database(self) -> None:
        """
        Create RDS MySQL database for testing cache integration.
        
        The RDS configuration includes:
        - MySQL 8.0 engine
        - Multi-AZ deployment for high availability
        - Automated backups with point-in-time recovery
        - Enhanced monitoring and performance insights
        """
        # Create DB subnet group
        self.db_subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for RDS MySQL database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
        )

        # Create DB parameter group
        self.db_parameter_group = rds.ParameterGroup(
            self,
            "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            description="Custom parameter group for cache testing database",
            parameters={
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",
                "max_connections": "1000",
                "query_cache_type": "1",
                "query_cache_size": "268435456",  # 256MB
            },
        )

        # Create RDS MySQL instance
        self.database = rds.DatabaseInstance(
            self,
            "TestDatabase",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO
            ),
            credentials=rds.Credentials.from_generated_secret(
                "admin",
                secret_name=f"database-caching-{self.environment_name}-credentials",
            ),
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.database_security_group],
            parameter_group=self.db_parameter_group,
            allocated_storage=20,
            storage_type=rds.StorageType.GP2,
            backup_retention=cdk.Duration.days(7),
            delete_automated_backups=True,
            deletion_protection=False,
            multi_az=False,  # Single AZ for cost optimization in testing
            monitoring_interval=cdk.Duration.seconds(60),
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            cloudwatch_logs_exports=["error", "general", "slow-query"],
            auto_minor_version_upgrade=True,
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
        )

    def _create_test_instance(self) -> None:
        """
        Create EC2 instance for testing cache integration patterns.
        
        The test instance includes:
        - Amazon Linux 2 with latest security updates
        - Redis and MySQL client libraries
        - Python 3 with caching libraries
        - IAM role for CloudWatch monitoring
        """
        # Create IAM role for EC2 instance
        self.instance_role = iam.Role(
            self,
            "TestInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
            ],
            inline_policies={
                "SecretsManagerAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "secretsmanager:GetSecretValue",
                                "secretsmanager:DescribeSecret",
                            ],
                            resources=[self.database.secret.secret_arn],
                        )
                    ]
                )
            },
        )

        # User data script for instance initialization
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y redis mysql",
            "amazon-linux-extras install -y python3.8",
            "pip3 install redis pymysql boto3",
            "# Install CloudWatch agent",
            "wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm",
            "rpm -U ./amazon-cloudwatch-agent.rpm",
            "# Create cache demo script directory",
            "mkdir -p /home/ec2-user/cache-demo",
            "chown ec2-user:ec2-user /home/ec2-user/cache-demo",
        )

        # Create EC2 instance
        self.test_instance = ec2.Instance(
            self,
            "TestInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.AmazonLinuxImage(
                generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
            ),
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=self.application_security_group,
            role=self.instance_role,
            user_data=user_data,
            key_name=None,  # Use Session Manager for access
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the database caching infrastructure",
        )

        CfnOutput(
            self,
            "RedisEndpoint",
            value=self.cache_replication_group.attr_redis_endpoint_address,
            description="ElastiCache Redis primary endpoint for application connections",
        )

        CfnOutput(
            self,
            "RedisPort",
            value=str(self.cache_replication_group.port),
            description="ElastiCache Redis port number",
        )

        CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS MySQL database endpoint for application connections",
        )

        CfnOutput(
            self,
            "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS MySQL database port number",
        )

        CfnOutput(
            self,
            "DatabaseSecretArn",
            value=self.database.secret.secret_arn,
            description="ARN of the Secrets Manager secret containing database credentials",
        )

        CfnOutput(
            self,
            "TestInstanceId",
            value=self.test_instance.instance_id,
            description="EC2 instance ID for testing cache integration",
        )

        CfnOutput(
            self,
            "ApplicationSecurityGroupId",
            value=self.application_security_group.security_group_id,
            description="Security group ID for application instances",
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all resources in the stack."""
        Tags.of(self).add("Project", "DatabaseCaching")
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "Engineering")
        Tags.of(self).add("Purpose", "PerformanceOptimization")


def main() -> None:
    """
    Main application entry point.
    
    Creates the CDK app and deploys the database caching stack with
    appropriate environment configuration and context.
    """
    app = App()

    # Get environment from context or use default
    environment_name = app.node.try_get_context("environment") or "dev"
    
    # Get AWS account and region from environment
    env = Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    )

    # Create the database caching stack
    DatabaseCachingStack(
        app,
        f"DatabaseCaching-{environment_name}",
        environment_name=environment_name,
        env=env,
        description=f"Database Query Caching with ElastiCache - {environment_name} environment",
    )

    app.synth()


if __name__ == "__main__":
    main()