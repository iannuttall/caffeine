#!/usr/bin/env node
import { readFileSync } from "node:fs";

const [, , command, filePath] = process.argv;
if (command !== "env" || !filePath) {
  console.error("usage: app_config.mjs env <app.config.json>");
  process.exit(2);
}

const quote = (value) => `'${String(value ?? "").replaceAll("'", "'\\''")}'`;
const output = (name, value) => {
  if (value !== undefined && value !== null) console.log(`${name}=${quote(value)}`);
};
const config = JSON.parse(readFileSync(filePath, "utf8"));

output("APP_DISPLAY", config.displayName);
output("BUNDLE_ID", config.bundleId);
output("TEAM_ID", config.teamId);
output("MIN_MACOS", config.minMacOS);
output("FEED_URL", config.feedURL);
output("DOWNLOAD_URL_PREFIX", config.downloadURLPrefix);
output("HOMEBREW_TAP", config.homebrewTap);
output("SPARKLE_PUBLIC_KEY", config.sparklePublicKey);
output("GH_OWNER", config.github?.owner);
output("GH_REPO", config.github?.repo);
