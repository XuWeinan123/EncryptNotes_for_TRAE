#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const args = new Set(process.argv.slice(2));
const apply = args.has("--apply");
const container =
  process.env.SEAL_NOTE_VAULT_DIR ||
  path.join(
    process.env.HOME,
    "Library",
    "Mobile Documents",
    "iCloud~com~xuweinan~sealnote",
    "Documents"
  );

const indexPath = path.join(container, "notes.json");
const legacyNotesDir = path.join(container, "notes");
const trashDir = path.join(container, "trash");
const conflictsDir = path.join(container, "conflicts");
const metaDir = path.join(container, ".meta");

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function parseMarkdown(content) {
  if (!content.startsWith("---\n")) {
    throw new Error("missing frontmatter");
  }
  const end = content.indexOf("\n---", 4);
  if (end === -1) {
    throw new Error("missing frontmatter end");
  }
  let bodyStart = end + "\n---".length;
  if (content[bodyStart] === "\n") bodyStart += 1;
  if (content[bodyStart] === "\n") bodyStart += 1;

  const frontmatter = content.slice(4, end);
  const values = {};
  for (const line of frontmatter.split("\n")) {
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    }
    values[key] = value;
  }

  return {
    noteId: values.note_id,
    title: values.title,
    body: content.slice(bodyStart)
  };
}

