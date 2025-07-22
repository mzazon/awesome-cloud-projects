/**
 * Multi-Tenant SaaS Tenant Resolver Lambda Function
 * 
 * This function handles complex tenant management operations including:
 * - Tenant creation and provisioning
 * - User role management
 * - Tenant settings updates
 * - Billing information management
 * - User provisioning with tenant isolation
 */

const AWS = require('aws-sdk');

// Initialize AWS services
const dynamodb = new AWS.DynamoDB.DocumentClient({
    region: process.env.AWS_REGION
});

const cognito = new AWS.CognitoIdentityServiceProvider({
    region: process.env.AWS_REGION
});

// Environment variables injected by Terraform
const TENANT_TABLE = '${tenant_table}';
const USER_TABLE = '${user_table}';
const ACTIVITY_LOG_TABLE = '${activity_table}';
const BILLING_TABLE = '${billing_table}';

/**
 * Main handler function for AppSync direct lambda resolvers
 */
exports.handler = async (event) => {
    console.log('Tenant resolver event:', JSON.stringify(event, null, 2));
    
    const { field, source, arguments: args, identity, request } = event;
    
    try {
        switch (field) {
            case 'createTenant':
                return await createTenant(args.input, identity);
            
            case 'updateTenantSettings':
                return await updateTenantSettings(args.tenantId, args.settings, identity);
            
            case 'provisionTenantUser':
                return await provisionTenantUser(args.input, identity);
            
            case 'updateUserRole':
                return await updateUserRole(args.userId, args.role, args.permissions, identity);
            
            case 'updateBillingInfo':
                return await updateBillingInfo(args.tenantId, args.billingInfo, identity);
            
            default:
                throw new Error(`Unknown field: $${field}`);
        }
    } catch (error) {
        console.error('Tenant resolver error:', error);
        throw new Error(`Tenant operation failed: $${error.message}`);
    }
};

/**
 * Create a new tenant with initial configuration
 */
async function createTenant(input, identity) {
    // Validate super admin permissions
    if (!hasRole(identity, 'SuperAdmins')) {
        throw new Error('Unauthorized: Only super admins can create tenants');
    }
    
    const tenantId = generateTenantId();
    const timestamp = new Date().toISOString();
    
    // Check if subdomain is available
    const existingTenant = await getTenantBySubdomain(input.subdomain);
    if (existingTenant) {
        throw new Error(`Subdomain $${input.subdomain} is already taken`);
    }
    
    // Create tenant record with comprehensive settings
    const tenant = {
        id: tenantId,
        name: input.name,
        domain: input.domain,
        subdomain: input.subdomain,
        status: 'TRIAL',
        plan: input.plan,
        settings: getDefaultTenantSettings(input.plan),
        customCSS: '',
        logo: '',
        primaryColor: '#4f46e5',
        secondaryColor: '#6b7280',
        timezone: 'America/New_York',
        locale: 'en-US',
        createdAt: timestamp,
        updatedAt: timestamp
    };
    
    // Store tenant in DynamoDB
    await dynamodb.put({
        TableName: TENANT_TABLE,
        Item: tenant,
        ConditionExpression: 'attribute_not_exists(id)'
    }).promise();
    
    // Create initial admin user for the tenant
    await createTenantAdmin(tenantId, {
        email: input.adminEmail,
        name: input.adminName
    });
    
    // Initialize tenant-specific resources
    await initializeTenantResources(tenantId);
    
    // Log tenant creation activity
    await logActivity({
        tenantId: tenantId,
        userId: identity.sub,
        action: 'TENANT_CREATED',
        resource: 'Tenant',
        resourceId: tenantId,
        metadata: {
            tenantName: input.name,
            plan: input.plan,
            domain: input.domain
        }
    });
    
    return tenant;
}

/**
 * Update tenant settings with validation
 */
async function updateTenantSettings(tenantId, settingsInput, identity) {
    // Validate permissions
    if (!hasRole(identity, 'SuperAdmins') && !isTenantAdmin(identity, tenantId)) {
        throw new Error('Unauthorized: Insufficient permissions');
    }
    
    const tenant = await getTenantById(tenantId);
    if (!tenant) {
        throw new Error('Tenant not found');
    }
    
    // Validate settings against plan limits
    validateSettingsAgainstPlan(settingsInput, tenant.plan);
    
    const updatedTenant = {
        ...tenant,
        settings: {
            ...tenant.settings,
            ...settingsInput
        },
        updatedAt: new Date().toISOString()
    };
    
    await dynamodb.put({
        TableName: TENANT_TABLE,
        Item: updatedTenant
    }).promise();
    
    // Log settings update
    await logActivity({
        tenantId: tenantId,
        userId: identity.sub,
        action: 'TENANT_SETTINGS_UPDATED',
        resource: 'TenantSettings',
        resourceId: tenantId,
        metadata: {
            updatedSettings: settingsInput
        }
    });
    
    return updatedTenant;
}

