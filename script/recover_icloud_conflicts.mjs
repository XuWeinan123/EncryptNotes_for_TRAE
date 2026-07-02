#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const args = new Set(process.argv.slice(2));
const apply = args.has("--apply");
const verbose = args.has("--verbose");
const recoverAllUnique = args.has("--recover-all-unique");
const base = process.env.BKW_VAULT_DIR
  || path.join(process.env.HOME, "Library/Mobile Documents/com~apple~CloudDocs/别看我");
const rootNotesDir = base;
const legacyNotesDir = path.join(base, "notes");
const notesDir = fs.existsSync(legacyNotesDir) ? legacyNotesDir : rootNotesDir;
const trashDir = path.join(base, "trash");
const metaDir = path.join(base, ".meta");
const indexPath = path.join(base, "notes.json");
const runId = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z");
const archiveDir = path.join(metaDir, `conflict-recovery-${runId}`);

function readFileWithTimeout(file, timeout = 4000) {
  return fs.readFileSync(file, "utf8");
}

function copyFileWithTimeout(src, dst, timeout = 5000) {
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  execFileSync("/bin/cp", ["-p", src, dst], { timeout });
}

function parseMarkdown(content) {
  if (!content.startsWith("---\n")) throw new Error("missing frontmatter");
  const end = content.indexOf("\n---", 4);
  if (end === -1) throw new Error("missing frontmatter end");
  let bodyStart = end + "\n---".length;
  if (content[bodyStart] === "\n") bodyStart += 1;
  if (content[bodyStart] === "\n") bodyStart += 1;
  const fm = content.slice(4, end);
  const body = content.slice(bodyStart);
  const values = {};
  for (const line of fm.split("\n")) {
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1);
    values[key] = value;
  }
  if (!values.note_id || !values.created_at || !values.updated_at) {
    throw new Error("incomplete frontmatter");
  }
  return {
    noteId: values.note_id,
    createdAt: values.created_at,
    updatedAt: values.updated_at,
    body,
    encrypted: body.startsWith("bkwenc:v1:")
  };
}

function renderMarkdown(note) {
  const frontmatter = [
    "---",
    `note_id: "${note.noteId}"`,
    `created_at: "${note.createdAt}"`,
    `updated_at: "${note.updatedAt}"`,
    "---"
  ].join("\n");
  return note.body ? `${frontmatter}\n\n${note.body}` : `${frontmatter}\n`;
}

