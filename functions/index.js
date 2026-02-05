const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();

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
  {cors: true}, // Enable CORS for iOS app
  async (req, res) => {
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
      console.log(`✅ Verified Spotify user: ${spotifyUser.id} (${spotifyUser.display_name})`);

      // Step 2: Ensure Firebase user exists with Spotify ID as UID
      try {
        await admin.auth().getUser(spotifyUser.id);
        console.log(`✅ User ${spotifyUser.id} already exists`);
      } catch (error) {
        if (error.code === "auth/user-not-found") {
          // Create the user if they don't exist
          await admin.auth().createUser({
            uid: spotifyUser.id,
            email: spotifyUser.email,
            displayName: spotifyUser.display_name,
            photoURL: spotifyUser.images?.[0]?.url,
          });
          console.log(`✅ Created new user ${spotifyUser.id}`);
        } else {
          throw error;
        }
      }

      // Step 3: Create custom token for this user
      const firebaseToken = await admin.auth().createCustomToken(spotifyUser.id);
      console.log(`🔑 Created custom token for Spotify user: ${spotifyUser.id}`);

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
      console.error("❌ Authentication error:", error);
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
      senderDisplayName,
      itemName,
      itemType,
      message,
    } = recommendation;

    console.log(`📬 New recommendation: ${senderDisplayName} sent ${itemName} to ${receiverId}`);

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
      const senderName = senderUsername || senderDisplayName || "Someone";
      const itemTypeLabel = itemType === "track" ? "song" : itemType;
      
      let notificationBody = `${senderName} sent you a ${itemTypeLabel}: ${itemName}`;
      if (message) {
        notificationBody += ` - "${message}"`;
      }

      // Send notification to all of user's devices
      const notifications = fcmTokens.map(async (token) => {
        try {
          await admin.messaging().send({
            token: token,
            notification: {
              title: "🎵 New Music Recommendation",
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
          console.log(`✅ Notification sent to token: ${token.substring(0, 20)}...`);
        } catch (error) {
          console.error(`❌ Error sending to token: ${error.message}`);
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
      console.log(`📱 Sent notifications to ${fcmTokens.length} device(s)`);
    } catch (error) {
      console.error("❌ Error in onRecommendationCreated:", error);
    }
  }
);
