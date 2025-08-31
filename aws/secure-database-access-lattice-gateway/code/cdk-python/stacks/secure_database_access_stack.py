"""
Secure Database Access Stack with VPC Lattice Resource Gateway

This stack creates a complete infrastructure for secure cross-account database access
using AWS VPC Lattice Resource Gateway. The solution includes:
- RDS MySQL database with encryption and private subnet deployment
- VPC Lattice Service Network for secure application networking
- Resource Gateway for database access abstraction and security
- Resource Configuration mapping database endpoints to VPC Lattice
- Security Groups implementing least privilege access controls
- IAM policies for cross-account authentication and authorization
- AWS RAM resource sharing for controlled cross-account access

Architecture:
- Database Owner Account: Contains RDS, Resource Gateway, Service Network
- Consumer Account: Accesses database through shared VPC Lattice resources
- Security: Multiple layers including VPC isolation, Security Groups, IAM, and RAM
"""

from typing import Optional, Dict, Any, List
import json

from aws_cdk import (
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    CustomResource,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_iam as iam,
    aws_ram as ram,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
    custom_resources as cr,
)
from constructs import Construct


class SecureDatabaseAccessStack(Stack):
    """
    CDK Stack for Secure Database Access with VPC Lattice Resource Gateway.
    
    This stack deploys a complete solution for secure cross-account database sharing
    using AWS VPC Lattice, including all necessary networking, security, and access
    control components.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        consumer_account_id: str,
        props: Optional[StackProps] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Secure Database Access Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            consumer_account_id: AWS Account ID that will consume the shared database
            props: Stack properties
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.consumer_account_id = consumer_account_id
        
        # Get configuration from context
        config = self._get_configuration()
        
        # Create VPC and networking components
        self.vpc = self._create_vpc(config)
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create RDS database with encryption and security
        self.database = self._create_rds_database(config)
        
        # Create VPC Lattice components
        self.service_network = self._create_service_network()
        self.resource_gateway = self._create_resource_gateway()
        self.resource_configuration = self._create_resource_configuration()
        
        # Configure IAM policies for cross-account access
        self._configure_iam_policies()
        
        # Create RAM resource share for cross-account sharing
        self.resource_share = self._create_ram_share()
        
        # Create CloudWatch log group for VPC Lattice (optional)
        self._create_monitoring_resources()
        
        # Create outputs for reference
        self._create_outputs()
    
    def _get_configuration(self) -> Dict[str, Any]:
        """
        Get configuration values from CDK context.
        
        Returns:
            Dictionary containing configuration values
        """
        return {
            "environment": self.node.try_get_context("environment") or "development",
            "enable_deletion_protection": self.node.try_get_context("enable_deletion_protection") or False,
            "database_backup_retention_days": self.node.try_get_context("database_backup_retention_days") or 7,
            "database_instance_class": self.node.try_get_context("database_instance_class") or "db.t3.micro",
            "database_allocated_storage": self.node.try_get_context("database_allocated_storage") or 20,
            "enable_performance_insights": self.node.try_get_context("enable_performance_insights") or False,
            "enable_enhanced_monitoring": self.node.try_get_context("enable_enhanced_monitoring") or False,
            "create_read_replica": self.node.try_get_context("create_read_replica") or False,
            "multi_az_deployment": self.node.try_get_context("multi_az_deployment") or False,
            "vpc_cidr": self.node.try_get_context("vpc_cidr") or "10.0.0.0/16",
            "create_new_vpc": self.node.try_get_context("create_new_vpc") or True,
            "enable_vpc_flow_logs": self.node.try_get_context("enable_vpc_flow_logs") or True,
            "enable_cloudtrail_logging": self.node.try_get_context("enable_cloudtrail_logging") or True,
        }
    
    def _create_vpc(self, config: Dict[str, Any]) -> ec2.Vpc:
        """
        Create VPC with private and public subnets for secure database deployment.
        
        Args:
            config: Configuration dictionary
            
        Returns:
            Created VPC instance
        """
        if config["create_new_vpc"]:
            # Create new VPC with secure configuration
            vpc = ec2.Vpc(
                self,
                "VpcLatticeVpc",
                ip_addresses=ec2.IpAddresses.cidr(config["vpc_cidr"]),
                max_azs=2,  # Use 2 AZs for high availability
                subnet_configuration=[
                    # Public subnets for NAT Gateways and ALB (if needed)
                    ec2.SubnetConfiguration(
                        name="PublicSubnet",
                        subnet_type=ec2.SubnetType.PUBLIC,
                        cidr_mask=24,
                    ),
                    # Private subnets for RDS and Resource Gateway
                    ec2.SubnetConfiguration(
                        name="PrivateSubnet",
                        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                        cidr_mask=24,
                    ),
                    # Isolated subnets for additional security (optional)
                    ec2.SubnetConfiguration(
                        name="IsolatedSubnet",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=28,
                    ),
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True,
                nat_gateways=1,  # Cost optimization - use 1 NAT Gateway
            )
            
            # Enable VPC Flow Logs for security monitoring
            if config["enable_vpc_flow_logs"]:
                flow_logs_role = iam.Role(
                    self,
                    "VpcFlowLogsRole",
                    assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
                    managed_policies=[
                        iam.ManagedPolicy.from_aws_managed_policy_name("service-role/VPCFlowLogsDeliveryRolePolicy")
                    ],
                )
                
                log_group = logs.LogGroup(
                    self,
                    "VpcFlowLogsGroup",
                    log_group_name=f"/aws/vpc/flowlogs/{self.stack_name}",
                    retention=logs.RetentionDays.ONE_MONTH,
                    removal_policy=RemovalPolicy.DESTROY,
                )
                
                ec2.FlowLog(
                    self,
                    "VpcFlowLogs",
                    resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
                    destination=ec2.FlowLogDestination.to_cloud_watch_logs(log_group, flow_logs_role),
                    traffic_type=ec2.FlowLogTrafficType.ALL,
                )
        else:
            # Use existing VPC (implement lookup logic if needed)
            raise NotImplementedError("Using existing VPC is not implemented in this example")
        
        return vpc
    
    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups with least privilege access controls.
        
        Returns:
            Dictionary containing security group references
        """
        # Security group for RDS database
        rds_sg = ec2.SecurityGroup(
            self,
            "RdsSecurityGroup",
            vpc=self.vpc,
            description="Security group for VPC Lattice shared RDS database",
            allow_all_outbound=False,  # Explicit outbound rules only
        )
        
        # Security group for Resource Gateway
        resource_gateway_sg = ec2.SecurityGroup(
            self,
            "ResourceGatewaySecurityGroup",
            vpc=self.vpc,
            description="Security group for VPC Lattice Resource Gateway",
            allow_all_outbound=False,  # Explicit outbound rules only
        )
        
        # Allow Resource Gateway to connect to RDS
        resource_gateway_sg.add_egress_rule(
            peer=rds_sg,
            connection=ec2.Port.tcp(3306),
            description="Allow Resource Gateway to connect to RDS MySQL",
        )
        
        # Allow RDS to receive connections from Resource Gateway
        rds_sg.add_ingress_rule(
            peer=resource_gateway_sg,
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL connections from Resource Gateway",
        )
        
        # Allow inbound traffic to Resource Gateway from VPC CIDR
        resource_gateway_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL traffic from VPC to Resource Gateway",
        )
        
        return {
            "rds": rds_sg,
            "resource_gateway": resource_gateway_sg,
        }
    
    def _create_rds_database(self, config: Dict[str, Any]) -> rds.DatabaseInstance:
        """
        Create RDS MySQL database with enterprise security configuration.
        
        Args:
            config: Configuration dictionary
            
        Returns:
            Created RDS database instance
        """
        # Create DB subnet group for RDS
        subnet_group = rds.SubnetGroup(
            self,
            "DbSubnetGroup",
            description="Subnet group for VPC Lattice shared database",
            vpc=self.vpc,
            subnet_group_name=f"lattice-db-subnet-group-{self.stack_name.lower()}",
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
        )
        
        # Create database credentials in Secrets Manager
        database_credentials = secretsmanager.Secret(
            self,
            "DatabaseCredentials",
            description="Credentials for VPC Lattice shared database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template=json.dumps({"username": "admin"}),
                generate_string_key="password",
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
                password_length=32,
            ),
        )
        
        # Create parameter group for performance optimization
        parameter_group = rds.ParameterGroup(
            self,
            "DbParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            description="Parameter group for VPC Lattice shared database",
            parameters={
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",  # 75% of available memory
                "max_connections": "1000",
                "slow_query_log": "1",
                "long_query_time": "1",
                "general_log": "1",
            },
        )
        
        # Create monitoring role if enhanced monitoring is enabled
        monitoring_role = None
        if config["enable_enhanced_monitoring"]:
            monitoring_role = iam.Role(
                self,
                "RdsMonitoringRole",
                assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonRDSEnhancedMonitoringRole")
                ],
            )
        
        # Create RDS database instance
        database = rds.DatabaseInstance(
            self,
            "SharedDatabase",
            instance_identifier=f"lattice-shared-db-{self.stack_name.lower()}",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO if config["database_instance_class"] == "db.t3.micro" else ec2.InstanceSize.SMALL
            ),
            credentials=rds.Credentials.from_secret(database_credentials),
            allocated_storage=config["database_allocated_storage"],
            storage_type=rds.StorageType.GP2,
            storage_encrypted=True,  # Enable encryption at rest
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[self.security_groups["rds"]],
            multi_az=config["multi_az_deployment"],
            publicly_accessible=False,  # Ensure database is not internet-accessible
            backup_retention=Duration.days(config["database_backup_retention_days"]),
            delete_automated_backups=not config["enable_deletion_protection"],
            deletion_protection=config["enable_deletion_protection"],
            parameter_group=parameter_group,
            monitoring_interval=Duration.seconds(60) if config["enable_enhanced_monitoring"] else None,
            monitoring_role=monitoring_role,
            enable_performance_insights=config["enable_performance_insights"],
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT if config["enable_performance_insights"] else None,
            cloudwatch_logs_exports=["error", "general", "slow-query"],  # Enable log exports
            auto_minor_version_upgrade=False,  # Explicit version control
            preferred_backup_window="03:00-04:00",  # Low traffic window
            preferred_maintenance_window="sun:04:00-sun:05:00",  # Maintenance window
        )
        
        # Add tags for cost allocation and management
        database.node.add_metadata("Purpose", "VPCLatticeDemo")
        database.node.add_metadata("SharedResource", "true")
        
        return database
    
    def _create_service_network(self) -> CustomResource:
        """
        Create VPC Lattice Service Network for secure application networking.
        
        Returns:
            Custom resource representing the Service Network
        """
        # Create service network using custom resource (VPC Lattice CDK constructs may not be available)
        service_network_provider = cr.Provider(
            self,
            "ServiceNetworkProvider",
            on_event_handler=self._create_vpc_lattice_lambda(),
        )
        
        service_network = CustomResource(
            self,
            "ServiceNetwork",
            service_token=service_network_provider.service_token,
            properties={
                "Action": "CreateServiceNetwork",
                "Name": f"lattice-network-{self.stack_name.lower()}",
                "AuthType": "AWS_IAM",
            },
        )
        
        # Associate VPC with service network
        vpc_association = CustomResource(
            self,
            "ServiceNetworkVpcAssociation",
            service_token=service_network_provider.service_token,
            properties={
                "Action": "CreateServiceNetworkVpcAssociation",
                "ServiceNetworkArn": service_network.get_att_string("Arn"),
                "VpcId": self.vpc.vpc_id,
                "SecurityGroupIds": [self.security_groups["resource_gateway"].security_group_id],
            },
        )
        vpc_association.node.add_dependency(service_network)
        
        return service_network
    
    def _create_resource_gateway(self) -> CustomResource:
        """
        Create VPC Lattice Resource Gateway for database access abstraction.
        
        Returns:
            Custom resource representing the Resource Gateway
        """
        resource_gateway_provider = cr.Provider(
            self,
            "ResourceGatewayProvider",
            on_event_handler=self._create_vpc_lattice_lambda(),
        )
        
        resource_gateway = CustomResource(
            self,
            "ResourceGateway",
            service_token=resource_gateway_provider.service_token,
            properties={
                "Action": "CreateResourceGateway",
                "Name": f"db-gateway-{self.stack_name.lower()}",
                "VpcId": self.vpc.vpc_id,
                "SubnetIds": [subnet.subnet_id for subnet in self.vpc.private_subnets],
                "SecurityGroupIds": [self.security_groups["resource_gateway"].security_group_id],
                "IpAddressType": "IPV4",
            },
        )
        
        return resource_gateway
    
    def _create_resource_configuration(self) -> CustomResource:
        """
        Create Resource Configuration mapping database to VPC Lattice.
        
        Returns:
            Custom resource representing the Resource Configuration
        """
        resource_config_provider = cr.Provider(
            self,
            "ResourceConfigProvider",
            on_event_handler=self._create_vpc_lattice_lambda(),
        )
        
        resource_configuration = CustomResource(
            self,
            "ResourceConfiguration",
            service_token=resource_config_provider.service_token,
            properties={
                "Action": "CreateResourceConfiguration",
                "Name": f"rds-config-{self.stack_name.lower()}",
                "Type": "SINGLE",
                "ResourceGatewayId": self.resource_gateway.get_att_string("Id"),
                "DomainName": self.database.instance_endpoint.hostname,
                "IpAddressType": "IPV4",
                "Protocol": "TCP",
                "Port": "3306",
            },
        )
        resource_configuration.node.add_dependency(self.resource_gateway)
        resource_configuration.node.add_dependency(self.database)
        
        # Associate resource configuration with service network
        config_association = CustomResource(
            self,
            "ResourceConfigAssociation",
            service_token=resource_config_provider.service_token,
            properties={
                "Action": "CreateResourceConfigurationAssociation",
                "ResourceConfigurationArn": resource_configuration.get_att_string("Arn"),
                "ServiceNetworkArn": self.service_network.get_att_string("Arn"),
            },
        )
        config_association.node.add_dependency(resource_configuration)
        config_association.node.add_dependency(self.service_network)
        
        return resource_configuration
    
    def _create_vpc_lattice_lambda(self):
        """
        Create Lambda function for VPC Lattice custom resource operations.
        
        Note: This is a simplified implementation. In production, you would
        implement the full Lambda function code for all VPC Lattice operations.
        """
        from aws_cdk.aws_lambda import Function, Runtime, Code
        
        lambda_function = Function(
            self,
            "VpcLatticeLambda",
            runtime=Runtime.PYTHON_3_9,
            handler="index.handler",
            code=Code.from_inline("""
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    
    # This is a placeholder implementation
    # In production, implement full VPC Lattice API operations
    
    request_type = event['RequestType']
    properties = event['ResourceProperties']
    
    if request_type == 'Create':
        # Implement VPC Lattice resource creation
        return {
            'PhysicalResourceId': 'vpc-lattice-resource',
            'Data': {
                'Arn': 'arn:aws:vpc-lattice:region:account:resource/placeholder',
                'Id': 'placeholder-id'
            }
        }
    elif request_type == 'Update':
        # Implement resource update
        return {
            'PhysicalResourceId': event['PhysicalResourceId']
        }
    elif request_type == 'Delete':
        # Implement resource deletion
        return {
            'PhysicalResourceId': event['PhysicalResourceId']
        }
            """),
        )
        
        # Grant necessary permissions
        lambda_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "vpc-lattice:*",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )
        
        return lambda_function
    
    def _configure_iam_policies(self) -> None:
        """
        Configure IAM policies for cross-account access to VPC Lattice resources.
        """
        # Create auth policy for service network
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": [f"arn:aws:iam::{self.consumer_account_id}:root"]
                    },
                    "Action": ["vpc-lattice-svcs:Invoke"],
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "vpc-lattice-svcs:SourceAccount": self.consumer_account_id
                        }
                    }
                }
            ]
        }
        
        # Apply auth policy using custom resource
        auth_policy_provider = cr.Provider(
            self,
            "AuthPolicyProvider",
            on_event_handler=self._create_vpc_lattice_lambda(),
        )
        
        CustomResource(
            self,
            "ServiceNetworkAuthPolicy",
            service_token=auth_policy_provider.service_token,
            properties={
                "Action": "PutAuthPolicy",
                "ResourceArn": self.service_network.get_att_string("Arn"),
                "Policy": json.dumps(auth_policy),
            },
        )
    
    def _create_ram_share(self) -> ram.CfnResourceShare:
        """
        Create AWS RAM resource share for cross-account access.
        
        Returns:
            RAM resource share
        """
        resource_share = ram.CfnResourceShare(
            self,
            "LatticeResourceShare",
            name=f"lattice-db-access-{self.stack_name.lower()}",
            resource_arns=[self.resource_configuration.get_att_string("Arn")],
            principals=[self.consumer_account_id],
            allow_external_principals=True,
            tags=[
                {
                    "key": "Purpose",
                    "value": "VPCLatticeDemo"
                },
                {
                    "key": "SharedResource",
                    "value": "true"
                }
            ]
        )
        
        return resource_share
    
    def _create_monitoring_resources(self) -> None:
        """
        Create CloudWatch resources for monitoring VPC Lattice access.
        """
        # Create log group for VPC Lattice access logs
        lattice_log_group = logs.LogGroup(
            self,
            "VpcLatticeAccessLogs",
            log_group_name=f"/aws/vpc-lattice/{self.stack_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create log group for database slow query logs
        db_log_group = logs.LogGroup(
            self,
            "DatabaseSlowQueryLogs",
            log_group_name=f"/aws/rds/slowquery/{self.stack_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
    
    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource references.
        """
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the VPC Lattice demo",
            export_name=f"{self.stack_name}-VpcId",
        )
        
        CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint hostname",
            export_name=f"{self.stack_name}-DatabaseEndpoint",
        )
        
        CfnOutput(
            self,
            "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS database port",
            export_name=f"{self.stack_name}-DatabasePort",
        )
        
        CfnOutput(
            self,
            "ServiceNetworkArn",
            value=self.service_network.get_att_string("Arn"),
            description="VPC Lattice Service Network ARN",
            export_name=f"{self.stack_name}-ServiceNetworkArn",
        )
        
        CfnOutput(
            self,
            "ResourceGatewayId",
            value=self.resource_gateway.get_att_string("Id"),
            description="VPC Lattice Resource Gateway ID",
            export_name=f"{self.stack_name}-ResourceGatewayId",
        )
        
        CfnOutput(
            self,
            "ResourceConfigurationArn",
            value=self.resource_configuration.get_att_string("Arn"),
            description="VPC Lattice Resource Configuration ARN",
            export_name=f"{self.stack_name}-ResourceConfigurationArn",
        )
        
        CfnOutput(
            self,
            "ConsumerAccountId",
            value=self.consumer_account_id,
            description="Consumer account ID for cross-account sharing",
            export_name=f"{self.stack_name}-ConsumerAccountId",
        )
        
        CfnOutput(
            self,
            "ResourceShareArn",
            value=self.resource_share.attr_arn,
            description="AWS RAM Resource Share ARN",
            export_name=f"{self.stack_name}-ResourceShareArn",
        )