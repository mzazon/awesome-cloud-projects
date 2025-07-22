const functions = require('@google-cloud/functions-framework');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp({
  projectId: '${project_id}',
  databaseURL: 'https://${project_id}-default-rtdb.firebaseio.com/'
});

// Get references to Firebase services
const db = admin.database();
const auth = admin.auth();

/**
 * HTTP Cloud Function to create a new collaborative document
 * Expects JSON body with: { title: string, initialContent?: string }
 */
functions.http('createDocument', async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    // Verify Firebase ID token
    const authHeader = req.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: No valid token provided' });
    }

    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await auth.verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Validate request body
    const { title, initialContent = '' } = req.body;
    
    if (!title || title.trim().length === 0) {
      return res.status(400).json({ error: 'Document title is required' });
    }

    if (title.length > 200) {
      return res.status(400).json({ error: 'Document title too long (max 200 characters)' });
    }

    // Generate document ID and create document data
    const documentRef = db.ref('documents').push();
    const documentId = documentRef.key;
    
    const documentData = {
      title: title.trim(),
      content: initialContent,
      owner: uid,
      collaborators: {
        [uid]: {
          role: 'owner',
          joinedAt: admin.database.ServerValue.TIMESTAMP,
          displayName: decodedToken.name || decodedToken.email || 'Anonymous'
        }
      },
      createdAt: admin.database.ServerValue.TIMESTAMP,
      lastModified: admin.database.ServerValue.TIMESTAMP,
      version: 1,
      isActive: true
    };

    // Save document to database
    await documentRef.set(documentData);
    
    // Log document creation
    console.log(`Document created: ${documentId} by user: ${uid}`);
    
    res.status(201).json({ 
      success: true,
      documentId: documentId,
      title: title.trim(),
      message: 'Document created successfully'
    });

  } catch (error) {
    console.error('Error creating document:', error);
    
    if (error.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'Token expired' });
    } else if (error.code === 'auth/invalid-id-token') {
      return res.status(401).json({ error: 'Invalid token' });
    }
    
    res.status(500).json({ 
      error: 'Internal server error',
      message: 'Failed to create document'
    });
  }
});

/**
 * HTTP Cloud Function to add a collaborator to a document
 * Expects JSON body with: { documentId: string, collaboratorEmail: string, role?: string }
 */
functions.http('addCollaborator', async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    // Verify Firebase ID token
    const authHeader = req.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: No valid token provided' });
    }

    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await auth.verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Validate request body
    const { documentId, collaboratorEmail, role = 'collaborator' } = req.body;
    
    if (!documentId || !collaboratorEmail) {
      return res.status(400).json({ 
        error: 'Document ID and collaborator email are required'
      });
    }

    // Validate role
    const validRoles = ['viewer', 'collaborator', 'editor'];
    if (!validRoles.includes(role)) {
      return res.status(400).json({ 
        error: `Invalid role. Must be one of: ${validRoles.join(', ')}`
      });
    }

    // Check if document exists and user has permission
    const docSnapshot = await db.ref(`documents/${documentId}`).once('value');
    const document = docSnapshot.val();
    
    if (!document) {
      return res.status(404).json({ error: 'Document not found' });
    }

    // Check if user is owner or has admin rights
    const userRole = document.collaborators?.[uid]?.role;
    if (document.owner !== uid && userRole !== 'admin') {
      return res.status(403).json({ 
        error: 'Permission denied: Only document owner can add collaborators'
      });
    }

    // Find user by email
    let collaboratorUser;
    try {
      collaboratorUser = await auth.getUserByEmail(collaboratorEmail);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        return res.status(404).json({ 
          error: 'User not found',
          message: 'The specified email address is not registered'
        });
      }
      throw error;
    }

    // Check if user is already a collaborator
    if (document.collaborators && document.collaborators[collaboratorUser.uid]) {
      return res.status(409).json({ 
        error: 'User is already a collaborator',
        currentRole: document.collaborators[collaboratorUser.uid].role
      });
    }

    // Add collaborator to document
    const collaboratorData = {
      role: role,
      joinedAt: admin.database.ServerValue.TIMESTAMP,
      addedBy: uid,
      displayName: collaboratorUser.displayName || collaboratorUser.email || 'Anonymous'
    };

    await db.ref(`documents/${documentId}/collaborators/${collaboratorUser.uid}`)
      .set(collaboratorData);

    // Update last modified timestamp
    await db.ref(`documents/${documentId}/lastModified`)
      .set(admin.database.ServerValue.TIMESTAMP);

    // Log collaborator addition
    console.log(`Collaborator added: ${collaboratorUser.uid} to document: ${documentId}`);
    
    res.status(200).json({ 
      success: true,
      collaboratorId: collaboratorUser.uid,
      collaboratorEmail: collaboratorEmail,
      role: role,
      message: 'Collaborator added successfully'
    });

  } catch (error) {
    console.error('Error adding collaborator:', error);
    
    if (error.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'Token expired' });
    } else if (error.code === 'auth/invalid-id-token') {
      return res.status(401).json({ error: 'Invalid token' });
    }
    
    res.status(500).json({ 
      error: 'Internal server error',
      message: 'Failed to add collaborator'
    });
  }
});

