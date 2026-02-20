# ============= _QuickNotes.ps1 — BildsyPS Quick Notes Plugin =============
# Lightweight note-taking via intents. Notes are stored as JSON in the
# plugin config directory and searchable via intent or direct function call.
#
# Enable with: Enable-BildsyPSPlugin 'QuickNotes'
# Configure:   Set-PluginConfig -Plugin QuickNotes -Key max_notes -Value 200

$PluginInfo = @{
    Version          = '1.0.0'
    Author           = 'BildsyPS'
    Description      = 'Quick note-taking — add, list, search, and delete notes via intents'
    MinBildsyPSVersion = '0.9.0'
}

$PluginCategories = @{
    'notes' = @{
        Name        = 'Quick Notes'
        Description = 'Capture and retrieve notes'
    }
}

$PluginConfig = @{
    'max_notes' = @{
        Default     = 100
        Description = 'Maximum number of notes to keep (oldest are pruned)'
    }
    'notes_file' = @{
        Default     = ''
        Description = 'Custom path for the notes JSON file (leave empty for default)'
    }
}

$PluginMetadata = @{
    'note_add' = @{
        Category    = 'notes'
        Description = 'Add a new quick note'
        Parameters  = @(
            @{ Name = 'text'; Required = $true; Description = 'Note content' }
            @{ Name = 'tag'; Required = $false; Description = 'Optional tag for categorization' }
        )
    }
    'note_list' = @{
        Category    = 'notes'
        Description = 'List recent notes'
        Parameters  = @(
            @{ Name = 'count'; Required = $false; Description = 'Number of notes to show (default: 10)' }
            @{ Name = 'tag'; Required = $false; Description = 'Filter by tag' }
        )
    }
    'note_search' = @{
        Category    = 'notes'
        Description = 'Search notes by keyword'
        Parameters  = @(
            @{ Name = 'query'; Required = $true; Description = 'Search term' }
        )
    }
    'note_delete' = @{
        Category    = 'notes'
        Description = 'Delete a note by its ID'
        Parameters  = @(
            @{ Name = 'id'; Required = $true; Description = 'Note ID (shown in note_list)' }
        )
        Safety = 'RequiresConfirmation'
    }
}

# ── Internal helpers (not exported as PluginFunctions since they are private) ──

function Get-NotesFilePath {
    $cfg = $global:PluginSettings['QuickNotes']
    $custom = if ($cfg -and $cfg['notes_file']) { $cfg['notes_file'] } else { '' }
    if ($custom) { return $custom }
    $dir = $global:PluginConfigPath
    if (-not $dir) { $dir = "$PSScriptRoot\Config" }
    return (Join-Path $dir 'QuickNotes-data.json')
}

function Read-Notes {
    $path = Get-NotesFilePath
    if (-not (Test-Path $path)) { return @() }
    try {
        $raw = Get-Content $path -Raw | ConvertFrom-Json
        return @($raw)
    }
    catch { return @() }
}

function Save-Notes {
    param($Notes)
    $path = Get-NotesFilePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Notes | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
}

$PluginIntents = @{
    'note_add' = {
        param($text, $tag)
        if (-not $text) {
            return @{ Success = $false; Output = "Error: 'text' parameter is required."; Error = $true }
        }

        $notes = @(Read-Notes)
        $maxId = 0
        foreach ($n in $notes) {
            if ($n.id -and $n.id -gt $maxId) { $maxId = $n.id }
        }

        $newNote = @{
            id        = $maxId + 1
            text      = $text
            tag       = if ($tag) { $tag } else { '' }
            created   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $notes += $newNote

        # Prune to max
        $cfg = $global:PluginSettings['QuickNotes']
        $maxNotes = if ($cfg -and $cfg['max_notes']) { [int]$cfg['max_notes'] } else { 100 }
        if ($notes.Count -gt $maxNotes) {
            $notes = @($notes | Select-Object -Last $maxNotes)
        }

        Save-Notes $notes

        $tagStr = if ($tag) { " [#$tag]" } else { '' }
        @{ Success = $true; Output = "Note #$($newNote.id) added$tagStr" }
    }

    'note_list' = {
        param($count, $tag)
        $notes = @(Read-Notes)
        if ($notes.Count -eq 0) {
            return @{ Success = $true; Output = 'No notes yet. Add one with note_add.' }
        }

        # Filter by tag if specified
        if ($tag) {
            $notes = @($notes | Where-Object { $_.tag -eq $tag })
            if ($notes.Count -eq 0) {
                return @{ Success = $true; Output = "No notes with tag '#$tag'." }
            }
        }

        $limit = if ($count) { [int]$count } else { 10 }
        $recent = @($notes | Select-Object -Last $limit)
        [array]::Reverse($recent)

        $lines = @("$($recent.Count) of $($notes.Count) note(s):")
        foreach ($n in $recent) {
            $tagStr = if ($n.tag) { " [#$($n.tag)]" } else { '' }
            $lines += "  #$($n.id) ($($n.created))$tagStr — $($n.text)"
        }

        @{ Success = $true; Output = ($lines -join "`n") }
    }

    'note_search' = {
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: 'query' parameter is required."; Error = $true }
        }

        $notes = @(Read-Notes)
        $found = @($notes | Where-Object { $_.text -like "*$query*" -or $_.tag -like "*$query*" })

        if ($found.Count -eq 0) {
            return @{ Success = $true; Output = "No notes matching '$query'." }
        }

        $lines = @("$($found.Count) match(es) for '$query':")
        foreach ($n in $found) {
            $tagStr = if ($n.tag) { " [#$($n.tag)]" } else { '' }
            $lines += "  #$($n.id) ($($n.created))$tagStr — $($n.text)"
        }

        @{ Success = $true; Output = ($lines -join "`n") }
    }

    'note_delete' = {
        param($id)
        if (-not $id) {
            return @{ Success = $false; Output = "Error: 'id' parameter is required."; Error = $true }
        }

        $notes = @(Read-Notes)
        $targetId = [int]$id
        $target = $notes | Where-Object { $_.id -eq $targetId }

        if (-not $target) {
            return @{ Success = $false; Output = "Note #$id not found."; Error = $true }
        }

        $notes = @($notes | Where-Object { $_.id -ne $targetId })
        Save-Notes $notes

        @{ Success = $true; Output = "Deleted note #$id." }
    }
}

