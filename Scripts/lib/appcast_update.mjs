#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";

const required = ["APPCAST", "CHANGELOG", "VERSION", "BUILD", "MIN_MACOS", "DOWNLOAD_URL", "ED_SIGNATURE", "ARTIFACT_LENGTH", "PUB_DATE"];
for (const name of required) {
  if (!process.env[name]) throw new Error(`Missing ${name}`);
}

const escapeXML = (value) => String(value)
  .replaceAll("&", "&amp;")
  .replaceAll('"', "&quot;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;");

const changelog = readFileSync(process.env.CHANGELOG, "utf8");
const heading = new RegExp(`^## ${process.env.VERSION.replaceAll(".", "\\.")}[^\\n]*$`, "m");
const start = changelog.search(heading);
let notes = "See the GitHub release notes for details.";
if (start >= 0) {
  const body = changelog.slice(start).split(/^## /m)[0].split("\n").slice(1).join("\n").trim();
  if (body) notes = body;
}
const description = notes
  .split("\n")
  .filter(Boolean)
  .map((line) => `<p>${escapeXML(line.replace(/^-\s*/, ""))}</p>`)
  .join("");

const item = `    <item>
      <title>${escapeXML(process.env.VERSION)}</title>
      <description><![CDATA[${description}]]></description>
      <pubDate>${escapeXML(process.env.PUB_DATE)}</pubDate>
      <sparkle:version>${escapeXML(process.env.BUILD)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXML(process.env.VERSION)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escapeXML(process.env.MIN_MACOS)}</sparkle:minimumSystemVersion>
      <enclosure url="${escapeXML(process.env.DOWNLOAD_URL)}" length="${escapeXML(process.env.ARTIFACT_LENGTH)}" type="application/octet-stream" sparkle:edSignature="${escapeXML(process.env.ED_SIGNATURE)}" />
    </item>`;

let xml = readFileSync(process.env.APPCAST, "utf8");
const existing = new RegExp(`\\s*<item>[\\s\\S]*?<sparkle:shortVersionString>${process.env.VERSION.replaceAll(".", "\\.")}</sparkle:shortVersionString>[\\s\\S]*?</item>`, "m");
xml = xml.replace(existing, "");
xml = xml.replace(/(\s*<language>[^<]+<\/language>)/, `$1\n${item}`);
writeFileSync(process.env.APPCAST, xml.endsWith("\n") ? xml : `${xml}\n`);
