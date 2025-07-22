/**
 * Gas Optimizer for Ethereum transactions
 * Provides intelligent gas price estimation and optimization strategies
 */

class GasOptimizer {
    constructor(web3Instance) {
        this.web3 = web3Instance;
        this.gasHistoryLimit = 5; // Number of recent blocks to analyze
        this.safetyMultiplier = 1.1; // 10% safety buffer for gas estimates
        this.priorityFeeDefault = '2000000000'; // 2 Gwei in wei
    }

    /**
     * Estimates optimal gas price based on network conditions
     * @returns {Promise<Object>} Gas price information
     */
    async estimateOptimalGasPrice() {
        try {
            // Get current gas price from the network
            const currentGasPrice = await this.web3.eth.getGasPrice();
            
            // Get latest block to check for EIP-1559 support
            const latestBlock = await this.web3.eth.getBlock('latest');
            
            // Initialize gas price info
            let gasInfo = {
                gasPrice: currentGasPrice,
                baseFee: null,
                maxFeePerGas: null,
                maxPriorityFeePerGas: null,
                networkCondition: 'normal'
            };

            // Check if network supports EIP-1559 (London hard fork)
            if (latestBlock.baseFeePerGas) {
                gasInfo.baseFee = latestBlock.baseFeePerGas;
                gasInfo.maxPriorityFeePerGas = this.priorityFeeDefault;
                
                // Calculate maxFeePerGas (baseFee + priorityFee + buffer)
                const baseFeeWei = BigInt(latestBlock.baseFeePerGas);
                const priorityFeeWei = BigInt(this.priorityFeeDefault);
                const bufferWei = baseFeeWei / BigInt(10); // 10% buffer
                
                gasInfo.maxFeePerGas = (baseFeeWei + priorityFeeWei + bufferWei).toString();
            }

            // Analyze network congestion
            const networkCondition = await this.analyzeNetworkCondition();
            gasInfo.networkCondition = networkCondition;

            // Adjust gas price based on network condition
            gasInfo = this.adjustGasPriceForCondition(gasInfo, networkCondition);

            return gasInfo;
        } catch (error) {
            console.error('Error estimating optimal gas price:', error);
            
            // Fallback to basic gas price estimation
            const fallbackGasPrice = await this.web3.eth.getGasPrice();
            return {
                gasPrice: (BigInt(fallbackGasPrice) * BigInt(110) / BigInt(100)).toString(), // 10% buffer
                baseFee: null,
                maxFeePerGas: null,
                maxPriorityFeePerGas: null,
                networkCondition: 'unknown'
            };
        }
    }

    /**
     * Analyzes network condition based on recent blocks
     * @returns {Promise<string>} Network condition: 'low', 'normal', 'high', 'congested'
     */
    async analyzeNetworkCondition() {
        try {
            const latestBlockNumber = await this.web3.eth.getBlockNumber();
            const blocks = [];
            
            // Get recent blocks for analysis
            for (let i = 0; i < this.gasHistoryLimit; i++) {
                const blockNumber = latestBlockNumber - BigInt(i);
                const block = await this.web3.eth.getBlock(blockNumber, true);
                blocks.push(block);
            }

            // Calculate average gas usage
            let totalGasUsed = BigInt(0);
            let totalGasLimit = BigInt(0);
            
            blocks.forEach(block => {
                totalGasUsed += BigInt(block.gasUsed);
                totalGasLimit += BigInt(block.gasLimit);
            });

            const avgGasUsage = Number(totalGasUsed * BigInt(100) / totalGasLimit);

            // Determine network condition based on gas usage
            if (avgGasUsage < 30) {
                return 'low';
            } else if (avgGasUsage < 70) {
                return 'normal';
            } else if (avgGasUsage < 90) {
                return 'high';
            } else {
                return 'congested';
            }
        } catch (error) {
            console.error('Error analyzing network condition:', error);
            return 'normal'; // Default to normal if analysis fails
        }
    }

    /**
     * Adjusts gas price based on network condition
     * @param {Object} gasInfo - Current gas information
     * @param {string} condition - Network condition
     * @returns {Object} Adjusted gas information
     */
    adjustGasPriceForCondition(gasInfo, condition) {
        const adjustments = {
            'low': 0.9,      // 10% reduction for low congestion
            'normal': 1.0,   // No adjustment for normal conditions
            'high': 1.2,     // 20% increase for high congestion
            'congested': 1.5 // 50% increase for congested network
        };

        const multiplier = adjustments[condition] || 1.0;
        
        // Apply adjustment to gas price
        const adjustedGasPrice = (BigInt(gasInfo.gasPrice) * BigInt(Math.floor(multiplier * 100)) / BigInt(100)).toString();
        
        // Update gas info
        gasInfo.gasPrice = adjustedGasPrice;
        
        // Adjust EIP-1559 fields if present
        if (gasInfo.maxFeePerGas) {
            gasInfo.maxFeePerGas = (BigInt(gasInfo.maxFeePerGas) * BigInt(Math.floor(multiplier * 100)) / BigInt(100)).toString();
        }
        
        if (gasInfo.maxPriorityFeePerGas) {
            gasInfo.maxPriorityFeePerGas = (BigInt(gasInfo.maxPriorityFeePerGas) * BigInt(Math.floor(multiplier * 100)) / BigInt(100)).toString();
        }

        return gasInfo;
    }

