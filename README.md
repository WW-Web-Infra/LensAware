# LensAware

An iOS companion app for Meta Ray-Ban smart glasses that turns what you see into spoken, actionable context — nutrition coaching, QR scanning, text reading, and custom AI-powered profiles via any external API.

## Overview

LensAware streams video from Meta Ray-Ban glasses and runs it through a configurable **Trigger → Action → Response** pipeline. Each profile defines what to look for, what to do with it, and how to respond — spoken aloud through the glasses.

## Features

### System Profiles
| Profile | What it does |
|---|---|
| **Health** | Detects food, estimates calories and macros, monitors ergonomics, coaches mindful eating |
| **QR Scanner** | Decodes QR codes and reads URLs aloud |

### Custom Profiles
Create your own profiles in 4 steps — name, trigger, action, tone.

**Triggers**
- **Full scene** — AI understands everything in frame
- **QR codes** — instant offline decoding
- **Text only** — reads visible text via on-device OCR

**Actions**
- **Read it aloud** — LLM describes what it sees for your profile
- **Look up a URL** — fetches content from a configured web endpoint
- **Search my catalogue** — matches against a local JSON dataset you upload
- **Call my API** — sends the image to any external REST API and speaks the response

**Call my API** supports:
- `base64_json` — image as base64 + query in a JSON body (OpenAI, Claude, Gemini, custom backends)
- `multipart` — binary multipart upload (PlantNet, traditional ML APIs)
- JSONPath `response_key` for nested responses, e.g. `results[0].species.commonNames[0]`

**Tones** — Coach, Alert

## Example: Floral Detection with PlantNet

Create a custom profile with:
```
Trigger:        Full scene
Action:         Call my API
Endpoint:       https://my-api.plantnet.org/v2/identify/all?api-key=YOUR_KEY&lang=en&include-related-images=false
Image format:   Multipart
Image field:    images
Response path:  results[0].species.commonNames[0]
```

The glasses will speak the plant name when one is detected.

## Requirements

- iOS 17+
- Meta Ray-Ban glasses (Ray-Ban Stories or Meta smart glasses)
- Meta AI app installed with Developer Mode enabled
- Xcode 16+ with Swift 6

## Setup

### 1. Clone and generate the Xcode project

```bash
git clone <repo>
cd LensAware
brew install xcodegen
xcodegen generate
```

### 2. Add API keys

```bash
cp LensAware/Config.plist.example LensAware/Config.plist
```

Open `LensAware/Config.plist` and replace `YOUR_GEMINI_API_KEY` with your key.

Get a free Gemini API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).

> `Config.plist` is in `.gitignore` and will never be committed. Do not commit it.

### 3. Connect glasses

1. Enable Developer Mode in the Meta AI app (Settings → Developer Mode)
2. Build and run LensAware on a physical iPhone
3. Tap **Connect Glasses** and follow the registration flow

## Architecture

```
Meta Ray-Ban Glasses
    ↓ DAT SDK (MWDATCore + MWDATCamera)
CameraStreamManager         — streams frames at 15 FPS, dispatches 1 frame every 3s
    ↓
HealthDetectionManager      — loads active profile, runs deduplication (30s window)
    ↓
RulesEngine                 — routes by triggerType and datasetType
    ├── handleVisionAI       — system Health profile via Gemini 1.5 Flash
    ├── handleCustomVisionAI — custom profiles: cloudAPI or LLM
    ├── handleQR             — Vision framework QR detection
    └── handleOCR            — Vision framework text recognition
    ↓
ResponsePlayer              — speaks results via AVSpeechSynthesizer over glasses audio
```

**Services**
- `ClaudeVisionService` — Gemini 1.5 Flash for structured health analysis and freeform profile descriptions
- `APILookupService` — generic HTTP client supporting base64 JSON and multipart image uploads with JSONPath response parsing
- `QRScannerService` — Vision framework QR detection with URL fetch, local catalogue, and API lookup
- `OCRService` — Vision framework text recognition (`VNRecognizeTextRequest`, accurate mode)
- `DatabaseManager` — SQLite3 persistence for profiles, rules, meal records, ergonomic events, QR scans

**Key design decisions**
- System profiles identified by stable UUID, not `isSystem` flag
- `RulesEngine` is `@MainActor final class`, not an actor — safe shared mutable state
- `frame.makeUIImage()` called synchronously before entering `Task` (DAT SDK requirement)
- New Swift files require 4 entries in `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase)

## Supported API Config Keys

For `Call my API` profiles, the `datasetConfigJSON` supports:

| Key | Description | Default |
|---|---|---|
| `endpoint` | Full URL including any query params | required |
| `auth_header` | Value for the `Authorization` header | none |
| `image_format` | `base64_json` or `multipart` | `base64_json` |
| `image_field` | Field name for the image | `image` |
| `response_key` | JSONPath to the response string, e.g. `choices[0].message.content` | none |

**JSONPath examples**

| API | `response_key` |
|---|---|
| OpenAI | `choices[0].message.content` |
| Anthropic Claude | `content[0].text` |
| Google Gemini | `candidates[0].content.parts[0].text` |
| PlantNet | `results[0].species.commonNames[0]` |
| AWS Rekognition | `Labels[0].Name` |

## Multi-tenancy

Every profile and rule carries a `tenantId`. The database schema is tenant-scoped throughout, making LensAware ready for multi-user or white-label deployments.

## License

MIT — see [LICENSE](LICENSE).
