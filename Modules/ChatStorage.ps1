# ===== ChatStorage.ps1 =====
# SQLite-backed chat session storage with FTS5 full-text search
# Requires PowerShell 7+ and Microsoft.Data.Sqlite (loaded from Modules/lib/)

$global:ChatDbPath = "$global:BildsyPSHome\data\bildsyps.db"
$global:ChatDbReady = $false
if (-not $global:ChatLogsPath) { $global:ChatLogsPath = "$global:BildsyPSHome\logs\sessions" }

# ===== Assembly Loading =====
function Initialize-SqliteAssembly {
    # Load Microsoft.Data.Sqlite and dependencies from Modules/lib/
    if ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.Data.Sqlite' }) {
        return $true
    }
    $libDir = "$PSScriptRoot\lib"

    # Ensure native e_sqlite3.dll is next to managed DLLs (required for manual Add-Type loading)
    $nativeInLib = Join-Path $libDir "e_sqlite3.dll"
    if (-not (Test-Path $nativeInLib)) {
        $runtimeNative = Join-Path $libDir "runtimes\win-x64\native\e_sqlite3.dll"
        if (Test-Path $runtimeNative) {
            Copy-Item $runtimeNative $nativeInLib -Force -ErrorAction SilentlyContinue
        }
    }

    $dlls = @(
        'SQLitePCLRaw.core.dll',
        'SQLitePCLRaw.provider.e_sqlite3.dll',
        'SQLitePCLRaw.batteries_v2.dll',
        'Microsoft.Data.Sqlite.dll'
    )
    foreach ($dll in $dlls) {
        $path = Join-Path $libDir $dll
        if (-not (Test-Path $path)) {
            Write-Verbose "ChatStorage: Missing $dll in $libDir"
            return $false
        }
        try {
            Add-Type -Path $path -ErrorAction Stop
        }
        catch [System.Reflection.ReflectionTypeLoadException] {
            # Already loaded or type conflicts -- acceptable
        }
        catch {
            Write-Verbose "ChatStorage: Failed to load $dll -- $($_.Exception.Message)"
            return $false
        }
    }
    try {
        [SQLitePCL.Batteries_V2]::Init()
    }
    catch {
        # Already initialized
    }
    return $true
}

