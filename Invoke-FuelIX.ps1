<#
.SYNOPSIS
    Interacts with FuelIX AI via direct prompt, pipeline, or interactive session.

.DESCRIPTION
    A robust wrapper for the FuelIX API. Supports JSON configuration, pipeline input, 
    and maintaining conversation history in interactive mode.

.PARAMETER Prompt
    The text prompt to send to the model. Can be passed via pipeline.

.PARAMETER Interactive
    Switch to start a persistent chat session in the console.

.PARAMETER ConfigPath
    Path to a JSON config file. Defaults to 'config.json' in the script's directory.

.PARAMETER ApiKey
    Overrides the API key in the config file or environment.

.PARAMETER Model
    Overrides the Model in the config file.

.PARAMETER MaxTokens
    Maximum tokens in the response (required by the Anthropic Messages API). Defaults to 4096.

.PARAMETER ApiFormat
    Which FuelIX endpoint/format to use: 'Messages' (/v1/messages, Anthropic format),
    'ChatCompletions' (/v1/chat/completions, OpenAI format), or 'Auto' (default).
    Auto uses Messages for Claude/Anthropic model names and ChatCompletions for everything else.
    Can also be set via "ApiFormat" in config.json.

.EXAMPLE
    "Explain recursion" | Invoke-FuelIX
#>

[CmdletBinding(DefaultParameterSetName = "Standard")]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = "Standard")]
    [string]$Prompt,

    [Parameter(Mandatory = $true, ParameterSetName = "InteractiveMode")]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\config.json",

    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [string]$Model,

    [Parameter(Mandatory = $false)]
    [int]$MaxTokens = 4096,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Auto", "Messages", "ChatCompletions")]
    [string]$ApiFormat
)

