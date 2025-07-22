const Web3 = require('web3');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const GasOptimizer = require('./gas-optimizer');

// Initialize AWS SDK clients
const ssmClient = new SSMClient({ region: '${aws_region}' });
const s3Client = new S3Client({ region: '${aws_region}' });

/**
 * Retrieves a parameter value from AWS Systems Manager Parameter Store
 * @param {string} name - Parameter name
 * @returns {Promise<string>} Parameter value
 */
async function getParameter(name) {
    try {
        const command = new GetParameterCommand({ Name: name });
        const response = await ssmClient.send(command);
        return response.Parameter.Value;
    } catch (error) {
        console.error(`Error retrieving parameter ${name}:`, error);
        throw error;
    }
}

/**
 * Retrieves contract artifacts from S3
 * @param {string} bucket - S3 bucket name
 * @param {string} key - S3 object key
 * @returns {Promise<Object>} Contract artifacts
 */
async function getContractArtifacts(bucket, key) {
    try {
        const command = new GetObjectCommand({ Bucket: bucket, Key: key });
        const response = await s3Client.send(command);
        return JSON.parse(await response.Body.transformToString());
    } catch (error) {
        console.error(`Error retrieving contract artifacts ${key}:`, error);
        throw error;
    }
}

/**
 * Stores contract artifacts in S3
 * @param {string} bucket - S3 bucket name
 * @param {string} key - S3 object key
 * @param {Object} data - Contract data to store
 * @returns {Promise<void>}
 */
async function putContractArtifacts(bucket, key, data) {
    try {
        const command = new PutObjectCommand({
            Bucket: bucket,
            Key: key,
            Body: JSON.stringify(data, null, 2),
            ContentType: 'application/json'
        });
        await s3Client.send(command);
    } catch (error) {
        console.error(`Error storing contract artifacts ${key}:`, error);
        throw error;
    }
}

/**
 * Validates Ethereum address format
 * @param {string} address - Ethereum address
 * @returns {boolean} True if valid address
 */
function isValidAddress(address) {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
}

/**
 * Main Lambda handler function
 * @param {Object} event - Lambda event object
 * @param {Object} context - Lambda context object
 * @returns {Promise<Object>} Lambda response
 */
exports.handler = async (event, context) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    // Set up response headers for CORS
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
    };
    
    try {
        // Handle preflight CORS requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: corsHeaders,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }
        
        // Parse request body
        let requestBody;
        try {
            requestBody = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        } catch (parseError) {
            console.error('Error parsing request body:', parseError);
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Invalid JSON in request body' })
            };
        }
        
        const action = requestBody.action;
        
        if (!action) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Action parameter is required' })
            };
        }
        
        // Get Ethereum node endpoint
        const httpEndpoint = await getParameter(`/ethereum/${function_name}/http-endpoint`);
        
        // Initialize Web3 with the managed blockchain node
        const web3 = new Web3(httpEndpoint);
        const gasOptimizer = new GasOptimizer(web3);
        
        // Handle different actions
        switch (action) {
            case 'getBlockNumber':
                return await handleGetBlockNumber(web3, corsHeaders);
                
            case 'getBalance':
                return await handleGetBalance(web3, requestBody, corsHeaders);
                
            case 'getGasPrice':
                return await handleGetGasPrice(gasOptimizer, corsHeaders);
                
            case 'deployContract':
                return await handleDeployContract(web3, gasOptimizer, requestBody, corsHeaders);
                
            case 'callContract':
                return await handleCallContract(web3, requestBody, corsHeaders);
                
            case 'sendTransaction':
                return await handleSendTransaction(web3, gasOptimizer, requestBody, corsHeaders);
                
            case 'getTransactionReceipt':
                return await handleGetTransactionReceipt(web3, requestBody, corsHeaders);
                
            case 'estimateGas':
                return await handleEstimateGas(web3, gasOptimizer, requestBody, corsHeaders);
                
            default:
                return {
                    statusCode: 400,
                    headers: corsHeaders,
                    body: JSON.stringify({ error: `Unknown action: ${action}` })
                };
        }
    } catch (error) {
        console.error('Lambda execution error:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ 
                error: 'Internal server error',
                message: error.message,
                requestId: context.awsRequestId
            })
        };
    }
};

/**
 * Handle get block number request
 */
async function handleGetBlockNumber(web3, corsHeaders) {
    try {
        const blockNumber = await web3.eth.getBlockNumber();
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ 
                blockNumber: blockNumber.toString(),
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error getting block number:', error);
        throw error;
    }
}

/**
 * Handle get balance request
 */
async function handleGetBalance(web3, requestBody, corsHeaders) {
    try {
        const { address } = requestBody;
        
        if (!address) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Address parameter is required' })
            };
        }
        
        if (!isValidAddress(address)) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Invalid Ethereum address format' })
            };
        }
        
        const balance = await web3.eth.getBalance(address);
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ 
                address,
                balance: balance.toString(),
                balanceInEther: web3.utils.fromWei(balance, 'ether'),
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error getting balance:', error);
        throw error;
    }
}

/**
 * Handle get gas price request
 */