# ===== Connection Helper =====
function Get-ChatDbConnection {
    param([string]$DbPath = $global:ChatDbPath)
    $conn = [Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$DbPath")
    $conn.Open()
    # Enable WAL mode and foreign keys
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;"
    $cmd.ExecuteNonQuery() | Out-Null
    $cmd.Dispose()
    return $conn
}

# ===== Schema =====
function Initialize-ChatDatabase {
    <#
    .SYNOPSIS
    Create the SQLite database and tables if they do not exist.
    Runs JSON-to-SQLite migration on first use if old session files are found.
    #>
    if (-not (Initialize-SqliteAssembly)) {
        Write-Verbose "ChatStorage: SQLite assemblies not available. Database features disabled."
        return $false
    }

    # Ensure data directory exists
    $dataDir = Split-Path $global:ChatDbPath -Parent
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    $conn = Get-ChatDbConnection
    try {
        $cmd = $conn.CreateCommand()

        $cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS sessions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    provider      TEXT,
    model         TEXT,
    system_prompt TEXT,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
    message_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role        TEXT NOT NULL CHECK(role IN ('system','user','assistant')),
    content     TEXT NOT NULL,
    timestamp   TEXT NOT NULL DEFAULT (datetime('now')),
    token_est   INTEGER,
    embedding   BLOB
);

CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_name ON sessions(name);
"@
        $cmd.ExecuteNonQuery() | Out-Null

        # Create FTS5 virtual table if it does not exist
        $cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='messages_fts'"
        $ftsExists = $cmd.ExecuteScalar()
        if (-not $ftsExists) {
            $cmd.CommandText = @"
CREATE VIRTUAL TABLE messages_fts USING fts5(content, content=messages, content_rowid=id);

CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
END;

CREATE TRIGGER messages_au AFTER UPDATE OF content ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
    INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;
"@
            $cmd.ExecuteNonQuery() | Out-Null
        }

        $cmd.Dispose()
        $global:ChatDbReady = $true

        # Run migration if needed
        Import-JsonSessionsToDb -Connection $conn

        return $true
    }
    catch {
        Write-Host "ChatStorage: Database init failed -- $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

# ===== CRUD Functions =====

function Save-ChatToDb {
    <#
    .SYNOPSIS
    Save a chat session (name, messages, metadata) to the SQLite database.
    Creates a new session or updates an existing one by name.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [array]$Messages = @(),
        [string]$Provider,
        [string]$Model,
        [string]$SystemPrompt
    )

    if (-not $global:ChatDbReady) { return $null }

    $conn = Get-ChatDbConnection
    try {
        $tx = $conn.BeginTransaction()

        # Check if session exists
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id FROM sessions WHERE name = @name"
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@name", $Name)) | Out-Null
        $sessionId = $cmd.ExecuteScalar()

        if ($sessionId) {
            # Update existing session metadata
            $cmd.CommandText = "UPDATE sessions SET provider = @prov, model = @model, updated_at = datetime('now'), message_count = @count WHERE id = @id"
            $cmd.Parameters.Clear()
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@prov", $(if ($Provider) { $Provider } else { [DBNull]::Value }))) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@model", $(if ($Model) { $Model } else { [DBNull]::Value }))) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@count", $Messages.Count)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@id", $sessionId)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null

            # Delete old messages and re-insert (simplest approach for full overwrite)
            $cmd.CommandText = "DELETE FROM messages WHERE session_id = @sid"
            $cmd.Parameters.Clear()
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sid", $sessionId)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
        }
        else {
            # Insert new session
            $cmd.CommandText = "INSERT INTO sessions (name, provider, model, system_prompt, message_count) VALUES (@name, @prov, @model, @sys, @count)"
            $cmd.Parameters.Clear()
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@name", $Name)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@prov", $(if ($Provider) { $Provider } else { [DBNull]::Value }))) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@model", $(if ($Model) { $Model } else { [DBNull]::Value }))) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sys", $(if ($SystemPrompt) { $SystemPrompt } else { [DBNull]::Value }))) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@count", $Messages.Count)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null

            $cmd.CommandText = "SELECT last_insert_rowid()"
            $cmd.Parameters.Clear()
            $sessionId = $cmd.ExecuteScalar()
        }

        # Insert messages
        foreach ($msg in $Messages) {
            $role = $msg.role
            $content = if ($msg.content -is [array]) { ($msg.content | ConvertTo-Json -Depth 5 -Compress) } else { "$($msg.content)" }
            $tokenEst = [math]::Ceiling($content.Length / 4)

            $cmd.CommandText = "INSERT INTO messages (session_id, role, content, token_est) VALUES (@sid, @role, @content, @tokens)"
            $cmd.Parameters.Clear()
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sid", $sessionId)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@role", $role)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@content", $content)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@tokens", $tokenEst)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
        }

        $tx.Commit()
        $cmd.Dispose()
        return $sessionId
    }
    catch {
        Write-Host "ChatStorage: Save failed -- $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Get-ChatSessionsFromDb {
    <#
    .SYNOPSIS
    List all sessions from the database. Returns an array of session metadata.
    #>
    param(
        [int]$Limit = 50,
        [string]$NameFilter
    )

    if (-not $global:ChatDbReady) { return @() }

    $conn = Get-ChatDbConnection
    try {
        $cmd = $conn.CreateCommand()
        if ($NameFilter) {
            $cmd.CommandText = "SELECT id, name, provider, model, created_at, updated_at, message_count FROM sessions WHERE name LIKE @filter ORDER BY updated_at DESC LIMIT @limit"
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@filter", "%$NameFilter%")) | Out-Null
        }
        else {
            $cmd.CommandText = "SELECT id, name, provider, model, created_at, updated_at, message_count FROM sessions ORDER BY updated_at DESC LIMIT @limit"
        }
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@limit", $Limit)) | Out-Null

        $reader = $cmd.ExecuteReader()
        $sessions = @()
        while ($reader.Read()) {
            $sessions += @{
                Id           = $reader.GetInt64(0)
                Name         = $reader.GetString(1)
                Provider     = if ($reader.IsDBNull(2)) { $null } else { $reader.GetString(2) }
                Model        = if ($reader.IsDBNull(3)) { $null } else { $reader.GetString(3) }
                CreatedAt    = $reader.GetString(4)
                UpdatedAt    = $reader.GetString(5)
                MessageCount = $reader.GetInt64(6)
            }
        }
        $reader.Close()
        $cmd.Dispose()
        return $sessions
    }
    catch {
        Write-Host "ChatStorage: List sessions failed -- $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Resume-ChatFromDb {
    <#
    .SYNOPSIS
    Load session messages by name or ID. Returns a hashtable with session metadata and messages array.
    #>
    param(
        [string]$Name,
        [int64]$Id = 0
    )

    if (-not $global:ChatDbReady) { return $null }

    $conn = Get-ChatDbConnection
    try {
        $cmd = $conn.CreateCommand()

        # Resolve session
        if ($Id -gt 0) {
            $cmd.CommandText = "SELECT id, name, provider, model, system_prompt FROM sessions WHERE id = @id"
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@id", $Id)) | Out-Null
        }
        else {
            $cmd.CommandText = "SELECT id, name, provider, model, system_prompt FROM sessions WHERE name = @name"
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@name", $Name)) | Out-Null
        }

        $reader = $cmd.ExecuteReader()
        if (-not $reader.Read()) {
            $reader.Close()
            $cmd.Dispose()
            return $null
        }

        $session = @{
            Id          = $reader.GetInt64(0)
            Name        = $reader.GetString(1)
            Provider    = if ($reader.IsDBNull(2)) { $null } else { $reader.GetString(2) }
            Model       = if ($reader.IsDBNull(3)) { $null } else { $reader.GetString(3) }
            SystemPrompt = if ($reader.IsDBNull(4)) { $null } else { $reader.GetString(4) }
            Messages    = @()
        }
        $reader.Close()

        # Load messages
        $cmd.CommandText = "SELECT role, content FROM messages WHERE session_id = @sid ORDER BY id ASC"
        $cmd.Parameters.Clear()
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sid", $session.Id)) | Out-Null
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $session.Messages += @{
                role    = $reader.GetString(0)
                content = $reader.GetString(1)
            }
        }
        $reader.Close()
        $cmd.Dispose()
        return $session
    }
    catch {
        Write-Host "ChatStorage: Resume failed -- $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Remove-ChatSessionFromDb {
    <#
    .SYNOPSIS
    Delete a session and its messages by name.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $global:ChatDbReady) { return $false }

    $conn = Get-ChatDbConnection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM sessions WHERE name = @name"
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@name", $Name)) | Out-Null
        $rows = $cmd.ExecuteNonQuery()
        $cmd.Dispose()
        return ($rows -gt 0)
    }
    catch {
        Write-Host "ChatStorage: Delete failed -- $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Rename-ChatSessionInDb {
    <#
    .SYNOPSIS
    Rename a session in the database.
    #>
    param(
        [Parameter(Mandatory)][string]$OldName,
        [Parameter(Mandatory)][string]$NewName
    )

    if (-not $global:ChatDbReady) { return $false }

    $conn = Get-ChatDbConnection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE sessions SET name = @new, updated_at = datetime('now') WHERE name = @old"
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@old", $OldName)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@new", $NewName)) | Out-Null
        $rows = $cmd.ExecuteNonQuery()
        $cmd.Dispose()
        return ($rows -gt 0)
    }
    catch {
        Write-Host "ChatStorage: Rename failed -- $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Search-ChatFTS {
    <#
    .SYNOPSIS
    Full-text search across all chat messages using FTS5. Returns matched messages with session context.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [int]$Limit = 20
    )

    if (-not $global:ChatDbReady) { return @() }

    $conn = Get-ChatDbConnection
    try {
        $cmd = $conn.CreateCommand()
        # Use FTS5 MATCH with snippet for context
        $cmd.CommandText = @"
SELECT
    s.name AS session_name,
    m.role,
    snippet(messages_fts, 0, '>>>', '<<<', '...', 48) AS snippet,
    m.timestamp,
    s.id AS session_id
FROM messages_fts
JOIN messages m ON messages_fts.rowid = m.id
JOIN sessions s ON m.session_id = s.id
WHERE messages_fts MATCH @query
ORDER BY rank
LIMIT @limit
"@
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@query", $Query)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@limit", $Limit)) | Out-Null

        $reader = $cmd.ExecuteReader()
        $results = @()
        while ($reader.Read()) {
            $results += @{
                SessionName = $reader.GetString(0)
                Role        = $reader.GetString(1)
                Snippet     = $reader.GetString(2)
                Timestamp   = $reader.GetString(3)
                SessionId   = $reader.GetInt64(4)
            }
        }
        $reader.Close()
        $cmd.Dispose()
        return $results
    }
    catch {
        Write-Host "ChatStorage: Search failed -- $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Export-ChatSessionFromDb {
    <#
    .SYNOPSIS
    Export a session from the database to a markdown file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$OutputPath
    )

    $session = Resume-ChatFromDb -Name $Name
    if (-not $session) {
        Write-Host "Session '$Name' not found in database." -ForegroundColor Yellow
        return $null
    }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $global:ChatLogsPath "$Name.md"
    }

    $md = @("# Chat Session: $Name", "", "Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "")
    if ($session.Provider) { $md += "Provider: $($session.Provider)" }
    if ($session.Model) { $md += "Model: $($session.Model)" }
    $md += @("", "---", "")

    foreach ($msg in $session.Messages) {
        $label = switch ($msg.role) {
            'system'    { '**System**' }
            'user'      { '**You**' }
            'assistant' { '**AI**' }
            default     { "**$($msg.role)**" }
        }
        $md += "$label`n"
        $md += "$($msg.content)`n"
        $md += "---`n"
    }

    $md -join "`n" | Set-Content -Path $OutputPath -Encoding UTF8
    return $OutputPath
}

