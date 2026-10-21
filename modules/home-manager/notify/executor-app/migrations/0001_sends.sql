-- One row per send attempt; the rate limits count rows that were not 'failed'.
CREATE TABLE sends (
  id TEXT PRIMARY KEY NOT NULL,
  created_at INTEGER NOT NULL,
  class TEXT NOT NULL, -- urgent | high | normal | low | code
  digest TEXT NOT NULL, -- title + message, for dropping repeats
  title TEXT NOT NULL,
  source TEXT NOT NULL,
  status TEXT NOT NULL, -- sending | sent | failed
  message_id TEXT
);
CREATE INDEX sends_created ON sends (created_at);
