import type { OpenapiToolNamesOptions } from "apps/openapi";

// Google publishes the Gmail API as a Discovery document, not OpenAPI. This is APIs.guru's
// maintained OpenAPI conversion of that document (unofficial). Its oauth2 schemes are
// implicit-flow descriptions, so bearer schemes of the same names carry the access token instead.
export const options = {
  source: { url: "https://api.apis.guru/v2/specs/googleapis.com/gmail/v1/openapi.json" },
  allowedOrigin: "https://gmail.googleapis.com",
  securitySchemes: {
    Oauth2c: { type: "http", scheme: "bearer" },
    Oauth2: { type: "http", scheme: "bearer" },
  },
  methods: {
    oauth: [
      { scheme: "Oauth2c", field: "access_token", part: "value", prefix: "" },
      { scheme: "Oauth2", field: "access_token", part: "value", prefix: "" },
    ],
  },
  oauth: [],
} satisfies OpenapiToolNamesOptions;