$PluginFunctions = @{
    'Format-NoteEntry' = {
        param($Note)
        $tagStr = if ($Note.tag) { " [#$($Note.tag)]" } else { '' }
        "#$($Note.id) ($($Note.created))$tagStr — $($Note.text)"
    }
    'Get-AllNotes' = {
        return @(Read-Notes)
    }
}

$PluginHooks = @{
    OnLoad = {
        # Ensure the notes file path is resolvable
        $path = Get-NotesFilePath
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

$PluginTests = @{
    'add and retrieve a note' = {
        $oldNotes = @(Read-Notes)
        try {
            # Add
            $r = & $global:IntentAliases['note_add'] 'Test note from self-test' 'test'
            if (-not $r.Success) { return @{ Success = $false; Output = "Add failed: $($r.Output)" } }

            # Verify it exists
            $notes = @(Read-Notes)
            $found = $notes | Where-Object { $_.text -eq 'Test note from self-test' }
            if (-not $found) { return @{ Success = $false; Output = 'Note not found after add' } }

            # Clean up: delete the test note
            $notes = @($notes | Where-Object { $_.text -ne 'Test note from self-test' })
            Save-Notes $notes

            @{ Success = $true; Output = 'Add/retrieve/cleanup cycle passed' }
        }
        catch {
            # Restore on error
            Save-Notes $oldNotes
            @{ Success = $false; Output = "Error: $($_.Exception.Message)" }
        }
    }
    'search finds matching notes' = {
        $oldNotes = @(Read-Notes)
        try {
            & $global:IntentAliases['note_add'] 'Unique-test-token-xyz' 'selftest' | Out-Null
            $r = & $global:IntentAliases['note_search'] 'Unique-test-token-xyz'

            # Clean up
            $notes = @(Read-Notes)
            $notes = @($notes | Where-Object { $_.text -ne 'Unique-test-token-xyz' })
            Save-Notes $notes

            $found = $r.Output -like '*1 match*'
            @{ Success = $found; Output = $r.Output }
        }
        catch {
            Save-Notes $oldNotes
            @{ Success = $false; Output = "Error: $($_.Exception.Message)" }
        }
    }
    'delete removes note' = {
        $oldNotes = @(Read-Notes)
        try {
            & $global:IntentAliases['note_add'] 'Delete-me-test-note' | Out-Null
            $notes = @(Read-Notes)
            $testNote = $notes | Where-Object { $_.text -eq 'Delete-me-test-note' } | Select-Object -Last 1

            if (-not $testNote) {
                Save-Notes $oldNotes
                return @{ Success = $false; Output = 'Could not find test note to delete' }
            }

            $r = & $global:IntentAliases['note_delete'] $testNote.id
            $afterDelete = @(Read-Notes)
            $stillExists = $afterDelete | Where-Object { $_.text -eq 'Delete-me-test-note' }

            # Restore original state
            Save-Notes $oldNotes

            @{ Success = ($r.Success -and -not $stillExists); Output = $r.Output }
        }
        catch {
            Save-Notes $oldNotes
            @{ Success = $false; Output = "Error: $($_.Exception.Message)" }
        }
    }
}
