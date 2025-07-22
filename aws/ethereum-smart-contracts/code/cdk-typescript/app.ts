#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as managedblockchain from 'aws-cdk-lib/aws-managedblockchain';
import * as cr from 'aws-cdk-lib/custom-resources';
import * as path from 'path';

/**
 * Properties for the EthereumManagedBlockchainStack
 */
export interface EthereumManagedBlockchainStackProps extends cdk.StackProps {
  /**
   * The Ethereum network to connect to
   * @default 'n-ethereum-mainnet'
   */
  readonly networkId?: string;

  /**
   * The instance type for the Ethereum node
   * @default 'bc.t3.xlarge'
   */
  readonly instanceType?: string;

  /**
   * The availability zone for the Ethereum node
   * @default 'us-east-1a'
   */
  readonly availabilityZone?: string;

  /**
   * Enable detailed CloudWatch monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;

  /**
   * Log retention period in days
   * @default 7
   */
  readonly logRetentionDays?: number;
}

/**
 * CDK Stack for Ethereum-compatible smart contracts with AWS Managed Blockchain
 * 
 * This stack creates:
 * - AWS Managed Blockchain Ethereum node
 * - Lambda function for smart contract interactions
 * - API Gateway for Web3 API access
 * - S3 bucket for contract artifacts
 * - CloudWatch monitoring and alarms
 * - IAM roles and policies with least privilege
 */
export class EthereumManagedBlockchainStack extends cdk.Stack {
  public readonly nodeId: string;
  public readonly httpEndpoint: string;
  public readonly wsEndpoint: string;
  public readonly apiEndpoint: string;
  public readonly artifactsBucket: s3.Bucket;
  public readonly contractManagerFunction: lambda.Function;
  public readonly web3Api: apigateway.RestApi;