begin {
    # 1. Load Config File
    $FileConfig = if (Test-Path $ConfigPath) { Get-Content $ConfigPath | ConvertFrom-Json } else { $null }

    # 2. Resolve Config (Param > File > Env > Default)
    $FinalApiKey = if ($ApiKey) { $ApiKey } elseif ($FileConfig.ApiKey) { $FileConfig.ApiKey } else { $env:FUELIX_API_KEY }
    $FinalModel  = if ($Model) { $Model } elseif ($FileConfig.Model) { $FileConfig.Model } else { "fuelix-default-model" }

    $FinalFormat = if ($ApiFormat) { $ApiFormat } elseif ($FileConfig.ApiFormat) { $FileConfig.ApiFormat } else { "Auto" }
    if ($FinalFormat -notin "Auto", "Messages", "ChatCompletions") {
        throw "Invalid ApiFormat '$FinalFormat'. Use Auto, Messages, or ChatCompletions."
    }
    if ($FinalFormat -eq "Auto") {
        $FinalFormat = if ($FinalModel -match '(?i)claude|anthropic') { "Messages" } else { "ChatCompletions" }
    }

    if ([string]::IsNullOrWhiteSpace($FinalApiKey)) {
        throw "API Key not found. Provide via -ApiKey, config.json, or `$env:FUELIX_API_KEY."
    }

    # Session-wide token usage (hashtable so the function can mutate it from its child scope)
    $SessionUsage = @{ Input = 0; Output = 0; CacheRead = 0; CacheWrite = 0; Requests = 0 }

    function Execute-ApiCall {
        param([array]$Messages)
        
        $Headers = @{
            "Content-Type"  = "application/json"
            "Authorization" = "Bearer $FinalApiKey"
        }

        if ($FinalFormat -eq "Messages") {
            # Anthropic Messages API: max_tokens is required
            $Uri = "https://api.fuelix.ai/v1/messages"
            $Headers["x-api-key"] = $FinalApiKey
            # $Headers["anthropic-version"] = "2023-06-01"
            $body = @{
                model      = $FinalModel
                max_tokens = $MaxTokens
                messages   = $Messages
                stream     = $false
            } | ConvertTo-Json -Depth 10
        } else {
            # OpenAI-compatible Chat Completions (works for OpenAI, Google, and other non-Anthropic models)
            $Uri = "https://api.fuelix.ai/v1/chat/completions"
            $body = @{
                model    = $FinalModel
                messages = $Messages
                stream   = $false
            } | ConvertTo-Json -Depth 10
        }
        Write-Verbose "POST $Uri (format: $FinalFormat)"

        try {
            $Res = Invoke-RestMethod -Uri $Uri -Method Post -Body $body -Headers $Headers -ErrorAction Stop
            if ($Res.usage) {
                $SessionUsage.Requests++
                if ($FinalFormat -eq "Messages") {
                    $in  = [int]$Res.usage.input_tokens
                    $out = [int]$Res.usage.output_tokens
                    $SessionUsage.CacheRead  += [int]$Res.usage.cache_read_input_tokens
                    $SessionUsage.CacheWrite += [int]$Res.usage.cache_creation_input_tokens
                } else {
                    $in  = [int]$Res.usage.prompt_tokens
                    $out = [int]$Res.usage.completion_tokens
                    $SessionUsage.CacheRead += [int]$Res.usage.prompt_tokens_details.cached_tokens
                }
                $SessionUsage.Input  += $in
                $SessionUsage.Output += $out
                Write-Verbose "Tokens - in: $in, out: $out"
            }
            if ($FinalFormat -eq "Messages") {
                # Anthropic format: content is an array of blocks; join all text blocks
                return (($Res.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join "")
            } else {
                # OpenAI format: choices[0].message.content
                return $Res.choices[0].message.content
            }
        } catch {
            $Err = $_
            $Details = [System.Collections.Generic.List[string]]::new()
            $Details.Add("API Request Failed")
            $Details.Add("  URI:    $Uri")
            $Details.Add("  Model:  $FinalModel")

            # Status code (present on HTTP errors in both PS 5.1 and 7+)
            $Response = $Err.Exception.Response
            if ($Response) {
                $Details.Add("  Status: $([int]$Response.StatusCode) $($Response.StatusCode)")
            }

            # Full exception chain, including inner exceptions
            $Ex = $Err.Exception
            $Depth = 0
            while ($Ex) {
                $Details.Add("  Error[$Depth] ($($Ex.GetType().FullName)): $($Ex.Message)")
                $Ex = $Ex.InnerException
                $Depth++
            }

            # Response body: PS 7+ exposes it via ErrorDetails; PS 5.1 requires reading the stream
            $RespBody = $Err.ErrorDetails.Message
            if (-not $RespBody -and $Response -and $Response.GetResponseStream) {
                try {
                    $Stream = $Response.GetResponseStream()
                    $Stream.Position = 0
                    $RespBody = [System.IO.StreamReader]::new($Stream).ReadToEnd()
                } catch { }
            }
            if ($RespBody) {
                # Pretty-print JSON error payloads when possible
                try { $RespBody = $RespBody | ConvertFrom-Json | ConvertTo-Json -Depth 10 } catch { }
                $Details.Add("  Response body:")
                $Details.Add(($RespBody -split "`r?`n" | ForEach-Object { "    $_" }) -join "`n")
            }

            Write-Verbose ("Stack trace:`n" + $Err.ScriptStackTrace)
            Write-Error ($Details -join "`n")
            return $null
        }
    }
}

process {
    if ($PSCmdlet.ParameterSetName -eq "Standard") {
        # Use standard 'content' field
        $Payload = @(@{ role = "user"; content = $Prompt })
        $Response = Execute-ApiCall -Messages $Payload
        if ($Response) { $Response }
    }
}

end {
    if ($Interactive) {
        $ChatHistory = @()

        # Prints a one-line token usage summary (session totals) after each response
        function Write-UsageLine {
            $total = $SessionUsage.Input + $SessionUsage.Output
            Write-Host ("[Requests: {0} | In: {1:N0} | Out: {2:N0} | Total: {3:N0}]" -f $SessionUsage.Requests, $SessionUsage.Input, $SessionUsage.Output, $total) -ForegroundColor DarkGray
        }

        Clear-Host
        $modelMessage = "Using Model - $FinalModel"
        $modelPadding = " " * [Math]::Max(0, [int]((50 - $modelMessage.Length) / 2))
        Write-Host "=============== FuelIX Interactive ===============" -ForegroundColor Cyan
        Write-Host "$($modelPadding+$modelMessage+$modelPadding)" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "     Type 'exit', 'quit', or 'clear' (to reset history)." -ForegroundColor Gray
        Write-Host ""

        try {
            while ($true) {
                $UserInput = Read-Host "`nYou"
                if ($UserInput -in "exit", "quit") { break }
                if ($UserInput -eq "clear") { $ChatHistory = @(); Write-Host "History cleared." -ForegroundColor Yellow; continue }
                if ([string]::IsNullOrWhiteSpace($UserInput)) { continue }

                $ChatHistory += @{ role = "user"; content = $UserInput }

                Write-Host "FuelIX: ..." -NoNewline -ForegroundColor Green
                $Response = Execute-ApiCall -Messages $ChatHistory

                if ($Response) {
                    # Clear the "..." and print response
                    Write-Host "`rFuelIX: $Response" -ForegroundColor Green
                    $ChatHistory += @{ role = "assistant"; content = $Response }
                    Write-UsageLine
                } else {
                    # Remove failed turn
                    $ChatHistory = @($ChatHistory | Select-Object -SkipLast 1)
                }
            }
        } finally {
            # Print the session summary (also runs on Ctrl+C)
            $total = $SessionUsage.Input + $SessionUsage.Output
            Write-Host ""
            Write-Host "============== Session Token Usage ==============" -ForegroundColor Cyan
            Write-Host ("  Requests:      {0:N0}" -f $SessionUsage.Requests) -ForegroundColor Cyan
            Write-Host ("  Input tokens:  {0:N0}" -f $SessionUsage.Input) -ForegroundColor Cyan
            Write-Host ("  Output tokens: {0:N0}" -f $SessionUsage.Output) -ForegroundColor Cyan
            if ($SessionUsage.CacheRead -or $SessionUsage.CacheWrite) {
                Write-Host ("  Cache read:    {0:N0}" -f $SessionUsage.CacheRead) -ForegroundColor Cyan
                Write-Host ("  Cache write:   {0:N0}" -f $SessionUsage.CacheWrite) -ForegroundColor Cyan
            }
            Write-Host ("  Total:         {0:N0}" -f $total) -ForegroundColor Cyan
            Write-Host "=================================================" -ForegroundColor Cyan
        }
    }
}