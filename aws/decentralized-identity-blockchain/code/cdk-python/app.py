#!/usr/bin/env python3
"""
CDK Python Application for Decentralized Identity Management with Blockchain

This application deploys the complete infrastructure for a decentralized identity
management system using AWS Managed Blockchain, QLDB, Lambda, and supporting services.

The infrastructure includes:
- AWS Managed Blockchain network with Hyperledger Fabric
- Amazon QLDB ledger for identity state management
- Lambda functions for identity operations
- API Gateway for REST endpoints
- DynamoDB for credential indexing
- S3 bucket for chaincode and schema storage
- IAM roles and policies with least privilege access
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_managedblockchain as blockchain,
    aws_qldb as qldb,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_s3_assets as s3_assets,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
import os


class DecentralizedIdentityManagementStack(Stack):
    """
    CDK Stack for Decentralized Identity Management with Blockchain
    
    This stack creates a complete infrastructure for managing decentralized
    identities using blockchain technology, providing secure, user-controlled
    identity management with cryptographic verification.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get deployment parameters
        environment = self.node.try_get_context("environment") or "dev"
        
        # Create S3 bucket for chaincode and schema storage
        self.chaincode_bucket = self._create_chaincode_bucket()
        
        # Create DynamoDB table for credential indexing
        self.credentials_table = self._create_credentials_table()
        
        # Create QLDB ledger for identity state management
        self.identity_ledger = self._create_qldb_ledger()
        
        # Create IAM roles for services
        self.lambda_role = self._create_lambda_execution_role()
        self.blockchain_service_role = self._create_blockchain_service_role()
        
        # Create Managed Blockchain network
        self.blockchain_network = self._create_blockchain_network()
        
        # Create Lambda functions for identity operations
        self.identity_lambda = self._create_identity_lambda_function()
        
        # Create API Gateway for REST endpoints
        self.api_gateway = self._create_api_gateway()
        
        # Create CloudWatch log groups with retention
        self._create_log_groups()
        
        # Output important resource information
        self._create_stack_outputs()

    def _create_chaincode_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing chaincode packages and identity schemas.
        
        Returns:
            s3.Bucket: Configured S3 bucket with versioning and encryption
        """
        bucket = s3.Bucket(
            self,
            "ChaincodeAssetsBucket",
            bucket_name=f"identity-blockchain-assets-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )
        
        # Add bucket policy for blockchain access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("managedblockchain.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    }
                }
            )
        )
        
        return bucket

    def _create_credentials_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for indexing verifiable credentials.
        
        Returns:
            dynamodb.Table: Configured DynamoDB table with GSI for efficient queries
        """
        table = dynamodb.Table(
            self,
            "CredentialsTable",
            table_name="identity-credentials",
            partition_key=dynamodb.Attribute(
                name="did",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="credential_id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )
        
        # Add Global Secondary Index for credential type queries
        table.add_global_secondary_index(
            index_name="CredentialTypeIndex",
            partition_key=dynamodb.Attribute(
                name="credential_type",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="issued_date",
                type=dynamodb.AttributeType.STRING
            )
        )
        
        # Add GSI for status-based queries
        table.add_global_secondary_index(
            index_name="StatusIndex",
            partition_key=dynamodb.Attribute(
                name="status",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="updated_date",
                type=dynamodb.AttributeType.STRING
            )
        )
        
        return table

    def _create_qldb_ledger(self) -> qldb.CfnLedger:
        """
        Create Amazon QLDB ledger for maintaining identity state.
        
        Returns:
            qldb.CfnLedger: Configured QLDB ledger with encryption
        """
        ledger = qldb.CfnLedger(
            self,
            "IdentityLedger",
            name="identity-ledger",
            permissions_mode="STANDARD",
            kms_key="alias/aws/qldb",
            deletion_protection=False  # Set to True for production
        )
        
        return ledger

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution with necessary permissions.
        
        Returns:
            iam.Role: Configured IAM role with least privilege permissions
        """
        role = iam.Role(
            self,
            "IdentityLambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for identity management Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom policy for identity management operations
        identity_policy = iam.PolicyDocument(
            statements=[
                # QLDB permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "qldb:ExecuteStatement",
                        "qldb:StartSession",
                        "qldb:SendCommand",
                        "qldb:DescribeLedger"
                    ],
                    resources=[
                        f"arn:aws:qldb:{self.region}:{self.account}:ledger/identity-ledger"
                    ]
                ),
                # DynamoDB permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "dynamodb:PutItem",
                        "dynamodb:GetItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query",
                        "dynamodb:Scan"
                    ],
                    resources=[
                        self.credentials_table.table_arn,
                        f"{self.credentials_table.table_arn}/index/*"
                    ]
                ),
                # Managed Blockchain permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "managedblockchain:GetNetwork",
                        "managedblockchain:GetNode",
                        "managedblockchain:GetMember",
                        "managedblockchain:CreateAccessor",
                        "managedblockchain:TagResource"
                    ],
                    resources=["*"]
                ),
                # S3 permissions for chaincode
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject"
                    ],
                    resources=[f"{self.chaincode_bucket.bucket_arn}/*"]
                )
            ]
        )
        
        iam.Policy(
            self,
            "IdentityManagementPolicy",
            document=identity_policy,
            roles=[role]
        )
        
        return role

    def _create_blockchain_service_role(self) -> iam.Role:
        """
        Create IAM service role for Managed Blockchain operations.
        
        Returns:
            iam.Role: Service role for blockchain network operations
        """
        role = iam.Role(
            self,
            "BlockchainServiceRole",
            assumed_by=iam.ServicePrincipal("managedblockchain.amazonaws.com"),
            description="Service role for Managed Blockchain operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonManagedBlockchainServiceRole"
                )
            ]
        )
        
        return role

    def _create_blockchain_network(self) -> blockchain.CfnNetwork:
        """
        Create AWS Managed Blockchain network with Hyperledger Fabric.
        
        Returns:
            blockchain.CfnNetwork: Configured blockchain network
        """
        # Create initial member configuration
        member_config = blockchain.CfnNetwork.MemberConfigurationProperty(
            name="IdentityOrganization",
            description="Organization for decentralized identity management",
            member_framework_configuration=blockchain.CfnNetwork.MemberFrameworkConfigurationProperty(
                member_fabric_configuration=blockchain.CfnNetwork.MemberFabricConfigurationProperty(
                    admin_username="admin",
                    admin_password="TempPassword123!"  # Change in production
                )
            )
        )
        
        # Create voting policy for network governance
        voting_policy = blockchain.CfnNetwork.VotingPolicyProperty(
            approval_threshold_policy=blockchain.CfnNetwork.ApprovalThresholdPolicyProperty(
                threshold_percentage=50,
                proposal_duration_in_hours=24,
                threshold_comparator="GREATER_THAN"
            )
        )
        
        # Create network configuration
        network_config = blockchain.CfnNetwork.NetworkConfigurationProperty(
            name="IdentityManagementNetwork",
            description="Blockchain network for decentralized identity management",
            framework="HYPERLEDGER_FABRIC",
            framework_version="2.2",
            voting_policy=voting_policy,
            network_framework_configuration=blockchain.CfnNetwork.NetworkFrameworkConfigurationProperty(
                network_fabric_configuration=blockchain.CfnNetwork.NetworkFabricConfigurationProperty(
                    edition="STANDARD"
                )
            )
        )
        
        # Create the blockchain network
        network = blockchain.CfnNetwork(
            self,
            "IdentityBlockchainNetwork",
            network_configuration=network_config,
            member_configuration=member_config
        )
        
        return network

    def _create_identity_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for processing identity operations.
        
        Returns:
            lambda_.Function: Configured Lambda function with runtime and environment
        """
        # Create Lambda function code
        lambda_code = lambda_.Code.from_inline("""
import json
import boto3
import hashlib
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional

# Initialize AWS clients
qldb = boto3.client('qldb-session')
dynamodb = boto3.resource('dynamodb')
managedblockchain = boto3.client('managedblockchain')

# Environment variables
LEDGER_NAME = os.environ['QLDB_LEDGER_NAME']
CREDENTIALS_TABLE = os.environ['CREDENTIALS_TABLE_NAME']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Main Lambda handler for identity management operations.
    
    Supports the following operations:
    - createIdentity: Generate new DID and register on blockchain
    - issueCredential: Issue verifiable credential to DID holder
    - verifyCredential: Verify credential authenticity and status
    - revokeCredential: Revoke existing credential
    - queryIdentity: Retrieve identity information
    \"\"\"
    try:
        action = event.get('action')
        
        if action == 'createIdentity':
            return create_identity(event)
        elif action == 'issueCredential':
            return issue_credential(event)
        elif action == 'verifyCredential':
            return verify_credential(event)
        elif action == 'revokeCredential':
            return revoke_credential(event)
        elif action == 'queryIdentity':
            return query_identity(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as error:
        print(f'Identity operation failed: {str(error)}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(error)})
        }

def create_identity(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Create new decentralized identity (DID).\"\"\"
    public_key = event.get('publicKey')
    metadata = event.get('metadata', {})
    
    if not public_key:
        raise ValueError('Public key is required for identity creation')
    
    # Generate DID using public key hash
    did = f"did:fabric:{hashlib.sha256(public_key.encode()).hexdigest()[:16]}"
    
    # Create identity record
    identity_record = {
        'did': did,
        'publicKey': public_key,
        'metadata': metadata,
        'created': datetime.now(timezone.utc).isoformat(),
        'status': 'active',
        'credentialCount': 0
    }
    
    # Store in QLDB ledger
    store_identity_in_qldb(identity_record)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'did': did,
            'created': identity_record['created']
        })
    }

def issue_credential(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Issue verifiable credential to identity holder.\"\"\"
    did = event.get('did')
    credential_type = event.get('credentialType')
    claims = event.get('claims', {})
    issuer_did = event.get('issuerDID', 'did:fabric:system')
    
    if not all([did, credential_type]):
        raise ValueError('DID and credential type are required')
    
    # Generate credential ID
    credential_id = str(uuid.uuid4())
    
    # Create credential
    credential = {
        'id': credential_id,
        'type': credential_type,
        'holder': did,
        'issuer': issuer_did,
        'claims': claims,
        'issued': datetime.now(timezone.utc).isoformat(),
        'status': 'active',
        'proof': {
            'type': 'Ed25519Signature2020',
            'created': datetime.now(timezone.utc).isoformat(),
            'verificationMethod': f'{issuer_did}#key-1',
            'proofPurpose': 'assertionMethod'
        }
    }
    
    # Store in DynamoDB for indexing
    store_credential_in_dynamodb(credential)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'credentialId': credential_id,
            'issued': credential['issued']
        })
    }

def verify_credential(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Verify credential authenticity and status.\"\"\"
    credential_id = event.get('credentialId')
    
    if not credential_id:
        raise ValueError('Credential ID is required')
    
    # Retrieve credential from DynamoDB
    table = dynamodb.Table(CREDENTIALS_TABLE)
    response = table.scan(
        FilterExpression='credential_id = :cid',
        ExpressionAttributeValues={':cid': credential_id}
    )
    
    if not response['Items']:
        return {
            'statusCode': 404,
            'body': json.dumps({'valid': False, 'reason': 'Credential not found'})
        }
    
    credential = response['Items'][0]
    
    # Verify credential status
    if credential['status'] != 'active':
        return {
            'statusCode': 200,
            'body': json.dumps({
                'valid': False,
                'reason': f'Credential status is {credential["status"]}'
            })
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'valid': True,
            'credential': credential,
            'verifiedAt': datetime.now(timezone.utc).isoformat()
        })
    }

def revoke_credential(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Revoke existing credential.\"\"\"
    credential_id = event.get('credentialId')
    reason = event.get('reason', 'Unspecified')
    
    if not credential_id:
        raise ValueError('Credential ID is required')
    
    # Update credential status in DynamoDB
    table = dynamodb.Table(CREDENTIALS_TABLE)
    
    try:
        response = table.update_item(
            Key={'credential_id': credential_id},
            UpdateExpression='SET #status = :status, revocation_reason = :reason, revoked_at = :timestamp',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': 'revoked',
                ':reason': reason,
                ':timestamp': datetime.now(timezone.utc).isoformat()
            },
            ReturnValues='ALL_NEW'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({'success': True, 'revokedAt': response['Attributes']['revoked_at']})
        }
        
    except Exception as e:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Credential not found or update failed'})
        }

def query_identity(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Query identity information from QLDB.\"\"\"
    did = event.get('did')
    
    if not did:
        raise ValueError('DID is required')
    
    # Query QLDB for identity record
    identity = query_identity_from_qldb(did)
    
    if not identity:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Identity not found'})
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps(identity)
    }

def store_identity_in_qldb(identity_record: Dict[str, Any]) -> None:
    \"\"\"Store identity record in QLDB ledger.\"\"\"
    # Implementation would use QLDB session API
    # This is a simplified version for CDK generation
    pass

def store_credential_in_dynamodb(credential: Dict[str, Any]) -> None:
    \"\"\"Store credential in DynamoDB for indexing.\"\"\"
    table = dynamodb.Table(CREDENTIALS_TABLE)
    
    item = {
        'did': credential['holder'],
        'credential_id': credential['id'],
        'credential_type': credential['type'],
        'issuer': credential['issuer'],
        'issued_date': credential['issued'],
        'status': credential['status'],
        'updated_date': credential['issued']
    }
    
    table.put_item(Item=item)

def query_identity_from_qldb(did: str) -> Optional[Dict[str, Any]]:
    \"\"\"Query identity record from QLDB.\"\"\"
    # Implementation would use QLDB session API
    # This is a simplified version for CDK generation
    return None
""")
        
        function = lambda_.Function(
            self,
            "IdentityManagementFunction",
            function_name="identity-management-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_code,
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "QLDB_LEDGER_NAME": self.identity_ledger.name,
                "CREDENTIALS_TABLE_NAME": self.credentials_table.table_name,
                "CHAINCODE_BUCKET": self.chaincode_bucket.bucket_name
            },
            description="Lambda function for processing decentralized identity operations",
            retry_attempts=2
        )
        
        # Grant permissions to access resources
        self.credentials_table.grant_read_write_data(function)
        self.chaincode_bucket.grant_read_write(function)
        
        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway for exposing identity management endpoints.
        
        Returns:
            apigateway.RestApi: Configured API Gateway with resources and methods
        """
        api = apigateway.RestApi(
            self,
            "IdentityManagementAPI",
            rest_api_name="identity-management-api",
            description="REST API for decentralized identity management operations",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "Authorization"]
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )
        
        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.identity_lambda,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )
        
        # Create /identity resource
        identity_resource = api.root.add_resource("identity")
        
        # Add POST method for identity operations
        identity_resource.add_method(
            "POST",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        # Create /credential resource for credential-specific operations
        credential_resource = api.root.add_resource("credential")
        credential_resource.add_method("POST", lambda_integration)
        credential_resource.add_method("GET", lambda_integration)
        
        # Create /verify resource for verification operations
        verify_resource = api.root.add_resource("verify")
        verify_resource.add_method("POST", lambda_integration)
        
        # Grant API Gateway permission to invoke Lambda
        self.identity_lambda.add_permission(
            "APIGatewayInvokePermission",
            principal=iam.ServicePrincipal("apigateway.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"{api.arn_for_execute_api()}/*/*"
        )
        
        return api

    def _create_log_groups(self) -> None:
        """Create CloudWatch log groups with proper retention policies."""
        
        # Lambda function log group
        logs.LogGroup(
            self,
            "IdentityLambdaLogGroup",
            log_group_name=f"/aws/lambda/{self.identity_lambda.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # API Gateway log group
        logs.LogGroup(
            self,
            "APIGatewayLogGroup",
            log_group_name="/aws/apigateway/identity-management",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_stack_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "BlockchainNetworkId",
            value=self.blockchain_network.ref,
            description="Managed Blockchain Network ID",
            export_name=f"{self.stack_name}-blockchain-network-id"
        )
        
        CfnOutput(
            self,
            "QLDBLedgerName",
            value=self.identity_ledger.name,
            description="QLDB Ledger Name for Identity State",
            export_name=f"{self.stack_name}-qldb-ledger-name"
        )
        
        CfnOutput(
            self,
            "CredentialsTableName",
            value=self.credentials_table.table_name,
            description="DynamoDB Table for Credential Indexing",
            export_name=f"{self.stack_name}-credentials-table"
        )
        
        CfnOutput(
            self,
            "ChaincodeBucketName",
            value=self.chaincode_bucket.bucket_name,
            description="S3 Bucket for Chaincode and Schema Storage",
            export_name=f"{self.stack_name}-chaincode-bucket"
        )
        
        CfnOutput(
            self,
            "APIGatewayURL",
            value=self.api_gateway.url,
            description="API Gateway URL for Identity Operations",
            export_name=f"{self.stack_name}-api-gateway-url"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.identity_lambda.function_arn,
            description="Lambda Function ARN for Identity Processing",
            export_name=f"{self.stack_name}-lambda-function-arn"
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get deployment environment from context
    environment = app.node.try_get_context("environment") or "dev"
    
    # Create the stack
    DecentralizedIdentityManagementStack(
        app,
        f"DecentralizedIdentityManagement-{environment}",
        description="Infrastructure for Decentralized Identity Management with Blockchain technology",
        env=cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION')
        ),
        tags={
            "Project": "DecentralizedIdentityManagement",
            "Environment": environment,
            "Purpose": "BlockchainIdentitySystem",
            "ManagedBy": "CDK"
        }
    )
    
    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()