/**
 * Provision a new user for a tenant
 */
async function provisionTenantUser(input, identity) {
    // Validate permissions
    if (!hasRole(identity, 'SuperAdmins') && !isTenantAdmin(identity, input.tenantId)) {
        throw new Error('Unauthorized: Insufficient permissions');
    }
    
    const tenant = await getTenantById(input.tenantId);
    if (!tenant) {
        throw new Error('Tenant not found');
    }
    
    // Check user limits
    const currentUserCount = await getUserCountForTenant(input.tenantId);
    if (currentUserCount >= tenant.settings.maxUsers) {
        throw new Error('User limit exceeded for this tenant');
    }
    
    // Generate user ID
    const userId = generateUserId();
    
    // Create user record
    const user = {
        id: userId,
        userId: userId,
        tenantId: input.tenantId,
        email: input.email,
        firstName: input.firstName,
        lastName: input.lastName,
        role: input.role,
        permissions: getPermissionsForRole(input.role),
        isActive: true,
        lastLoginAt: null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
    };
    
    await dynamodb.put({
        TableName: USER_TABLE,
        Item: user
    }).promise();
    
    // Log user creation
    await logActivity({
        tenantId: input.tenantId,
        userId: identity.sub,
        action: 'USER_PROVISIONED',
        resource: 'User',
        resourceId: userId,
        metadata: {
            email: input.email,
            role: input.role,
            tenantId: input.tenantId
        }
    });
    
    return user;
}

/**
 * Update user role and permissions
 */
async function updateUserRole(userId, role, permissions, identity) {
    const user = await getUserById(userId);
    if (!user) {
        throw new Error('User not found');
    }
    
    // Validate permissions
    if (!hasRole(identity, 'SuperAdmins') && !isTenantAdmin(identity, user.tenantId)) {
        throw new Error('Unauthorized: Insufficient permissions');
    }
    
    const updatedUser = {
        ...user,
        role: role,
        permissions: permissions,
        updatedAt: new Date().toISOString()
    };
    
    await dynamodb.put({
        TableName: USER_TABLE,
        Item: updatedUser
    }).promise();
    
    // Log role update
    await logActivity({
        tenantId: user.tenantId,
        userId: identity.sub,
        action: 'USER_ROLE_UPDATED',
        resource: 'User',
        resourceId: userId,
        metadata: {
            oldRole: user.role,
            newRole: role,
            permissions: permissions
        }
    });
    
    return updatedUser;
}

/**
 * Update billing information for a tenant
 */
async function updateBillingInfo(tenantId, billingInfoInput, identity) {
    // Validate permissions
    if (!hasRole(identity, 'SuperAdmins') && !isTenantAdmin(identity, tenantId)) {
        throw new Error('Unauthorized: Insufficient permissions');
    }
    
    const existingBilling = await getBillingInfoByTenantId(tenantId);
    const timestamp = new Date().toISOString();
    
    const billingInfo = {
        ...existingBilling,
        ...billingInfoInput,
        tenantId: tenantId,
        updatedAt: timestamp,
        ...(existingBilling ? {} : { id: generateBillingId(), createdAt: timestamp })
    };
    
    await dynamodb.put({
        TableName: BILLING_TABLE,
        Item: billingInfo
    }).promise();
    
    // Log billing update
    await logActivity({
        tenantId: tenantId,
        userId: identity.sub,
        action: 'BILLING_INFO_UPDATED',
        resource: 'BillingInfo',
        resourceId: billingInfo.id,
        metadata: {
            plan: billingInfoInput.plan
        }
    });
    
    return billingInfo;
}

// Helper Functions

function generateTenantId() {
    return `tenant_$${Date.now()}_$${Math.random().toString(36).substr(2, 9)}`;
}

function generateUserId() {
    return `user_$${Date.now()}_$${Math.random().toString(36).substr(2, 9)}`;
}