function stripHeadingMarker(line) {
  const match = /^(#{1,6})\s+(.+)$/.exec(line);
  return match ? match[2].trim() : line;
}

function stripWrappingPunctuation(value) {
  const pairs = [
    ['"', '"'],
    ["'", "'"],
    ["`", "`"],
    ["“", "”"],
    ["‘", "’"],
    ["《", "》"],
    ["「", "」"],
    ["『", "』"]
  ];
  let result = value.trim();
  let changed = true;
  while (changed && result.length >= 2) {
    changed = false;
    for (const [open, close] of pairs) {
      if (result.startsWith(open) && result.endsWith(close)) {
        result = result.slice(open.length, -close.length).trim();
        changed = true;
        break;
      }
    }
  }
  return result;
}

const generatedTitleMaxLength = 20;

function isMarkdownHeading(line) {
  return /^#{1,6}\s+\S/.test(line.trim());
}

function sanitizeTitle(title, emptyTitle = "（空笔记）", limitsLength = false) {
  const firstLine = (title || "")
    .split(/\r?\n/)
    .find((line) => line.trim().length > 0) || "";
  let cleaned = stripHeadingMarker(firstLine.trim());
  cleaned = stripWrappingPunctuation(cleaned);
  cleaned = stripHeadingMarker(cleaned);
  cleaned = cleaned
    .replace(/[\/\\:?%*|"<>]/g, "-")
    .replace(/[\r\n\t\0-\x1F\x7F]/g, "-")
    .replace(/\s+/g, " ")
    .replace(/-+/g, "-")
    .replace(/^[ .-]+|[ .-]+$/g, "");

  if (!cleaned) cleaned = emptyTitle;
  if (limitsLength && [...cleaned].length > generatedTitleMaxLength) {
    cleaned = [...cleaned].slice(0, generatedTitleMaxLength).join("").replace(/^[ .-]+|[ .-]+$/g, "");
  }
  return cleaned || emptyTitle;
}

function titleFromOldFileName(fileName, noteId) {
  const stem = fileName.endsWith(".md") ? fileName.slice(0, -3) : fileName;
  const suffix = `-${noteId}`;
  return stem.endsWith(suffix) ? stem.slice(0, -suffix.length) : stem.replace(/（\d+）$/, "");
}

function titleForEntry(entry, markdown) {
  if (markdown.body.trimStart().startsWith("snenc:v1:")) {
    return {
      title: markdown.title || titleFromOldFileName(entry.file_name, entry.note_id),
      limitsLength: true
    };
  }
  const firstLine = markdown.body
    .trim()
    .split(/\r?\n/)
    .find((line) => line.trim().length > 0);
  return {
    title: firstLine || markdown.title || titleFromOldFileName(entry.file_name, entry.note_id),
    limitsLength: !firstLine || !isMarkdownHeading(firstLine)
  };
}

function fileNameForTitle(title, limitsLength = true) {
  return `${sanitizeTitle(title, "（空笔记）", limitsLength)}.md`;
}

function pathForEntry(entry) {
  if (entry.location === "trash") {
    return path.join(trashDir, entry.file_name);
  }
  const rootPath = path.join(container, entry.file_name);
  if (fs.existsSync(rootPath)) return rootPath;
  return path.join(legacyNotesDir, entry.file_name);
}

function uniqueFileName(preferred, reserved) {
  const parsed = path.parse(preferred);
  let candidate = preferred;
  let suffix = 2;
  while (reserved.has(candidate)) {
    candidate = `${parsed.name}（${suffix}）${parsed.ext}`;
    suffix += 1;
  }
  reserved.add(candidate);
  return candidate;
}

function listMarkdown(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((name) => name.endsWith(".md"))
    .map((name) => path.join(dir, name));
}

function copyBackup(src, backupDir) {
  if (!fs.existsSync(src)) return;
  const rel = path.relative(container, src);
  const dst = path.join(backupDir, rel.startsWith("..") ? path.basename(src) : rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
}

if (!fs.existsSync(indexPath)) {
  console.error(`Index not found: ${indexPath}`);
  process.exit(1);
}

const index = JSON.parse(fs.readFileSync(indexPath, "utf8"));
const entries = Array.isArray(index.entries) ? index.entries : [];
const activeEntries = entries.filter((entry) => entry.location === "notes");
const activeSources = new Set(activeEntries.map((entry) => pathForEntry(entry)));
const reserved = new Set(
  listMarkdown(container)
    .filter((file) => !activeSources.has(file))
    .map((file) => path.basename(file))
);
const changes = [];
const missing = [];
const parseFailures = [];
const conflictMoves = [];

for (const entry of activeEntries) {
  const src = pathForEntry(entry);
  if (!fs.existsSync(src)) {
    missing.push(entry);
    continue;
  }

  let markdown;
  try {
    markdown = parseMarkdown(fs.readFileSync(src, "utf8"));
  } catch (error) {
    parseFailures.push({ entry, error: error.message });
    reserved.add(entry.file_name);
    continue;
  }

  const titleInfo = titleForEntry(entry, markdown);
  const preferred = fileNameForTitle(titleInfo.title, titleInfo.limitsLength);
  const targetName = uniqueFileName(preferred, reserved);
  const dst = path.join(container, targetName);
  if (src !== dst || entry.file_name !== targetName) {
    changes.push({ entry, from: src, to: dst, targetName });
  }
}

for (const file of listMarkdown(container)) {
  if (/-conflict-\d+\.md$/.test(path.basename(file))) {
    conflictMoves.push({
      from: file,
      to: path.join(conflictsDir, path.basename(file))
    });
  }
}

console.log(`${apply ? "APPLY" : "DRY RUN"} Seal Note filename migration`);
console.log(`Vault: ${container}`);
console.log(`Active renames/moves: ${changes.length}`);
for (const change of changes) {
  console.log(`- ${path.relative(container, change.from)} -> ${path.relative(container, change.to)}`);
}
console.log(`Missing indexed active files to remove: ${missing.length}`);
for (const entry of missing) {
  console.log(`- ${entry.note_id}: ${entry.file_name}`);
}
console.log(`Root conflict files to move: ${conflictMoves.length}`);
for (const move of conflictMoves) {
  console.log(`- ${path.relative(container, move.from)} -> ${path.relative(container, move.to)}`);
}
if (parseFailures.length) {
  console.log(`Parse failures kept unchanged: ${parseFailures.length}`);
  for (const item of parseFailures) {
    console.log(`- ${item.entry.note_id}: ${item.entry.file_name} (${item.error})`);
  }
}

if (!apply) {
  process.exit(parseFailures.length ? 2 : 0);
}

const runDir = path.join(metaDir, `filename-migration-${timestamp()}`);
const backupDir = path.join(runDir, "backup");
fs.mkdirSync(backupDir, { recursive: true });
copyBackup(indexPath, backupDir);
for (const change of changes) copyBackup(change.from, backupDir);
for (const move of conflictMoves) copyBackup(move.from, backupDir);

for (const change of changes) {
  fs.mkdirSync(path.dirname(change.to), { recursive: true });
  fs.renameSync(change.from, change.to);
  change.entry.file_name = change.targetName;
}

for (const move of conflictMoves) {
  fs.mkdirSync(path.dirname(move.to), { recursive: true });
  if (!fs.existsSync(move.to)) {
    fs.renameSync(move.from, move.to);
  }
}

if (missing.length) {
  const missingIds = new Set(missing.map((entry) => entry.note_id));
  index.entries = entries.filter((entry) => !missingIds.has(entry.note_id));
}

const tempIndex = `${indexPath}.tmp-${process.pid}`;
fs.writeFileSync(tempIndex, `${JSON.stringify(index, null, 2)}\n`, "utf8");
fs.renameSync(tempIndex, indexPath);

console.log(`Backup: ${backupDir}`);
console.log(`Done.`);
