#!/usr/bin/env python3
"""
CDK Application for Ethereum-Compatible Smart Contracts with Managed Blockchain

This application creates the complete infrastructure for deploying and managing
Ethereum smart contracts using AWS Managed Blockchain, Lambda, and API Gateway.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_managedblockchain as managedblockchain,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_s3 as s3,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    Tags,
)
import json
from typing import Any, Dict


class EthereumBlockchainStack(Stack):
    """
    Stack for Ethereum blockchain infrastructure with smart contract management.
    
    This stack creates:
    - AWS Managed Blockchain Ethereum node
    - Lambda function for smart contract interactions
    - API Gateway for REST API access
    - S3 bucket for contract artifacts
    - IAM roles and policies
    - CloudWatch monitoring and alarms
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        ethereum_network: str = "n-ethereum-mainnet",
        instance_type: str = "bc.t3.xlarge",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for contract artifacts
        self.contract_artifacts_bucket = s3.Bucket(
            self,
            "ContractArtifactsBucket",
            bucket_name=f"ethereum-artifacts-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create IAM role for Lambda function
        self.lambda_role = iam.Role(
            self,
            "EthereumLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add inline policy for Managed Blockchain and S3 access
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "managedblockchain:GET*",
                    "managedblockchain:List*",
                    "managedblockchain:InvokeAction",
                ],
                resources=["*"],
            )
        )

        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:PutObject"],
                resources=[f"{self.contract_artifacts_bucket.bucket_arn}/*"],
            )
        )

        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ssm:GetParameter", "ssm:GetParameters"],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/ethereum/*"
                ],
            )
        )

        # Create Ethereum node using Managed Blockchain
        self.ethereum_node = managedblockchain.CfnNode(
            self,
            "EthereumNode",
            network_id=ethereum_network,
            node_configuration=managedblockchain.CfnNode.NodeConfigurationProperty(
                instance_type=instance_type,
                availability_zone=f"{self.region}a",
            ),
        )

        # Create Lambda function for smart contract management
        self.contract_manager_lambda = lambda_.Function(
            self,
            "ContractManagerLambda",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "BUCKET_NAME": self.contract_artifacts_bucket.bucket_name,
                "ETHEREUM_NETWORK": ethereum_network,
                "NODE_ID": self.ethereum_node.attr_node_id,
            },
            description="Lambda function for Ethereum smart contract interactions",
        )

        # Create API Gateway for REST API
        self.api_gateway = apigateway.RestApi(
            self,
            "EthereumAPI",
            rest_api_name="ethereum-smart-contract-api",
            description="REST API for Ethereum smart contract operations",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization"],
            ),
            cloud_watch_role=True,
        )

        # Create /ethereum resource
        ethereum_resource = self.api_gateway.root.add_resource("ethereum")
        
        # Add POST method to /ethereum
        ethereum_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(
                self.contract_manager_lambda,
                proxy=True,
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_parameters={
                            "method.response.header.Access-Control-Allow-Origin": "'*'"
                        },
                    )
                ],
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    },
                )
            ],
        )

        # Create CloudWatch Log Group for API Gateway
        self.api_log_group = logs.LogGroup(
            self,
            "ApiGatewayLogGroup",
            log_group_name=f"/aws/apigateway/{self.api_gateway.rest_api_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudWatch dashboard for monitoring
        self.dashboard = cloudwatch.Dashboard(
            self,
            "EthereumBlockchainDashboard",
            dashboard_name=f"Ethereum-Blockchain-{self.stack_name}",
        )

        # Add Lambda metrics to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                left=[
                    self.contract_manager_lambda.metric_duration(),
                    self.contract_manager_lambda.metric_errors(),
                    self.contract_manager_lambda.metric_invocations(),
                ],
                width=12,
            )
        )

        # Add API Gateway metrics to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="API Gateway Metrics",
                left=[
                    self.api_gateway.metric_count(),
                    self.api_gateway.metric_latency(),
                    self.api_gateway.metric_client_error(),
                    self.api_gateway.metric_server_error(),
                ],
                width=12,
            )
        )

        # Create CloudWatch alarm for Lambda errors
        self.lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            metric=self.contract_manager_lambda.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            alarm_description="Alarm for Lambda function errors",
        )

        # Store node endpoints in Parameter Store (custom resource)
        self.node_endpoint_parameter = ssm.StringParameter(
            self,
            "NodeHttpEndpointParameter",
            parameter_name=f"/ethereum/{self.contract_manager_lambda.function_name}/http-endpoint",
            string_value=f"https://{self.ethereum_node.attr_node_id}.{ethereum_network}.managedblockchain.{self.region}.amazonaws.com",
            description="Ethereum node HTTP endpoint",
        )

        self.node_ws_parameter = ssm.StringParameter(
            self,
            "NodeWebSocketEndpointParameter",
            parameter_name=f"/ethereum/{self.contract_manager_lambda.function_name}/ws-endpoint",
            string_value=f"wss://{self.ethereum_node.attr_node_id}.{ethereum_network}.managedblockchain.{self.region}.amazonaws.com",
            description="Ethereum node WebSocket endpoint",
        )

        # Add tags to all resources
        Tags.of(self).add("Project", "EthereumSmartContracts")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "CDK")

        # Output important values
        cdk.CfnOutput(
            self,
            "EthereumNodeId",
            value=self.ethereum_node.attr_node_id,
            description="Ethereum Managed Blockchain Node ID",
        )

        cdk.CfnOutput(
            self,
            "ContractArtifactsBucket",
            value=self.contract_artifacts_bucket.bucket_name,
            description="S3 bucket for contract artifacts",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.contract_manager_lambda.function_name,
            description="Lambda function name for contract management",
        )

        cdk.CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api_gateway.url,
            description="API Gateway URL for Ethereum operations",
        )

        cdk.CfnOutput(
            self,
            "EthereumEndpoint",
            value=f"{self.api_gateway.url}ethereum",
            description="Complete endpoint for Ethereum smart contract operations",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as a string.
        This code handles smart contract interactions with the Ethereum network.
        """
        return """
const Web3 = require('web3');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');

const ssmClient = new SSMClient({ region: process.env.AWS_REGION });
const s3Client = new S3Client({ region: process.env.AWS_REGION });

async function getParameter(name) {
    const command = new GetParameterCommand({ Name: name });
    const response = await ssmClient.send(command);
    return response.Parameter.Value;
}

async function getContractArtifacts(bucket, key) {
    try {
        const command = new GetObjectCommand({ Bucket: bucket, Key: key });
        const response = await s3Client.send(command);
        return JSON.parse(await response.Body.transformToString());
    } catch (error) {
        console.log('Contract artifacts not found:', error.message);
        return null;
    }
}

exports.handler = async (event) => {
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,HEAD,OPTIONS,POST,PUT'
    };
    
    try {
        // Handle preflight OPTIONS request
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: corsHeaders,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }
        
        const body = JSON.parse(event.body || '{}');
        const action = body.action;
        
        // Get Ethereum node endpoint
        const httpEndpoint = await getParameter(
            `/ethereum/${process.env.AWS_LAMBDA_FUNCTION_NAME}/http-endpoint`
        );
        
        const web3 = new Web3(httpEndpoint);
        
        let result;
        
        switch (action) {
            case 'getBlockNumber':
                const blockNumber = await web3.eth.getBlockNumber();
                result = { blockNumber: blockNumber.toString() };
                break;
            
            case 'getBalance':
                const address = body.address;
                if (!address) {
                    throw new Error('Address is required for balance query');
                }
                const balance = await web3.eth.getBalance(address);
                result = { 
                    address, 
                    balance: web3.utils.fromWei(balance, 'ether') + ' ETH'
                };
                break;
            
            case 'deployContract':
                const contractData = await getContractArtifacts(
                    process.env.BUCKET_NAME, 
                    'contracts/SimpleToken.json'
                );
                
                if (!contractData) {
                    throw new Error('Contract artifacts not found. Please upload contract to S3.');
                }
                
                const contract = new web3.eth.Contract(contractData.abi);
                const deployTx = contract.deploy({
                    data: contractData.bytecode,
                    arguments: [body.initialSupply || 1000000]
                });
                
                const gasEstimate = await deployTx.estimateGas();
                const gasPrice = await web3.eth.getGasPrice();
                
                result = {
                    message: 'Contract deployment ready',
                    gasEstimate: gasEstimate.toString(),
                    gasPrice: gasPrice.toString(),
                    estimatedCost: web3.utils.fromWei(
                        (BigInt(gasEstimate) * BigInt(gasPrice)).toString(),
                        'ether'
                    ) + ' ETH',
                    deploymentData: deployTx.encodeABI()
                };
                break;
            
            case 'callContract':
                const contractAbi = await getContractArtifacts(
                    process.env.BUCKET_NAME, 
                    'contracts/SimpleToken.json'
                );
                
                if (!contractAbi) {
                    throw new Error('Contract ABI not found. Please upload contract to S3.');
                }
                
                if (!body.contractAddress) {
                    throw new Error('Contract address is required');
                }
                
                if (!body.method) {
                    throw new Error('Contract method is required');
                }
                
                const contractInstance = new web3.eth.Contract(
                    contractAbi.abi, 
                    body.contractAddress
                );
                
                const methodResult = await contractInstance.methods[body.method](...(body.params || [])).call();
                
                result = { 
                    method: body.method,
                    contractAddress: body.contractAddress,
                    result: methodResult
                };
                break;
            
            case 'getGasPrice':
                const currentGasPrice = await web3.eth.getGasPrice();
                const block = await web3.eth.getBlock('latest');
                
                result = {
                    gasPrice: currentGasPrice.toString(),
                    gasPriceGwei: web3.utils.fromWei(currentGasPrice, 'gwei'),
                    blockNumber: block.number.toString(),
                    baseFeePerGas: block.baseFeePerGas ? block.baseFeePerGas.toString() : 'N/A'
                };
                break;
            
            default:
                throw new Error(`Unknown action: ${action}`);
        }
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify(result)
        };
        
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ 
                error: error.message,
                timestamp: new Date().toISOString()
            })
        };
    }
};
"""


app = cdk.App()

# Create the stack
ethereum_stack = EthereumBlockchainStack(
    app,
    "EthereumBlockchainStack",
    description="Complete infrastructure for Ethereum smart contracts with AWS Managed Blockchain",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region") or "us-east-1",
    ),
)

app.synth()