/**
 * HTTP Cloud Function to get user's documents
 * Returns list of documents the user owns or collaborates on
 */
functions.http('getUserDocuments', async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    // Verify Firebase ID token
    const authHeader = req.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: No valid token provided' });
    }

    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await auth.verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Get all documents where user is a collaborator
    const snapshot = await db.ref('documents')
      .orderByChild(`collaborators/${uid}`)
      .once('value');

    const documents = [];
    
    snapshot.forEach((child) => {
      const doc = child.val();
      
      // Only include active documents where user is a collaborator
      if (doc && doc.isActive !== false && doc.collaborators && doc.collaborators[uid]) {
        const userRole = doc.collaborators[uid].role;
        
        documents.push({
          id: child.key,
          title: doc.title,
          lastModified: doc.lastModified,
          createdAt: doc.createdAt,
          version: doc.version || 1,
          role: userRole,
          isOwner: doc.owner === uid,
          collaboratorCount: Object.keys(doc.collaborators || {}).length,
          preview: doc.content ? doc.content.substring(0, 100) + '...' : ''
        });
      }
    });

    // Sort documents by last modified (newest first)
    documents.sort((a, b) => (b.lastModified || 0) - (a.lastModified || 0));

    // Log document retrieval
    console.log(`Retrieved ${documents.length} documents for user: ${uid}`);
    
    res.status(200).json({ 
      success: true,
      documents: documents,
      totalCount: documents.length
    });

  } catch (error) {
    console.error('Error fetching user documents:', error);
    
    if (error.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'Token expired' });
    } else if (error.code === 'auth/invalid-id-token') {
      return res.status(401).json({ error: 'Invalid token' });
    }
    
    res.status(500).json({ 
      error: 'Internal server error',
      message: 'Failed to fetch documents'
    });
  }
});

/**
 * HTTP Cloud Function to track document changes
 * This function can be called by database triggers or webhooks
 */
functions.http('trackDocumentChange', async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    const { documentId, changeType, userId } = req.body;

    if (!documentId || !changeType) {
      return res.status(400).json({ 
        error: 'Document ID and change type are required'
      });
    }

    // Update document metadata
    const updates = {
      lastModified: admin.database.ServerValue.TIMESTAMP
    };

    // Increment version for content changes
    if (changeType === 'content') {
      const versionRef = db.ref(`documents/${documentId}/version`);
      await versionRef.transaction((currentVersion) => {
        return (currentVersion || 0) + 1;
      });
    }

    // Apply updates
    await db.ref(`documents/${documentId}`).update(updates);

    // Log the change
    console.log(`Document ${documentId} modified: ${changeType} by ${userId || 'unknown'}`);

    res.status(200).json({ 
      success: true,
      message: 'Document change tracked successfully'
    });

  } catch (error) {
    console.error('Error tracking document change:', error);
    res.status(500).json({ 
      error: 'Internal server error',
      message: 'Failed to track document change'
    });
  }
});