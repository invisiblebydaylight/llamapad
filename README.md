# llamapad (v0.3.0)

A native MacOS and iOS chat application for local LLM inference, built on top of [llama.cpp](https://github.com/ggml-org/llama.cpp/) and [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm). Everything runs on-device. The app is sandboxed with access only to the files you select. Network access is optional and only used for features you explicitly enable (Currently: Text-to-Speech setup). No microphone use.

Features conversation management, Jinja template support, text-to-speech
and a privacy-first design philosophy.

<a href="./screenshots/main_interface.png">
    <img src="./screenshots/main_interface.png" style="max-width: 800px;" alt="The main chat interface">
</a>

The main chat window has a message bubble style with a collapsable view of the 'thinking'
output of reasoning models. There's a simple 'trash' button to clear the log and a 'gear' button
to show the configuration options. 

<a href="./screenshots/interface_explained.png">
    <img src="./screenshots/interface_explained.png" style="max-width: 800px;" alt="The main chat interface">
</a>

The options window has several tabs. The first one hold options related to the LLM model itself.
In the screenshot, you can see basic controls for the model and sampler, but when the advanced settings
expand, there are multiple penalty types as well as basic DRY and XTC support.

<a href="./screenshots/options.png">
    <img src="./screenshots/options.png" style="max-width: 800px;" alt="The basic configuration options">
</a>

The voice tab shows shows the options for text-to-speech. In order to see the 'speak' 'button next to messages
when hovering over them, you have TTS enabled. If auto-play is enabled, as soon as the AI message
finishes generating it will attempt to speak it out loud using TTS.

<a href="./screenshots/options_tts.png">
    <img src="./screenshots/options_tts.png" style="max-width: 800px;" alt="The text-to-speech configuration options">
</a>


## Features
* Embedded [llama.cpp](https://github.com/ggml-org/llama.cpp/) library for native text generation.
* Embedded [MLX](https://github.com/ml-explore/mlx-swift-lm) library for native Apple Silicon support.
* AI chat interface with customizable sampler settings and basic model configuration options.
* Text-to-speech support for AI messages, including an auto-play mode to automatically speak the generated messages.
* Edit, regenerate, delete, continuation and generation of new responses are all supported.
* Simple, but effective use of the KV cache to keep prompt processing to a minimum for GGUF models.
* Basic conversation based workflow, supporting many chatlogs.
* Jinja support for prompt formatting using the [swift-jinja](https://github.com/huggingface/swift-jinja) library.


### Recent changes (newer to older):
* Support for TTS has been changed to the [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) library, which supports a number of TTS engines. This means that support for multiple engines will be enabled. Currently there is: Kokoro and Qwen3-TTS.
* Support for MLX models has landed! It might still be rough around the edges as it's a new backend. To support having a new backend implementation, a common protocol has been developed and utilized.
* Performance metrics are now recorded for each message and shown on mouse hover (macOS) or swipe (iOS).
* Added Gemma-4 thinking tag delimiter detection as well as the `[think]` and `[/think]` tags some Mistral models use.
* Lazy-loading the model is now supported. LLMs no longer load automatically on application startup. A Load/Eject
  button has been added next to the config button to manually control the behavior, otherwise the configured
  model is loaded when the user sends a message, generates a response or regenerates an existing one.
* KV cache quantization now supported and settings can be found in the 'Advanced' group of the Model config tab.
* Embedded [swift-jinja](https://github.com/huggingface/swift-jinja) to use embedded Jinja templates
  for prompt construction if possible; still can override to built-in templates from llama.cpp...
* Conversations can be created, renamed, duplicated and deleted.
* System message is now in conversation metadata.
* Multiple conversation support which includes turning the 'chatlog' concept
  from single-file to folder-structure with multiple files.
* KV cache optimizations for chatting to minimize delays from prompt ingestion.


## How To Install

Start by cloning the repository and then making sure that the submodule for [llama.cpp](https://github.com/ggml-org/llama.cpp/)
is updated. Once the source code is there and up-to-date, change to the `llama.cpp` directory and use the
built in script to build the apple frameworks required by the Xcode project.

```bash
git clone --recurse-submodules https://github.com/invisiblebydaylight/llamapad.git
cd llamapad/llama.cpp
./build-xcframework.sh
cd ..
```

Now you can open up the `LlamaPad.xcodeproj` file in Xcode and run it. When attempting to deploy it to
something like an iPad, you may have to change your Signing credentials for the project before it builds
and runs on the target device.

### Text-to-Speech Setup

#### Kokoro
Clone or download from [mlx-community/Kokoro-82M-bf16](https://huggingface.co/mlx-community/Kokoro-82M-bf16). Voice names are short identifiers like `af_heart`, `af_bella`, `am_adam`. See the [Kokoro voices list](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/voices/VOICES.md) for options. For language, use a two letter code like "en".

Kokoro requires a one-time network download of G2P support files (~5MB). Enable TTS in configuration and generate speech once with Internet access. After caching, TTS works offline.

#### Qwen3 TTS
This family of TTS models comes in different variants:

**Base - ** [mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit) - Simple TTS with built in voice.

**Custom - ** [mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16) - Supports named speakers (Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee) with style prompting.

**Voice Designer - ** [mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16) - Voices are based on descriptive prompts:

| Example Prompt | Result |
|----------------|--------|
| `A cheerful young female voice with high pitch and energetic tone.` | Animated, bright delivery |
| `A calm male voice with moderate depth and a measured, thoughtful delivery.` | Grounded, intelligent sound |
| `A grounded male voice with warm resonance and a steady, unhurried pace.` | Warm, reassuring tone |



## Known Limitations

* Using quantized KV cache instead of F16 may cause problems with flash attention on some models.
* If you want to get wild and crazy with your Mac and increase the amount of memory usable
  by Metal, you can run a command like this (which sets the limit to 20GB) to boost your upper limit:
  `sudo sysctl iogpu.wired_limit_mb=20480`
* If you're really pushing the memory limit of your device with the LLM, it's possible that
  you'll get errors when trying to use TTS and the error message will have a coreaudio exception.
  There are currently no guard rails on what size models you can load; with great power
  comes great responsibility.


## Future Goals

Eventually, if interest continues, this application will get more features developed to make it
a more robust experience:

* Tool call support ; MCP support
* Backend expansion into remote OpenAI-compatible API endpoints for extra flexibility.
* Paralizable, batched requests that might be useful for behind-the-scenes agent stuff.
* Multimodal input to send images to vision models and handle speech-to-text as well as text-to-speech.
* Maybe even more inventive things like visualizing token logits at each step for illustration purposes
  or memory systems.


## Simple Developer Example

The ['simple-example' branch](https://github.com/invisiblebydaylight/llamapad/tree/simple-example) 
consists of the version of this application that is essentially like a minimum viable product for AI chatting:
it has the scrollable chat bubble history, the input widgets, the basic model and sampler configuration
and all the bits required to use [llama.cpp](https://github.com/ggml-org/llama.cpp/) as the embedded
text inference engine so that users just need this app and a GGUF file of their choosing.

It was branched off of 'main' before any major development on non-essential features started to
keep a simple focus on just providing AI chatting functionality.


## Dev Dependencies
* [llama.cpp](https://github.com/ggml-org/llama.cpp/) is used as the primary AI inference engine.
* [swift-jinja](https://github.com/huggingface/swift-jinja) is used as the embedded Jinja parser.
* [MarkdownView](https://github.com/LiYanan2004/MarkdownView.git) to render chat as markdown.
* [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) is used for text-to-speech synthesis.
* [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) for MLX language model support.


## Implementation Notes

### KV Cache & Context Anchoring
To maintain high performance, LlamaPad uses an "anchored" window strategy. 
- The `reservedContextBuffer` defines the minimum headroom kept for AI generation and thinking.
- When the context usage exceeds `contextLength - reservedContextBuffer`, the window "slides" forward.
- **The Runway Effect:** To prevent frequent, costly prompt re-ingestion, the window doesn't just slide by one message; it slides far enough to create a "runway" equal to the `contextRunway` amount. This means you will see a significant drop in context usage when the anchor moves (`reservedContextBuffer` + contextRunway), providing space for several turns of uninterrupted discourse.
- MLX context handling differs from llama.cpp. While the llama.cpp backend uses an anchored window with runway to minimize KV cache regeneration, the MLX backend only truncates older mesages to fit and re-ingests the entire promopt on each generation.

### iOS and macOS
* The `Increased Memory Limit` capability has been added to load models greater than 4GB in size.
* The configuration and chatlog are saved in the app's application support directory on macOS, is something like: 
  `/Users/<USER>/Library/Containers/LlamaPad/Data/Library/Application Support/com.invisiblebydaylight.LlamaPad/`
* Metal was really obnoxious about not releasing memory no matter how long the app sleeps after freeing the model,
  context and sampler. Turns out, adding a dummy GPU operation using MLX forced a synchronization point, clearing
  the Metal command queue which caused the memory to *actually* be released.


## License

MIT Licensed