# ===== JSON Migration =====
function Import-JsonSessionsToDb {
    <#
    .SYNOPSIS
    One-time migration: import existing JSON session files into the SQLite database.
    #>
    param(
        [Microsoft.Data.Sqlite.SqliteConnection]$Connection
    )

    $logsPath = $global:ChatLogsPath
    $indexPath = Join-Path $logsPath "index.json"

    # Only migrate if index.json exists and DB has no sessions yet
    if (-not (Test-Path $indexPath)) { return }

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM sessions"
    $existingCount = $cmd.ExecuteScalar()
    if ($existingCount -gt 0) {
        $cmd.Dispose()
        return
    }

    try {
        $index = Get-Content $indexPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "ChatStorage: Failed to parse index.json for migration -- $($_.Exception.Message)" -ForegroundColor Yellow
        $cmd.Dispose()
        return
    }

    $migrated = 0
    $failed = 0

    foreach ($prop in $index.PSObject.Properties) {
        $sessionName = $prop.Name
        $meta = $prop.Value
        $filePath = Join-Path $logsPath $meta.file

        if (-not (Test-Path $filePath)) {
            $failed++
            continue
        }

        try {
            $sessionData = Get-Content $filePath -Raw | ConvertFrom-Json

            # Insert session
            $cmd.CommandText = "INSERT INTO sessions (name, provider, model, system_prompt, created_at, message_count) VALUES (@name, @prov, @model, @sys, @created, @count)"
            $cmd.Parameters.Clear()
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@name", $sessionName)) | Out-Null
            $prov = if ($sessionData.provider) { $sessionData.provider } else { [DBNull]::Value }
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@prov", $prov)) | Out-Null
            $model = if ($sessionData.model) { $sessionData.model } else { [DBNull]::Value }
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@model", $model)) | Out-Null
            $sys = if ($sessionData.system_prompt) { $sessionData.system_prompt } else { [DBNull]::Value }
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sys", $sys)) | Out-Null
            $created = if ($meta.saved) { $meta.saved } else { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@created", $created)) | Out-Null
            $msgCount = if ($sessionData.messages) { $sessionData.messages.Count } else { 0 }
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@count", $msgCount)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null

            $cmd.CommandText = "SELECT last_insert_rowid()"
            $cmd.Parameters.Clear()
            $sessionId = $cmd.ExecuteScalar()

            # Insert messages
            if ($sessionData.messages) {
                foreach ($msg in $sessionData.messages) {
                    $role = "$($msg.role)"
                    $content = "$($msg.content)"
                    if (-not $role -or -not $content) { continue }
                    $tokenEst = [math]::Ceiling($content.Length / 4)

                    $cmd.CommandText = "INSERT INTO messages (session_id, role, content, token_est) VALUES (@sid, @role, @content, @tokens)"
                    $cmd.Parameters.Clear()
                    $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sid", $sessionId)) | Out-Null
                    $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@role", $role)) | Out-Null
                    $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@content", $content)) | Out-Null
                    $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@tokens", $tokenEst)) | Out-Null
                    $cmd.ExecuteNonQuery() | Out-Null
                }
            }
            $migrated++
        }
        catch {
            Write-Verbose "ChatStorage: Failed to migrate session '$sessionName' -- $($_.Exception.Message)"
            $failed++
        }
    }

    $cmd.Dispose()

    # Rename old index
    if ($migrated -gt 0) {
        Rename-Item $indexPath "$indexPath.migrated" -Force -ErrorAction SilentlyContinue
        Write-Host "[ChatStorage] Migrated $migrated session(s) from JSON to SQLite." -ForegroundColor Cyan
        if ($failed -gt 0) {
            Write-Host "  $failed session(s) failed to migrate." -ForegroundColor Yellow
        }
    }
}

# ===== Initialize on load =====
$dbInitResult = Initialize-ChatDatabase
if ($dbInitResult) {
    Write-Verbose "ChatStorage loaded: SQLite database ready at $global:ChatDbPath"
}
else {
    Write-Verbose "ChatStorage: Database not available, JSON fallback will be used."
}
