/**
 * Multi-Tenant SaaS Authentication Triggers Lambda Function
 * 
 * This function handles Cognito User Pool Lambda triggers for:
 * - Pre Sign-up validation and tenant resolution
 * - Post Confirmation user provisioning
 * - Pre Authentication security checks
 * - Token Generation with custom claims
 */

const AWS = require('aws-sdk');

// Initialize AWS services
const dynamodb = new AWS.DynamoDB.DocumentClient({
    region: process.env.AWS_REGION
});

const cognitoIdentityServiceProvider = new AWS.CognitoIdentityServiceProvider({
    region: process.env.AWS_REGION
});

// Environment variables injected by Terraform
const TENANT_TABLE = '${tenant_table}';
const USER_TABLE = '${user_table}';
const ACTIVITY_LOG_TABLE = '${activity_table}';

/**
 * Main handler function for Cognito Lambda triggers
 */
exports.handler = async (event) => {
    console.log('Tenant auth trigger:', JSON.stringify(event, null, 2));
    
    try {
        switch (event.triggerSource) {
            case 'PreSignUp_SignUp':
            case 'PreSignUp_ExternalProvider':
                return await handlePreSignUp(event);
            
            case 'PostConfirmation_ConfirmSignUp':
            case 'PostConfirmation_ConfirmForgotPassword':
                return await handlePostConfirmation(event);
            
            case 'PreAuthentication_Authentication':
                return await handlePreAuthentication(event);
            
            case 'TokenGeneration_HostedAuth':
            case 'TokenGeneration_Authentication':
            case 'TokenGeneration_NewPasswordChallenge':
            case 'TokenGeneration_AuthenticateDevice':
                return await handleTokenGeneration(event);
            
            default:
                console.log('Unhandled trigger source:', event.triggerSource);
                return event;
        }
    } catch (error) {
        console.error('Tenant auth trigger error:', error);
        throw error;
    }
};

/**
 * Handle pre-signup validation and tenant resolution
 */
async function handlePreSignUp(event) {
    const { userAttributes } = event.request;
    const email = userAttributes.email;
    const domain = email.split('@')[1];
    
    console.log('Pre-signup for email:', email, 'domain:', domain);
    
    // Extract tenant information from custom attributes or domain
    let tenantId = userAttributes['custom:tenant_id'];
    
    if (!tenantId) {
        // Try to resolve tenant from domain mapping
        const tenant = await getTenantByDomain(domain);
        if (!tenant) {
            throw new Error(`No tenant found for domain: $${domain}. Please contact your administrator.`);
        }
        
        tenantId = tenant.id;
        
        // Add tenant ID to user attributes
        event.response.userAttributes = {
            ...event.response.userAttributes,
            'custom:tenant_id': tenantId
        };
    }
    
    // Validate tenant status and user limits
    const tenant = await getTenantById(tenantId);
    if (!tenant) {
        throw new Error('Tenant does not exist');
    }
    
    if (tenant.status !== 'ACTIVE' && tenant.status !== 'TRIAL') {
        throw new Error(`Tenant account is $${tenant.status.toLowerCase()}. Please contact your administrator.`);
    }
    
    // Check user limits for the tenant
    const userCount = await getUserCountForTenant(tenantId);
    if (userCount >= tenant.settings.maxUsers) {
        throw new Error(`User limit ($${tenant.settings.maxUsers}) exceeded for this tenant. Please contact your administrator.`);
    }
    
    // Auto-confirm user for known domains (optional)
    if (tenant.settings.autoConfirmUsers) {
        event.response.autoConfirmUser = true;
        event.response.autoVerifyEmail = true;
    }
    
    console.log('Pre-signup validation passed for tenant:', tenantId);
    return event;
}

/**
 * Handle post-confirmation user provisioning
 */
