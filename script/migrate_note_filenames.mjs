#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const apply = process.argv.includes("--apply");
const container =
  process.env.SEAL_NOTE_VAULT_DIR ||
  process.env.BKW_VAULT_DIR ||
  path.join(
    process.env.HOME,
    "Library",
    "Mobile Documents",
    "iCloud~com~biekanwo~EncryptNotes"
  );

const indexPath = path.join(container, "notes.json");
const notesDir = path.join(container, "notes");
const metaDir = path.join(container, "meta");

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function parseMarkdown(content) {
  if (!content.startsWith("---\n")) {
    return { frontmatter: "", body: content };
  }
  const end = content.indexOf("\n---\n", 4);
  if (end === -1) {
    return { frontmatter: "", body: content };
  }
  return {
    frontmatter: content.slice(4, end),
    body: content.slice(end + 5)
  };
}

function titleFromBody(body, encrypted) {
  if (encrypted || body.trimStart().startsWith("bkwenc:v1:")) {
    return "加密笔记";
  }
  const firstLine = body
    .trim()
    .split(/\r?\n/)
    .find((line) => line.trim().length > 0);
  return firstLine?.trim() || "空笔记";
}

function fileNameFor(noteId, body, encrypted) {
  let cleaned = titleFromBody(body, encrypted)
    .replace(/[\/\\:?%*|"<>]/g, "-")
    .replace(/[\r\n\t\0-\x1F\x7F]/g, "-")
    .replace(/\s+/g, " ")
    .replace(/-+/g, "-")
    .replace(/^[ .-]+|[ .-]+$/g, "");

  if (!cleaned) {
    cleaned = "空笔记";
  }
  if ([...cleaned].length > 72) {
    cleaned = [...cleaned].slice(0, 72).join("").replace(/^[ .-]+|[ .-]+$/g, "");
  }
  return `${cleaned}-${noteId}.md`;
}

function copyIfExists(src, dst) {
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.cpSync(src, dst, { recursive: true, force: true, preserveTimestamps: true });
}

if (!fs.existsSync(indexPath)) {
  console.error(`Index not found: ${indexPath}`);
  process.exit(1);
}

const index = JSON.parse(fs.readFileSync(indexPath, "utf8"));
const changes = [];
const skipped = [];

for (const entry of index.entries || []) {
  if (entry.location !== "notes") continue;
  if (!entry.file_name?.endsWith(".md")) continue;

  const src = path.join(notesDir, entry.file_name);
  if (!fs.existsSync(src)) {
    skipped.push({ noteId: entry.note_id, reason: "missing source", fileName: entry.file_name });
    continue;
  }

  const content = fs.readFileSync(src, "utf8");
  const { body } = parseMarkdown(content);
  const targetFileName = fileNameFor(entry.note_id, body, entry.mode === "encrypted");
  const dst = path.join(notesDir, targetFileName);

  if (entry.file_name === targetFileName) continue;

  if (fs.existsSync(dst)) {
    skipped.push({ noteId: entry.note_id, reason: "target exists", fileName: targetFileName });
    continue;
  }

  changes.push({
    noteId: entry.note_id,
    from: entry.file_name,
    to: targetFileName,
    src,
    dst,
    entry
  });
}

console.log(`${apply ? "APPLY" : "DRY RUN"} filename migration`);
console.log(`Vault: ${container}`);
console.log(`Planned renames: ${changes.length}`);
for (const change of changes) {
  console.log(`- ${change.from} -> ${change.to}`);
}
if (skipped.length) {
  console.log(`Skipped: ${skipped.length}`);
  for (const item of skipped) {
    console.log(`- ${item.noteId}: ${item.reason} (${item.fileName})`);
  }
}

if (!apply || changes.length === 0) {
  process.exit(skipped.length ? 2 : 0);
}

const runDir = path.join(metaDir, `filename-migration-${timestamp()}`);
const backupDir = path.join(runDir, "backup");
fs.mkdirSync(backupDir, { recursive: true });
copyIfExists(indexPath, path.join(backupDir, "notes.json"));
copyIfExists(notesDir, path.join(backupDir, "notes"));

for (const change of changes) {
  fs.renameSync(change.src, change.dst);
  change.entry.file_name = change.to;
}

const tempIndex = `${indexPath}.tmp-${process.pid}`;
fs.writeFileSync(tempIndex, `${JSON.stringify(index, null, 2)}\n`, "utf8");
fs.renameSync(tempIndex, indexPath);

console.log(`Backup: ${backupDir}`);
console.log(`Renamed: ${changes.length}`);
