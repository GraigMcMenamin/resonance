const {onRequest} = require("firebase-functions/v2/https");
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
