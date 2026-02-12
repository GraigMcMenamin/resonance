const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
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
      
      let notificationBody = `${senderName} sent you a ${itemTypeLabel} "${itemName}"`;
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

      // Get FCM tokens for all buddies
      const buddyNotifications = buddyIds.map(async (buddyId) => {
        try {
          const buddyDoc = await admin.firestore()
            .collection("users")
            .doc(buddyId)
            .get();

          if (!buddyDoc.exists) {
            console.log(`Buddy ${buddyId} not found`);
            return;
          }

          const buddyData = buddyDoc.data();
          const fcmTokens = buddyData.fcmTokens || [];

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
