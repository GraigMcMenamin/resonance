const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();

// Define secrets (stored in Google Cloud Secret Manager)
const spotifyClientId = defineSecret("SPOTIFY_CLIENT_ID");
const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");

/**
 * Cloud Function: Create Firebase custom token from Spotify access token
 * 
 * This ensures the same Spotify user always gets the same Firebase UID,
 * making ratings persistent across devices and sessions.
 * 
 * POST /authenticateWithSpotify
 * Body: { spotifyAccessToken: string }
 * Response: { firebaseToken: string, user: object }
 */
exports.authenticateWithSpotify = onRequest(
  {
    cors: true, // Enable CORS for iOS app
    maxInstances: 10, // Limit concurrent instances
  },
  async (req, res) => {
    // Set cache headers for better performance
    res.set('Cache-Control', 'private, max-age=300'); // Cache for 5 minutes
    
    // Only allow POST requests
    if (req.method !== "POST") {
      return res.status(405).json({error: "Method not allowed"});
    }

    const {spotifyAccessToken} = req.body;

    if (!spotifyAccessToken) {
      return res.status(400).json({error: "Missing spotifyAccessToken"});
    }

    try {
      // Step 1: Verify Spotify token and get user profile
      const spotifyResponse = await fetch("https://api.spotify.com/v1/me", {
        headers: {
          "Authorization": `Bearer ${spotifyAccessToken}`,
        },
      });

      if (!spotifyResponse.ok) {
        console.error("Spotify API error:", spotifyResponse.status);
        return res.status(401).json({
          error: "Invalid Spotify token",
          details: await spotifyResponse.text(),
        });
      }

      const spotifyUser = await spotifyResponse.json();
      console.log(`Verified Spotify user: ${spotifyUser.id} (${spotifyUser.display_name})`);

      // Step 2: Ensure Firebase user exists with Spotify ID as UID
      try {
        await admin.auth().getUser(spotifyUser.id);
        console.log(`User ${spotifyUser.id} already exists`);
      } catch (error) {
        if (error.code === "auth/user-not-found") {
          // Create the user if they don't exist
          await admin.auth().createUser({
            uid: spotifyUser.id,
            email: spotifyUser.email,
            displayName: spotifyUser.display_name,
            photoURL: spotifyUser.images?.[0]?.url,
          });
          console.log(`Created new user ${spotifyUser.id}`);
        } else {
          throw error;
        }
      }

      // Step 3: Create custom token for this user
      const firebaseToken = await admin.auth().createCustomToken(spotifyUser.id);
      console.log(`Created custom token for Spotify user: ${spotifyUser.id}`);

      // Step 3: Return token and user info to iOS app
      return res.status(200).json({
        firebaseToken,
        user: {
          id: spotifyUser.id,
          displayName: spotifyUser.display_name,
          email: spotifyUser.email,
          imageURL: spotifyUser.images?.[0]?.url,
        },
      });
    } catch (error) {
      console.error("Authentication error:", error);
      return res.status(500).json({
        error: "Internal server error",
        message: error.message,
      });
    }
  }
);

/**
 * Cloud Function: Send push notification when a music recommendation is created
 * 
 * Triggered when a new document is created in the recommendations collection.
 * Sends a push notification to the receiver's device.
 */
exports.onRecommendationCreated = onDocumentCreated(
  "recommendations/{recommendationId}",
  async (event) => {
    const recommendation = event.data?.data();
    
    if (!recommendation) {
      console.log("No recommendation data found");
      return;
    }

    const {
      receiverId,
      senderUsername,
      itemName,
      itemType,
      message,
    } = recommendation;

    console.log(`📬 New recommendation: ${senderUsername || 'Someone'} sent ${itemName} to ${receiverId}`);

    try {
      // Get receiver's FCM tokens from their user document
      const userDoc = await admin.firestore()
        .collection("users")
        .doc(receiverId)
        .get();

      if (!userDoc.exists) {
        console.log(`User ${receiverId} not found`);
        return;
      }

      const userData = userDoc.data();
      const fcmTokens = userData.fcmTokens || [];

      if (fcmTokens.length === 0) {
        console.log(`No FCM tokens for user ${receiverId}`);
        return;
      }

      // Build notification content
      const senderName = senderUsername || "Someone";
      const itemTypeLabel = itemType === "track" ? "song" : itemType;
      
      // Use "an" for vowel-starting words (artist, album)
      const article = /^[aeiou]/i.test(itemTypeLabel) ? "an" : "a";
      
      let notificationBody = `${senderName} sent you ${article} ${itemTypeLabel} "${itemName}"`;
      if (message) {
        notificationBody += ` and said: ${message}`;
      }

      // Send notification to all of user's devices
      const notifications = fcmTokens.map(async (token) => {
        try {
          await admin.messaging().send({
            token: token,
            notification: {
              title: "Resonance",
              body: notificationBody,
            },
            data: {
              type: "recommendation",
              recommendationId: event.params.recommendationId,
              spotifyId: recommendation.spotifyId,
              itemType: itemType,
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                },
              },
            },
          });
          console.log(`Notification sent to token: ${token.substring(0, 20)}...`);
        } catch (error) {
          console.error(`Error sending to token: ${error.message}`);
          // If token is invalid, remove it from the user's tokens
          if (error.code === "messaging/invalid-registration-token" ||
              error.code === "messaging/registration-token-not-registered") {
            console.log(`Removing invalid token: ${token.substring(0, 20)}...`);
            await admin.firestore()
              .collection("users")
              .doc(receiverId)
              .update({
                fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
              });
          }
        }
      });

      await Promise.all(notifications);
      console.log(`Sent notifications to ${fcmTokens.length} device(s)`);
    } catch (error) {
      console.error("Error in onRecommendationCreated:", error);
    }
  }
);

