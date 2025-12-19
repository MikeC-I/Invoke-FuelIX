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
    Overrides the Model in the config file. Defaults to 'gemini-2.5-flash'.

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
    [string]$Model
)

begin {
    # 1. Load Config File
    $FileConfig = if (Test-Path $ConfigPath) { Get-Content $ConfigPath | ConvertFrom-Json } else { $null }

    # 2. Resolve Config (Param > File > Env > Default)
    $FinalApiKey = if ($ApiKey) { $ApiKey } elseif ($FileConfig.ApiKey) { $FileConfig.ApiKey } else { $env:FUELIX_API_KEY }
    $FinalModel  = if ($Model) { $Model } elseif ($FileConfig.Model) { $FileConfig.Model } else { "fuelix-default-model" }

    if ([string]::IsNullOrWhiteSpace($FinalApiKey)) {
        throw "API Key not found. Provide via -ApiKey, config.json, or `$env:FUELIX_API_KEY."
    }

    function Execute-ApiCall {
        param([array]$Messages)
        
        $body = @{
            model    = $FinalModel
            messages = $Messages
            stream   = $false
        } | ConvertTo-Json

        $Headers = @{
            "Content-Type"  = "application/json"
            "Authorization" = "Bearer $FinalApiKey"
        }

        $Uri = "https://api.fuelix.ai/v1/chat/completions"
        
        try {
            $Res = Invoke-RestMethod -Uri $Uri -Method Post -Body $body -Headers $Headers -ErrorAction Stop
            # FuelIX/OpenAI Standard: choices[0].message.content
            return $Res.choices[0].message.content
        } catch {
            Write-Error "API Request Failed: $($_.Exception.Message)"
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
        $modelMessage = "Using Model - $FinalModel"
        $modelPadding = " " * ((50 - $modelMessage.Length) / 2)
        Clear-Host
        Write-Host "=============== FuelIX Interactive ===============" -ForegroundColor Cyan
        Write-Host "$($modelPadding+$modelMessage+$modelPadding)" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "     Type 'exit', 'quit', or 'cls' (to clear)." -ForegroundColor Gray
        Write-Host ""

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
            } else {
                # Remove failed turn
                $ChatHistory = $ChatHistory[0..($ChatHistory.Count - 2)]
            }
        }
    }
}