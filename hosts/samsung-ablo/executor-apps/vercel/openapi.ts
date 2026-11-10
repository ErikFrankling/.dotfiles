import type { OpenapiToolNamesOptions } from "apps/openapi";

export const options = {
  source: { url: "https://openapi.vercel.sh/" },
  allowedOrigin: "https://api.vercel.com",
  securitySchemes: { bearerToken: { type: "http", scheme: "bearer" } },
  methods: { apiKey: [{ scheme: "bearerToken", field: "token", part: "value", prefix: "" }] },
  oauth: [],
} satisfies OpenapiToolNamesOptions;