function generateBillingId() {
    return `billing_$${Date.now()}_$${Math.random().toString(36).substr(2, 9)}`;
}

function getDefaultTenantSettings(plan) {
    const settingsMap = {
        TRIAL: {
            maxUsers: 5,
            maxProjects: 3,
            maxStorageGB: 1.0,
            allowedFeatures: ['basic_tasks', 'basic_projects'],
            ssoEnabled: false,
            auditingEnabled: false,
            dataRetentionDays: 30,
            apiRateLimit: 100
        },
        BASIC: {
            maxUsers: 25,
            maxProjects: 10,
            maxStorageGB: 5.0,
            allowedFeatures: ['basic_tasks', 'basic_projects', 'reporting'],
            ssoEnabled: false,
            auditingEnabled: true,
            dataRetentionDays: 90,
            apiRateLimit: 500
        },
        PROFESSIONAL: {
            maxUsers: 100,
            maxProjects: 50,
            maxStorageGB: 25.0,
            allowedFeatures: ['basic_tasks', 'basic_projects', 'reporting', 'advanced_analytics', 'integrations'],
            ssoEnabled: true,
            auditingEnabled: true,
            dataRetentionDays: 365,
            apiRateLimit: 2000
        },
        ENTERPRISE: {
            maxUsers: 1000,
            maxProjects: 500,
            maxStorageGB: 100.0,
            allowedFeatures: ['all'],
            ssoEnabled: true,
            auditingEnabled: true,
            dataRetentionDays: 2555, // 7 years
            apiRateLimit: 10000
        }
    };
    
    return settingsMap[plan] || settingsMap.TRIAL;
}

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

function hasRole(identity, role) {
    const groups = identity.groups || [];
    return groups.includes(role);
}

function isTenantAdmin(identity, tenantId) {
    // Check if user is admin of the specific tenant
    const tenantClaim = identity.claims['custom:tenant_id'];
    const roles = identity.claims['custom:roles']?.split(',') || [];
    
    return tenantClaim === tenantId && roles.includes('TENANT_ADMIN');
}

async function getTenantById(tenantId) {
    const result = await dynamodb.get({
        TableName: TENANT_TABLE,
        Key: { id: tenantId }
    }).promise();
    
    return result.Item;
}

async function getTenantBySubdomain(subdomain) {
    const result = await dynamodb.scan({
        TableName: TENANT_TABLE,
        FilterExpression: 'subdomain = :subdomain',
        ExpressionAttributeValues: {
            ':subdomain': subdomain
        }
    }).promise();
    
    return result.Items.length > 0 ? result.Items[0] : null;
}

async function getUserById(userId) {
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

async function getBillingInfoByTenantId(tenantId) {
    const result = await dynamodb.query({
        TableName: BILLING_TABLE,
        IndexName: 'byTenant',
        KeyConditionExpression: 'tenantId = :tenantId',
        ExpressionAttributeValues: {
            ':tenantId': tenantId
        }
    }).promise();
    
    return result.Items.length > 0 ? result.Items[0] : null;
}

function validateSettingsAgainstPlan(settings, plan) {
    const planLimits = getDefaultTenantSettings(plan);
    
    if (settings.maxUsers && settings.maxUsers > planLimits.maxUsers) {
        throw new Error(`User limit exceeds plan maximum of $${planLimits.maxUsers}`);
    }
    
    if (settings.maxProjects && settings.maxProjects > planLimits.maxProjects) {
        throw new Error(`Project limit exceeds plan maximum of $${planLimits.maxProjects}`);
    }
    
    if (settings.maxStorageGB && settings.maxStorageGB > planLimits.maxStorageGB) {
        throw new Error(`Storage limit exceeds plan maximum of $${planLimits.maxStorageGB}GB`);
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

// Placeholder functions for Cognito integration
async function createTenantAdmin(tenantId, adminData) {
    // Implementation would create the initial tenant admin using Cognito
    console.log('Creating tenant admin:', { tenantId, adminData });
    
    // This would typically:
    // 1. Create Cognito user
    // 2. Set temporary password
    // 3. Add to tenant admin group
    // 4. Send welcome email
}

async function initializeTenantResources(tenantId) {
    // Implementation would set up tenant-specific resources
    console.log('Initializing tenant resources:', tenantId);
    
    // This would typically:
    // 1. Create tenant-specific S3 prefixes
    // 2. Initialize default project templates
    // 3. Set up tenant-specific configurations
    // 4. Create initial feature flags
}