/**
 * Cloud Function: Send push notification when a buddy rates or reviews something
 * 
 * Triggered when a rating document is created or updated in the ratings collection.
 * Sends a push notification to all of the user's buddies.
 */
exports.onRatingCreated = onDocumentWritten(
  "ratings/{ratingId}",
  async (event) => {
    const rating = event.data?.after?.data();
    const previousRating = event.data?.before?.data();
    
    if (!rating) {
      console.log("No rating data found (rating was deleted)");
      return;
    }

    const {
      userId,
      userName,
      username,
      name: itemName,
      artistName,
      type: itemType,
      percentage,
      reviewContent,
      hasReviewContent,
    } = rating;

    // Determine if this is a new rating or an update
    const isNew = !previousRating;
    const hadReview = previousRating?.reviewContent && previousRating.reviewContent.trim() !== "";
    const hasReview = reviewContent && reviewContent.trim() !== "";
    const isNewReview = hasReview && !hadReview;

    // Only send notifications for new ratings or new reviews
    if (!isNew && !isNewReview) {
      console.log("Rating update without new review, skipping notification");
      return;
    }

    const userDisplayName = username || userName || "A buddy";
    const action = isNewReview ? "reviewed" : "rated";
    
    console.log(`${userDisplayName} ${action}: ${itemName} (${percentage}%)`);

    try {
      // Get the user's buddies from their subcollection
      const buddiesSnapshot = await admin.firestore()
        .collection("users")
        .doc(userId)
        .collection("buddies")
        .get();

      if (buddiesSnapshot.empty) {
        console.log(`User ${userId} has no buddies, skipping notifications`);
        return;
      }

      const buddyIds = buddiesSnapshot.docs.map((doc) => doc.id);
      console.log(`Sending notifications to ${buddyIds.length} buddies`);

      // Batch fetch all buddy documents (Firestore 'in' query supports up to 10 items)
      // Split into chunks of 10 for batch fetching
      const buddyChunks = [];
      for (let i = 0; i < buddyIds.length; i += 10) {
        buddyChunks.push(buddyIds.slice(i, i + 10));
      }

      const allBuddyDocs = [];
      for (const chunk of buddyChunks) {
        const buddyDocsSnapshot = await admin.firestore()
          .collection("users")
          .where(admin.firestore.FieldPath.documentId(), "in", chunk)
          .get();
        allBuddyDocs.push(...buddyDocsSnapshot.docs);
      }

      console.log(`Fetched ${allBuddyDocs.length} buddy documents`);

      // Process all buddies in parallel
      const buddyNotifications = allBuddyDocs.map(async (buddyDoc) => {
        try {
          const buddyData = buddyDoc.data();
          const fcmTokens = buddyData.fcmTokens || [];
          const buddyId = buddyDoc.id;

          if (fcmTokens.length === 0) {
            console.log(`No FCM tokens for buddy ${buddyId}`);
            return;
          }

          // Build notification content
          let notificationBody = "";
          if (isNewReview) {
            notificationBody = `${userDisplayName} reviewed ${itemName}`;
            if (artistName) {
              notificationBody += ` by ${artistName}`;
            }
            notificationBody += ` (${percentage}%)`;
          } else {
            notificationBody = `${userDisplayName} rated ${itemName}`;
            if (artistName) {
              notificationBody += ` by ${artistName}`;
            }
            notificationBody += ` ${percentage}%`;
          }

          const notificationTitle = isNewReview ? "New Review" : "New Rating";

          // Send to all of this buddy's devices
          const tokenPromises = fcmTokens.map(async (token) => {
            try {
              await admin.messaging().send({
                token: token,
                notification: {
                  title: notificationTitle,
                  body: notificationBody,
                },
                data: {
                  type: isNewReview ? "review" : "rating",
                  ratingId: event.params.ratingId,
                  userId: userId,
                  spotifyId: rating.spotifyId,
                  itemType: itemType,
                  itemName: itemName,
                },
                apns: {
                  payload: {
                    aps: {
                      sound: "default",
                      badge: 1,
                    },
                  },
                },
              });
              console.log(`Notification sent to buddy ${buddyId}, token: ${token.substring(0, 20)}...`);
            } catch (error) {
              console.error(`Error sending to token: ${error.message}`);
              // If token is invalid, remove it
              if (error.code === "messaging/invalid-registration-token" ||
                  error.code === "messaging/registration-token-not-registered") {
                console.log(`Removing invalid token from buddy ${buddyId}: ${token.substring(0, 20)}...`);
                await admin.firestore()
                  .collection("users")
                  .doc(buddyId)
                  .update({
                    fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
                  });
              }
            }
          });

          await Promise.all(tokenPromises);
        } catch (error) {
          console.error(`Error processing buddy ${buddyId}: ${error.message}`);
        }
      });

      await Promise.all(buddyNotifications);
      console.log(`Finished sending notifications to buddies`);
    } catch (error) {
      console.error("Error in onRatingCreated:", error);
    }
  }
);

