BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'CodeArtifacts — Offline' {

    Context 'Get-CodeBlocks' {
        It 'Extracts a single fenced code block' {
            $text = "Here is code:`n`` `` ``powershell`nWrite-Output 'hi'`n`` `` ```n".Replace(' ', '')
            $blocks = Get-CodeBlocks -Text $text
            @($blocks).Count | Should -Be 1
            $blocks[0].Language | Should -Be 'powershell'
            $blocks[0].Code | Should -Match 'Write-Output'
        }

        It 'Extracts multiple code blocks' {
            $fence = '``' + '`'
            $text = "First:`n${fence}python`nprint('a')`n${fence}`nSecond:`n${fence}js`nconsole.log('b')`n${fence}`n"
            $blocks = Get-CodeBlocks -Text $text
            @($blocks).Count | Should -Be 2
            $blocks[0].Language | Should -Be 'python'
            $blocks[1].Language | Should -Be 'js'
        }

        It 'Returns empty for text with no code blocks' {
            $blocks = Get-CodeBlocks -Text 'Just plain text, no code here.'
            @($blocks).Count | Should -Be 0
        }

        It 'Defaults language to text when not specified' {
            $fence = '``' + '`'
            $text = "Code:`n${fence}`nsome content`n${fence}`n"
            $blocks = Get-CodeBlocks -Text $text
            @($blocks).Count | Should -Be 1
            $blocks[0].Language | Should -Be 'text'
        }

        It 'Tracks blocks in SessionArtifacts with -Track' {
            $global:SessionArtifacts = @()
            $fence = '``' + '`'
            $text = "Code:`n${fence}powershell`nGet-Date`n${fence}`n"
            Get-CodeBlocks -Text $text -Track
            $global:SessionArtifacts.Count | Should -Be 1
        }

        It 'Sets correct Index and LineCount' {
            $fence = '``' + '`'
            $text = "Block:`n${fence}ps1`nline1`nline2`nline3`n${fence}`n"
            $blocks = Get-CodeBlocks -Text $text
            $blocks[0].Index | Should -Be 1
            $blocks[0].LineCount | Should -Be 3
        }

        It 'Ignores empty code blocks' {
            $fence = '``' + '`'
            $text = "Empty:`n${fence}powershell`n`n${fence}`n"
            $blocks = Get-CodeBlocks -Text $text
            @($blocks).Count | Should -Be 0
        }
    }

    Context 'Save-Artifact' {
        BeforeAll {
            $global:ArtifactsPath = "$global:BildsyPSHome\builds\artifacts"
            New-Item -ItemType Directory -Path $global:ArtifactsPath -Force | Out-Null
        }

        It 'Saves code to a file by direct -Code parameter' {
            $outPath = "$global:BildsyPSHome\builds\artifacts\test-save.ps1"
            Save-Artifact -Code 'Write-Output "saved"' -Language 'powershell' -Path $outPath -Force
            Test-Path $outPath | Should -BeTrue
            $content = Get-Content $outPath -Raw
            $content | Should -Match 'Write-Output'
        }

        It 'Saves artifact by index from SessionArtifacts' {
            $global:SessionArtifacts = @(
                [PSCustomObject]@{
                    Index = 1; Language = 'powershell'; Code = 'Get-Date'
                    LineCount = 1; Saved = $false; SavedPath = $null; Executed = $false
                }
            )
            $outPath = "$global:BildsyPSHome\builds\artifacts\test-idx.ps1"
            Save-Artifact -Index 1 -Path $outPath -Force
            Test-Path $outPath | Should -BeTrue
        }
    }

    Context 'Invoke-Artifact' {
        It 'Executes PowerShell code and returns result' {
            $result = Invoke-Artifact -Code 'Write-Output "artifact-test"' -Language 'powershell' -NoConfirm
            $result.Success | Should -BeTrue
            $result.Output | Should -Match 'artifact-test'
        }

        It 'Returns error for unsupported language' {
            $result = Invoke-Artifact -Code 'fn main() {}' -Language 'rust_nonexistent_xyz'
            $result.Success | Should -BeFalse
        }

        It 'Returns error for invalid index' {
            $result = Invoke-Artifact -Index 999
            $result.Success | Should -BeFalse
        }
    }

    Context 'ArtifactRunners registry' {
        It 'Has entries for common languages' {
            $global:ArtifactRunners.ContainsKey('powershell') | Should -BeTrue
            $global:ArtifactRunners.ContainsKey('python') | Should -BeTrue
            $global:ArtifactRunners.ContainsKey('javascript') | Should -BeTrue
            $global:ArtifactRunners.ContainsKey('bash') | Should -BeTrue
        }

        It 'Each runner has Ext and Safe properties' {
            foreach ($key in $global:ArtifactRunners.Keys) {
                $runner = $global:ArtifactRunners[$key]
                $runner.ContainsKey('Ext') | Should -BeTrue
                $runner.ContainsKey('Safe') | Should -BeTrue
            }
        }
    }

    Context 'Show-SessionArtifacts' {
        It 'Does not throw with empty artifacts' {
            $global:SessionArtifacts = @()
            { Show-SessionArtifacts } | Should -Not -Throw
        }

        It 'Does not throw with populated artifacts' {
            $global:SessionArtifacts = @(
                [PSCustomObject]@{
                    Index = 1; Language = 'powershell'; Code = 'Get-Date'
                    LineCount = 1; Saved = $false; SavedPath = $null; Executed = $false
                }
            )
            { Show-SessionArtifacts } | Should -Not -Throw
        }
    }
}
