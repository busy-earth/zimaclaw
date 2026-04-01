# Zimaclaw Transcript Analysis
### Actionable Technical Insights Extracted from 6 Video Transcripts

**Zimaclaw architecture:**
```
XMPP (listen) → Zig orchestrator (steer/drive) → Pi RPC over stdin/stdout (drive) + emacsclient --eval (steer) → NixOS
```

---

## 01 — XMPP on NixOS (Tony)
**Source:** [XMPP is the End Game of Chat Protocols (2027 Edition)](https://youtu.be/XwMWUZYUTvM)

### Exact NixOS Prosody configuration

```nix
# Variables at top of xmpp.nix
let
  domain     = "xmpp.yourdomain.com";
  mucDomain  = "conference.${domain}";
  uploadDomain = "upload.${domain}";
in {

  services.prosody = {
    enable = true;

    # Admin account (declarative)
    admins = [ "admin@${domain}" ];

    # Global SSL — points to ACME-managed certs
    ssl = {
      cert = "/var/lib/acme/${domain}/fullchain.pem";
      key  = "/var/lib/acme/${domain}/key.pem";
    };

    # HTTP file sharing (100 MB limit)
    httpFileshare = {
      domain          = uploadDomain;
      uploadFileSizeLimit = 100 * 1024 * 1024;
    };

    # Multi-user chat
    muc = [{
      domain              = mucDomain;
      name                = "Chat rooms";
      restrictRoomCreation = false;
    }];

    # Virtual host
    virtualHosts."${domain}" = {
      enable = true;
      domain = domain;
      ssl = {
        cert = "/var/lib/acme/${domain}/fullchain.pem";
        key  = "/var/lib/acme/${domain}/key.pem";
      };
    };

    # Modules
    modules = {
      roster   = true;   # contact lists
      sasl     = true;   # authentication
      tls      = true;   # encryption
      dialback = true;   # server-to-server verification
      disco    = true;   # service discovery
      carbons  = true;   # multi-device message sync
      pep      = true;   # personal eventing (avatars, status)
      mam      = true;   # message archive management / history
      ping     = true;   # keepalives
      admin_adhoc = true; # admin commands via XMPP
      http_files  = true; # file upload
    };

    # Disable open registration — create accounts manually
    allowRegistration = false;
  };
```

### Shared cert group
```nix
  users.groups.certs.members = [ "prosody" "nginx" ];
```

### ACME configuration
```nix
  security.acme = {
    acceptTerms = true;
    defaults.email = "you@yourdomain.com";

    certs."${domain}" = {
      group      = "certs";
      webroot    = "/var/lib/acme/acme-challenge";
      postRun    = "systemctl reload prosody";
      extraDomainNames = [ mucDomain uploadDomain ]; # single cert covers all 3 domains
    };
  };
```

### nginx configuration (for ACME challenge only)
```nix
  services.nginx = {
    enable = true;
    virtualHosts."${domain}" = {
      locations."/.well-known/acme-challenge".root = "/var/lib/acme/acme-challenge";
      locations."/".return = "404"; # not a real website
    };
  };
```

### Firewall ports
```nix
  networking.firewall.allowedTCPPorts = [
    80    # ACME HTTP challenge
    443   # HTTPS file uploads
    5222  # XMPP client connections (C2S)
    5269  # XMPP server federation (S2S)
    5281  # Prosody HTTP upload port
  ];
```

### Account creation (CLI)
```bash
# After nixos-rebuild switch:
sudo prosodyctl adduser test@xmpp.yourdomain.com
# Prompts for password interactively
```

### Rebuild command
```bash
sudo nixos-rebuild switch --flake /path/to/nixos#hostname
```

### Key architectural properties for Zimaclaw
- **No content caching from other servers** — MUC history stays on the server hosting the room only. Ideal for a single-device claw that must never store foreign content.
- **Lightweight enough to run on 1990s hardware** — Pi Zero / minimal NixOS machine is sufficient.
- **Matrix bridge available** — Tony shows bridging XMPP ↔ Matrix rooms, meaning Zimaclaw could bridge to Matrix if needed without changing the XMPP listen layer.
- **Gajim** is the recommended desktop client; for a headless server only the Prosody daemon is needed.

---

## 02 — NixOS From Scratch (Tony)
**Source:** [How to Install NixOS From Scratch (2026 Edition)](https://youtu.be/2QjzI5dXwDY)

### flake.nix structure

```nix
{
  description = "nixos-from-scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs"; # prevents HM pulling its own nixpkgs → avoids mismatched package sets
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    nixosConfigurations."nixos-btw" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix

        home-manager.nixosModules.homeManager {
          home-manager = {
            useGlobalPkgs   = true;
            useUserPackages = true;

            # *** THE backup-file-extension TRICK ***
            # When HM downloads a config and one already exists on disk,
            # instead of crashing it renames the old file to *.backup.
            # Critical during first-run or migration.
            backupFileExtension = "backup";

            users.tony = import ./home.nix;
          };
        }
      ];
    };
  };
}
```

### `backup-file-extension` trick
Setting `home-manager.backupFileExtension = "backup"` prevents `home-manager switch` from aborting when a target config file already exists on the filesystem. Instead of crashing it renames the conflicting file to `<name>.backup`. Essential for first installs and migration to home-manager management.

### Home-manager integration pattern
Home-manager is embedded **inside** the flake outputs as a NixOS module (`home-manager.nixosModules.homeManager`), not as a standalone tool. This means `nixos-rebuild switch` rebuilds both system and user configs atomically.

### System-level vs home-manager package split
| Layer | What goes there | Example from transcript |
|---|---|---|
| `configuration.nix` (`environment.systemPackages`) | System-wide, needed before login, or shared across users | `vim`, `git`, `alacritty`, `firefox` |
| `home.nix` (`programs.*` / `home.packages`) | Per-user config + dotfiles | `programs.git.enable`, `programs.bash` with aliases |

Tony puts `firefox` at the system level for simplicity during initial install, then migrates to home-manager after first boot.

### Font installation pattern
```nix
# In configuration.nix — system level
fonts.packages = with pkgs; [
  nerd-fonts.jetbrains-mono
];
```

### Experimental features enabling
```nix
# In configuration.nix
nix.settings.experimental-features = "nix-command flakes";
```
Both `nix-command` (enables `nix flake update`, etc.) and `flakes` must be listed together.

### Baseline minimal home.nix
```nix
{ config, pkgs, ... }: {
  home.username      = "tony";
  home.homeDirectory = "/home/tony";
  home.stateVersion  = "25.05";

  programs.git.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      btw = "echo I use nixos btw"; # sanity check alias
    };
  };
}
```

### Installation command
```bash
nixos-install --flake /mnt/etc/nixos#nixos-btw
```

### Disk partitioning reference (for NixOS on Pi / minimal hardware)
```
Partition 1: 1G  — EFI system (mkfs.fat -F 32)
Partition 2: 4G  — Linux swap (mkswap)
Partition 3: rest — Linux ext4 root (mkfs.ext4)
```

### Zimaclaw implications
- Flakes pin the entire dependency graph to a specific nixpkgs commit — reproducible Pi builds.
- `backupFileExtension` is a must-have when first deploying home-manager onto a live system.
- The pattern of embedding HM inside `nixosConfigurations` rather than using `homeConfigurations` means one `nixos-rebuild switch` manages everything — cleaner for a claw device that should be fully declarative.

---

## 03 — The Final Linux Rabbit Hole (Joshua)
**Source:** [the final linux rabbit hole...](https://youtu.be/nUaIr9GoCDI)

### Literate config approach — single readme.org tangled into modules

Joshua's entire NixOS configuration lives in one file: `readme.org` (~2,300 lines). All NixOS module files in `modules/` are **tangled** from that single org file.

```
nixos-config/
├── readme.org              ← single source of truth; everything tangled from here
├── configuration.nix       ← imports all modules
├── hardware/
│   ├── theological.nix     ← per-machine hardware override
│   └── ...
└── modules/
    ├── programs.nix        ← desktop apps
    ├── cli-tui.nix         ← terminal tools
    ├── emacs.nix           ← Doom Emacs + dotfiles
    ├── browsers.nix        ← Firefox + extensions
    ├── dev.nix             ← language toolchains
    └── theming.nix         ← colors, fonts
```

The literate config gives: (1) self-documenting config, (2) one commit = one source of truth, (3) tangle generates files on demand.

### `mkOutOfStoreSymlink` pattern (GNU Stow replacement)

The standard home-manager approach copies dotfiles into the Nix store and symlinks them. This means you must run `home-manager switch` to see config changes.

`mkOutOfStoreSymlink` creates a symlink that points **directly to the file in the repo**, bypassing the Nix store:

```nix
# In home.nix
home.file.".config/doom".source =
  config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos-config/modules/doom";
```

**Result:** Edit a file in `~/nixos-config/modules/doom/`, changes appear immediately in `~/.config/doom/` — no `home-manager switch` needed. This is the NixOS-native GNU Stow equivalent.

### Module organization

| Module | Contents |
|---|---|
| `programs.nix` | GUI desktop apps used daily |
| `cli-tui.nix` | Terminal/TUI tools (ripgrep, fzf, etc.) |
| `emacs.nix` | Doom Emacs config; symlinked via `mkOutOfStoreSymlink` |
| `browsers.nix` | Firefox + declarative extensions |
| `dev.nix` | Language toolchains (largely replaced by devenv per-project) |
| `theming.nix` | GTK/Qt theme, fonts, cursor |

All machines share the same module set but have different `configuration.nix` imports for hardware.

### devenv / direnv for per-project dev shells

```nix
# devenv.nix inside a project
{ pkgs, ... }: {
  packages = [ pkgs.air pkgs.tailwindcss pkgs.nodePackages.clean-css ];

  env.DATABASE_URL = "...";  # loaded from age-encrypted secrets

  scripts.dev.exec = ''
    air & tailwindcss -w & ...
  '';
}
```

`direnv` + `devenv` means: `cd` into a project directory → environment activates automatically → leave → gone. No global pollution. Per-project shells are ephemeral and fully declarative.

### Secrets management with age

```bash
# Encrypt a secret
age -e -r <recipient-pubkey> -o secret.age plaintext

# Decrypt at devenv activation time — exposed as env var inside the shell
```

Age-encrypted secrets can be version-controlled (they are ciphertext). Joshua's Go tool (`go-secrets`) wraps age for project secret management and can be run from any machine via `nix run github:jblais493/go-secrets`.

### Firefox plugin management via home-manager

```nix
# In browsers.nix
programs.firefox = {
  enable = true;
  profiles.default = {
    extensions.packages = with pkgs.firefox-addons; [
      ublock-origin
      bitwarden
      # ...
    ];
  };
};
```

Extensions are installed declaratively — no manual visit to addons.mozilla.org needed on new machines.

### How dotfiles live inside the Nix repository

Doom Emacs config lives at `nixos-config/modules/doom/`. `mkOutOfStoreSymlink` points `~/.config/doom` there. Any edit to a file in the repo is immediately live. Git commit captures the change. Result: dotfiles, NixOS config, and secret management are all in one repository.

### Zimaclaw implications
- Literate org config is ideal for Zimaclaw's `readme.org` as the single spec + implementation document.
- `mkOutOfStoreSymlink` for the Zig orchestrator source and Pi config means edits to the live claw are immediately effective — no rebuild cycle for config changes.
- devenv/direnv is the right pattern for Pi's per-project coding contexts — Zimaclaw could activate a project shell before handing the Pi agent a task.
- Age secrets integration means API keys and credentials can be declaratively managed and version-controlled safely.

---

## 04 — Emacs is my Computer (Joshua)
**Source:** [Emacs is my COMPUTER now...](https://youtu.be/n5VMWuxLi10)

### Emacs as the computing surface — why it replaces the GUI

Joshua's thesis: **Emacs buffers ARE the screen.** Every application function (email, RSS, music, files, passwords, calendar, web search, terminal) becomes an Emacs buffer. Context switching disappears — everything is one keymap, one environment, one composable surface.

The key insight quoted from the HackerNews thread: *"The more I learn about Emacs, the more I feel we took the wrong fork in the road in terms of the desktop metaphor decades ago."* Joshua agrees: Emacs is the closest thing to a truly integrated computing environment.

For Zimaclaw: **`emacsclient --eval` becomes the steer layer** — the Zig orchestrator can evaluate arbitrary Elisp in the running Emacs instance, giving it full programmatic access to all Emacs capabilities (file management, org-capture, mu4e email, elfeed, etc.).

### Why NOT EXWM (single-threaded hang risk)

Two reasons:
1. Wayland/Hyperland is where Linux window management is moving. EXWM is X11 only.
2. **Emacs is single-threaded.** Using it as the window manager means any blocking operation (RSS fetch, large file load, LLM response) hangs the entire WM. Even updating an elfeed feed can cause a freeze.

The workaround some users suggest: FIFO queues + keyboard macros executed on the Emacs side, with Hyperland as a thin client. Joshua hasn't implemented this yet but considers it interesting.

**Zimaclaw implication:** Never use EXWM. Use `emacsclient --eval` from Zig instead — this keeps the Zig orchestrator as the WM-equivalent, with Emacs as a powerful buffer-server, not the window manager itself.

### emacsclient usage patterns

Joshua **never launches a new Emacs instance for work.** Emacs starts at system boot (loaded in the systemd user session or Hyperland startup). All interaction goes through `emacsclient`:

```bash
emacsclient -e '(org-capture nil "t")'         # capture a task from anywhere
emacsclient -e '(mu4e)'                          # open email
emacsclient -e '(dired "~/projects")'            # open file browser
emacsclient -e '(elfeed)'                        # open RSS reader
emacsclient -e '(emms-play-directory "~/music")' # start music
emacsclient --create-frame                        # create a new visible frame
```

For Zimaclaw: the Zig orchestrator calls `emacsclient --eval <elisp>` to steer the computing surface. This replaces the Swift accessibility-tree approach from the Mac Mini agent.

### Workspace management

| Workspace | Contents |
|---|---|
| 1 | Emacs — always, exclusively |
| 2 | Firefox |
| Others | Terminals, other apps as needed |

Hyperland keybind `Alt+Space` → brings focus back to workspace 1 (Emacs) from anywhere. This workspace discipline means the steer layer always knows where Emacs lives.

### Go-based launcher script for system calls to Emacs

Joshua replaced individual bash scripts with a compiled Go binary that makes `emacsclient` system calls:

```go
// Hyperland config references compiled binary:
// bind = ALT, SPACE, exec, /home/joshua/.local/bin/emacs-launcher switch-to-emacs
// bind = CTRL SHIFT, C, exec, /home/joshua/.local/bin/emacs-launcher org-capture
// bind = ALT, P, exec, /home/joshua/.local/bin/emacs-launcher password-store
// bind = ALT, F, exec, /home/joshua/.local/bin/emacs-launcher dirvish
// bind = ALT, E, exec, /home/joshua/.local/bin/emacs-launcher vterm
```

The Go binary wraps `emacsclient --eval` calls. Motivation: bash scripts were slow (~visible lag); the compiled Go binary is fast enough to feel instantaneous. ~700 lines of Go.

**Zimaclaw implication:** The Zig orchestrator is the exact equivalent — a compiled binary that calls `emacsclient --eval`. Zig is better than Go for this because it has no runtime, compiles to a tiny binary, and has direct POSIX syscall access.

### org-capture from anywhere in the system

```bash
# From any workspace, any application:
Ctrl+Shift+C  →  emacsclient -e '(org-capture nil "t")'
```

This opens an org-capture buffer in Emacs workspace 1, captures the note/task, and returns focus to wherever the user was. Works across all workspaces.

**Zimaclaw implication:** The XMPP listener can trigger `emacsclient -e '(org-capture nil "t")'` to let a remote human inject a task into the Emacs agenda from XMPP, without being physically at the machine.

### mu4e, elfeed, EMMS, Dired/Dirvish, password store

| Tool | Emacs package | Hyperland keybind | emacsclient call |
|---|---|---|---| 
| Email | mu4e | (custom) | `(mu4e)` |
| RSS | elfeed | Ctrl+Alt+Z | `(elfeed)` |
| Music | EMMS | (custom) | `(emms-play-directory ...)` |
| Files | Dirvish (Dired wrapper) | Alt+F | `(dirvish)` |
| Passwords | password-store.el | Alt+P | `(password-store-copy ...)` |
| Calendar | org-agenda | (custom) | `(org-agenda)` |

Joshua prefers Dirvish over plain Dired because it shows image previews in the file browser. All of these are accessible to the Zimaclaw orchestrator via `emacsclient --eval`.

### The key insight: "Emacs buffers ARE the screen"

> "Emacs allows you to kind of just create. It gets out of your way once it's become this instrument that you just know how to use."

When Emacs handles email, files, music, RSS, calendar, and notes, the agent steer layer (`emacsclient --eval`) has programmatic access to **all of those things** through a single interface. There is no need for GUI automation (accessibility trees, OCR, screen coordinates) — just Elisp function calls.

---

## 05 — Pi Coding Agent (IndyDevDan)
**Source:** [The Pi Coding Agent: The ONLY REAL Claude Code COMPETITOR](https://youtu.be/f8cfH5XX-XU)

### Pi agent overview

Pi is an open-source, minimalist agent harness created by Mario Zechner. It provides the agent loop — you customize everything else. Default system prompt: ~200 tokens (vs Claude Code's ~10,000). Default tools: `read`, `write`, `edit`, `bash`. No built-in sub-agent support — you build that yourself.

Pi powers OpenClaw, previously MaltBot, and previously ClawBot.

### Pi customization surface: system prompts, tools, hooks, themes, widgets

```
Customizable elements:
├── System prompt        — override the 200-token default; append purpose/context
├── Tools                — register custom tools callable during the agent loop
├── Hooks (25+)          — tap into agent lifecycle events
│   ├── on_input         — intercept user input (used for till-done blocking)
│   ├── on_tool_call     — intercept before any tool runs
│   ├── on_agent_end     — run after agent completes a turn
│   └── on_session_*     — session start/end
├── Widgets              — persistent UI panels that stick in the terminal session
├── Footer/status line   — customizable bottom bar (model, context window, tool counter, etc.)
├── Themes               — full color/style control; IndyDevDan ships 13 custom themes
├── Key bindings         — register custom keyboard shortcuts (e.g., Ctrl+X for theme cycle)
└── Extensions           — TypeScript modules that compose all of the above
```

Extensions are TypeScript files (~700 lines for complex ones). They are stacked: `pi -e extension1.ts -e extension2.ts`.

### Pi's 25+ hooks

Key hooks used in the transcript:

| Hook | Used for |
|---|---|
| `on_input` | Block `ls` until a to-do item exists (till-done extension) |
| `on_tool_call` | Count tool calls; block dangerous commands (damage-control extension) |
| `on_agent_end` | Collect sub-agent results into primary agent |
| `on_session_start` | Ask user for agent purpose (purpose-gate extension) |

The full hook list is in Pi's TypeScript SDK. IndyDevDan notes: "Pi has a lot more plug-in points than Claude Code."

### Multi-agent orchestration patterns

Pi has **no built-in sub-agent support** — everything must be built via extensions. IndyDevDan demonstrates:

**1. Sub-agent widget (parallel workers)**
```
/sub <prompt>    → spawns a new Pi instance with that prompt
                 → result collected by primary agent
/sub clear       → dismiss a sub-agent
```

**2. Agent teams (specialized roles)**
```yaml
# teams.yaml
teams:
  - name: scout-plan-build-review
    agents: [scout, planner, builder, reviewer]
  - name: plan-build
    agents: [planner, builder]
```
Primary agent dispatches to named agents: scout → find info → pass to builder.

**3. Agent chains / pipelines**
Three scouts chained: scout1 output → scout2 input → scout3 input → primary agent. Sequential refinement.

**4. Meta-agent**
8 domain-expert agents (one per Pi customization domain) orchestrated by a single meta Pi agent. The meta agent queries experts in parallel and synthesizes their answers into new Pi agent configs.

### The "80% Claude Code / 20% Pi" strategy

> "Bet big on the leader (Claude Code), but hedge with open source. 80% Claude Code, 20% Pi for deep customization, experimental next-gen agentic coding, and multi-agent coding workflows. Think in 'ands,' not 'ors.'"

Use Claude Code for standard work. Use Pi when you need: (a) full harness control, (b) any model (Gemini, GPT, local), (c) version pinning without lock-in, (d) experimental multi-agent workflows.

### How Pi handles different models

Pi is model-agnostic. The model is specified at invocation:
```bash
pi --model claude-sonnet-4-6   # Anthropic
pi --model gemini-3-flash       # Google
pi --model gpt-4o               # OpenAI
pi --model glm-5                # Zhipu
pi --model claude-haiku-3-5     # cheap/fast for subtasks
```
No code changes needed — just change the flag. This is the critical advantage for Zimaclaw: Pi can be told which model to use for which subtask (expensive model for planning, cheap model for file reads).

### Version pinning and forking approach

Pi is open source (GitHub). Options:
1. **Pin a version:** `git checkout v1.2.3` — freeze Pi at a known-good version. A Pi update cannot break your Zimaclaw.
2. **Fork:** Clone Pi repo, add your own extensions to the fork, reference via flake input. Full control.
3. **Pin and forget:** Use Nix to pin the Pi derivation to a specific commit hash.

Recommended: fork Pi, add Zimaclaw-specific extensions (stdin/stdout RPC wrapper, XMPP result reporter), pin in flake.

### Zimaclaw-specific Pi customization

For Zimaclaw, Pi is the **drive** layer. Key customizations needed:

```typescript
// Extension: zimaclaw-rpc.ts
// Wraps Pi in stdin/stdout RPC mode so the Zig orchestrator can drive it

registerHook('on_agent_end', async (result) => {
  // Write result to stdout in structured format for Zig to parse
  process.stdout.write(JSON.stringify({ done: true, result: result.text }) + '\n');
});

registerHook('on_input', async (input) => {
  // Read next instruction from stdin (Zig orchestrator pipe)
  // ...
});
```

The Zig orchestrator spawns Pi as a child process and communicates over stdin/stdout — the "RPC over stdin/stdout" pattern described in Zimaclaw's architecture.

---

## 06 — Mac Mini Agent (IndyDevDan)
**Source:** [Mac Mini Agents: OpenClaw is a NIGHTMARE... Use these SKILLS instead](https://youtu.be/LOazLNQnB80)

### The listen/steer/drive architecture in detail

```
┌─────────────────────────────────────────────────────────┐
│                    TRIGGER LAYER                         │
│  listen: HTTP server (Python) waiting for job requests   │
│  direct: CLI client that POSTs to listen server         │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTP POST (job prompt + params)
                        ▼
┌─────────────────────────────────────────────────────────┐
│                  DEVICE LAYER                            │
│  AI agent (Claude Code) running with two skills:        │
│  ┌──────────────────┐  ┌────────────────────────────┐   │
│  │  STEER SKILL     │  │  DRIVE SKILL               │   │
│  │  Swift app       │  │  tmux wrapper              │   │
│  │  - accessibility │  │  - spin up new terminals   │   │
│  │    tree read     │  │  - send commands to panes  │   │
│  │  - OCR           │  │  - read terminal output    │   │
│  │  - click/type    │  │  - fire off sub-agents     │   │
│  │  - screenshot    │  └────────────────────────────┘   │
│  └──────────────────┘                                    │
└─────────────────────────────────────────────────────────┘
                        │ AirDrop / result file
                        ▼
              Human engineer's device
```

### Listen: HTTP server trigger layer

```python
# apps/listen — Python HTTP server
# Waits for incoming job requests from anywhere on the network
# When a job arrives: spawns a new Claude Code instance in a tmux window
# with the job prompt injected as the initial user message

# direct CLI client sends:
# POST http://mac-mini.local:PORT/job
# { "prompt": "...", "job_id": "uuid" }
```

The listen server is stateless. Each job gets its own tmux window + Claude Code instance. Multiple jobs can run concurrently (separate tmux panes).

**Zimaclaw equivalent:** XMPP client (listen layer). Instead of an HTTP server, the Zig orchestrator listens on an XMPP connection. An incoming XMPP message is a job trigger.

### Steer: Swift app for macOS GUI control

The steer application is a Swift CLI tool that exposes:
- **Accessibility tree** — read the UI element tree of any macOS app
- **OCR** — extract text from screen regions
- **Click** — click at XY coordinates or on accessibility elements
- **Type** — send keystrokes to the focused window
- **Screenshot** — capture proof-of-work images

The agent uses steer as a skill (`steer.md` context file, ~130 lines of instructions):
```
Focus on the target app first.
Then verify the app is focused before clicking.
Use the accessibility tree to find elements by label, not coordinates.
Take a screenshot after every significant action as proof of work.
```

**Zimaclaw equivalent:** `emacsclient --eval` replaces Swift + accessibility tree. Since Emacs is the computing surface, no accessibility tree walk is needed — just call the right Elisp function directly. Example mapping:

| Mac steer action | Zimaclaw emacsclient equivalent |
|---|---|
| Click "compose email" | `(mu4e-compose-new)` |
| Navigate to file | `(find-file "/path/to/file")` |
| Type into buffer | `(insert "text")` |
| Switch app | `(switch-to-buffer "buffer-name")` |
| Take screenshot (proof) | `(screenshot-region ...)` or shell screenshot |

### Drive: tmux terminal automation

```bash
# drive CLI: thin wrapper over tmux
drive new-window "my-task"         # create a new tmux window
drive send-keys "my-window" "ls"   # send a command to a named window
drive capture-pane "my-window"     # read current terminal output
drive kill-window "my-window"      # clean up when done
```

The agent spawns multiple tmux windows to do parallel work. Each window can run an independent coding agent or shell task.

**Zimaclaw equivalent:** Pi RPC over stdin/stdout. Instead of tmux windows, the Zig orchestrator manages Pi process instances. But tmux is still useful for human visibility into what the agent is doing.

### YAML job system for multi-device scaling

```yaml
# jobs/<job-id>.yaml — created automatically per job
job_id: "abc-123"
command: "research macbooks"
prompt: "Research the new Mac devices..."
status: running
device: "mac-mini-local"
started_at: "2026-03-09T10:00:00Z"
```

```bash
# Check job status from anywhere:
direct job abc-123 http://mac-mini.local:PORT
# → returns YAML summary of job
```

The YAML job system means agents can also query job status — `direct job <id>` is just another tool the agent can call. This enables self-monitoring.

**Zimaclaw equivalent:** A simple text/JSON file per job written to disk, readable by both the Zig orchestrator and by `emacsclient --eval` (Emacs can read JSON natively via `json-read`). The XMPP channel is the human-facing status channel.

### "Proof of work" pattern

Every agent task ends with explicit proof:
1. **Screenshots** — captured after each significant action; grouped in a folder
2. **Log files** — hook output written to disk proving hooks fired
3. **Summary document** — TextEdit / markdown doc summarizing all work done
4. **AirDrop** — final deliverable sent to human engineer's device

The spec drives this:
```markdown
# In the job prompt
Deliverables:
- Updated codebase with all hooks implemented
- AirDropped to human's MacBook containing:
  - Screenshots of visual proof for each hook
  - TextEdit document summarizing changes
```

**Zimaclaw equivalent:**
- Screenshots → `scrot` or `import` (ImageMagick) on NixOS
- Summary → org-capture into an org file, or a markdown file
- AirDrop → XMPP file transfer (HTTP upload via Prosody) back to human's XMPP client
- Logs → structured output written by Pi hooks, readable by Zig

### Why OpenClaw is dangerous

IndyDevDan quotes Karpathy on this explicitly:

> "It's a security nightmare. There's so much that can go wrong."

Specific risks:
1. **Aggressive package management** — OpenClaw installs packages without restraint. On NixOS this is less of an issue (imperatively installed packages don't survive rebuild) but Pi running in YOLO mode could still `nix-env -i` things.
2. **Prompt injection** — An XMPP message crafted to contain malicious instructions could hijack the agent. The listen/steer/drive architecture mitigates this by keeping the trigger layer (XMPP) separate from the execution layer (Pi), with the Zig orchestrator as a validation layer between them.
3. **Reckless code generation at scale** — generating vulnerable code that gets deployed.
4. **No ownership understanding** — vibe coding means the operator doesn't know what the agent is actually doing.

Zimaclaw mitigations:
- Zig orchestrator validates/sanitizes XMPP messages before passing to Pi
- Pi runs with explicit tool allowlists (damage-control extension)
- NixOS rebuild required to make system-level changes permanent
- All Pi actions logged for post-hoc audit

### "Agentic engineering = knowing what agents do so well you don't have to look"

> "Agentic engineering is knowing what your agents are doing so well you don't have to look. Vibe coding is not knowing and not looking."

The practical implication for Zimaclaw: every Pi action should be observable. The Zig orchestrator should log all `emacsclient` calls and Pi stdin/stdout exchanges. The XMPP channel is the human-readable summary of what happened.

### The just-file command runner pattern

```bash
# justfile (alias: j = just)
send prompt url:
    direct start {{url}} "{{prompt}}"

job id url:
    direct job {{id}} {{url}}

listen:
    python apps/listen/main.py

# Usage:
j send "research MacBooks" http://mac-mini.local:8080
j job abc-123 http://mac-mini.local:8080
j listen
```

`just` is a command runner (like make but without build semantics). Commands can call other commands — `send` calls `direct`. Just-files accumulate all operational workflows for the system.

**Zimaclaw equivalent:** A `justfile` at the root of the nixos-config repo:
```bash
# justfile
rebuild:
    sudo nixos-rebuild switch --flake .#zimaclaw

xmpp-adduser user:
    sudo prosodyctl adduser {{user}}@xmpp.yourdomain.com

agent-send prompt:
    # Send a job prompt to the Zig orchestrator via XMPP or direct stdin
    ...
```

### AirDrop as agent→human communication

In the Mac Mini setup, the agent's final deliverable is AirDropped to the human engineer's device. This is elegant: the human gets a push notification when the job is done, without polling.

**Zimaclaw equivalent:** XMPP push notification. When Pi completes a job, the Zig orchestrator sends an XMPP message to the human's account (or XMPP room) with a summary and any attached files (via Prosody's HTTP file upload). The human's XMPP client (Gajim) shows a notification.

---

## Synthesis: Zimaclaw Architecture Mappings

### Direct equivalences

| Mac Mini Agent component | Zimaclaw component | Notes |
|---|---|---|
| HTTP listen server (Python) | XMPP client in Zig (listen) | Federation means any XMPP account can trigger jobs |
| Swift steer app (accessibility tree) | `emacsclient --eval <elisp>` (steer) | Elisp is more precise than accessibility trees; no OCR needed |
| tmux drive wrapper | Pi RPC over stdin/stdout (drive) | Pi manages its own terminal; Zig owns the process |
| AirDrop | XMPP file transfer (Prosody HTTP upload) | |
| macOS | NixOS | Declarative, reproducible, lightweight |
| justfile runner | justfile runner (identical) | Same pattern applies |
| Claude Code agent | Pi agent (or Claude Code via Pi) | Pi allows model switching |
| YAML job files | JSON/text job files on disk | Readable by both Zig and `emacsclient` |

### NixOS service configuration for Zimaclaw

```nix
# zimaclaw.nix — combined services file
{ config, pkgs, ... }: {

  # XMPP server (listen layer)
  services.prosody = {
    enable = true;
    # ... (full config from transcript 01)
    allowRegistration = false;
  };

  # Emacs daemon (steer layer)
  services.emacs = {
    enable  = true;
    package = pkgs.emacs29;
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 5222 5269 5281 ];

  # Pi agent available system-wide
  environment.systemPackages = [ pkgs.pi ]; # or custom derivation

  # Zig orchestrator (built from source in flake)
  systemd.services.zimaclaw-zig = {
    enable      = true;
    wantedBy    = [ "multi-user.target" ];
    after       = [ "prosody.service" "emacs.service" ];
    serviceConfig.ExecStart = "${pkgs.zimaclaw}/bin/zimaclaw";
  };
}
```

### Recommended flake.nix structure for Zimaclaw

```nix
{
  inputs = {
    nixpkgs.url         = "nixpkgs/nixos-25.05";
    home-manager.url    = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Pin Pi at a known-good commit to avoid upstream breakage
    pi.url = "github:badagent/pi/<commit-hash>";
  };

  outputs = { self, nixpkgs, home-manager, pi, ... }: {
    nixosConfigurations.zimaclaw = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux"; # Pi hardware
      modules = [
        ./configuration.nix
        ./xmpp.nix
        ./zimaclaw.nix
        home-manager.nixosModules.homeManager {
          home-manager.backupFileExtension = "backup";
          home-manager.useGlobalPkgs      = true;
          home-manager.useUserPackages    = true;
          home-manager.users.zimaclaw     = import ./home.nix;
        }
      ];
    };
  };
}
```

### Key implementation decisions derived from transcripts

1. **XMPP federation (transcript 01):** Use Prosody with MAM (message archive management) so the Zig orchestrator can replay missed messages after restarts. Enable carbons for multi-device sync if running a human client alongside.

2. **Literate config (transcript 03):** Put the entire Zimaclaw spec + implementation in `readme.org`. Tangle generates `xmpp.nix`, `zimaclaw.nix`, Pi extensions, and the Zig orchestrator source. One file is the source of truth.

3. **`mkOutOfStoreSymlink` (transcript 03):** Link Pi's extension directory and the Zig orchestrator config directly from the repo. Edits to agent behavior are immediately live without a rebuild.

4. **devenv for coding tasks (transcript 03):** When the Pi agent needs to work on a specific project, the Zig orchestrator can `direnv exec <project-dir> pi` to activate that project's dev shell automatically before handing Pi the task.

5. **Age secrets (transcript 03):** Store API keys (Anthropic, etc.) in age-encrypted files in the nixos-config repo. Expose them to Pi via devenv's `env` section.

6. **`emacsclient --eval` speed (transcript 04):** Joshua replaced bash scripts with a compiled Go binary because the bash approach had visible lag. Zig is even faster — compile the orchestrator as a tight binary with no runtime overhead.

7. **Workspace discipline (transcript 04):** Emacs lives on workspace 1, always. The Zig steer layer can assume this: `emacsclient` calls always reach the Emacs instance on WS1.

8. **Pi hooks for Zimaclaw RPC (transcript 05):** Use `on_agent_end` to write structured output to stdout. Use `on_input` to read next instruction from stdin. This is the minimal RPC interface between Zig and Pi.

9. **Proof of work (transcript 06):** After every Pi task, capture a screenshot, write a summary to an org file, and send it back via XMPP file transfer. This gives the human operator an audit trail and completion notification.

10. **Version-pin Pi in the flake (transcript 05):** Pi is built by one person. A single upstream commit could break Zimaclaw. Pin to a known-good commit in `flake.nix` inputs.

### Security model (from transcript 06)

```
XMPP message arrives
        │
        ▼
Zig orchestrator:
  - Validate sender JID (must be in allowlist)
  - Strip/escape any Elisp or shell metacharacters
  - Parse structured command format only (not free-form shell)
  - Log the raw message before processing
        │
        ▼
emacsclient --eval (pre-approved Elisp functions only)
        OR
Pi stdin (structured JSON task, not raw shell)
        │
        ▼
Pi runs with damage-control extension:
  - Blocks rm -rf, nix-env -i, git push to main, etc.
  - All tool calls logged
  - Agent cannot exfiltrate files without going through XMPP upload
        │
        ▼
Result → XMPP message back to sender
```

This mitigates the prompt injection risk that makes OpenClaw dangerous. The Zig layer is the security boundary.