async function handlePostConfirmation(event) {
    const { userPoolId, userName, userAttributes } = event;
    const tenantId = userAttributes['custom:tenant_id'];
    
    console.log('Post-confirmation for user:', userName, 'tenant:', tenantId);
    
    try {
        // Create user record in DynamoDB
        const user = {
            id: `user_$${Date.now()}_$${Math.random().toString(36).substr(2, 9)}`,
            userId: userName,
            tenantId: tenantId,
            email: userAttributes.email,
            firstName: userAttributes.given_name || '',
            lastName: userAttributes.family_name || '',
            role: 'VIEWER', // Default role for self-signup
            permissions: getPermissionsForRole('VIEWER'),
            isActive: true,
            lastLoginAt: null,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
        };
        
        await dynamodb.put({
            TableName: USER_TABLE,
            Item: user,
            ConditionExpression: 'attribute_not_exists(userId)'
        }).promise();
        
        // Add user to default tenant group
        const tenantGroupName = `Tenant_$${tenantId}_Users`;
        try {
            await cognitoIdentityServiceProvider.adminAddUserToGroup({
                GroupName: tenantGroupName,
                Username: userName,
                UserPoolId: userPoolId
            }).promise();
        } catch (groupError) {
            console.warn('Failed to add user to tenant group (group may not exist):', groupError.message);
            // Continue without failing - groups can be managed separately
        }
        
        // Update user custom attributes with role
        await cognitoIdentityServiceProvider.adminUpdateUserAttributes({
            UserPoolId: userPoolId,
            Username: userName,
            UserAttributes: [
                {
                    Name: 'custom:user_role',
                    Value: 'VIEWER'
                }
            ]
        }).promise();
        
        // Log user creation activity
        await logActivity({
            tenantId: tenantId,
            userId: userName,
            action: 'USER_CONFIRMED',
            resource: 'User',
            resourceId: userName,
            metadata: {
                email: userAttributes.email,
                role: 'VIEWER',
                signupMethod: 'self_signup'
            }
        });
        
        console.log('User provisioned successfully:', userName);
        return event;
        
    } catch (error) {
        console.error('Post confirmation error:', error);
        
        // Log the error but don't fail the authentication
        await logActivity({
            tenantId: tenantId,
            userId: userName,
            action: 'USER_PROVISIONING_FAILED',
            resource: 'User',
            resourceId: userName,
            metadata: {
                error: error.message,
                email: userAttributes.email
            }
        });
        
        return event;
    }
}

/**
 * Handle pre-authentication security and validation checks
 */
async function handlePreAuthentication(event) {
    const { userPoolId, userName, userAttributes } = event;
    const tenantId = userAttributes['custom:tenant_id'];
    
    console.log('Pre-authentication for user:', userName, 'tenant:', tenantId);
    
    // Validate tenant status
    const tenant = await getTenantById(tenantId);
    if (!tenant) {
        throw new Error('Tenant not found');
    }
    
    // Check tenant status
    switch (tenant.status) {
        case 'SUSPENDED':
            throw new Error('Tenant account is suspended. Please contact support.');
        case 'EXPIRED':
            throw new Error('Tenant subscription has expired. Please contact your administrator.');
        case 'CANCELLED':
            throw new Error('Tenant account has been cancelled. Please contact support.');
    }
    
    // Check user status in our database
    const user = await getUserByUserId(userName);
    if (!user || !user.isActive) {
        throw new Error('User account is inactive. Please contact your administrator.');
    }
    
    // Rate limiting check - prevent brute force attacks
    const recentLoginAttempts = await getRecentLoginAttempts(userName);
    if (recentLoginAttempts.length > 10) {
        throw new Error('Too many login attempts. Please try again later.');
    }
    
    // Check for tenant-specific authentication policies
    if (tenant.settings.ssoEnabled && !userAttributes.identities) {
        // If SSO is required but user is not using SSO
        console.warn('SSO required but user attempting password auth');
    }
    
    console.log('Pre-authentication checks passed for user:', userName);
    return event;
}

/**
 * Handle token generation with custom claims
 */
async function handleTokenGeneration(event) {
    const { userName, userAttributes } = event.request;
    const tenantId = userAttributes['custom:tenant_id'];
    
    console.log('Token generation for user:', userName, 'tenant:', tenantId);
    
    try {
        // Get user details from our database
        const user = await getUserByUserId(userName);
        const tenant = await getTenantById(tenantId);
        
        if (user && tenant) {
            // Update last login time
            await updateUserLastLogin(userName);
            
            // Get user groups from Cognito
            const groups = await getUserGroups(event.userPoolId, userName);
            
            // Prepare custom claims for the JWT token
            const customClaims = {
                'custom:tenant_id': tenantId,
                'custom:tenant_name': tenant.name,
                'custom:tenant_plan': tenant.plan,
                'custom:tenant_subdomain': tenant.subdomain,
                'custom:user_role': user.role,
                'custom:permissions': user.permissions.join(','),
                'custom:groups': groups.join(','),
                'custom:features': tenant.settings.allowedFeatures.join(','),
                'custom:last_login': new Date().toISOString(),
                'custom:tenant_status': tenant.status
            };
            
            // Add tenant-specific metadata
            if (tenant.settings.customDomain) {
                customClaims['custom:custom_domain'] = tenant.settings.customDomain;
            }
            
            // Set the custom claims in the token
            event.response = {
                claimsOverrideDetails: {
                    claimsToAddOrOverride: customClaims,
                    groupOverrideDetails: {
                        groupsToOverride: groups,
                        preferredRole: user.role
                    }
                }
            };
            
            // Log successful authentication
            await logActivity({
                tenantId: tenantId,
                userId: userName,
                action: 'USER_LOGIN',
                resource: 'Authentication',
                resourceId: userName,
                metadata: {
                    tenant: tenant.name,
                    role: user.role,
                    loginTime: new Date().toISOString()
                }
            });
            
            console.log('Token generated with custom claims for user:', userName);
        } else {
            console.warn('User or tenant not found during token generation:', { userName, tenantId });
        }
        
        return event;
        
    } catch (error) {
        console.error('Token generation error:', error);
        
        // Log the error but don't fail the authentication
        await logActivity({
            tenantId: tenantId,
            userId: userName,
            action: 'TOKEN_GENERATION_ERROR',
            resource: 'Authentication',
            resourceId: userName,
            metadata: {
                error: error.message
            }
        });
        
        return event;
    }
}

