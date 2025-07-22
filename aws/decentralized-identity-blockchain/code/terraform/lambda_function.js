// Identity Management Lambda Function for Decentralized Identity Blockchain
const AWS = require('aws-sdk');

// Initialize AWS services
const qldb = new AWS.QLDB();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const managedblockchain = new AWS.ManagedBlockchain();

// Environment variables
const DYNAMODB_TABLE_NAME = process.env.DYNAMODB_TABLE_NAME;
const QLDB_LEDGER_NAME = process.env.QLDB_LEDGER_NAME;
const S3_BUCKET_NAME = process.env.S3_BUCKET_NAME;
const NETWORK_ID = process.env.NETWORK_ID;
const MEMBER_ID = process.env.MEMBER_ID;
const NODE_ID = process.env.NODE_ID;

/**
 * Main Lambda handler for identity management operations
 */
exports.handler = async (event, context) => {
    console.log('Identity Management Request:', JSON.stringify(event, null, 2));
    
    try {
        // Parse the request body
        const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        const { action, ...params } = body;

        let result;
        
        switch (action) {
            case 'createIdentity':
                result = await createIdentity(params);
                break;
            case 'issueCredential':
                result = await issueCredential(params);
                break;
            case 'verifyCredential':
                result = await verifyCredential(params);
                break;
            case 'revokeCredential':
                result = await revokeCredential(params);
                break;
            case 'queryIdentity':
                result = await queryIdentity(params);
                break;
            case 'queryCredentials':
                result = await queryCredentials(params);
                break;
            case 'getNetworkStatus':
                result = await getNetworkStatus();
                break;
            default:
                throw new Error(`Unknown action: ${action}`);
        }

        return createResponse(200, {
            success: true,
            data: result,
            timestamp: new Date().toISOString()
        });

    } catch (error) {
        console.error('Identity operation failed:', error);
        
        return createResponse(500, {
            success: false,
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
};

/**
 * Create a new decentralized identity (DID)
 */
async function createIdentity({ publicKey, metadata = {} }) {
    console.log('Creating new identity...');
    
    // Generate DID from public key
    const crypto = require('crypto');
    const didHash = crypto.createHash('sha256').update(publicKey).digest('hex').substring(0, 16);
    const did = `did:fabric:${didHash}`;
    
    const identity = {
        did: did,
        publicKey: publicKey,
        metadata: metadata,
        created: new Date().toISOString(),
        status: 'active',
        credentialCount: 0,
        lastUpdated: new Date().toISOString()
    };

    try {
        // Store in QLDB for cryptographic verification
        await storeInQLDB('IdentityRecords', identity);
        
        // Store in DynamoDB for fast queries
        await dynamodb.put({
            TableName: DYNAMODB_TABLE_NAME,
            Item: {
                did: did,
                credential_id: 'IDENTITY_RECORD',
                type: 'IDENTITY',
                data: identity,
                created: identity.created,
                status: 'active'
            }
        }).promise();

        console.log(`Identity created successfully: ${did}`);
        
        // Simulate blockchain transaction (in production, this would use Fabric SDK)
        await simulateBlockchainTransaction('createDID', {
            did: did,
            publicKey: publicKey,
            metadata: JSON.stringify(metadata)
        });

        return {
            did: did,
            status: 'created',
            transactionId: generateTransactionId(),
            blockNumber: Math.floor(Math.random() * 1000000)
        };

    } catch (error) {
        console.error('Failed to create identity:', error);
        throw new Error(`Identity creation failed: ${error.message}`);
    }
}

/**
 * Issue a verifiable credential to a DID
 */
async function issueCredential({ did, credentialType, claims, issuerDID = 'did:fabric:issuer' }) {
    console.log(`Issuing credential of type ${credentialType} to ${did}`);
    
    // Verify DID exists
    const identity = await getIdentityFromQLDB(did);
    if (!identity) {
        throw new Error(`Identity ${did} does not exist`);
    }

    // Generate credential ID
    const credentialId = require('crypto').randomBytes(16).toString('hex');
    
    const credential = {
        id: credentialId,
        type: credentialType,
        holder: did,
        issuer: issuerDID,
        claims: claims,
        issued: new Date().toISOString(),
        status: 'active',
        proof: {
            type: 'Ed25519Signature2020',
            created: new Date().toISOString(),
            verificationMethod: `${issuerDID}#key-1`,
            proofPurpose: 'assertionMethod',
            proofValue: generateProofValue(credentialId, claims)
        }
    };

    try {
        // Store credential in QLDB
        await storeInQLDB('Credentials', credential);
        
        // Index in DynamoDB
        await dynamodb.put({
            TableName: DYNAMODB_TABLE_NAME,
            Item: {
                did: did,
                credential_id: credentialId,
                type: credentialType,
                data: credential,
                issued_at: credential.issued,
                status: 'active'
            }
        }).promise();

        // Update identity credential count
        await updateIdentityCredentialCount(did, 1);

        console.log(`Credential issued successfully: ${credentialId}`);
        
        // Simulate blockchain transaction
        await simulateBlockchainTransaction('issueCredential', {
            credentialId: credentialId,
            did: did,
            type: credentialType,
            issuer: issuerDID
        });

        return {
            credentialId: credentialId,
            status: 'issued',
            transactionId: generateTransactionId(),
            blockNumber: Math.floor(Math.random() * 1000000)
        };

    } catch (error) {
        console.error('Failed to issue credential:', error);
        throw new Error(`Credential issuance failed: ${error.message}`);
    }
}

/**
 * Verify a credential
 */
async function verifyCredential({ credentialId }) {
    console.log(`Verifying credential: ${credentialId}`);
    
    try {
        // Get credential from DynamoDB
        const credentialData = await dynamodb.get({
            TableName: DYNAMODB_TABLE_NAME,
            Key: {
                did: 'LOOKUP_BY_CREDENTIAL_ID', // This would need proper GSI
                credential_id: credentialId
            }
        }).promise();

        if (!credentialData.Item) {
            // Fallback to scanning (not recommended for production)
            const scanResult = await dynamodb.scan({
                TableName: DYNAMODB_TABLE_NAME,
                FilterExpression: 'credential_id = :cid',
                ExpressionAttributeValues: {
                    ':cid': credentialId
                }
            }).promise();

            if (scanResult.Items.length === 0) {
                return {
                    valid: false,
                    reason: 'Credential not found',
                    verifiedAt: new Date().toISOString()
                };
            }
            credentialData.Item = scanResult.Items[0];
        }

        const credential = credentialData.Item.data;
        
        // Verify holder identity exists and is active
        const identity = await getIdentityFromQLDB(credential.holder);
        if (!identity) {
            return {
                valid: false,
                reason: 'Holder identity not found',
                verifiedAt: new Date().toISOString()
            };
        }

        // Check credential and identity status
        if (credential.status !== 'active' || identity.status !== 'active') {
            return {
                valid: false,
                reason: 'Credential or identity is not active',
                verifiedAt: new Date().toISOString()
            };
        }

        // Verify cryptographic proof (simplified)
        const isProofValid = verifyProofValue(credential.proof.proofValue, credentialId, credential.claims);
        
        if (!isProofValid) {
            return {
                valid: false,
                reason: 'Invalid cryptographic proof',
                verifiedAt: new Date().toISOString()
            };
        }

        console.log(`Credential verified successfully: ${credentialId}`);

        return {
            valid: true,
            credential: credential,
            identity: identity,
            verifiedAt: new Date().toISOString(),
            verificationMethod: 'blockchain-qldb-hybrid'
        };

    } catch (error) {
        console.error('Failed to verify credential:', error);
        throw new Error(`Credential verification failed: ${error.message}`);
    }
}

/**
 * Revoke a credential
 */
async function revokeCredential({ credentialId, reason = 'Not specified' }) {
    console.log(`Revoking credential: ${credentialId}`);
    
    try {
        // Get current credential
        const scanResult = await dynamodb.scan({
            TableName: DYNAMODB_TABLE_NAME,
            FilterExpression: 'credential_id = :cid',
            ExpressionAttributeValues: {
                ':cid': credentialId
            }
        }).promise();

        if (scanResult.Items.length === 0) {
            throw new Error(`Credential ${credentialId} not found`);
        }

        const item = scanResult.Items[0];
        const credential = item.data;
        
        // Update credential status
        credential.status = 'revoked';
        credential.revocationReason = reason;
        credential.revokedAt = new Date().toISOString();

        // Update in DynamoDB
        await dynamodb.update({
            TableName: DYNAMODB_TABLE_NAME,
            Key: {
                did: item.did,
                credential_id: credentialId
            },
            UpdateExpression: 'SET #data = :data, #status = :status',
            ExpressionAttributeNames: {
                '#data': 'data',
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':data': credential,
                ':status': 'revoked'
            }
        }).promise();

        // Store revocation in QLDB
        await storeInQLDB('Revocations', {
            credentialId: credentialId,
            reason: reason,
            revokedAt: credential.revokedAt,
            revokedBy: 'system' // In production, this would be the authenticated user
        });

        console.log(`Credential revoked successfully: ${credentialId}`);
        
        // Simulate blockchain transaction
        await simulateBlockchainTransaction('revokeCredential', {
            credentialId: credentialId,
            reason: reason,
            revokedAt: credential.revokedAt
        });

        return {
            credentialId: credentialId,
            status: 'revoked',
            reason: reason,
            transactionId: generateTransactionId(),
            blockNumber: Math.floor(Math.random() * 1000000)
        };

    } catch (error) {
        console.error('Failed to revoke credential:', error);
        throw new Error(`Credential revocation failed: ${error.message}`);
    }
}

/**
 * Query identity information
 */
async function queryIdentity({ did }) {
    console.log(`Querying identity: ${did}`);
    
    try {
        const identity = await getIdentityFromQLDB(did);
        
        if (!identity) {
            throw new Error(`Identity ${did} not found`);
        }

        // Get associated credentials
        const credentials = await dynamodb.query({
            TableName: DYNAMODB_TABLE_NAME,
            KeyConditionExpression: 'did = :did',
            FilterExpression: '#type <> :identityType',
            ExpressionAttributeNames: {
                '#type': 'type'
            },
            ExpressionAttributeValues: {
                ':did': did,
                ':identityType': 'IDENTITY'
            }
        }).promise();

        return {
            identity: identity,
            credentials: credentials.Items.map(item => ({
                id: item.credential_id,
                type: item.type,
                status: item.status,
                issued: item.issued_at
            })),
            totalCredentials: credentials.Count
        };

    } catch (error) {
        console.error('Failed to query identity:', error);
        throw new Error(`Identity query failed: ${error.message}`);
    }
}

/**
 * Query credentials for a DID
 */
async function queryCredentials({ did, credentialType = null, status = 'active' }) {
    console.log(`Querying credentials for DID: ${did}`);
    
    try {
        let filterExpression = '#status = :status';
        let expressionAttributeNames = { '#status': 'status' };
        let expressionAttributeValues = { ':status': status, ':did': did };

        if (credentialType) {
            filterExpression += ' AND #type = :type';
            expressionAttributeNames['#type'] = 'type';
            expressionAttributeValues[':type'] = credentialType;
        }

        const result = await dynamodb.query({
            TableName: DYNAMODB_TABLE_NAME,
            KeyConditionExpression: 'did = :did',
            FilterExpression: filterExpression,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues
        }).promise();

        return {
            credentials: result.Items.map(item => item.data),
            count: result.Count,
            did: did
        };

    } catch (error) {
        console.error('Failed to query credentials:', error);
        throw new Error(`Credential query failed: ${error.message}`);
    }
}

/**
 * Get blockchain network status
 */
async function getNetworkStatus() {
    console.log('Getting blockchain network status...');
    
    try {
        const networkInfo = await managedblockchain.getNetwork({
            NetworkId: NETWORK_ID
        }).promise();

        const memberInfo = await managedblockchain.getMember({
            NetworkId: NETWORK_ID,
            MemberId: MEMBER_ID
        }).promise();

        const nodeInfo = await managedblockchain.getNode({
            NetworkId: NETWORK_ID,
            MemberId: MEMBER_ID,
            NodeId: NODE_ID
        }).promise();

        return {
            network: {
                id: NETWORK_ID,
                name: networkInfo.Network.Name,
                status: networkInfo.Network.Status,
                framework: networkInfo.Network.Framework
            },
            member: {
                id: MEMBER_ID,
                name: memberInfo.Member.Name,
                status: memberInfo.Member.Status
            },
            node: {
                id: NODE_ID,
                status: nodeInfo.Node.Status,
                instanceType: nodeInfo.Node.InstanceType
            }
        };

    } catch (error) {
        console.error('Failed to get network status:', error);
        throw new Error(`Network status query failed: ${error.message}`);
    }
}

/**
 * Helper Functions
 */

function createResponse(statusCode, body) {
    return {
        statusCode: statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
        },
        body: JSON.stringify(body)
    };
}

async function storeInQLDB(tableName, data) {
    // In a real implementation, this would use the QLDB driver
    // For now, we simulate QLDB storage
    console.log(`Storing in QLDB table ${tableName}:`, data);
    
    // Store metadata in S3 as a backup
    const key = `qldb-backup/${tableName}/${data.id || data.did || Date.now()}.json`;
    await s3.putObject({
        Bucket: S3_BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(data),
        ContentType: 'application/json'
    }).promise();
    
    return true;
}

async function getIdentityFromQLDB(did) {
    // In a real implementation, this would query QLDB
    // For now, we get from DynamoDB
    try {
        const result = await dynamodb.get({
            TableName: DYNAMODB_TABLE_NAME,
            Key: {
                did: did,
                credential_id: 'IDENTITY_RECORD'
            }
        }).promise();

        return result.Item ? result.Item.data : null;
    } catch (error) {
        console.error('Failed to get identity from QLDB:', error);
        return null;
    }
}

async function updateIdentityCredentialCount(did, increment) {
    await dynamodb.update({
        TableName: DYNAMODB_TABLE_NAME,
        Key: {
            did: did,
            credential_id: 'IDENTITY_RECORD'
        },
        UpdateExpression: 'ADD #data.credentialCount :inc',
        ExpressionAttributeNames: {
            '#data': 'data'
        },
        ExpressionAttributeValues: {
            ':inc': increment
        }
    }).promise();
}

function generateTransactionId() {
    return require('crypto').randomBytes(32).toString('hex');
}

function generateProofValue(credentialId, claims) {
    // Simplified proof generation - in production, use proper cryptographic signatures
    const crypto = require('crypto');
    const data = credentialId + JSON.stringify(claims);
    return crypto.createHash('sha256').update(data).digest('hex');
}

function verifyProofValue(proofValue, credentialId, claims) {
    // Simplified proof verification
    const expectedProof = generateProofValue(credentialId, claims);
    return proofValue === expectedProof;
}

async function simulateBlockchainTransaction(operation, data) {
    // In a real implementation, this would use Hyperledger Fabric SDK
    // For now, we log the transaction and store metadata
    console.log(`Blockchain Transaction - Operation: ${operation}`, data);
    
    const transactionRecord = {
        operation: operation,
        data: data,
        timestamp: new Date().toISOString(),
        transactionId: generateTransactionId(),
        blockNumber: Math.floor(Math.random() * 1000000)
    };

    // Store transaction record in S3
    const key = `blockchain-transactions/${transactionRecord.transactionId}.json`;
    await s3.putObject({
        Bucket: S3_BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(transactionRecord),
        ContentType: 'application/json'
    }).promise();

    return transactionRecord;
}