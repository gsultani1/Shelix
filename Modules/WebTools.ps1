# ===== WebTools.ps1 =====
# Web search and retrieval tools for AI assistant

# ===== Search Engine Configuration =====
# API keys are loaded from Config/.env file (see Config/.env.example)
# Uses Get-ConfigValue which checks .env first, then falls back to environment variables

function Initialize-SearchConfig {
    # Called after ConfigLoader is loaded to get API keys
    $global:SearchEngineConfig = @{
        # DuckDuckGo - Free, no API key needed (always available as fallback)
        DuckDuckGo = @{
            Enabled = $true
        }
        
        # RapidAPI Google Search - Fast Google results
        # Get yours at: https://rapidapi.com/apigeek/api/google-search72
        RapidAPI = @{
            Enabled = $true
            ApiKey = Get-ConfigValue -Key 'RAPIDAPI_KEY'
            Host = 'google-search72.p.rapidapi.com'
        }
        
        # Google Custom Search
        # Get yours at: https://developers.google.com/custom-search/v1/overview
        Google = @{
            Enabled = $false
            ApiKey = Get-ConfigValue -Key 'GOOGLE_SEARCH_API_KEY'
            SearchEngineId = Get-ConfigValue -Key 'GOOGLE_SEARCH_ENGINE_ID'
        }
        
        # Bing Search
        # Get yours at: https://www.microsoft.com/en-us/bing/apis/bing-web-search-api
        Bing = @{
            Enabled = $false
            ApiKey = Get-ConfigValue -Key 'BING_SEARCH_API_KEY'
        }
        
        # SerpAPI - Unified search API
        # Get yours at: https://serpapi.com/
        SerpAPI = @{
            Enabled = $false
            ApiKey = Get-ConfigValue -Key 'SERPAPI_KEY'
        }
    }
}

# Initialize config (will use Get-ConfigValue from ConfigLoader)
if (Get-Command Get-ConfigValue -ErrorAction SilentlyContinue) {
    Initialize-SearchConfig
} else {
    # Fallback if ConfigLoader not loaded yet
    $global:SearchEngineConfig = @{
        DuckDuckGo = @{ Enabled = $true }
        RapidAPI = @{ Enabled = $true; ApiKey = $env:RAPIDAPI_KEY; Host = 'google-search72.p.rapidapi.com' }
    }
}

# ===== RapidAPI Google Search =====
function Invoke-RapidAPISearch {
    <#
    .SYNOPSIS
    Search using RapidAPI Google Search (requires API key)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query,
        [int]$MaxResults = 5
    )
    
    $config = $global:SearchEngineConfig.RapidAPI
    if (-not $config.Enabled -or -not $config.ApiKey) {
        return @{ Success = $false; Message = "RapidAPI not configured. Set `$env:RAPIDAPI_KEY" }
    }
    
    try {
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
        $url = "https://$($config.Host)/search?q=$encodedQuery&num=$MaxResults"
        
        $headers = @{
            'x-rapidapi-key' = $config.ApiKey
            'x-rapidapi-host' = $config.Host
        }
        
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 15
        
        $results = @()
        if ($response.items) {
            foreach ($item in $response.items | Select-Object -First $MaxResults) {
                $results += @{
                    Title = $item.title
                    Snippet = $item.snippet
                    Url = $item.link
                    Type = "Google"
                }
            }
        }
        
        if ($results.Count -eq 0) {
            return @{ Success = $false; Message = "No results from RapidAPI"; Results = @() }
        }
        
        return @{
            Success = $true
            Query = $Query
            ResultCount = $results.Count
            Results = $results
            Source = "RapidAPI"
        }
    }
    catch {
        return @{ Success = $false; Message = "RapidAPI error: $($_.Exception.Message)" }
    }
}