// Helper Functions

function getPermissionsForRole(role) {
    const rolePermissions = {
        TENANT_ADMIN: [
            'tenant:read', 'tenant:update', 'users:manage', 'projects:manage',
            'billing:read', 'billing:update', 'settings:update', 'audit:read'
        ],
        PROJECT_MANAGER: [
            'projects:create', 'projects:read', 'projects:update', 'projects:delete',
            'tasks:manage', 'users:read', 'reports:read'
        ],
        TEAM_LEAD: [
            'projects:read', 'projects:update', 'tasks:manage', 'users:read'
        ],
        DEVELOPER: [
            'projects:read', 'tasks:read', 'tasks:update', 'tasks:create'
        ],
        VIEWER: [
            'projects:read', 'tasks:read'
        ],
        GUEST: [
            'tasks:read'
        ]
    };
    
    return rolePermissions[role] || rolePermissions.GUEST;
}

async function getTenantById(tenantId) {
    if (!tenantId) return null;
    
    const result = await dynamodb.get({
        TableName: TENANT_TABLE,
        Key: { id: tenantId }
    }).promise();
    
    return result.Item;
}

async function getTenantByDomain(domain) {
    const result = await dynamodb.scan({
        TableName: TENANT_TABLE,
        FilterExpression: '#domain = :domain',
        ExpressionAttributeNames: {
            '#domain': 'domain'
        },
        ExpressionAttributeValues: {
            ':domain': domain
        }
    }).promise();
    
    return result.Items.length > 0 ? result.Items[0] : null;
}

async function getUserByUserId(userId) {
    const result = await dynamodb.scan({
        TableName: USER_TABLE,
        FilterExpression: 'userId = :userId',
        ExpressionAttributeValues: {
            ':userId': userId
        }
    }).promise();
    
    return result.Items.length > 0 ? result.Items[0] : null;
}

async function getUserCountForTenant(tenantId) {
    const result = await dynamodb.query({
        TableName: USER_TABLE,
        IndexName: 'byTenant',
        KeyConditionExpression: 'tenantId = :tenantId',
        ExpressionAttributeValues: {
            ':tenantId': tenantId
        },
        Select: 'COUNT'
    }).promise();
    
    return result.Count;
}

async function getUserGroups(userPoolId, userName) {
    try {
        const result = await cognitoIdentityServiceProvider.adminListGroupsForUser({
            UserPoolId: userPoolId,
            Username: userName
        }).promise();
        
        return result.Groups.map(group => group.GroupName);
    } catch (error) {
        console.error('Error getting user groups:', error);
        return [];
    }
}

async function updateUserLastLogin(userId) {
    try {
        const result = await dynamodb.scan({
            TableName: USER_TABLE,
            FilterExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            }
        }).promise();
        
        if (result.Items.length > 0) {
            const user = result.Items[0];
            await dynamodb.update({
                TableName: USER_TABLE,
                Key: { id: user.id },
                UpdateExpression: 'SET lastLoginAt = :timestamp, updatedAt = :timestamp',
                ExpressionAttributeValues: {
                    ':timestamp': new Date().toISOString()
                }
            }).promise();
        }
    } catch (error) {
        console.error('Error updating last login:', error);
    }
}

async function getRecentLoginAttempts(userId) {
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    
    try {
        const result = await dynamodb.query({
            TableName: ACTIVITY_LOG_TABLE,
            IndexName: 'byUser',
            KeyConditionExpression: 'userId = :userId AND createdAt > :timestamp',
            FilterExpression: '#action IN (:login, :failed_login)',
            ExpressionAttributeNames: {
                '#action': 'action'
            },
            ExpressionAttributeValues: {
                ':userId': userId,
                ':timestamp': oneHourAgo,
                ':login': 'USER_LOGIN',
                ':failed_login': 'LOGIN_FAILED'
            }
        }).promise();
        
        return result.Items || [];
    } catch (error) {
        console.error('Error getting recent login attempts:', error);
        return [];
    }
}

async function logActivity(activity) {
    try {
        const logEntry = {
            id: `activity_$${Date.now()}_$${Math.random().toString(36).substr(2, 9)}`,
            ...activity,
            createdAt: new Date().toISOString(),
            ttl: Math.floor(Date.now() / 1000) + (90 * 24 * 60 * 60) // 90 days TTL
        };
        
        await dynamodb.put({
            TableName: ACTIVITY_LOG_TABLE,
            Item: logEntry
        }).promise();
    } catch (error) {
        console.error('Error logging activity:', error);
        // Don't throw error for logging failures
    }
}