const { Firestore } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore with project ID from template variable
const firestore = new Firestore({
  projectId: '${project_id}'
});

/**
 * Cloud Function for submitting votes
 * Handles vote submission with duplicate prevention using Firestore transactions
 */
functions.http('submitVote', async (req, res) => {
  // Configure CORS headers for cross-origin requests
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  // Only accept POST requests for vote submission
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }
  
  try {
    const { topicId, option, userId } = req.body;
    
    // Validate required input parameters
    if (!topicId || !option || !userId) {
      res.status(400).json({ 
        error: 'Missing required fields',
        required: ['topicId', 'option', 'userId']
      });
      return;
    }
    
    // Validate input format and length
    if (typeof topicId !== 'string' || topicId.length > 100) {
      res.status(400).json({ error: 'Invalid topicId format or length' });
      return;
    }
    
    if (typeof option !== 'string' || option.length > 100) {
      res.status(400).json({ error: 'Invalid option format or length' });
      return;
    }
    
    if (typeof userId !== 'string' || userId.length > 100) {
      res.status(400).json({ error: 'Invalid userId format or length' });
      return;
    }
    
    // Create composite key for user vote tracking (prevents duplicates)
    const userVoteRef = firestore
      .collection('votes')
      .doc(`${topicId}_${userId}`);
    
    // Check if user has already voted on this topic
    const userVoteDoc = await userVoteRef.get();
    
    if (userVoteDoc.exists) {
      res.status(409).json({ 
        error: 'User already voted on this topic',
        existingVote: {
          option: userVoteDoc.data().option,
          timestamp: userVoteDoc.data().timestamp
        }
      });
      return;
    }
    
    // Use Firestore transaction to ensure atomicity of vote recording and counting
    await firestore.runTransaction(async (transaction) => {
      // Record the individual vote for duplicate prevention
      transaction.set(userVoteRef, {
        topicId,
        option,
        userId,
        timestamp: Firestore.Timestamp.now(),
        ipAddress: req.headers['x-forwarded-for'] || req.connection.remoteAddress || 'unknown'
      });
      
      // Update the vote count for this topic and option
      const countRef = firestore
        .collection('voteCounts')
        .doc(`${topicId}_${option}`);
      
      const countDoc = await transaction.get(countRef);
      const currentCount = countDoc.exists ? countDoc.data().count || 0 : 0;
      
      transaction.set(countRef, {
        topicId,
        option,
        count: currentCount + 1,
        lastUpdated: Firestore.Timestamp.now()
      });
      
      // Update topic metadata (optional: track total votes per topic)
      const topicRef = firestore
        .collection('topics')
        .doc(topicId);
      
      const topicDoc = await transaction.get(topicRef);
      const totalVotes = topicDoc.exists ? (topicDoc.data().totalVotes || 0) + 1 : 1;
      
      transaction.set(topicRef, {
        topicId,
        totalVotes,
        lastVoteTimestamp: Firestore.Timestamp.now()
      }, { merge: true });
    });
    
    console.log(`Vote recorded successfully: ${userId} voted ${option} for ${topicId}`);
    
    res.status(200).json({ 
      success: true, 
      message: 'Vote recorded successfully',
      vote: {
        topicId,
        option,
        userId,
        timestamp: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error('Error processing vote:', error);
    
    // Provide specific error messages for debugging while avoiding sensitive data exposure
    if (error.code === 'PERMISSION_DENIED') {
      res.status(403).json({ error: 'Permission denied accessing Firestore' });
    } else if (error.code === 'UNAVAILABLE') {
      res.status(503).json({ error: 'Service temporarily unavailable' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

/**
 * Cloud Function for retrieving voting results
 * Returns vote counts for a specific topic
 */
functions.http('getResults', async (req, res) => {
  // Configure CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    const { topicId } = req.query;
    
    // Validate required query parameter
    if (!topicId) {
      res.status(400).json({ 
        error: 'Missing required parameter: topicId',
        example: '?topicId=your-topic-id'
      });
      return;
    }
    
    // Validate topicId format
    if (typeof topicId !== 'string' || topicId.length > 100) {
      res.status(400).json({ error: 'Invalid topicId format or length' });
      return;
    }
    
    // Query vote counts for the specified topic
    const countsSnapshot = await firestore
      .collection('voteCounts')
      .where('topicId', '==', topicId)
      .get();
    
    // Build results object from Firestore documents
    const results = {};
    let totalVotes = 0;
    
    countsSnapshot.forEach(doc => {
      const data = doc.data();
      results[data.option] = data.count || 0;
      totalVotes += data.count || 0;
    });
    
    // Get topic metadata if available
    let topicMetadata = {};
    try {
      const topicDoc = await firestore
        .collection('topics')
        .doc(topicId)
        .get();
      
      if (topicDoc.exists) {
        const topicData = topicDoc.data();
        topicMetadata = {
          totalVotes: topicData.totalVotes || totalVotes,
          lastVoteTimestamp: topicData.lastVoteTimestamp?.toDate()?.toISOString() || null
        };
      }
    } catch (metadataError) {
      console.warn('Could not retrieve topic metadata:', metadataError);
    }
    
    console.log(`Results retrieved for topic: ${topicId}, total votes: ${totalVotes}`);
    
    res.status(200).json({ 
      topicId, 
      results,
      totalVotes,
      metadata: topicMetadata,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Error getting results:', error);
    
    // Provide specific error messages for debugging
    if (error.code === 'PERMISSION_DENIED') {
      res.status(403).json({ error: 'Permission denied accessing Firestore' });
    } else if (error.code === 'UNAVAILABLE') {
      res.status(503).json({ error: 'Service temporarily unavailable' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

// Health check endpoint for monitoring
functions.http('health', async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    // Test Firestore connectivity
    await firestore.collection('_health').limit(1).get();
    
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      service: 'voting-system-functions'
    });
  } catch (error) {
    console.error('Health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: 'Database connectivity issue',
      timestamp: new Date().toISOString()
    });
  }
});