  constructor(scope: Construct, id: string, props: EthereumManagedBlockchainStackProps = {}) {
    super(scope, id, props);

    const {
      networkId = 'n-ethereum-mainnet',
      instanceType = 'bc.t3.xlarge',
      availabilityZone = `${this.region}a`,
      enableDetailedMonitoring = true,
      logRetentionDays = 7,
    } = props;

    // Generate unique suffix for resources
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for contract artifacts
    this.artifactsBucket = new s3.Bucket(this, 'EthereumArtifactsBucket', {
      bucketName: `ethereum-artifacts-${this.account}-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'CleanupOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'EthereumLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add policies for Managed Blockchain access
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'managedblockchain:GetNode',
          'managedblockchain:ListNodes',
          'managedblockchain:GetNetwork',
        ],
        resources: ['*'],
      })
    );

    // Add S3 permissions for contract artifacts
    this.artifactsBucket.grantReadWrite(lambdaRole);

    // Add SSM permissions for parameter access
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ssm:GetParameter',
          'ssm:GetParameters',
          'ssm:GetParametersByPath',
        ],
        resources: [
          `arn:aws:ssm:${this.region}:${this.account}:parameter/ethereum/*`,
        ],
      })
    );

    // Create Ethereum node using Custom Resource
    const nodeCreationRole = new iam.Role(this, 'NodeCreationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    nodeCreationRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'managedblockchain:CreateNode',
          'managedblockchain:DeleteNode',
          'managedblockchain:GetNode',
          'managedblockchain:ListNodes',
          'managedblockchain:GetNetwork',
        ],
        resources: ['*'],
      })
    );

    // Custom Resource Lambda for node creation
    const nodeCreationLambda = new lambda.Function(this, 'NodeCreationLambda', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      role: nodeCreationRole,
      timeout: cdk.Duration.minutes(10),
      code: lambda.Code.fromInline(`
        const { ManagedBlockchainClient, CreateNodeCommand, DeleteNodeCommand, GetNodeCommand } = require('@aws-sdk/client-managedblockchain');
        const { SSMClient, PutParameterCommand, DeleteParameterCommand } = require('@aws-sdk/client-ssm');

        const managedBlockchain = new ManagedBlockchainClient({});
        const ssm = new SSMClient({});

        exports.handler = async (event) => {
          console.log('Event:', JSON.stringify(event, null, 2));
          
          const { RequestType, ResourceProperties } = event;
          const { NetworkId, InstanceType, AvailabilityZone, FunctionName } = ResourceProperties;
          
          try {
            if (RequestType === 'Create' || RequestType === 'Update') {
              const createCommand = new CreateNodeCommand({
                NetworkId,
                NodeConfiguration: {
                  InstanceType,
                  AvailabilityZone,
                },
              });
              
              const response = await managedBlockchain.send(createCommand);
              const nodeId = response.NodeId;
              
              // Wait for node to be available
              let nodeStatus = 'CREATING';
              while (nodeStatus === 'CREATING') {
                await new Promise(resolve => setTimeout(resolve, 30000)); // Wait 30 seconds
                
                const getCommand = new GetNodeCommand({
                  NetworkId,
                  NodeId: nodeId,
                });
                
                const nodeResponse = await managedBlockchain.send(getCommand);
                nodeStatus = nodeResponse.Node.Status;
                
                if (nodeStatus === 'FAILED') {
                  throw new Error('Node creation failed');
                }
              }
              
              const httpEndpoint = nodeResponse.Node.HttpEndpoint;
              const wsEndpoint = nodeResponse.Node.WebsocketEndpoint;
              
              // Store endpoints in Parameter Store
              await ssm.send(new PutParameterCommand({
                Name: \`/ethereum/\${FunctionName}/http-endpoint\`,
                Value: httpEndpoint,
                Type: 'String',
                Overwrite: true,
              }));
              
              await ssm.send(new PutParameterCommand({
                Name: \`/ethereum/\${FunctionName}/ws-endpoint\`,
                Value: wsEndpoint,
                Type: 'String',
                Overwrite: true,
              }));
              
              return {
                PhysicalResourceId: nodeId,
                Data: {
                  NodeId: nodeId,
                  HttpEndpoint: httpEndpoint,
                  WebsocketEndpoint: wsEndpoint,
                },
              };
            } else if (RequestType === 'Delete') {
              const nodeId = event.PhysicalResourceId;
              
              if (nodeId && nodeId !== 'FAILED') {
                const deleteCommand = new DeleteNodeCommand({
                  NetworkId,
                  NodeId: nodeId,
                });
                
                await managedBlockchain.send(deleteCommand);
                
                // Clean up parameters
                try {
                  await ssm.send(new DeleteParameterCommand({
                    Name: \`/ethereum/\${FunctionName}/http-endpoint\`,
                  }));
                  
                  await ssm.send(new DeleteParameterCommand({
                    Name: \`/ethereum/\${FunctionName}/ws-endpoint\`,
                  }));
                } catch (err) {
                  console.log('Parameter cleanup error (non-critical):', err);
                }
              }
              
              return {
                PhysicalResourceId: nodeId,
              };
            }
          } catch (error) {
            console.error('Error:', error);
            throw error;
          }
        };
      `),
    });

    // Create custom resource for Ethereum node
    const ethereumNode = new cdk.CustomResource(this, 'EthereumNode', {
      serviceToken: nodeCreationLambda.functionArn,
      properties: {
        NetworkId: networkId,
        InstanceType: instanceType,
        AvailabilityZone: availabilityZone,
        FunctionName: `eth-contract-manager-${uniqueSuffix}`,
      },
    });

    // Extract node information
    this.nodeId = ethereumNode.getAttString('NodeId');
    this.httpEndpoint = ethereumNode.getAttString('HttpEndpoint');
    this.wsEndpoint = ethereumNode.getAttString('WebsocketEndpoint');

    // Create Lambda function for contract management
    this.contractManagerFunction = new lambda.Function(this, 'EthereumContractManager', {
      functionName: `eth-contract-manager-${uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(1),
      memorySize: 512,
      environment: {
        BUCKET_NAME: this.artifactsBucket.bucketName,
        FUNCTION_NAME: `eth-contract-manager-${uniqueSuffix}`,
        NODE_ID: this.nodeId,
      },
      code: lambda.Code.fromInline(`
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
            const command = new GetObjectCommand({ Bucket: bucket, Key: key });
            const response = await s3Client.send(command);
            return JSON.parse(await response.Body.transformToString());
        }
        
        class GasOptimizer {
            constructor(web3Instance) {
                this.web3 = web3Instance;
            }
            
            async estimateOptimalGasPrice() {
                try {
                    const gasPrice = await this.web3.eth.getGasPrice();
                    const block = await this.web3.eth.getBlock('latest');
                    
                    const baseFee = block.baseFeePerGas || gasPrice;
                    const priorityFee = this.web3.utils.toWei('2', 'gwei');
                    
                    return {
                        gasPrice: gasPrice,
                        baseFee: baseFee,
                        maxFeePerGas: BigInt(baseFee) + BigInt(priorityFee),
                        maxPriorityFeePerGas: priorityFee
                    };
                } catch (error) {
                    console.error('Gas estimation error:', error);
                    throw error;
                }
            }
            
            async estimateContractGas(contract, method, params = []) {
                try {
                    const gasEstimate = await contract.methods[method](...params).estimateGas();
                    const gasPrice = await this.estimateOptimalGasPrice();
                    
                    return {
                        gasLimit: Math.ceil(gasEstimate * 1.2),
                        gasPrice: gasPrice,
                        estimatedCost: this.web3.utils.fromWei(
                            (BigInt(gasEstimate) * BigInt(gasPrice.gasPrice)).toString(),
                            'ether'
                        )
                    };
                } catch (error) {
                    console.error('Contract gas estimation error:', error);
                    throw error;
                }
            }
        }
        
        exports.handler = async (event) => {
            try {
                const httpEndpoint = await getParameter(\`/ethereum/\${process.env.FUNCTION_NAME}/http-endpoint\`);
                const web3 = new Web3(httpEndpoint);
                const gasOptimizer = new GasOptimizer(web3);
                
                const action = event.action;
                
                switch (action) {
                    case 'getBlockNumber':
                        const blockNumber = await web3.eth.getBlockNumber();
                        return {
                            statusCode: 200,
                            body: JSON.stringify({ 
                                blockNumber: blockNumber.toString(),
                                nodeId: process.env.NODE_ID
                            })
                        };
                    
                    case 'getBalance':
                        const address = event.address;
                        const balance = await web3.eth.getBalance(address);
                        return {
                            statusCode: 200,
                            body: JSON.stringify({ 
                                address, 
                                balance: web3.utils.fromWei(balance, 'ether') + ' ETH',
                                nodeId: process.env.NODE_ID
                            })
                        };
                    
                    case 'getGasPrice':
                        const gasInfo = await gasOptimizer.estimateOptimalGasPrice();
                        return {
                            statusCode: 200,
                            body: JSON.stringify({
                                gasPrice: gasInfo.gasPrice,
                                gasPriceGwei: web3.utils.fromWei(gasInfo.gasPrice, 'gwei'),
                                nodeId: process.env.NODE_ID
                            })
                        };
                    
                    case 'deployContract':
                        const contractData = await getContractArtifacts(
                            process.env.BUCKET_NAME, 
                            'contracts/SimpleToken.json'
                        );
                        
                        const contract = new web3.eth.Contract(contractData.abi);
                        const deployTx = contract.deploy({
                            data: contractData.bytecode,
                            arguments: [event.initialSupply || 1000000]
                        });
                        
                        const gasEstimate = await gasOptimizer.estimateContractGas(
                            contract, 
                            'constructor', 
                            [event.initialSupply || 1000000]
                        );
                        
                        return {
                            statusCode: 200,
                            body: JSON.stringify({
                                message: 'Contract deployment prepared',
                                gasEstimate: gasEstimate,
                                data: deployTx.encodeABI(),
                                nodeId: process.env.NODE_ID
                            })
                        };
                    
                    case 'callContract':
                        const contractAbi = await getContractArtifacts(
                            process.env.BUCKET_NAME, 
                            'contracts/SimpleToken.json'
                        );
                        
                        const contractInstance = new web3.eth.Contract(
                            contractAbi.abi, 
                            event.contractAddress
                        );
                        
                        const result = await contractInstance.methods[event.method](...event.params).call();
                        
                        return {
                            statusCode: 200,
                            body: JSON.stringify({ 
                                result,
                                nodeId: process.env.NODE_ID
                            })
                        };
                    
                    case 'getNetworkInfo':
                        const networkId = await web3.eth.net.getId();
                        const peerCount = await web3.eth.net.getPeerCount();
                        const syncing = await web3.eth.isSyncing();
                        
                        return {
                            statusCode: 200,
                            body: JSON.stringify({
                                networkId: networkId,
                                peerCount: peerCount,
                                syncing: syncing,
                                nodeId: process.env.NODE_ID
                            })
                        };
                    
                    default:
                        return {
                            statusCode: 400,
                            body: JSON.stringify({ 
                                error: 'Unknown action',
                                availableActions: [
                                    'getBlockNumber',
                                    'getBalance',
                                    'getGasPrice',
                                    'deployContract',
                                    'callContract',
                                    'getNetworkInfo'
                                ]
                            })
                        };
                }
            } catch (error) {
                console.error('Error:', error);
                return {
                    statusCode: 500,
                    body: JSON.stringify({ 
                        error: error.message,
                        nodeId: process.env.NODE_ID
                    })
                };
            }
        };
      `),
    });

    // Ensure Lambda function is created after the node
    this.contractManagerFunction.node.addDependency(ethereumNode);

    // Create API Gateway
    this.web3Api = new apigateway.RestApi(this, 'EthereumWeb3Api', {
      restApiName: `ethereum-api-${uniqueSuffix}`,
      description: 'Ethereum Smart Contract API powered by AWS Managed Blockchain',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      deployOptions: {
        stageName: 'prod',
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
    });

    // Create API resources and methods
    const ethereumResource = this.web3Api.root.addResource('ethereum');
    
    // Add POST method for contract interactions
    ethereumResource.addMethod('POST', new apigateway.LambdaIntegration(this.contractManagerFunction), {
      operationName: 'EthereumContractInteraction',
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '400',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // Add GET method for health check
    ethereumResource.addMethod('GET', new apigateway.LambdaIntegration(this.contractManagerFunction), {
      operationName: 'EthereumHealthCheck',
      requestParameters: {
        'method.request.querystring.action': false,
      },
    });

    this.apiEndpoint = this.web3Api.url;

    // Create CloudWatch Log Groups
    const apiLogGroup = new logs.LogGroup(this, 'ApiGatewayLogGroup', {
      logGroupName: `/aws/apigateway/ethereum-api-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const lambdaLogGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/eth-contract-manager-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch Dashboard
    if (enableDetailedMonitoring) {
      const dashboard = new cloudwatch.Dashboard(this, 'EthereumBlockchainDashboard', {
        dashboardName: `Ethereum-Blockchain-${uniqueSuffix}`,
        widgets: [
          [
            new cloudwatch.GraphWidget({
              title: 'Lambda Performance',
              width: 12,
              height: 6,
              left: [
                this.contractManagerFunction.metricDuration({
                  statistic: 'Average',
                  period: cdk.Duration.minutes(5),
                }),
                this.contractManagerFunction.metricErrors({
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
                this.contractManagerFunction.metricInvocations({
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
              ],
            }),
            new cloudwatch.GraphWidget({
              title: 'API Gateway Metrics',
              width: 12,
              height: 6,
              left: [
                this.web3Api.metricCount({
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
                this.web3Api.metricLatency({
                  statistic: 'Average',
                  period: cdk.Duration.minutes(5),
                }),
                this.web3Api.metricClientError({
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
                this.web3Api.metricServerError({
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
              ],
            }),
          ],
        ],
      });

      // Create CloudWatch Alarms
      const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
        alarmName: `${this.contractManagerFunction.functionName}-errors`,
        alarmDescription: 'Lambda function errors',
        metric: this.contractManagerFunction.metricErrors({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 5,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      const apiErrorAlarm = new cloudwatch.Alarm(this, 'ApiErrorAlarm', {
        alarmName: `ethereum-api-${uniqueSuffix}-errors`,
        alarmDescription: 'API Gateway 5xx errors',
        metric: this.web3Api.metricServerError({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 10,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
    }

    // Create sample contract artifacts
    const contractArtifacts = {
      abi: [
        {
          "inputs": [
            {
              "internalType": "uint256",
              "name": "_initialSupply",
              "type": "uint256"
            }
          ],
          "stateMutability": "nonpayable",
          "type": "constructor"
        },
        {
          "anonymous": false,
          "inputs": [
            {
              "indexed": true,
              "internalType": "address",
              "name": "owner",
              "type": "address"
            },
            {
              "indexed": true,
              "internalType": "address",
              "name": "spender",
              "type": "address"
            },
            {
              "indexed": false,
              "internalType": "uint256",
              "name": "value",
              "type": "uint256"
            }
          ],
          "name": "Approval",
          "type": "event"
        },
        {
          "anonymous": false,
          "inputs": [
            {
              "indexed": true,
              "internalType": "address",
              "name": "from",
              "type": "address"
            },
            {
              "indexed": true,
              "internalType": "address",
              "name": "to",
              "type": "address"
            },
            {
              "indexed": false,
              "internalType": "uint256",
              "name": "value",
              "type": "uint256"
            }
          ],
          "name": "Transfer",
          "type": "event"
        },
        {
          "inputs": [
            {
              "internalType": "address",
              "name": "spender",
              "type": "address"
            },
            {
              "internalType": "uint256",
              "name": "amount",
              "type": "uint256"
            }
          ],
          "name": "approve",
          "outputs": [
            {
              "internalType": "bool",
              "name": "",
              "type": "bool"
            }
          ],
          "stateMutability": "nonpayable",
          "type": "function"
        },
        {
          "inputs": [
            {
              "internalType": "address",
              "name": "account",
              "type": "address"
            }
          ],
          "name": "balanceOf",
          "outputs": [
            {
              "internalType": "uint256",
              "name": "",
              "type": "uint256"
            }
          ],
          "stateMutability": "view",
          "type": "function"
        },
        {
          "inputs": [],
          "name": "decimals",
          "outputs": [
            {
              "internalType": "uint8",
              "name": "",
              "type": "uint8"
            }
          ],
          "stateMutability": "view",
          "type": "function"
        },
        {
          "inputs": [],
          "name": "name",
          "outputs": [
            {
              "internalType": "string",
              "name": "",
              "type": "string"
            }
          ],
          "stateMutability": "view",
          "type": "function"
        },
        {
          "inputs": [],
          "name": "symbol",
          "outputs": [
            {
              "internalType": "string",
              "name": "",
              "type": "string"
            }
          ],
          "stateMutability": "view",
          "type": "function"
        },
        {
          "inputs": [],
          "name": "totalSupply",
          "outputs": [
            {
              "internalType": "uint256",
              "name": "",
              "type": "uint256"
            }
          ],
          "stateMutability": "view",
          "type": "function"
        },
        {
          "inputs": [
            {
              "internalType": "address",
              "name": "to",
              "type": "address"
            },
            {
              "internalType": "uint256",
              "name": "amount",
              "type": "uint256"
            }
          ],
          "name": "transfer",
          "outputs": [
            {
              "internalType": "bool",
              "name": "",
              "type": "bool"
            }
          ],
          "stateMutability": "nonpayable",
          "type": "function"
        },
        {
          "inputs": [
            {
              "internalType": "address",
              "name": "from",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "to",
              "type": "address"
            },
            {
              "internalType": "uint256",
              "name": "amount",
              "type": "uint256"
            }
          ],
          "name": "transferFrom",
          "outputs": [
            {
              "internalType": "bool",
              "name": "",
              "type": "bool"
            }
          ],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ],
      bytecode: "0x608060405234801561001057600080fd5b5060405161113238038061113283398101604081905261002f9161012a565b6040805180820190915260208082527f415753204d616e6167656420426c6f636b636861696e20546f6b656e00000000908201526000906100709082610202565b50604080518082019091526004808252634142544d60e01b602083015260019061009a9082610202565b506002805460ff19166012179055600254600a906100b890600a6103b6565b6100c290846103c9565b6100cc91906103e0565b6003556003546000336001600160a01b0316815260046020526040812091909155600354604051909133917fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef9190a350610402565b60006020828403121561013c57600080fd5b5051919050565b634e487b7160e01b600052604160045260246000fd5b600181811c9082168061016d57607f821691505b60208210810361018d57634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156101fd57600081815260208120601f850160051c810160208610156101ba5750805b601f850160051c820191505b818110156101d9578281556001016101c6565b505050505b505050565b81516001600160401b0381111561020357610203610143565b610217816102118454610159565b84610193565b602080601f83116001811461024c57600084156102345750858301515b600019600386901b1c1916600185901b1785556101d9565b600085815260208120601f198616915b8281101561027b5788860151825594840194600190910190840161025c565b50858210156102995787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b634e487b7160e01b600052601160045260246000fd5b600181815b808511156102fa5781600019048211156102e0576102e06102a9565b808516156102ed57918102915b93841c93908002906102c4565b509250929050565b60008261031157506001610384565b8161031e57506000610384565b816001811461033457600281146103405761035c565b6001915050610384565b60ff841115610351576103516102a9565b50506001821b610384565b5060208310610133831016604e8410600b8410161715610380575081810a610384565b61038a83836102bf565b806000190482111561039e5761039e6102a9565b029392505050565b60006103b2838361010d565b9392505050565b600082198211156103cc576103cc6102a9565b500190565b60008160001904831182151516156103e7576103e76102a9565b500290565b6000826103fd576103fd6102a9565b500490565b610d2180610411600039000"
    };

    // Deploy contract artifacts to S3
    const deployArtifacts = new cdk.CustomResource(this, 'DeployContractArtifacts', {
      serviceToken: new lambda.Function(this, 'DeployArtifactsLambda', {
        runtime: lambda.Runtime.NODEJS_18_X,
        handler: 'index.handler',
        timeout: cdk.Duration.minutes(5),
        code: lambda.Code.fromInline(`
          const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
          const s3 = new S3Client({});
          
          exports.handler = async (event) => {
            const { RequestType, ResourceProperties } = event;
            const { BucketName, ContractArtifacts } = ResourceProperties;
            
            if (RequestType === 'Create' || RequestType === 'Update') {
              try {
                await s3.send(new PutObjectCommand({
                  Bucket: BucketName,
                  Key: 'contracts/SimpleToken.json',
                  Body: JSON.stringify(ContractArtifacts, null, 2),
                  ContentType: 'application/json',
                }));
                
                const solidityCode = \`// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleToken {
    string public name = "AWS Managed Blockchain Token";
    string public symbol = "AMBT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(uint256 _initialSupply) {
        totalSupply = _initialSupply * 10**decimals;
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balances[from] >= amount, "Insufficient balance");
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}\`;
                
                await s3.send(new PutObjectCommand({
                  Bucket: BucketName,
                  Key: 'contracts/SimpleToken.sol',
                  Body: solidityCode,
                  ContentType: 'text/plain',
                }));
                
                return { PhysicalResourceId: 'contract-artifacts' };
              } catch (error) {
                console.error('Error deploying artifacts:', error);
                throw error;
              }
            }
            
            return { PhysicalResourceId: event.PhysicalResourceId };
          };
        `),
        role: new iam.Role(this, 'ArtifactsDeployRole', {
          assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
          managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
          ],
          inlinePolicies: {
            S3Access: new iam.PolicyDocument({
              statements: [
                new iam.PolicyStatement({
                  effect: iam.Effect.ALLOW,
                  actions: ['s3:PutObject'],
                  resources: [`${this.artifactsBucket.bucketArn}/*`],
                }),
              ],
            }),
          },
        }),
      }).functionArn,
      properties: {
        BucketName: this.artifactsBucket.bucketName,
        ContractArtifacts: contractArtifacts,
      },
    });

    // Outputs
    new cdk.CfnOutput(this, 'NodeId', {
      value: this.nodeId,
      description: 'Ethereum node ID',
    });

    new cdk.CfnOutput(this, 'HttpEndpoint', {
      value: this.httpEndpoint,
      description: 'Ethereum node HTTP endpoint',
    });

    new cdk.CfnOutput(this, 'WebSocketEndpoint', {
      value: this.wsEndpoint,
      description: 'Ethereum node WebSocket endpoint',
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.apiEndpoint,
      description: 'API Gateway endpoint for Web3 interactions',
    });

    new cdk.CfnOutput(this, 'ArtifactsBucket', {
      value: this.artifactsBucket.bucketName,
      description: 'S3 bucket for contract artifacts',
    });

    new cdk.CfnOutput(this, 'LambdaFunction', {
      value: this.contractManagerFunction.functionName,
      description: 'Lambda function for contract management',
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `curl -X POST ${this.apiEndpoint}ethereum -H "Content-Type: application/json" -d '{"action":"getBlockNumber"}'`,
      description: 'Test command to verify API functionality',
    });
  }
}

/**
 * CDK App for deploying Ethereum Managed Blockchain infrastructure
 */
const app = new cdk.App();

// Create stack with environment configuration
new EthereumManagedBlockchainStack(app, 'EthereumManagedBlockchainStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CDK stack for Ethereum-compatible smart contracts with AWS Managed Blockchain',
  tags: {
    Project: 'EthereumSmartContracts',
    Environment: 'Development',
    Owner: 'DevOps',
    CostCenter: 'Blockchain',
  },
});

app.synth();