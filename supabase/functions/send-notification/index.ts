// @ts-nocheck
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function base64UrlEncode(data: Uint8Array): string {
  let binary = "";
  for (const byte of data) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function stringToUint8Array(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

async function createFirebaseAccessToken(
  serviceAccount: {
    client_email: string;
    private_key: string;
  },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64UrlEncode(
    stringToUint8Array(JSON.stringify({
      alg: "RS256",
      typ: "JWT",
    })),
  );

  const payload = base64UrlEncode(
    stringToUint8Array(JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })),
  );

  const unsignedToken = `${header}.${payload}`;

  const pem = serviceAccount.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binaryKey = Uint8Array.from(
    atob(pem),
    (character) => character.charCodeAt(0),
  );

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    stringToUint8Array(unsignedToken),
  );

  const jwt = `${unsignedToken}.${base64UrlEncode(
    new Uint8Array(signature),
  )}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await response.json();

  if (!response.ok) {
    throw new Error(
      `Failed to obtain Firebase access token: ${JSON.stringify(tokenData)}`,
    );
  }

  return tokenData.access_token;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({
          error: "Only POST requests are allowed",
        }),
        {
          status: 405,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    const body = await req.json();

    const {
      token,
      title,
      message,
    } = body;

    if (!token || !title || !message) {
      return new Response(
        JSON.stringify({
          error: "token, title and message are required",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    const firebaseSecret = Deno.env.get(
      "FIREBASE_SERVICE_ACCOUNT_BASE64",
    );

    if (!firebaseSecret) {
      return new Response(
        JSON.stringify({
          error: "Firebase service account secret is not configured",
        }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    const decoded = atob(firebaseSecret);
    const firebaseJson = JSON.parse(decoded);

    const accessToken = await createFirebaseAccessToken(
      firebaseJson,
    );

    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${firebaseJson.project_id}/messages:send`;

    const fcmResponse = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title,
            body: message,
          },
        },
      }),
    });

    const fcmData = await fcmResponse.json();

    if (!fcmResponse.ok) {
      return new Response(
        JSON.stringify({
          error: "Firebase rejected the notification",
          details: fcmData,
        }),
        {
          status: fcmResponse.status,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: "Notification sent successfully",
        firebase: fcmData,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error
          ? error.message
          : "Unknown error",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }
});