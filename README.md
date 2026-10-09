# Invoke-FuelIX 🤖

[![PowerShell Core](https://img.shields.io/badge/PowerShell-%3E%3D7.0-blue.svg)](https://microsoft.com/powershell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust, pipeline-aware PowerShell wrapper for FuelIX LLM API. Seamlessly integrate generative AI into your terminal workflows, automation scripts, or enjoy a full interactive chat experience directly from the CLI.

---

## ✨ Features

* **Pipeline Ready:** Pipe text directly into the model and pipe the response into files or other commands.
* **Interactive Mode:** A persistent chat session that remembers conversation history (type `clear` to reset it, `exit` or `quit` to leave).
* **Multiple API Formats:** Uses the Anthropic Messages API (`/v1/messages`) for Claude models and the OpenAI-compatible Chat Completions API (`/v1/chat/completions`) for everything else. The format is auto-detected from the model name, or you can set it explicitly.
* **Token Usage Tracking:** Interactive mode prints running token totals after each response and a session summary on exit (including cache read/write tokens when reported).
* **Detailed Error Reporting:** Failed requests report the URI, model, HTTP status, the full exception chain and the API response body.
* **Flexible Config:** Manage API key, model and API format via a `config.json` file, parameters, or environment variables.
* **Dev-Friendly:** Full support for `-Verbose` (shows the request URI/format and token counts), `-ErrorAction`, and standard PowerShell parameter sets.
* **Modern Models:** Works with Claude, `gpt-5`, `gemini-2.5-pro`, and many more.

---

## 🚀 Quick Start

### 1. Installation
Clone this repository or download the `Invoke-FuelIX.ps1` script to your local machine.

```powershell
git clone https://github.com/MikeC-I/Invoke-FuelIX.git
cd Invoke-FuelIX
```

### 2. Configuration
Create a `config.json` file in the same directory as the script to store your credentials:

```json
{
    "ApiKey": "YOUR_FUELIX_PROJECT_KEY",
    "Model": "gemini-2.5-flash",
    "ApiFormat": "Auto"
}
```
`ApiFormat` is optional (`Auto`, `Messages` or `ChatCompletions`; defaults to `Auto`).

*Alternatively, set a system environment variable (API key only):* `$env:FUELIX_API_KEY = "your_key"`.

**Resolution order** for API key and model: explicit parameter → `config.json` → `$env:FUELIX_API_KEY` (API key only) → default model (`fuelix-default-model`). `ApiFormat` resolves: parameter → `config.json` → `Auto`. The script throws if no API key can be found.

### 3. Usage

**Pipeline usage (Automation):**
```powershell
"Convert this CSV data to JSON: Name, Age `n John, 30" | .\Invoke-FuelIX.ps1 | Out-File data.json
```

**Direct Command:**
```powershell
$response = .\Invoke-FuelIX.ps1 -Prompt "What are the top 3 features of PowerShell 7?"
```

**Interactive Chat:**
```powershell
.\Invoke-FuelIX.ps1 -Interactive
```

**Choose a model, format, and response length:**
```powershell
.\Invoke-FuelIX.ps1 -Prompt "Summarize this" -Model "claude-sonnet-5-5" -MaxTokens 8192
.\Invoke-FuelIX.ps1 -Prompt "Hello" -Model "gpt-5" -ApiFormat ChatCompletions -Verbose
```

---

## 🛠 Parameters

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `-Prompt` | `String` | The text input for the AI. Supports Pipeline input. |
| `-Interactive` | `Switch` | Starts a stateful chat session in the console. |
| `-ConfigPath` | `String` | Custom path to your JSON config (Defaults to `config.json` in the script folder). |
| `-ApiKey` | `String` | Manually provide API key (Overrides config/env). |
| `-Model` | `String` | Specify model (e.g., `gemini-2.5-pro`). Overrides config. |
| `-MaxTokens` | `Int` | Maximum tokens in the response (default `4096`). Sent only for the Messages format, where it is required. |
| `-ApiFormat` | `String` | `Auto` (default), `Messages` (`/v1/messages`, Anthropic format) or `ChatCompletions` (`/v1/chat/completions`, OpenAI format). Auto picks Messages when the model name contains `claude` or `anthropic`, otherwise ChatCompletions. |

`-Prompt` and `-Interactive` are mutually exclusive.

---

## 🔧 Troubleshooting

* **Unauthorized (401):** Ensure your API key is correct in `config.json` or your environment variables.
* **Model Not Found:** Ensure the model string matches the FuelIX model naming conventions.
* **Wrong endpoint / unexpected response shape:** Run with `-Verbose` to see which endpoint and format are used, and override with `-ApiFormat` if auto-detection picked the wrong one.
* **Request failed:** The error output includes the HTTP status and response body from the API to help diagnose the problem.
* **Execution Policy:** If the script won't run, try: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`.

---

### License
Distributed under the MIT License. See `LICENSE` for more information.