function sha(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function uniqueDestination(dir, fileName) {
  let candidate = path.join(dir, fileName);
  if (!fs.existsSync(candidate)) return candidate;
  const parsed = path.parse(fileName);
  let idx = 2;
  while (true) {
    candidate = path.join(dir, `${parsed.name}-${idx}${parsed.ext}`);
    if (!fs.existsSync(candidate)) return candidate;
    idx += 1;
  }
}

function moveToArchive(src, category) {
  const dstDir = path.join(archiveDir, category);
  fs.mkdirSync(dstDir, { recursive: true });
  const dst = uniqueDestination(dstDir, path.basename(src));
  fs.renameSync(src, dst);
  return dst;
}

function backupVault(files) {
  const backupDir = path.join(archiveDir, "backup");
  fs.mkdirSync(backupDir, { recursive: true });
  for (const file of [indexPath, path.join(base, "vault.json")]) {
    if (fs.existsSync(file)) copyFileWithTimeout(file, path.join(backupDir, path.basename(file)));
  }
  for (const file of files) {
    const rel = path.relative(base, file);
    copyFileWithTimeout(file, path.join(backupDir, rel));
  }
  if (fs.existsSync(trashDir)) {
    for (const name of fs.readdirSync(trashDir).filter((name) => name.endsWith(".md"))) {
      const file = path.join(trashDir, name);
      copyFileWithTimeout(file, path.join(backupDir, "trash", name));
    }
  }
  return backupDir;
}

if (!fs.existsSync(notesDir)) {
  console.error(`notes directory not found: ${notesDir}`);
  process.exit(2);
}
if (!fs.existsSync(indexPath)) {
  console.error(`index not found: ${indexPath}`);
  process.exit(2);
}

const index = JSON.parse(fs.readFileSync(indexPath, "utf8"));
const entries = Array.isArray(index.entries) ? index.entries : [];
const entryByFile = new Map(entries.map((entry) => [entry.file_name, entry]));
const entryById = new Map(entries.map((entry) => [entry.note_id, entry]));
const files = fs.readdirSync(notesDir)
  .filter((name) => name.endsWith(".md"))
  .map((name) => path.join(notesDir, name));

const parsedFiles = [];
const skipped = [];
for (const file of files) {
  try {
    if (verbose) console.error(`reading ${path.basename(file)}`);
    const content = readFileWithTimeout(file);
    const note = parseMarkdown(content);
    parsedFiles.push({
      file,
      fileName: path.basename(file),
      isConflict: path.basename(file).includes("-conflict-"),
      note,
      hash: sha(note.body)
    });
  } catch (error) {
    skipped.push({ file, reason: error.message });
  }
}

const activeHashes = new Set();
for (const item of parsedFiles) {
  const entry = entryByFile.get(item.fileName);
  if (entry?.location === "notes") activeHashes.add(item.hash);
}

const groups = new Map();
for (const item of parsedFiles) {
  if (!groups.has(item.note.noteId)) groups.set(item.note.noteId, []);
  groups.get(item.note.noteId).push(item);
}

const actions = [];
const recoveredEntries = [];
const archivedSources = [];
for (const [noteId, group] of groups) {
  const indexed = group.find((item) => entryByFile.get(item.fileName)?.location === "notes");
  const canonical = indexed
    || group.find((item) => item.fileName === `${noteId}.md` && !item.isConflict)
    || group.toSorted((a, b) => b.note.updatedAt.localeCompare(a.note.updatedAt))[0];

  const candidates = group
    .filter((item) => (item.isConflict || !entryByFile.has(item.fileName)) && item.file !== canonical.file)
    .toSorted((a, b) => b.note.updatedAt.localeCompare(a.note.updatedAt));
  const recoveredHashes = new Map();
  const recoverable = candidates.filter((item) => item.hash !== canonical.hash && !activeHashes.has(item.hash));
  const selectedRecoveries = recoverAllUnique
    ? recoverable.filter((item) => {
        if (recoveredHashes.has(item.hash)) return false;
        recoveredHashes.set(item.hash, true);
        return true;
      })
    : recoverable.slice(0, 1);
  const selectedFiles = new Set(selectedRecoveries.map((item) => item.file));
  const selectedByHash = new Map(selectedRecoveries.map((item) => [item.hash, item.fileName]));

  for (const item of candidates) {
    if (!selectedFiles.has(item.file)) {
      actions.push({
        type: item.hash === canonical.hash || activeHashes.has(item.hash) || selectedByHash.has(item.hash)
          ? "archive_duplicate"
          : "archive_superseded_conflict",
        source: item.file,
        noteId,
        duplicateOf: selectedByHash.get(item.hash) || canonical.fileName
      });
      continue;
    }

    const newId = crypto.randomUUID().toUpperCase();
    const newFileName = `${newId}.md`;
    const newFile = path.join(notesDir, newFileName);
    const recoveredNote = {
      ...item.note,
      noteId: newId
    };
    const entry = {
      note_id: newId,
      file_name: newFileName,
      mode: item.note.encrypted ? "encrypted" : "plain",
      location: "notes"
    };

    actions.push({
      type: "recover_unique_conflict",
      source: item.file,
      noteId,
      recoveredFile: newFile,
      newNoteId: newId,
      updatedAt: item.note.updatedAt
    });
    recoveredEntries.push({ entry, note: recoveredNote, file: newFile });
    activeHashes.add(item.hash);
  }
}

const unindexedNormalFiles = parsedFiles.filter((item) => !item.isConflict && !entryByFile.has(item.fileName));
for (const item of unindexedNormalFiles) {
  if (entryById.has(item.note.noteId)) continue;
  const entry = {
    note_id: item.note.noteId,
    file_name: item.fileName,
    mode: item.note.encrypted ? "encrypted" : "plain",
    location: "notes"
  };
  actions.push({
    type: "add_unindexed_normal_file_to_index",
    source: item.file,
    noteId: item.note.noteId
  });
  recoveredEntries.push({ entry, note: null, file: null });
}

const summary = {
  mode: apply ? "apply" : "dry-run",
  base,
  notesDir,
  totalNoteFiles: files.length,
  parsedFiles: parsedFiles.length,
  skippedFiles: skipped.length,
  indexedEntries: entries.length,
  conflictFiles: parsedFiles.filter((item) => item.isConflict).length,
  actions: {
    recoverUniqueConflicts: actions.filter((action) => action.type === "recover_unique_conflict").length,
    archiveDuplicates: actions.filter((action) => action.type === "archive_duplicate").length,
    archiveSupersededConflicts: actions.filter((action) => action.type === "archive_superseded_conflict").length,
    addUnindexedNormalFiles: actions.filter((action) => action.type === "add_unindexed_normal_file_to_index").length
  },
  archiveDir: apply ? archiveDir : null
};

if (!apply) {
  console.log(JSON.stringify({ summary, skipped, sampleActions: actions.slice(0, 30) }, null, 2));
  process.exit(0);
}

fs.mkdirSync(archiveDir, { recursive: true });
const backupDir = backupVault(files);
for (const recovered of recoveredEntries) {
  if (recovered.note && recovered.file) {
    fs.writeFileSync(recovered.file, renderMarkdown(recovered.note), "utf8");
  }
  index.entries.push(recovered.entry);
}

for (const action of actions) {
  if (
    action.type !== "recover_unique_conflict"
    && action.type !== "archive_duplicate"
    && action.type !== "archive_superseded_conflict"
  ) continue;
  if (!fs.existsSync(action.source)) continue;
  const category = action.type === "recover_unique_conflict"
    ? "recovered-sources"
    : action.type === "archive_duplicate"
      ? "duplicates"
      : "superseded-conflicts";
  const dst = moveToArchive(action.source, category);
  archivedSources.push({ ...action, archivedTo: dst });
}

fs.writeFileSync(indexPath, JSON.stringify(index, null, 2) + "\n", "utf8");
const manifest = { summary: { ...summary, archiveDir, backupDir }, skipped, actions: archivedSources };
fs.writeFileSync(path.join(archiveDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n", "utf8");
console.log(JSON.stringify(manifest.summary, null, 2));
