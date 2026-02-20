BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
    . "$global:ModulesPath\UserSkills.ps1"

    # Helper: write a skills JSON file and reload cleanly
    function Set-TestSkills {
        param([hashtable]$Skills)
        $payload = @{ skills = $Skills }
        $payload | ConvertTo-Json -Depth 10 |
            Set-Content -Path $global:UserSkillsPath -Encoding UTF8
        if (Get-Command Unregister-UserSkills -ErrorAction SilentlyContinue) {
            Unregister-UserSkills
        }
        Import-UserSkills -Quiet
    }
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'UserSkills — Offline' {

    Context 'Import-UserSkills' {

        It 'Registers a simple skill into IntentAliases and LoadedUserSkills' {
            Set-TestSkills @{
                hello = @{
                    description = 'Say hello'
                    steps       = @( @{ command = 'Write-Output "hello"' } )
                }
            }
            $global:IntentAliases.Contains('hello')      | Should -BeTrue
            $global:LoadedUserSkills.Contains('hello')    | Should -BeTrue
        }

        It 'Stores metadata with correct description' {
            Set-TestSkills @{
                meta_check = @{
                    description = 'Metadata test'
                    steps       = @(
                        @{ command = 'echo 1' }
                        @{ command = 'echo 2' }
                        @{ command = 'echo 3' }
                    )
                }
            }
            $global:IntentMetadata.ContainsKey('meta_check') | Should -BeTrue
            $global:IntentMetadata['meta_check'].Description | Should -Be 'Metadata test'
        }

        It 'Registers multiple skills from a single JSON file' {
            Set-TestSkills @{
                alpha = @{
                    description = 'First'
                    steps       = @( @{ command = 'echo a' } )
                }
                bravo = @{
                    description = 'Second'
                    steps       = @( @{ command = 'echo b' } )
                }
                charlie = @{
                    description = 'Third'
                    steps       = @( @{ command = 'echo c' } )
                }
            }
            $global:LoadedUserSkills.Count | Should -BeGreaterOrEqual 3
            foreach ($name in @('alpha', 'bravo', 'charlie')) {
                $global:IntentAliases.Contains($name) | Should -BeTrue
            }
        }

        It 'Creates a shell-invocable function for each skill' {
            Set-TestSkills @{
                shell_test = @{
                    description = 'Shell function test'
                    steps       = @( @{ command = 'Write-Output "shell ok"' } )
                }
            }
            Get-Command shell_test -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Skips skills that conflict with existing built-in intents' {
            Set-TestSkills @{
                list_files = @{
                    description = 'Conflict test'
                    steps       = @( @{ command = 'echo conflict' } )
                }
            }
            $global:LoadedUserSkills.Contains('list_files') | Should -BeFalse
        }

        It 'Preserves existing built-in intent when a conflict occurs' {
            $builtinBefore = $global:IntentAliases['list_files']
            Set-TestSkills @{
                list_files = @{
                    description = 'Should not overwrite'
                    steps       = @( @{ command = 'echo nope' } )
                }
            }
            $global:IntentAliases['list_files'] | Should -Be $builtinBefore
        }

        It 'Handles missing UserSkills.json without throwing' {
            $saved = $global:UserSkillsPath
            $global:UserSkillsPath = Join-Path $global:BildsyPSHome 'skills' 'nonexistent.json'
            # Also ensure $global:BildsyPSModulePath points away from the example file
            $savedMod = $global:BildsyPSModulePath
            $global:BildsyPSModulePath = $global:BildsyPSHome
            { Import-UserSkills -Quiet } | Should -Not -Throw
            $global:UserSkillsPath = $saved
            $global:BildsyPSModulePath = $savedMod
        }

        It 'Handles malformed JSON without throwing' {
            $bad = Join-Path $global:BildsyPSHome 'skills' 'bad.json'
            Set-Content -Path $bad -Value 'not valid json {{{' -Encoding UTF8
            $saved = $global:UserSkillsPath
            $global:UserSkillsPath = $bad
            { Import-UserSkills -Quiet } | Should -Not -Throw
            $global:UserSkillsPath = $saved
        }

        It 'Handles JSON missing the skills property without throwing' {
            $empty = Join-Path $global:BildsyPSHome 'skills' 'no_skills.json'
            '{"version": 1}' | Set-Content -Path $empty -Encoding UTF8
            $saved = $global:UserSkillsPath
            $global:UserSkillsPath = $empty
            { Import-UserSkills -Quiet } | Should -Not -Throw
            $global:UserSkillsPath = $saved
        }

        It 'Skips a skill definition with no steps array' {
            Set-TestSkills @{
                no_steps = @{
                    description = 'Missing steps entirely'
                }
            }
            $global:LoadedUserSkills.Contains('no_steps') | Should -BeFalse
        }

        It 'Skips a skill definition with an empty steps array' {
            Set-TestSkills @{
                empty_steps = @{
                    description = 'Zero steps'
                    steps       = @()
                }
            }
            $global:LoadedUserSkills.Contains('empty_steps') | Should -BeFalse
        }
    }

    Context 'Unregister-UserSkills' {

        It 'Removes all user skills from both registries' {
            Set-TestSkills @{
                unreg_a = @{
                    description = 'A'
                    steps       = @( @{ command = 'echo a' } )
                }
                unreg_b = @{
                    description = 'B'
                    steps       = @( @{ command = 'echo b' } )
                }
            }
            $global:LoadedUserSkills.Count | Should -BeGreaterOrEqual 2
            Unregister-UserSkills
            $global:LoadedUserSkills.Count            | Should -Be 0
            $global:IntentAliases.Contains('unreg_a') | Should -BeFalse
            $global:IntentAliases.Contains('unreg_b') | Should -BeFalse
        }

        It 'Removes shell functions when unregistering' {
            Set-TestSkills @{
                fn_cleanup = @{
                    description = 'Function cleanup test'
                    steps       = @( @{ command = 'echo clean' } )
                }
            }
            Get-Command fn_cleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            Unregister-UserSkills
            Get-Command fn_cleanup -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }

        It 'Does not throw when called with no skills loaded' {
            Unregister-UserSkills
            { Unregister-UserSkills } | Should -Not -Throw
        }

        It 'Does not remove built-in intents' {
            Set-TestSkills @{
                temp = @{
                    description = 'Temp'
                    steps       = @( @{ command = 'echo t' } )
                }
            }
            Unregister-UserSkills
            $global:IntentAliases.Contains('list_files') | Should -BeTrue
        }
    }

    Context 'Remove-UserSkill' {

        It 'Removes a specific skill from registries and JSON file' {
            Set-TestSkills @{
                remove_me = @{
                    description = 'To be removed'
                    steps       = @( @{ command = 'echo remove' } )
                }
                keep_me = @{
                    description = 'Should stay'
                    steps       = @( @{ command = 'echo keep' } )
                }
            }
            Remove-UserSkill -Name 'remove_me'
            $global:IntentAliases.Contains('remove_me')      | Should -BeFalse
            $global:LoadedUserSkills.Contains('remove_me')    | Should -BeFalse
            $global:IntentAliases.Contains('keep_me')         | Should -BeTrue
            $global:LoadedUserSkills.Contains('keep_me')      | Should -BeTrue
            $data = Get-Content $global:UserSkillsPath -Raw | ConvertFrom-Json
            ($data.skills.PSObject.Properties.Name -contains 'remove_me') | Should -BeFalse
            ($data.skills.PSObject.Properties.Name -contains 'keep_me')   | Should -BeTrue
        }

        It 'Does not throw when removing a nonexistent skill' {
            Set-TestSkills @{
                exists = @{
                    description = 'I exist'
                    steps       = @( @{ command = 'echo here' } )
                }
            }
            { Remove-UserSkill -Name 'does_not_exist' } | Should -Not -Throw
        }
    }

    Context 'Parameter Substitution' {

        It 'Substitutes a single parameter placeholder in step commands' {
            Set-TestSkills @{
                greet = @{
                    description = 'Greet by name'
                    parameters  = @(
                        @{ name = 'who'; required = $true; description = 'Name' }
                    )
                    steps = @(
                        @{ command = 'Write-Output "Hello {who}"' }
                    )
                }
            }
            $result = Invoke-UserSkill -Name 'greet' -Parameters @{ who = 'George' }
            $result.Output | Should -Match 'Hello George'
        }

        It 'Substitutes multiple distinct parameters across steps' {
            Set-TestSkills @{
                multi_param = @{
                    description = 'Multi param'
                    parameters  = @(
                        @{ name = 'first'; required = $true; description = 'First' }
                        @{ name = 'second'; required = $true; description = 'Second' }
                    )
                    steps = @(
                        @{ command = 'Write-Output "{first}"' }
                        @{ command = 'Write-Output "{second}"' }
                    )
                }
            }
            $result = Invoke-UserSkill -Name 'multi_param' -Parameters @{
                first  = 'Alpha'
                second = 'Bravo'
            }
            $result.Output | Should -Match 'Alpha'
            $result.Output | Should -Match 'Bravo'
        }

        It 'Leaves placeholder literal when parameter value is not supplied' {
            Set-TestSkills @{
                optional_test = @{
                    description = 'Optional param'
                    parameters  = @(
                        @{ name = 'opt'; required = $false; description = 'Optional' }
                    )
                    steps = @(
                        @{ command = 'Write-Output "val={opt}"' }
                    )
                }
            }
            $result = Invoke-UserSkill -Name 'optional_test' -Parameters @{}
            $result.Output | Should -Match '\{opt\}'
        }
    }

    Context 'Invoke-UserSkill' {

        It 'Executes a single-step skill and returns output' {
            Set-TestSkills @{
                simple_exec = @{
                    description = 'Simple exec'
                    steps       = @( @{ command = 'Write-Output "executed"' } )
                }
            }
            $result = Invoke-UserSkill -Name 'simple_exec'
            $result.Success | Should -BeTrue
            $result.Output  | Should -Match 'executed'
        }

        It 'Executes multi-step skills in order' {
            Set-TestSkills @{
                ordered = @{
                    description = 'Order test'
                    steps = @(
                        @{ command = 'Write-Output "step_1"' }
                        @{ command = 'Write-Output "step_2"' }
                        @{ command = 'Write-Output "step_3"' }
                    )
                }
            }
            $result = Invoke-UserSkill -Name 'ordered'
            $result.Success | Should -BeTrue
            $result.Output  | Should -Match 'step_1'
            $result.Output  | Should -Match 'step_2'
            $result.Output  | Should -Match 'step_3'
        }

        It 'Returns failure result for a nonexistent skill' {
            $result = Invoke-UserSkill -Name 'ghost_skill'
            $result.Success | Should -BeFalse
        }

        It 'Handles a step that throws without killing the entire skill' {
            Set-TestSkills @{
                partial_fail = @{
                    description = 'One bad step'
                    steps = @(
                        @{ command = 'Write-Output "before"' }
                        @{ command = 'throw "intentional error"' }
                        @{ command = 'Write-Output "after"' }
                    )
                }
            }
            { Invoke-UserSkill -Name 'partial_fail' } | Should -Not -Throw
        }
    }

    Context 'Trigger Registration' {

        It 'Registers trigger phrases into IntentAliases' {
            Set-TestSkills @{
                deploy_test = @{
                    description = 'Deploy trigger test'
                    triggers    = @('deploy staging', 'push to staging')
                    steps       = @( @{ command = 'echo deploying' } )
                }
            }
            $global:IntentAliases.Contains('deploy staging')  | Should -BeTrue
            $global:IntentAliases.Contains('push to staging') | Should -BeTrue
        }

        It 'Cleans up triggers when skill is unregistered' {
            Set-TestSkills @{
                trig_cleanup = @{
                    description = 'Trigger cleanup'
                    triggers    = @('run cleanup')
                    steps       = @( @{ command = 'echo clean' } )
                }
            }
            $global:IntentAliases.Contains('run cleanup') | Should -BeTrue
            Unregister-UserSkills
            $global:IntentAliases.Contains('run cleanup') | Should -BeFalse
        }
    }

    Context 'Idempotency' {

        It 'Is idempotent when called multiple times' {
            Set-TestSkills @{
                idempotent = @{
                    description = 'Reload me'
                    steps       = @( @{ command = 'echo reload' } )
                }
            }
            Import-UserSkills -Quiet
            Import-UserSkills -Quiet
            $global:LoadedUserSkills.Contains('idempotent') | Should -BeTrue
            # Count should be 1, not duplicated
            @($global:LoadedUserSkills.Keys | Where-Object { $_ -eq 'idempotent' }).Count | Should -Be 1
        }
    }

    Context 'Safety via confirm field' {

        It 'Sets RequiresConfirmation when confirm is true' {
            Set-TestSkills @{
                dangerous = @{
                    description = 'Needs confirmation'
                    confirm     = $true
                    steps       = @( @{ command = 'echo danger' } )
                }
            }
            $meta = $global:IntentMetadata['dangerous']
            $meta | Should -Not -BeNullOrEmpty
            $meta.Safety | Should -Be 'RequiresConfirmation'
        }

        It 'Defaults to null safety when confirm is not set' {
            Set-TestSkills @{
                safe_default = @{
                    description = 'No confirm field'
                    steps       = @( @{ command = 'echo safe' } )
                }
            }
            $meta = $global:IntentMetadata['safe_default']
            $meta.Safety | Should -Not -Be 'RequiresConfirmation'
        }
    }

    Context 'Get-UserSkillsPrompt' {

        It 'Returns prompt text containing skill names when skills are loaded' {
            Set-TestSkills @{
                prompt_skill = @{
                    description = 'For prompt test'
                    steps       = @( @{ command = 'echo prompt' } )
                }
            }
            $prompt = Get-UserSkillsPrompt
            $prompt | Should -Match 'USER SKILLS'
            $prompt | Should -Match 'prompt_skill'
        }

        It 'Includes parameter info in prompt text' {
            Set-TestSkills @{
                param_prompt = @{
                    description = 'Param prompt test'
                    parameters  = @(
                        @{ name = 'target'; required = $true; description = 'Target host' }
                    )
                    steps = @( @{ command = 'echo {target}' } )
                }
            }
            $prompt = Get-UserSkillsPrompt
            $prompt | Should -Match 'target'
        }

        It 'Returns empty string when no skills are loaded' {
            Unregister-UserSkills
            $prompt = Get-UserSkillsPrompt
            $prompt | Should -Be ''
        }
    }
}
