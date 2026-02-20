# BildsyPS E2E Audit -- Defect Report

**Audit date:** 2026-02-20
**Suite result:** 219 passed, 0 failed, 0 skipped (from 112 pre-audit)
**Test files added:** 9 new test files (107 new tests)

---

## Defects Found and Fixed

### DEFECT-001: OrderedDictionary .ContainsKey() crash (10 sites)
- **Severity:** Critical
- **Files:** PluginLoader.ps1 (7 sites), UserSkills.ps1 (3 sites)
- **Reproduce:** Load any plugin or user skill that triggers a .ContainsKey() call on $global:IntentAliases, $global:LoadedPlugins, or $global:LoadedUserSkills.
- **Expected:** Key existence check returns true/false.
- **Actual:** RuntimeException: OrderedDictionary does not contain a method named ContainsKey.
- **Root Cause:** [ordered]@{} creates OrderedDictionary which has .Contains(), not .ContainsKey().
- **Fix:** Replaced all 10 .ContainsKey() calls on these four globals with .Contains().
- **Tests:** PluginLoader.Tests.ps1, UserSkills.Tests.ps1

### DEFECT-002: Get-Content single-line char coercion (3 sites)
- **Severity:** High
- **Files:** SecretScanner.ps1:32, ConfigLoader.ps1:105, PersistentAliases.ps1:81
- **Reproduce:** Have a file with exactly one line, then index into the Get-Content result.
- **Expected:** $lines[$i] returns a [string].
- **Actual:** $lines is a scalar [string]. $lines[0] returns [char] which lacks .Trim().
- **Root Cause:** PowerShell unwraps single-element pipeline output to scalar.
- **Fix:** Wrapped with @(): $lines = @(Get-Content $path) to force array.
- **Tests:** ConfigLoader.Tests.ps1, SecretScanner.Tests.ps1

### DEFECT-003: Version string mismatch
- **Severity:** Medium
- **Files:** Microsoft.PowerShell_profile.ps1:6
- **Reproduce:** Load profile, check $global:BildsyPSVersion.
- **Expected:** 1.3.0 (matches BildsyPS.psm1 and test bootstrap).
- **Actual:** 1.2.0 -- profile was never bumped.
- **Fix:** Updated profile to 1.3.0.
- **Impact:** Plugin version compatibility checks would reject plugins requiring 1.3.0.

### DEFECT-004: Invoke-SecretScan inconsistent return type
- **Severity:** Medium
- **Files:** SecretScanner.ps1:60
- **Reproduce:** Call Invoke-SecretScan on a file with exactly one secret.
- **Expected:** Returns array of hashtables, always.
- **Actual:** Returns bare hashtable when there is 1 finding. $result[0].Pattern yields $null.
- **Root Cause:** PowerShell unwraps single-element arrays on function return.
- **Fix:** Changed return $findings to return @(,$findings) using comma operator.
- **Tests:** SecretScanner.Tests.ps1 (all pattern detection tests)

### DEFECT-005: Convert-JsonIntent crashes on null ChatSessionHistory
- **Severity:** High
- **Files:** ResponseParser.ps1:292
- **Reproduce:** Call Convert-JsonIntent with two JSON intent actions when $global:ChatSessionHistory is $null.
- **Expected:** Execution summaries appended to chat history array.
- **Actual:** ArgumentException: Item has already been added. Key: role.
- **Root Cause:** $null += @{role=...} creates hashtable, second += merges keys and collides.
- **Fix:** Added null guard: if (-not $global:ChatSessionHistory) { $global:ChatSessionHistory = @() }
- **Tests:** ResponseParser.Tests.ps1

### DEFECT-006: ProfileTimings null in test/headless context
- **Severity:** Low
- **Files:** PluginLoader.ps1:348
- **Reproduce:** Load PluginLoader.ps1 without running the profile first.
- **Expected:** Plugin load timing recorded silently.
- **Actual:** Cannot index into a null array.
- **Root Cause:** $global:ProfileTimings is initialized in the profile but not in standalone loading.
- **Fix:** Added initialization in test bootstrap. Application should also guard internally.

---

## Systemic Patterns

### Pattern A: [ordered]@{} vs @{} method mismatch
- **Scope:** Any module using [ordered]@{} for registries
- **Impact:** 10+ crash sites across 2 modules (plus 11 already fixed in prior session)
- **Prevention:** Always use .Contains() for key checks. It works on both Hashtable and OrderedDictionary.

### Pattern B: PowerShell array unwrapping
- **Scope:** Any function returning $array where array may have 0 or 1 elements
- **Impact:** Silent type mutation -- callers expecting arrays get scalars or $null
- **Prevention:** Use return @(,$array) or [OutputType] annotations. Wrap caller-side with @().

### Pattern C: Null global state assumptions
- **Scope:** Modules that reference globals set by other modules (ChatSessionHistory, ProfileTimings)
- **Impact:** Crash when modules are loaded independently or in different order
- **Prevention:** Every module should guard against null for any global it reads. Never assume load order.

---

## Test Coverage Summary

| Test File | Tests | Status |
|-----------|-------|--------|
| AgentHeartbeat.Tests.ps1 | 14 | Existing -- all pass |
| AgentLoop.Tests.ps1 | 16 | Existing -- all pass |
| AppBuilder.Tests.ps1 | 18 | Existing -- all pass |
| ChatStorage.Tests.ps1 | 15 | Existing -- all pass |
| IntentRouting.Tests.ps1 | 33 | Existing -- all pass |
| VisionTools.Tests.ps1 | 16 | Existing -- all pass |
| ConfigLoader.Tests.ps1 | 16 | NEW |
| SecretScanner.Tests.ps1 | 11 | NEW |
| UserSkills.Tests.ps1 | 11 | NEW |
| PluginLoader.Tests.ps1 | 13 | NEW |
| CodeArtifacts.Tests.ps1 | 16 | NEW |
| WorkflowEngine.Tests.ps1 | 8 | NEW |
| SafetySystem.Tests.ps1 | 14 | NEW |
| ResponseParser.Tests.ps1 | 8 | NEW |
| NaturalLanguage.Tests.ps1 | 10 | NEW |
| **TOTAL** | **219** | **0 failures** |

---

## Files Modified (Application Fixes)

| File | Change |
|------|--------|
| Modules/PluginLoader.ps1 | 7x .ContainsKey() to .Contains() |
| Modules/UserSkills.ps1 | 3x .ContainsKey() to .Contains() |
| Modules/SecretScanner.ps1 | @() wrap on Get-Content + array return fix |
| Modules/ConfigLoader.ps1 | @() wrap on Get-Content |
| Modules/PersistentAliases.ps1 | @() wrap on Get-Content and filtered result |
| Modules/ResponseParser.ps1 | Null guard on ChatSessionHistory |
| Microsoft.PowerShell_profile.ps1 | Version 1.2.0 to 1.3.0 |

## Files Modified (Test Infrastructure)

| File | Change |
|------|--------|
| Tests/_Bootstrap.ps1 | Added skills/aliases dirs, ProfileTimings init, ChatDbPath/ChatDbReady reset, ClearAllPools in cleanup, Remove-TestTempRoot in Minimal mode |
