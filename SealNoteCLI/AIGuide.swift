import Foundation

enum SealNoteAIGuide {
    static let markdown = """
    # Seal Note CLI Guide

    This document is the authoritative usage guide for the installed `sealnote`
    binary. Follow it instead of assuming undocumented commands or editing Seal
    Note's files directly.

    - CLI protocol version: 1
    - Service-command output format: versioned JSON
    - Scope: plain notes only
    - Transport: authenticated localhost connection to the running Seal Note app

    ## Discoverability

    ```bash
    sealnote --help
    sealnote guide
    ```

    `help` prints a short command summary. `guide` prints this complete Markdown
    document. Both commands work without launching Seal Note. All commands below
    require Seal Note to be running with command-line access enabled in Settings
    > Advanced.

    ## Commands

    ```text
    sealnote status
    sealnote list [--limit N] [--offset N]
    sealnote search <query> [--tag <tag>] [--limit N] [--offset N]
    sealnote get <note-id> [--body-only]
    sealnote create [--allow-empty] < body.md
    sealnote update <note-id> --if-revision <revision> [--allow-empty] < body.md
    sealnote trash <note-id> --if-revision <revision>
    ```

    ### `status`

    Check service availability before doing other work. The result reports the
    app version and active storage type.

    ```bash
    sealnote status
    ```

    ### `list`

    List note metadata in stable newest-first order. Bodies are omitted. The
    default page size is 50, the maximum is 200, and the default offset is 0.

    ```bash
    sealnote list --limit 50 --offset 0
    ```

    If `result.pagination.has_more` is `true`, request the next page by adding
    the returned `limit` to the returned `offset`.

    ### `search`

    Search titles and bodies case-insensitively. `--tag` accepts either `work`
    or `#work`. Search results omit bodies; use `get` for the selected note.

    ```bash
    sealnote search 'project' --tag '#work' --limit 20
    ```

    ### `get`

    Read one note, including its body and current revision.

    ```bash
    sealnote get <note-id>
    sealnote get <note-id> --body-only
    ```

    `--body-only` writes the raw body to stdout instead of a JSON envelope.

    ### `create`

    Create a plain note. The body is read only from stdin so note contents do not
    need to appear in shell history.

    ```bash
    printf '%s' 'New note body #work' | sealnote create
    sealnote create < body.md
    ```

    Empty or whitespace-only bodies are rejected unless `--allow-empty` is used.
    Input must be valid UTF-8 and no larger than 5 MiB.

    ### `update`

    Replace a note's entire body. Always call `get` immediately before updating
    and pass its latest `revision` through `--if-revision`.

    ```bash
    printf '%s' 'Complete replacement body' | \\
      sealnote update <note-id> --if-revision <revision>
    ```

    This is a full-body replacement, not a patch or append operation. Do not
    retry a `revision_conflict` with the old revision: read the note again,
    reconcile the latest body with the intended change, then submit once using
    the new revision. Close the note's Seal Note window before updating it.

    ### `trash`

    Move a note to Seal Note's trash. Read it immediately beforehand and pass
    the latest revision.

    ```bash
    sealnote trash <note-id> --if-revision <revision>
    ```

    Close the note's Seal Note window first. There are no CLI commands for
    restoring notes, emptying trash, or permanently deleting notes.

    ## JSON contract

    Successful service commands write JSON to stdout:

    ```json
    {
      "api_version": 1,
      "ok": true,
      "request_id": "...",
      "result": {}
    }
    ```

    Failed service commands write JSON to stderr:

    ```json
    {
      "api_version": 1,
      "error": {
        "code": "revision_conflict",
        "message": "The note changed. Read it again before updating."
      },
      "ok": false,
      "request_id": "..."
    }
    ```

    A note object has these fields:

    ```json
    {
      "id": "note identifier",
      "title": "derived display title",
      "created_at": "ISO-8601 timestamp",
      "updated_at": "ISO-8601 timestamp",
      "revision": "opaque concurrency token",
      "is_encrypted": false,
      "body": "present only for get/create/update"
    }
    ```

    Treat `id` and `revision` as opaque strings. Do not construct or alter them.

    ## Exit statuses and recovery

    - `0`: success
    - `1`: internal or unclassified failure; report the error
    - `2`: invalid arguments, empty body, or incompatible protocol; correct the request
    - `3`: service unavailable; open Seal Note and enable CLI access
    - `4`: authentication or permission failure; do not bypass it
    - `5`: note not found; search or list again
    - `6`: revision conflict or note window open; re-read or ask the user to close it

    Error codes may include `invalid_arguments`, `service_unavailable`,
    `authentication_failed`, `unsupported_version`, `permission_denied`,
    `key_unavailable`, `not_found`, `revision_conflict`, `note_open`,
    `empty_body`, and `internal_error`.

    ## Security and behavioral rules for AI agents

    1. Use only documented CLI commands. Never edit Markdown files, `index.json`,
       App Group endpoint files, session tokens, or the vault directly.
    2. Encrypted notes are intentionally invisible to the CLI. Do not infer their
       titles, identifiers, count, or contents, and do not attempt to bypass this.
    3. Preserve the complete existing body unless the user explicitly asks to
       replace or remove content. `update` replaces the whole body.
    4. Read the latest revision immediately before every `update` or `trash`.
    5. Ask for confirmation before destructive or broad operations when the
       user's instruction does not already authorize them.
    6. Do not place sensitive note bodies directly in command arguments. Supply
       bodies through stdin.

    ## Recommended agent workflow

    1. Run `sealnote guide` when CLI behavior is unknown.
    2. Run `sealnote status` and stop if the service is unavailable.
    3. Use `search` or paginated `list` to identify candidate notes.
    4. Use `get` to read the selected note and obtain its latest revision.
    5. Make the smallest user-authorized change while preserving unrelated text.
    6. Use `update --if-revision` once, then verify with another `get`.
    7. On a conflict, re-read and reconcile; never overwrite blindly.
    """
}