    /**
     * Estimates gas for a specific contract method
     * @param {Object} contract - Web3 contract instance
     * @param {string} method - Contract method name
     * @param {Array} params - Method parameters
     * @param {Object} options - Additional options (from, value, etc.)
     * @returns {Promise<Object>} Gas estimation information
     */
    async estimateContractGas(contract, method, params = [], options = {}) {
        try {
            // Handle deployment case
            if (method === 'deploy') {
                const deployTx = contract.deploy({
                    data: contract.options.data || options.data,
                    arguments: params
                });
                
                const gasEstimate = await deployTx.estimateGas(options);
                const gasInfo = await this.estimateOptimalGasPrice();
                
                return {
                    gasLimit: Math.ceil(Number(gasEstimate) * this.safetyMultiplier),
                    gasPrice: gasInfo,
                    estimatedCost: this.web3.utils.fromWei(
                        (BigInt(gasEstimate) * BigInt(gasInfo.gasPrice)).toString(),
                        'ether'
                    ),
                    method: 'deploy',
                    params
                };
            }

            // Handle regular method calls
            const gasEstimate = await contract.methods[method](...params).estimateGas(options);
            const gasInfo = await this.estimateOptimalGasPrice();
            
            return {
                gasLimit: Math.ceil(Number(gasEstimate) * this.safetyMultiplier),
                gasPrice: gasInfo,
                estimatedCost: this.web3.utils.fromWei(
                    (BigInt(gasEstimate) * BigInt(gasInfo.gasPrice)).toString(),
                    'ether'
                ),
                method,
                params
            };
        } catch (error) {
            console.error('Error estimating contract gas:', error);
            throw new Error(`Gas estimation failed for method ${method}: ${error.message}`);
        }
    }

    /**
     * Estimates gas for a simple transaction
     * @param {Object} txObject - Transaction object
     * @returns {Promise<Object>} Gas estimation information
     */
    async estimateTransactionGas(txObject) {
        try {
            const gasEstimate = await this.web3.eth.estimateGas(txObject);
            const gasInfo = await this.estimateOptimalGasPrice();
            
            return {
                gasLimit: Math.ceil(Number(gasEstimate) * this.safetyMultiplier),
                gasPrice: gasInfo,
                estimatedCost: this.web3.utils.fromWei(
                    (BigInt(gasEstimate) * BigInt(gasInfo.gasPrice)).toString(),
                    'ether'
                ),
                transactionObject: txObject
            };
        } catch (error) {
            console.error('Error estimating transaction gas:', error);
            throw new Error(`Transaction gas estimation failed: ${error.message}`);
        }
    }

    /**
     * Calculates transaction cost in various units
     * @param {string} gasLimit - Gas limit for the transaction
     * @param {string} gasPrice - Gas price in wei
     * @returns {Object} Cost information in different units
     */
    calculateTransactionCost(gasLimit, gasPrice) {
        const costWei = (BigInt(gasLimit) * BigInt(gasPrice)).toString();
        
        return {
            wei: costWei,
            gwei: this.web3.utils.fromWei(costWei, 'gwei'),
            ether: this.web3.utils.fromWei(costWei, 'ether'),
            gasLimit: gasLimit.toString(),
            gasPrice: gasPrice.toString()
        };
    }

    /**
     * Provides gas optimization recommendations
     * @param {string} method - Contract method or transaction type
     * @param {Object} gasInfo - Current gas information
     * @returns {Object} Optimization recommendations
     */
    getOptimizationRecommendations(method, gasInfo) {
        const recommendations = {
            general: [
                'Monitor network congestion before sending transactions',
                'Use gas price oracles for dynamic pricing',
                'Consider batching multiple operations'
            ],
            specific: []
        };

        // Method-specific recommendations
        if (method === 'deploy') {
            recommendations.specific.push(
                'Deploy during low network congestion periods',
                'Optimize contract bytecode size',
                'Use CREATE2 for deterministic addresses'
            );
        } else if (method.includes('transfer')) {
            recommendations.specific.push(
                'Batch multiple transfers to reduce gas costs',
                'Use multicall patterns for efficiency',
                'Consider using gas tokens during high congestion'
            );
        }

        // Network condition recommendations
        if (gasInfo.networkCondition === 'congested') {
            recommendations.specific.push(
                'Consider delaying non-urgent transactions',
                'Use higher gas prices for faster confirmation',
                'Monitor mempool for optimal timing'
            );
        }

        return recommendations;
    }

    /**
     * Validates gas parameters
     * @param {Object} gasParams - Gas parameters to validate
     * @returns {Object} Validation result
     */
    validateGasParameters(gasParams) {
        const errors = [];
        const warnings = [];

        // Check gas limit
        if (gasParams.gasLimit) {
            const gasLimit = Number(gasParams.gasLimit);
            if (gasLimit < 21000) {
                errors.push('Gas limit cannot be less than 21,000');
            }
            if (gasLimit > 12000000) {
                warnings.push('Gas limit is very high, transaction may fail');
            }
        }

        // Check gas price
        if (gasParams.gasPrice) {
            const gasPrice = Number(gasParams.gasPrice);
            if (gasPrice < 1000000000) { // 1 Gwei
                warnings.push('Gas price is very low, transaction may be slow');
            }
            if (gasPrice > 100000000000) { // 100 Gwei
                warnings.push('Gas price is very high, transaction will be expensive');
            }
        }

        return {
            isValid: errors.length === 0,
            errors,
            warnings
        };
    }
}

module.exports = GasOptimizer;