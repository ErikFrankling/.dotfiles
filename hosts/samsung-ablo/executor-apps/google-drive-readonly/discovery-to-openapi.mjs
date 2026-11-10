// Converts Google's Drive v3 Discovery document into the vendored drive-openapi.json.
// Usage: node discovery-to-openapi.mjs <discovery.json> > drive-openapi.json
// Fetch the input from https://www.googleapis.com/discovery/v1/apis/drive/v3/rest
import { readFileSync } from "node:fs";

const d = JSON.parse(readFileSync(process.argv[2], "utf8"));

const schema = (s) => {
  if (!s) return {};
  if (s.$ref) return { $ref: `#/components/schemas/${s.$ref}` };
  const out = {};
  if (s.description) out.description = s.description;
  if (s.type === "any") return out;
  if (s.type) out.type = s.type;
  if (s.format) out.format = s.format;
  if (s.enum) out.enum = s.enum;
  if (s.properties) {
    out.properties = Object.fromEntries(Object.entries(s.properties).map(([k, v]) => [k, schema(v)]));
  }
  if (s.additionalProperties) out.additionalProperties = schema(s.additionalProperties);
  if (s.items) out.items = schema(s.items);
  return out;
};

const param = (name, p) => {
  const base = schema({ type: p.type, format: p.format, enum: p.enum });
  return {
    name,
    in: p.location,
    required: p.location === "path" ? true : Boolean(p.required),
    description: p.description,
    schema: p.repeated ? { type: "array", items: base } : base,
  };
};

const paths = {};
const walk = (resources) => {
  for (const r of Object.values(resources ?? {})) {
    for (const m of Object.values(r.methods ?? {})) {
      const key = `/${m.path.replace(/^\//, "")}`;
      const params = Object.entries(m.parameters ?? {}).map(([n, p]) => param(n, p));
      params.push({ name: "fields", in: "query", required: false, description: d.parameters.fields.description, schema: { type: "string" } });
      const op = {
        operationId: m.id,
        description: m.description?.trim(),
        parameters: params,
        responses: {
          200: m.response
            ? { description: "Success", content: { "application/json": { schema: schema(m.response) } } }
            : { description: "Success" },
        },
        security: [{ bearer: [] }],
      };
      if (m.request) {
        op.requestBody = { required: true, content: { "application/json": { schema: schema(m.request) } } };
      }
      (paths[key] ??= {})[m.httpMethod.toLowerCase()] = op;
    }
    walk(r.resources);
  }
};
walk(d.resources);

const doc = {
  openapi: "3.0.3",
  info: {
    title: d.title,
    version: `${d.version} (discovery revision ${d.revision})`,
    description: d.description,
  },
  servers: [{ url: d.baseUrl.replace(/\/$/, "") }],
  security: [{ bearer: [] }],
  paths,
  components: {
    schemas: Object.fromEntries(Object.entries(d.schemas).map(([k, v]) => [k, schema(v)])),
    securitySchemes: { bearer: { type: "http", scheme: "bearer" } },
  },
};
process.stdout.write(JSON.stringify(doc, null, 1) + "\n");
