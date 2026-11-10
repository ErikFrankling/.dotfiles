// drive-openapi.json is generated from Google's own Drive v3 Discovery document (revision 20261005)
// by discovery-to-openapi.mjs; see README. Credentials go only to www.googleapis.com.
import type { JsonObject } from "apps";
import type { OpenapiToolNamesOptions } from "apps/openapi";
import drive from "./drive-openapi.json" with { type: "json" };

// The inferred JSON type has no index signature, so widen it once here.
const document: JsonObject = JSON.parse(JSON.stringify(drive));

// Every operation in the generated document already carries a plain bearer requirement.
export const options = {
  source: { document },
  allowedOrigin: "https://www.googleapis.com",
  securitySchemes: { bearer: { type: "http", scheme: "bearer" } },
  methods: {
    oauth: [{ scheme: "bearer", field: "access_token", part: "value", prefix: "" }],
  },
  oauth: [],
} satisfies OpenapiToolNamesOptions;