# ===== Main Web Search (tries RapidAPI first, falls back to DuckDuckGo) =====
function Invoke-WebSearch {
    <#
    .SYNOPSIS
    Search the web - uses RapidAPI if configured, otherwise DuckDuckGo
    
    .PARAMETER Query
    Search query string
    
    .PARAMETER MaxResults
    Maximum number of results to return (default 5)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query,
        [int]$MaxResults = 5
    )
    
    # Try RapidAPI first if configured
    $rapidConfig = $global:SearchEngineConfig.RapidAPI
    if ($rapidConfig.Enabled -and $rapidConfig.ApiKey) {
        $result = Invoke-RapidAPISearch -Query $Query -MaxResults $MaxResults
        if ($result.Success) {
            return $result
        }
    }
    
    # Fallback to DuckDuckGo
    try {
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
        $url = "https://api.duckduckgo.com/?q=$encodedQuery&format=json&no_html=1&skip_disambig=1"
        
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10
        
        $results = @()
        
        # Abstract (main answer)
        if ($response.Abstract) {
            $results += @{
                Title = $response.Heading
                Snippet = $response.Abstract
                Url = $response.AbstractURL
                Source = $response.AbstractSource
                Type = "Abstract"
            }
        }
        
        # Related topics
        if ($response.RelatedTopics) {
            foreach ($topic in $response.RelatedTopics | Select-Object -First ($MaxResults - $results.Count)) {
                if ($topic.Text -and $topic.FirstURL) {
                    $results += @{
                        Title = ($topic.Text -split ' - ')[0]
                        Snippet = $topic.Text
                        Url = $topic.FirstURL
                        Type = "Related"
                    }
                }
            }
        }
        
        # Instant answer
        if ($response.Answer) {
            $results = @(@{
                Title = "Instant Answer"
                Snippet = $response.Answer
                Url = ""
                Type = "Instant"
            }) + $results
        }
        
        if ($results.Count -eq 0) {
            # Fallback: Try DuckDuckGo HTML search scraping
            try {
                $htmlUrl = "https://html.duckduckgo.com/html/?q=$encodedQuery"
                $htmlResponse = Invoke-WebRequest -Uri $htmlUrl -UseBasicParsing -TimeoutSec 15 -Headers @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
                
                # Extract result links and snippets from HTML
                $linkMatches = [regex]::Matches($htmlResponse.Content, '<a class="result__a" href="([^"]+)"[^>]*>([^<]+)</a>')
                $snippetMatches = [regex]::Matches($htmlResponse.Content, '<a class="result__snippet"[^>]*>([^<]+)</a>')
                
                for ($i = 0; $i -lt [Math]::Min($linkMatches.Count, $MaxResults); $i++) {
                    $title = $linkMatches[$i].Groups[2].Value -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
                    $link = $linkMatches[$i].Groups[1].Value
                    # DuckDuckGo uses redirect URLs, extract actual URL
                    if ($link -match 'uddg=([^&]+)') {
                        $link = [System.Web.HttpUtility]::UrlDecode($Matches[1])
                    }
                    $snippet = if ($i -lt $snippetMatches.Count) { 
                        $snippetMatches[$i].Groups[1].Value -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '<[^>]+>', ''
                    } else { "" }
                    
                    $results += @{
                        Title = $title
                        Snippet = $snippet
                        Url = $link
                        Type = "Web"
                    }
                }
            }
            catch {
                # HTML fallback failed too
            }
        }
        
        if ($results.Count -eq 0) {
            return @{
                Success = $false
                Query = $Query
                Message = "No results found. Try 'open_browser_search' to search in your browser."
                Results = @()
            }
        }
        
        return @{
            Success = $true
            Query = $Query
            ResultCount = $results.Count
            Results = $results
        }
    }
    catch {
        return @{
            Success = $false
            Query = $Query
            Message = "Search failed: $($_.Exception.Message)"
            Results = @()
        }
    }
}

