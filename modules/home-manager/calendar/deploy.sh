#!/usr/bin/env bash
# Deploy executor-app/ to Executor as the app "Calendar" (creates it the first
# time). Usage: ./deploy.sh   Needs /run/secrets/executor-api-key.
set -euo pipefail
cd "$(dirname "$0")/executor-app"
url=https://executor.erikfrankling.duckdns.org/mcp
key=$(cat /run/secrets/executor-api-key)
files=$(jq -n --rawfile i index.ts --rawfile p package.json \
  '[{path:"index.ts",content:$i},{path:"package.json",content:$p}]')
code="const files = $files;
const org = (await tools.executor.context.get({})).organization;
const list = await tools.executor.organization.inventory({ path: { organization: org } });
let appId = list.apps.find((a) => a.name === 'Calendar')?.id ?? null;
if (!appId) appId = (await tools.executor.appManagement.create({ path: { organization: org }, body: { name: 'Calendar', files } })).id;
const d = await tools.executor.appManagement.deploy({ path: { organization: org, app: appId }, body: { files } });
return { appId, version: d.version?.id ?? d.version };"
hdr=(-H "Authorization: Bearer $key" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
sid=$(curl -sS -D - -o /dev/null "${hdr[@]}" "$url" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"calendar-deploy","version":"1"}}}' |
  awk 'tolower($1)=="mcp-session-id:"{print $2}' | tr -d '\r')
curl -sS -o /dev/null "${hdr[@]}" -H "Mcp-Session-Id: $sid" "$url" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
jq -n --arg code "$code" '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:"execute",arguments:{code:$code}}}' |
  curl -sS "${hdr[@]}" -H "Mcp-Session-Id: $sid" "$url" -d @- | sed -n 's/^data: //p;/^{/p' | jq -r '.result.content[0].text // .'