/**
 * Cloud Function: Maintain like count on ratings/reviews
 * 
 * Triggered when a like is added to a rating's likes subcollection.
 * Increments the likesCount field on the parent rating document.
 */
exports.onReviewLikeCreated = onDocumentCreated(
  "ratings/{ratingId}/likes/{likeId}",
  async (event) => {
    try {
      const ratingRef = event.data.ref.parent.parent;
      await ratingRef.update({
        likesCount: admin.firestore.FieldValue.increment(1),
      });
      console.log(`Incremented likesCount for rating ${event.params.ratingId}`);
    } catch (error) {
      console.error("Error incrementing likesCount:", error);
    }
  }
);

/**
 * Cloud Function: Maintain like count on ratings/reviews
 * 
 * Triggered when a like is removed from a rating's likes subcollection.
 * Decrements the likesCount field on the parent rating document.
 */
exports.onReviewLikeDeleted = onDocumentDeleted(
  "ratings/{ratingId}/likes/{likeId}",
  async (event) => {
    try {
      const ratingRef = event.data.ref.parent.parent;
      await ratingRef.update({
        likesCount: admin.firestore.FieldValue.increment(-1),
      });
      console.log(`Decremented likesCount for rating ${event.params.ratingId}`);
    } catch (error) {
      console.error("Error decrementing likesCount:", error);
    }
  }
);

/**
 * Cloud Function: Maintain comment count on ratings/reviews
 * 
 * Triggered when a comment is added to a rating's comments subcollection.
 * Increments the commentsCount field on the parent rating document.
 */
exports.onReviewCommentCreated = onDocumentCreated(
  "ratings/{ratingId}/comments/{commentId}",
  async (event) => {
    try {
      const ratingRef = event.data.ref.parent.parent;
      await ratingRef.update({
        commentsCount: admin.firestore.FieldValue.increment(1),
      });
      console.log(`Incremented commentsCount for rating ${event.params.ratingId}`);
    } catch (error) {
      console.error("Error incrementing commentsCount:", error);
    }
  }
);

/**
 * Cloud Function: Maintain comment count on ratings/reviews
 * 
 * Triggered when a comment is removed from a rating's comments subcollection.
 * Decrements the commentsCount field on the parent rating document.
 */
exports.onReviewCommentDeleted = onDocumentDeleted(
  "ratings/{ratingId}/comments/{commentId}",
  async (event) => {
    try {
      const ratingRef = event.data.ref.parent.parent;
      await ratingRef.update({
        commentsCount: admin.firestore.FieldValue.increment(-1),
      });
      console.log(`Decremented commentsCount for rating ${event.params.ratingId}`);
    } catch (error) {
      console.error("Error decrementing commentsCount:", error);
    }
  }
);

/**
 * Cloud Function: Maintain like count on comments
 * 
 * Triggered when a like is added to a comment's likes subcollection.
 * Increments the likesCount field on the parent comment document.
 */
exports.onCommentLikeCreated = onDocumentCreated(
  "ratings/{ratingId}/comments/{commentId}/likes/{likeId}",
  async (event) => {
    try {
      const commentRef = event.data.ref.parent.parent;
      await commentRef.update({
        likesCount: admin.firestore.FieldValue.increment(1),
      });
      console.log(`Incremented likesCount for comment ${event.params.commentId}`);
    } catch (error) {
      console.error("Error incrementing comment likesCount:", error);
    }
  }
);