async function handleGetGasPrice(gasOptimizer, corsHeaders) {
    try {
        const gasInfo = await gasOptimizer.estimateOptimalGasPrice();
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                gasPrice: gasInfo.gasPrice.toString(),
                baseFee: gasInfo.baseFee.toString(),
                maxFeePerGas: gasInfo.maxFeePerGas.toString(),
                maxPriorityFeePerGas: gasInfo.maxPriorityFeePerGas.toString(),
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error getting gas price:', error);
        throw error;
    }
}

/**
 * Handle deploy contract request
 */
async function handleDeployContract(web3, gasOptimizer, requestBody, corsHeaders) {
    try {
        const { initialSupply = 1000000, contractName = 'SimpleToken' } = requestBody;
        
        // Get contract artifacts from S3
        const contractData = await getContractArtifacts(
            '${bucket_name}',
            `contracts/${contractName}.json`
        );
        
        if (!contractData || !contractData.abi || !contractData.bytecode) {
            return {
                statusCode: 404,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Contract artifacts not found or invalid' })
            };
        }
        
        // Create contract instance
        const contract = new web3.eth.Contract(contractData.abi);
        
        // Prepare deployment transaction
        const deployTx = contract.deploy({
            data: contractData.bytecode,
            arguments: [initialSupply]
        });
        
        // Estimate gas for deployment
        const gasEstimate = await gasOptimizer.estimateContractGas(contract, 'deploy', [initialSupply]);
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                message: 'Contract deployment prepared',
                contractName,
                initialSupply,
                gasEstimate: gasEstimate.gasLimit,
                gasPrice: gasEstimate.gasPrice,
                estimatedCost: gasEstimate.estimatedCost,
                deploymentData: deployTx.encodeABI(),
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error preparing contract deployment:', error);
        throw error;
    }
}

/**
 * Handle call contract request
 */
async function handleCallContract(web3, requestBody, corsHeaders) {
    try {
        const { contractAddress, method, params = [], contractName = 'SimpleToken' } = requestBody;
        
        if (!contractAddress || !method) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'contractAddress and method parameters are required' })
            };
        }
        
        if (!isValidAddress(contractAddress)) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Invalid contract address format' })
            };
        }
        
        // Get contract ABI from S3
        const contractData = await getContractArtifacts(
            '${bucket_name}',
            `contracts/${contractName}.json`
        );
        
        if (!contractData || !contractData.abi) {
            return {
                statusCode: 404,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Contract ABI not found' })
            };
        }
        
        // Create contract instance
        const contract = new web3.eth.Contract(contractData.abi, contractAddress);
        
        // Call contract method
        const result = await contract.methods[method](...params).call();
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                contractAddress,
                method,
                params,
                result: result.toString(),
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error calling contract:', error);
        throw error;
    }
}

/**
 * Handle send transaction request
 */
async function handleSendTransaction(web3, gasOptimizer, requestBody, corsHeaders) {
    try {
        const { from, to, value, data, gasLimit } = requestBody;
        
        if (!from || !to) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'from and to parameters are required' })
            };
        }
        
        if (!isValidAddress(from) || !isValidAddress(to)) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Invalid address format' })
            };
        }
        
        // Get optimal gas price
        const gasInfo = await gasOptimizer.estimateOptimalGasPrice();
        
        // Prepare transaction object
        const txObject = {
            from,
            to,
            value: value || '0',
            data: data || '0x',
            gas: gasLimit || '21000',
            gasPrice: gasInfo.gasPrice
        };
        
        // Note: For production, you would need to handle transaction signing
        // This is a simulation of transaction preparation
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                message: 'Transaction prepared (signing required for execution)',
                transactionObject: txObject,
                estimatedGasCost: gasInfo.gasPrice,
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error preparing transaction:', error);
        throw error;
    }
}

/**
 * Handle get transaction receipt request
 */
async function handleGetTransactionReceipt(web3, requestBody, corsHeaders) {
    try {
        const { transactionHash } = requestBody;
        
        if (!transactionHash) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'transactionHash parameter is required' })
            };
        }
        
        const receipt = await web3.eth.getTransactionReceipt(transactionHash);
        
        if (!receipt) {
            return {
                statusCode: 404,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Transaction not found' })
            };
        }
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                transactionHash,
                receipt,
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error getting transaction receipt:', error);
        throw error;
    }
}

/**
 * Handle estimate gas request
 */
async function handleEstimateGas(web3, gasOptimizer, requestBody, corsHeaders) {
    try {
        const { from, to, value, data } = requestBody;
        
        if (!from || !to) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'from and to parameters are required' })
            };
        }
        
        if (!isValidAddress(from) || !isValidAddress(to)) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Invalid address format' })
            };
        }
        
        // Estimate gas for the transaction
        const gasEstimate = await web3.eth.estimateGas({
            from,
            to,
            value: value || '0',
            data: data || '0x'
        });
        
        // Get optimal gas price
        const gasInfo = await gasOptimizer.estimateOptimalGasPrice();
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                gasEstimate: gasEstimate.toString(),
                gasPrice: gasInfo.gasPrice.toString(),
                estimatedCost: web3.utils.fromWei(
                    (BigInt(gasEstimate) * BigInt(gasInfo.gasPrice)).toString(),
                    'ether'
                ),
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Error estimating gas:', error);
        throw error;
    }
}