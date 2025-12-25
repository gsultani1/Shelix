# ===== WebTools.ps1 =====
# Web search and retrieval tools for AI assistant

# ===== DuckDuckGo Instant Answer API =====
function Invoke-WebSearch {
    <#
    .SYNOPSIS
    Search the web and return results using DuckDuckGo API
    
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
            return @{
                Success = $false
                Query = $Query
                Message = "No instant results found. Try a more specific query or use search_web to open Google."
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