/**
 * Cloud Function: Maintain like count on comments
 * 
 * Triggered when a like is removed from a comment's likes subcollection.
 * Decrements the likesCount field on the parent comment document.
 */
exports.onCommentLikeDeleted = onDocumentDeleted(
  "ratings/{ratingId}/comments/{commentId}/likes/{likeId}",
  async (event) => {
    try {
      const commentRef = event.data.ref.parent.parent;
      await commentRef.update({
        likesCount: admin.firestore.FieldValue.increment(-1),
      });
      console.log(`Decremented likesCount for comment ${event.params.commentId}`);
    } catch (error) {
      console.error("Error decrementing comment likesCount:", error);
    }
  }
);

// =============================================================================
// Spotify Token Proxy Functions
// These keep the client_secret on the server side only.
// =============================================================================

/**
 * Cloud Function: Get a Spotify client credentials token
 * Used by SpotifyService for search & metadata API calls.
 *
 * POST /getSpotifyToken
 * Body: (none required)
 * Response: { accessToken: string, expiresIn: number }
 */
exports.getSpotifyToken = onRequest(
  {
    cors: true,
    maxInstances: 10,
    secrets: [spotifyClientId, spotifyClientSecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({error: "Method not allowed"});
    }

    try {
      const clientId = spotifyClientId.value();
      const clientSecret = spotifyClientSecret.value();
      const authString = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");

      const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
        method: "POST",
        headers: {
          "Authorization": `Basic ${authString}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: "grant_type=client_credentials",
      });

      if (!tokenResponse.ok) {
        const errorBody = await tokenResponse.text();
        console.error("Spotify client credentials error:", tokenResponse.status, errorBody);
        return res.status(tokenResponse.status).json({error: "Failed to get token"});
      }

      const data = await tokenResponse.json();
      return res.status(200).json({
        accessToken: data.access_token,
        expiresIn: data.expires_in,
      });
    } catch (error) {
      console.error("getSpotifyToken error:", error);
      return res.status(500).json({error: "Internal server error"});
    }
  }
);

/**
 * Cloud Function: Exchange a Spotify authorization code for tokens
 * Used during OAuth login flow.
 *
 * POST /exchangeSpotifyCode
 * Body: { code: string, redirectUri: string }
 * Response: { accessToken, refreshToken, expiresIn }
 */
exports.exchangeSpotifyCode = onRequest(
  {
    cors: true,
    maxInstances: 10,
    secrets: [spotifyClientId, spotifyClientSecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({error: "Method not allowed"});
    }

    const {code, redirectUri} = req.body;

    if (!code || !redirectUri) {
      return res.status(400).json({error: "Missing code or redirectUri"});
    }

    try {
      const clientId = spotifyClientId.value();
      const clientSecret = spotifyClientSecret.value();

      const bodyParams = new URLSearchParams({
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirectUri,
        client_id: clientId,
        client_secret: clientSecret,
      });

      const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: bodyParams.toString(),
      });

      if (!tokenResponse.ok) {
        const errorBody = await tokenResponse.text();
        console.error("Spotify code exchange error:", tokenResponse.status, errorBody);
        return res.status(tokenResponse.status).json({error: "Token exchange failed"});
      }

      const data = await tokenResponse.json();
      return res.status(200).json({
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresIn: data.expires_in,
      });
    } catch (error) {
      console.error("exchangeSpotifyCode error:", error);
      return res.status(500).json({error: "Internal server error"});
    }
  }
);

/**
 * Cloud Function: Refresh a Spotify access token
 *
 * POST /refreshSpotifyToken
 * Body: { refreshToken: string }
 * Response: { accessToken, refreshToken?, expiresIn }
 */
exports.refreshSpotifyToken = onRequest(
  {
    cors: true,
    maxInstances: 10,
    secrets: [spotifyClientId, spotifyClientSecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({error: "Method not allowed"});
    }

    const {refreshToken} = req.body;

    if (!refreshToken) {
      return res.status(400).json({error: "Missing refreshToken"});
    }

    try {
      const clientId = spotifyClientId.value();
      const clientSecret = spotifyClientSecret.value();

      const bodyParams = new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: refreshToken,
        client_id: clientId,
        client_secret: clientSecret,
      });

      const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: bodyParams.toString(),
      });

      if (!tokenResponse.ok) {
        const errorBody = await tokenResponse.text();
        console.error("Spotify token refresh error:", tokenResponse.status, errorBody);
        return res.status(tokenResponse.status).json({error: "Token refresh failed"});
      }

      const data = await tokenResponse.json();
      return res.status(200).json({
        accessToken: data.access_token,
        refreshToken: data.refresh_token || null,
        expiresIn: data.expires_in,
      });
    } catch (error) {
      console.error("refreshSpotifyToken error:", error);
      return res.status(500).json({error: "Internal server error"});
    }
  }
);