# ===== Fetch Web Page Content =====
function Get-WebPageContent {
    <#
    .SYNOPSIS
    Fetch and extract text content from a web page
    
    .PARAMETER Url
    URL to fetch
    
    .PARAMETER MaxLength
    Maximum characters to return (default 2000)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [int]$MaxLength = 2000
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec 15 -UseBasicParsing
        
        # Extract text content (basic HTML stripping)
        $content = $response.Content
        
        # Remove script and style tags
        $content = $content -replace '<script[^>]*>[\s\S]*?</script>', ''
        $content = $content -replace '<style[^>]*>[\s\S]*?</style>', ''
        
        # Remove HTML tags
        $content = $content -replace '<[^>]+>', ' '
        
        # Decode HTML entities
        $content = [System.Web.HttpUtility]::HtmlDecode($content)
        
        # Clean up whitespace
        $content = $content -replace '\s+', ' '
        $content = $content.Trim()
        
        # Truncate if too long
        if ($content.Length -gt $MaxLength) {
            $content = $content.Substring(0, $MaxLength) + "... [truncated]"
        }
        
        return @{
            Success = $true
            Url = $Url
            Content = $content
            Length = $content.Length
        }
    }
    catch {
        return @{
            Success = $false
            Url = $Url
            Message = "Failed to fetch page: $($_.Exception.Message)"
        }
    }
}

# ===== Wikipedia Search =====
function Search-Wikipedia {
    <#
    .SYNOPSIS
    Search Wikipedia and return article summaries
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query,
        [int]$MaxResults = 3
    )
    
    try {
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
        
        # Search for articles
        $searchUrl = "https://en.wikipedia.org/w/api.php?action=opensearch&search=$encodedQuery&limit=$MaxResults&format=json"
        $searchResponse = Invoke-RestMethod -Uri $searchUrl -Method Get -TimeoutSec 10
        
        $titles = $searchResponse[1]
        $descriptions = $searchResponse[2]
        $urls = $searchResponse[3]
        
        if ($titles.Count -eq 0) {
            return @{
                Success = $false
                Query = $Query
                Message = "No Wikipedia articles found"
                Results = @()
            }
        }
        
        $results = @()
        for ($i = 0; $i -lt $titles.Count; $i++) {
            $results += @{
                Title = $titles[$i]
                Summary = $descriptions[$i]
                Url = $urls[$i]
            }
        }
        
        # Get full summary for first result
        if ($results.Count -gt 0) {
            $summaryUrl = "https://en.wikipedia.org/api/rest_v1/page/summary/$([System.Web.HttpUtility]::UrlEncode($titles[0]))"
            try {
                $summaryResponse = Invoke-RestMethod -Uri $summaryUrl -Method Get -TimeoutSec 10
                $results[0].FullSummary = $summaryResponse.extract
            } catch { }
        }
        
        return @{
            Success = $true
            Query = $Query
            ResultCount = $results.Count
            Results = $results
        }
    }
    catch {
        return @{
            Success = $false
            Query = $Query
            Message = "Wikipedia search failed: $($_.Exception.Message)"
            Results = @()
        }
    }
}

# ===== News Search (via DuckDuckGo) =====
function Search-News {
    <#
    .SYNOPSIS
    Search for recent news articles
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query
    )
    
    # Use DuckDuckGo news search
    $result = Invoke-WebSearch -Query "$Query news recent"
    $result.Type = "News"
    return $result
}

# ===== Format Results for AI =====
function Format-SearchResultsForAI {
    param($SearchResult)
    
    if (-not $SearchResult.Success) {
        return "Search failed: $($SearchResult.Message)"
    }
    
    $output = "Search results for '$($SearchResult.Query)':`n`n"
    
    $i = 1
    foreach ($result in $SearchResult.Results) {
        $output += "$i. **$($result.Title)**`n"
        if ($result.Snippet) {
            $output += "   $($result.Snippet)`n"
        }
        if ($result.FullSummary) {
            $output += "   $($result.FullSummary)`n"
        }
        if ($result.Url) {
            $output += "   URL: $($result.Url)`n"
        }
        $output += "`n"
        $i++
    }
    
    return $output
}

# ===== Export for use in intents =====
$global:WebToolsAvailable = $true
