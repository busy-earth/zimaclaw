# NixOS Component Research

Comprehensive research into declarative NixOS configuration patterns for six key components. All snippets are drawn from real configs, the NixOS Wiki, and the nixpkgs source.

---

## Table of Contents

1. [NixOS Emacs Daemon Service](#1-nixos-emacs-daemon-service)
2. [NixOS Prosody XMPP Server](#2-nixos-prosody-xmpp-server)
3. [NixOS Zig Packaging](#3-nixos-zig-packaging)
4. [NixOS Node.js / npm Global Packages](#4-nixos-nodejs--npm-global-packages)
5. [NixOS Wireguard + Tailscale](#5-nixos-wireguard--tailscale)
6. [NixOS Flake Structure for Appliance](#6-nixos-flake-structure-for-appliance)

---

## 1. NixOS Emacs Daemon Service

**References:** [NixOS Wiki – Emacs](https://wiki.nixos.org/wiki/Emacs) | [nix-community/emacs-overlay](https://github.com/nix-community/emacs-overlay) | [MyNixOS services.emacs options](https://mynixos.com/nixpkgs/options/services.emacs)

### 1.1 System-Level Emacs Daemon (`services.emacs`)

The NixOS module `services.emacs` installs a **systemd user service** for the Emacs daemon. It is the canonical way to run Emacs headlessly on NixOS.

**`services.emacs` option reference:**

| Option | Type | Description |
|--------|------|-------------|
| `services.emacs.enable` | bool | Enable the systemd user service for the Emacs daemon |
| `services.emacs.install` | bool | Install the service unit without enabling it at login |
| `services.emacs.package` | package | The emacs package to use (defaults to `pkgs.emacs`) |
| `services.emacs.defaultEditor` | bool | Set `EDITOR=emacsclient` system-wide |
| `services.emacs.startWithGraphical` | bool | Start with the graphical session instead of any session |

**Minimal system-level daemon (configuration.nix):**

```nix
services.emacs = {
  enable = true;
  defaultEditor = true;
  # For headless / nox use:
  package = pkgs.emacs-nox;
};
```

**With custom package including Nix-managed packages:**

```nix
services.emacs = {
  enable = true;
  defaultEditor = true;
  package = with pkgs; (
    (emacsPackagesFor emacs-nox).emacsWithPackages (
      epkgs: [
        epkgs.vterm
        epkgs.magit
        epkgs.nix-mode
      ]
    )
  );
};
```

**Important:** If `(emacsPackagesFor emacs-nox)` is present, do **not** also list `emacs-nox` in `environment.systemPackages` — `nixos-rebuild` will warn about link collisions.

### 1.2 Home-Manager vs System-Level Emacs

**System-level (`configuration.nix`):**
- Uses `services.emacs` — creates a systemd *user* service
- Package is global; all users share it
- The daemon starts at login (or with the graphical session)

**Home-manager level (`home.nix`):**
- Uses `programs.emacs` (install + configure) and `services.emacs` (daemon)
- Per-user control; home-manager manages the service unit
- Can declaratively specify packages via `extraPackages`

```nix
# home.nix — minimal home-manager Emacs config
programs.emacs = {
  enable = true;
  package = pkgs.emacs-nox;        # headless variant
  extraPackages = epkgs: [
    epkgs.nix-mode
    epkgs.magit
    epkgs.company
  ];
  extraConfig = ''
    (setq standard-indent 2)
    (server-start)
  '';
};

# Enable the user daemon service
services.emacs = {
  enable = true;
  defaultEditor = true;
};
```

**Gotcha:** After `nixos-rebuild switch`, user daemon units are **not automatically reloaded**. Run `systemctl --user daemon-reload && systemctl --user restart emacs` or log out and back in. Alternatively, use socket activation (see below).

### 1.3 Socket Activation

Home-manager's `services.emacs` supports socket activation — the daemon starts on the first `emacsclient` connection:

```nix
# home.nix
services.emacs = {
  enable = true;
  socketActivation.enable = true;   # starts daemon on first emacsclient call
};
```

**Socket path:** When started by systemd, the socket lives at:

```
/run/user/<UID>/emacs/server
```

To connect explicitly:

```bash
emacsclient --socket-name /run/user/$(id -u)/emacs/server -nw
```

The `EDITOR` variable set by `defaultEditor = true` uses `emacsclient` which auto-discovers the socket. For shell scripts you may want:

```bash
export ALTERNATE_EDITOR=""   # causes emacsclient to start daemon if not running
export EDITOR="emacsclient -t"
```

### 1.4 `mkOutOfStoreSymlink` Pattern

[Joshua Blais's nixos-config](https://github.com/jblais493/nixos-config) uses `config.lib.file.mkOutOfStoreSymlink` to keep dotfiles editable without requiring a full `nixos-rebuild`/`home-manager switch` for every change.

```nix
# home.nix — mkOutOfStoreSymlink for live-editable dotfiles
home.file = {
  ".config/doom" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixos-config/dotfiles/doom";
  };
  ".config/emacs" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixos-config/dotfiles/emacs";
  };
};
```

**How it works:** Instead of copying files into the Nix store, it creates a plain symlink pointing directly at the source path. Editing the file is immediately reflected without a rebuild.

**Critical gotcha with flakes:** When using flakes, `toString ./.` evaluates to the *Nix store copy* of the flake, not the live checkout. This means `mkOutOfStoreSymlink ../config/nvim` will still point into the store after `home-manager switch`. The workaround is to use **absolute paths** via `config.home.homeDirectory`:

```nix
# CORRECT — uses absolute path so symlink points to live checkout
home.file.".config/nvim".source =
  config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/nixos-config/dotfiles/nvim";

# WRONG (with flakes) — points into /nix/store copy of the flake
home.file.".config/nvim".source =
  config.lib.file.mkOutOfStoreSymlink ../dotfiles/nvim;
```

### 1.5 Managing Emacs Packages Declaratively

#### Method A: `emacsPackagesFor` (simple, no overlay)

```nix
environment.systemPackages = with pkgs; [
  ((emacsPackagesFor emacs-nox).emacsWithPackages (epkgs: [
    epkgs.magit
    epkgs.nix-mode
    epkgs.evil
    epkgs.company
    epkgs.lsp-mode
  ]))
];
```

#### Method B: `emacs-overlay` + `emacsWithPackagesFromUsePackage`

The [nix-community/emacs-overlay](https://github.com/nix-community/emacs-overlay) provides bleeding-edge Emacs builds and a special function that reads your `init.el` (or `init.org`) and auto-installs all `:ensure`d packages.

**Add the overlay (flake):**

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
  };

  outputs = { self, nixpkgs, emacs-overlay, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ emacs-overlay.overlays.default ]; }
        ./configuration.nix
      ];
    };
  };
}
```

**Use `emacsWithPackagesFromUsePackage` in configuration.nix:**

```nix
{ pkgs, ... }:
{
  services.emacs = {
    enable = true;
    package = pkgs.emacsWithPackagesFromUsePackage {
      # Point at your actual init file
      config = ./emacs.el;           # or ./emacs.org for Org-mode babel
      defaultInitFile = true;        # include config as default init

      # Base emacs build — emacs-overlay provides these:
      # emacs-unstable, emacs-git, emacs-pgtk, emacs-nox-unstable, etc.
      package = pkgs.emacs-nox-unstable;  # headless daemon

      # Pull in all :ensure t packages automatically
      alwaysEnsure = true;

      # Extra packages not mentioned in config
      extraEmacsPackages = epkgs: [
        epkgs.vterm
        epkgs.treesit-grammars.with-all-grammars
        pkgs.shellcheck   # runtime tool, not an elisp package
      ];
    };
  };
}
```

**Available emacs-overlay package attributes:**

| Attribute | Description |
|-----------|-------------|
| `emacs-git` | Latest Emacs from git master |
| `emacs-unstable` | Latest stable release, nightly cache |
| `emacs-pgtk` | Pure GTK (Wayland-native) |
| `emacs-nox` | No X11/GUI (headless) |
| `emacs-nox-unstable` | Latest release, no GUI |

### 1.6 Running `emacs-nox` in Daemon Mode

For a headless server or agent box:

```nix
# configuration.nix
services.emacs = {
  enable = true;
  package = pkgs.emacs-nox;
  # startWithGraphical = false; (default for nox, already headless)
};

environment.variables = {
  ALTERNATE_EDITOR = "";           # auto-start daemon
  EDITOR           = "emacsclient -t";
  VISUAL           = "emacsclient -t";
};
```

The systemd unit starts the daemon at user login. Check with:

```bash
systemctl --user status emacs.service
journalctl --user -u emacs.service
```

Connect:

```bash
emacsclient -t                         # terminal
emacsclient -t --socket-name server    # explicit socket name
```

---

## 2. NixOS Prosody XMPP Server

**References:** [NixOS Wiki – Prosody](https://wiki.nixos.org/wiki/Prosody) | [MyNixOS services.prosody options](https://mynixos.com/nixpkgs/options/services.prosody) | [NixOS Manual – Prosody](https://nixos.org/manual/nixos/stable/)

### 2.1 Full `services.prosody` Option Reference

| Option | Description |
|--------|-------------|
| `services.prosody.enable` | Enable the Prosody service |
| `services.prosody.admins` | List of admin JIDs, e.g. `[ "admin@example.org" ]` |
| `services.prosody.allowRegistration` | Allow self-registration (set `false` for private servers) |
| `services.prosody.authentication` | Auth mechanism: `"internal_plain"`, `"internal_hashed"`, `"ldap"` |
| `services.prosody.c2sRequireEncryption` | Force TLS for client connections |
| `services.prosody.s2sRequireEncryption` | Force TLS for server-to-server |
| `services.prosody.s2sSecureAuth` | Require valid certs for s2s (blocks federation) |
| `services.prosody.s2sSecureDomains` | Require certs only for listed domains |
| `services.prosody.s2sInsecureDomains` | Allow insecure s2s for specific domains |
| `services.prosody.xmppComplianceSuite` | Enable XEP-0423 recommended module set |
| `services.prosody.ssl` | Global SSL cert/key paths |
| `services.prosody.virtualHosts` | Attrset of virtual host definitions |
| `services.prosody.muc` | List of MUC component configurations |
| `services.prosody.modules.*` | Enable/disable individual modules |
| `services.prosody.extraModules` | List of extra module names to load |
| `services.prosody.extraPluginPaths` | Additional plugin search directories |
| `services.prosody.extraConfig` | Raw Lua config appended verbatim |
| `services.prosody.httpInterfaces` | Interfaces for HTTP server |
| `services.prosody.httpPorts` | HTTP listening ports |
| `services.prosody.httpsInterfaces` | Interfaces for HTTPS server |
| `services.prosody.httpsPorts` | HTTPS listening ports |
| `services.prosody.dataDir` | Data directory (default `/var/lib/prosody`) |
| `services.prosody.user` | Unix user to run as |
| `services.prosody.group` | Unix group to run as |
| `services.prosody.package` | Prosody package |
| `services.prosody.log` | Logging configuration |
| `services.prosody.checkConfig` | Run `prosodyctl check config` at activation |
| `services.prosody.disco_items` | Discoverable service items list |
| `services.prosody.httpFileShare` | Built-in HTTP file share module config |

### 2.2 Private Server (No TLS, Wireguard-Only)

For a server that lives exclusively on a private Wireguard network, TLS is optional — all traffic is already encrypted at the VPN layer.

```nix
# configuration.nix — Prosody over Wireguard, no external TLS
{ config, pkgs, ... }:

let
  domain   = "xmpp.local";     # internal domain, not public
  wgAddr   = "10.0.0.1";       # Wireguard IP of this machine
in
{
  services.prosody = {
    enable              = true;
    admins              = [ "admin@${domain}" ];
    allowRegistration   = false;       # private server: no self-registration

    # Disable TLS requirements — VPN handles encryption
    c2sRequireEncryption = false;
    s2sRequireEncryption = false;
    s2sSecureAuth        = false;
    xmppComplianceSuite  = false;

    authentication = "internal_hashed";  # hashed passwords

    # Disable modules not needed for a private setup
    modules = {
      admin_adhoc       = false;
      cloud_notify      = false;
      pep               = false;
      blocklist         = false;
      bookmarks         = false;
      dialback          = false;   # s2s dialback not needed
      register          = false;
      vcard_legacy      = false;
    };

    virtualHosts = {
      "main" = {
        domain  = domain;
        enabled = true;
      };
    };

    # Bind to Wireguard interface only
    extraConfig = ''
      -- Listen only on the VPN interface
      interfaces = { "${wgAddr}" }
      c2s_interfaces = { "${wgAddr}" }
    '';
  };

  # Open client ports only on the wg0 interface
  networking.firewall.interfaces.wg0 = {
    allowedTCPPorts = [
      5222   # XMPP c2s (plain)
      5269   # XMPP s2s (if needed)
    ];
  };
}
```

### 2.3 Full Public Server with ACME/Let's Encrypt + MUC

```nix
# configuration.nix — public Prosody with Let's Encrypt
{ config, pkgs, ... }:

let
  domainName  = "example.org";
  sslCertDir  = config.security.acme.certs."${domainName}".directory;
in
{
  # Let ACME user access certs — Prosody needs to read them
  security.acme.certs."${domainName}" = {
    email      = "admin@${domainName}";
    group      = "prosody";              # give Prosody group access
  };

  services.prosody = {
    enable            = true;
    admins            = [ "admin@${domainName}" ];
    allowRegistration = false;
    authentication    = "internal_plain";
    s2sSecureAuth     = true;
    c2sRequireEncryption = true;

    # Global SSL from ACME
    ssl = {
      cert = "${sslCertDir}/fullchain.pem";
      key  = "${sslCertDir}/key.pem";
    };

    # Disable optional modules for a minimal setup
    modules = {
      admin_adhoc  = false;
      pep          = false;
      blocklist    = false;
      bookmarks    = false;
      dialback     = false;
      register     = false;
      vcard_legacy = false;
    };

    xmppComplianceSuite = false;

    virtualHosts = {
      "main" = {
        domain  = domainName;
        enabled = true;
        # Per-vhost SSL (inherits global if omitted)
        ssl = {
          cert = "${sslCertDir}/fullchain.pem";
          key  = "${sslCertDir}/key.pem";
        };
      };
    };

    # MUC (Multi-User Chat) component
    muc = [
      {
        domain              = "muc.xmpp.${domainName}";
        restrictRoomCreation = false;
        # Additional MUC options:
        # roomDefaultPublic         = false;   # rooms private by default
        # roomDefaultMembersOnly    = false;
        # roomDefaultModerated      = false;
        # maxHistoryMessages        = 20;
      }
    ];

    # SQLite storage (more performant than default file storage)
    extraConfig = ''
      storage = "sql"
      sql = {
        driver   = "SQLite3";
        database = "prosody.sqlite";
      }
    '';
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [
    5222   # XMPP c2s
    5223   # XMPP c2s legacy SSL
    5269   # XMPP s2s
  ];
}
```

### 2.4 MUC Configuration Options

The `services.prosody.muc` option is a list of attrsets:

```nix
services.prosody.muc = [
  {
    domain               = "muc.example.org";
    name                 = "My Chat Rooms";              # server display name
    restrictRoomCreation = "local";    # "local"|false|true
    moderation           = "none";     # "none"|"moderated"
    maxHistoryMessages   = 20;
    roomDefaultPublic    = false;      # rooms private by default
    roomDefaultMembersOnly = false;
    roomDefaultModerated = false;
    roomDefaultHistoryLength = 20;
    roomDefaultLanguage  = "en";
    roomDefaultChangeSubject = false;
    roomDefaultPublicJids = false;
    roomLocking          = true;
    roomLockTimeout      = 300;
    tombstones           = true;
    tombstoneExpiry      = 2678400;   # seconds
    extraConfig          = "";
  }
];
```

### 2.5 `prosodyctl` Account Management

Prosody does not provide a NixOS option for declarative account creation. Accounts must be managed imperatively:

```bash
# Create a user
sudo -u prosody prosodyctl adduser admin@example.org

# Set/change password
sudo -u prosody prosodyctl passwd admin@example.org

# Delete a user
sudo -u prosody prosodyctl deluser admin@example.org

# Check configuration and DNS
sudo -u prosody prosodyctl check config
sudo -u prosody prosodyctl check dns

# Check XMPP service connectivity
sudo -u prosody prosodyctl status
```

### 2.6 Firewall Port Reference

| Protocol | Ports | Purpose |
|----------|-------|---------|
| TCP | 5222, 5223 | Client-to-server (c2s) |
| TCP | 5269 | Server-to-server (s2s) |
| TCP | 5347 | Component protocol |
| TCP | 5280, 5281 | HTTP/HTTPS (BOSH, WebSocket) |
| TCP | 443 | HTTPS upload (if using http_upload_external) |
| TCP/UDP | 3478, 3479, 5349, 5350 | STUN/TURN (coturn) |
| UDP | 49152–65535 | coturn media relay range |

**Binding to interface only (interface-scoped firewall):**

```nix
# Only open ports on the wg0 interface, not the public interface
networking.firewall.interfaces.wg0.allowedTCPPorts = [ 5222 5223 5269 ];
```

### 2.7 Common Gotchas

1. **Cert permissions:** ACME certs are owned by `acme:acme`. You must add Prosody's group to ACME's cert group or use `security.acme.certs."domain".group = "prosody"`.
2. **Module conflicts:** `xmppComplianceSuite = true` enables a fixed set of modules; disabling individual modules in `modules = {}` may conflict if the compliance suite re-enables them.
3. **prosodyctl is imperative:** User accounts, room configs, and SSL certs can't be managed purely declaratively — plan for imperative post-deployment steps.
4. **`c2sRequireEncryption = false`:** Required for plain-text clients on VPN-only setups. Prosody's default is `true`, so this must be explicitly overridden.
5. **DNS SRV records:** For public servers, `_xmpp-client._tcp` and `_xmpp-server._tcp` SRV records are needed. Run `prosodyctl check dns` after DNS changes.

---

## 3. NixOS Zig Packaging

**References:** [Cloudef/zig2nix](https://github.com/Cloudef/zig2nix) | [NixOS Discourse – zig2nix](https://discourse.nixos.org/t/zig2nix-flake-for-packaging-building-and-running-zig-projects/38444) | [Ziggit – Build with Nix](https://ziggit.dev/t/build-and-use-the-latest-zig-using-nix/543)

### 3.1 Option A: `zig2nix` (Recommended for `build.zig.zon` Projects)

[zig2nix](https://github.com/Cloudef/zig2nix) is a Nix flake that bridges Zig's package manager with Nix. It handles `build.zig.zon` dependency fetching, cross-compilation, and Zig version pinning.

**Initialize a new Zig project with zig2nix template:**

```bash
nix flake init -t github:Cloudef/zig2nix
```

**Generated `flake.nix` for a Zig project:**

```nix
{
  description = "My Zig application";

  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-unstable";
    zig2nix.url   = "github:Cloudef/zig2nix";
  };

  outputs = { self, nixpkgs, zig2nix }:
    let
      system  = "x86_64-linux";
      pkgs    = import nixpkgs { inherit system; };

      # Create a Zig environment pinned to a specific version
      env = zig2nix.outputs.zig-env.${system} {
        zig = zig2nix.outputs.packages.${system}.zig-latest;
      };

    in {
      # Build the default Zig package
      packages.${system}.default = env.package {
        # Reads build.zig.zon for metadata
        src = ./.;

        # REQUIRED: pre-generate with:
        #   nix run github:Cloudef/zig2nix -- zon2lock build.zig.zon
        # Commit build.zig.zon2json-lock to your repo!
        # zigBuildZonLock = ./build.zig.zon2json-lock;  # auto-detected

        # Build flags passed to `zig build`
        # zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];

        # Runtime library path wrapping
        # zigWrapperLibs = [ pkgs.openssl ];
        # zigWrapperBins = [ pkgs.git ];
      };

      devShells.${system}.default = env.mkShell {
        # Extra packages available in the dev shell
        packages = with pkgs; [ git ];
      };
    };
}
```

**Handling `build.zig.zon` dependencies:**

```bash
# Step 1: Generate the lock file (requires network, run once)
nix run github:Cloudef/zig2nix -- zon2lock build.zig.zon
# This creates build.zig.zon2json-lock

# Step 2: Commit the lock file
git add build.zig.zon2json-lock

# Step 3: Subsequent builds are fully offline/reproducible
nix build
```

**Why the lock file is needed:** Zig's `build.zig.zon` specifies package URLs with hashes, but Nix's sandbox blocks network access during builds. `zig2nix` converts the ZON dependency tree into a Nix derivation (`deriveLockFile`) that pre-fetches all dependencies.

### 3.2 Option B: Manual `stdenv.mkDerivation` (Simple Projects)

For projects without `build.zig.zon` dependencies, or to use the Zig version shipped in nixpkgs:

```nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation rec {
  pname   = "my-zig-app";
  version = "0.1.0";

  src = pkgs.fetchFromGitHub {
    owner  = "yourname";
    repo   = "my-zig-app";
    rev    = "v${version}";
    hash   = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ pkgs.zig ];

  # Zig build system
  buildPhase = ''
    export HOME=$TMPDIR   # zig needs a writable HOME
    zig build -Doptimize=ReleaseSafe --prefix $out
  '';

  installPhase = ''
    # zig build --prefix $out already installs to $out/bin
    true
  '';

  meta = with pkgs.lib; {
    description = "My Zig application";
    license     = licenses.mit;
    platforms   = platforms.linux;
  };
}
```

**Flake version:**

```nix
{
  description = "Simple Zig application (no build.zig.zon deps)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs   = import nixpkgs { inherit system; };
    in {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname   = "my-zig-app";
        version = "0.1.0";
        src     = ./.;

        nativeBuildInputs = [ pkgs.zig ];

        buildPhase = ''
          export HOME=$TMPDIR
          zig build -Doptimize=ReleaseSafe --prefix $out
        '';

        installPhase = "true";
      };
    };
}
```

### 3.3 Cross-Compilation with zig2nix

zig2nix has first-class cross-compilation support:

```nix
# In your flake.nix outputs:
packages = {
  # Native build
  default = env.package { src = ./.; };

  # Cross-compile for aarch64-linux
  aarch64 = (zig2nix.outputs.zig-env."aarch64-linux" {}).package {
    src = ./.;
  };

  # Cross-compile with musl (static binary)
  static = env.package {
    src = ./.;
    zigPreferMusl = true;
  };
};
```

`zig2nix` automatically uses `pkgsForTarget` which selects binary cache packages for flake-compatible targets and falls back to cross-compilation for exotic targets.

### 3.4 Adding a Zig Package to Your NixOS Config

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig2nix.url = "github:Cloudef/zig2nix";
    my-zig-app.url = "github:yourname/my-zig-app";  # if it has a flake
  };

  outputs = { self, nixpkgs, zig2nix, my-zig-app, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            my-zig-app.packages.x86_64-linux.default
          ];
        })
        ./configuration.nix
      ];
    };
  };
}
```

### 3.5 Common Gotchas

1. **`build.zig.zon2json-lock` must be committed:** Without it, `zig2nix` tries to fetch dependencies at build time, which fails in the Nix sandbox. Always run `zon2lock` and commit the result.
2. **`export HOME=$TMPDIR`:** Zig writes cache files to `$HOME/.cache/zig`. The Nix build sandbox has no writable home — this env var is mandatory.
3. **Zig version mismatch:** `build.zig.zon` often pins a Zig version. Use `zig2nix`'s versioned packages (`zig-0_13_0`, `zig-latest`, `zig-master`) rather than nixpkgs's `pkgs.zig`, which may be behind.
4. **AppArmor in GitHub Actions:** If building with zig2nix in CI on Ubuntu runners, disable AppArmor user namespace restrictions: `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`.

---

## 4. NixOS Node.js / npm Global Packages

**References:** [NixOS Wiki – Node.js](https://wiki.nixos.org/wiki/Node.js) | [NixOS Discourse – npm packages](https://discourse.nixos.org/t/future-of-npm-packages-in-nixpkgs/14285) | [nixpkgs buildNpmPackage source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/node/build-npm-package/default.nix)

### 4.1 Installing npm Packages from nixpkgs

nixpkgs ships many npm packages under the `nodePackages` namespace:

```nix
environment.systemPackages = with pkgs; [
  nodejs
  nodePackages.typescript
  nodePackages.prettier
  nodePackages.eslint
  nodePackages.npm      # npm itself
];
```

Search available packages: `nix search nixpkgs nodePackages.<name>`

### 4.2 The "Pi Coding Agent" / Custom npm Packages

For npm packages not in nixpkgs (like custom agents or tools), use `buildNpmPackage`:

```nix
# Package a custom npm CLI tool
{ pkgs, lib, ... }:

let
  my-npm-tool = pkgs.buildNpmPackage rec {
    pname   = "my-npm-tool";
    version = "1.2.3";

    src = pkgs.fetchFromGitHub {
      owner  = "vendor";
      repo   = "my-npm-tool";
      rev    = "v${version}";
      hash   = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    # The hash of all npm dependencies (from package-lock.json)
    # To get the hash: set to lib.fakeHash, build, copy the 'got:' value
    npmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";

    # If the package has a build step:
    # npmBuildScript = "build";

    # Install flags
    # npmInstallFlags = [ "--production" ];

    meta = {
      description = "My custom npm tool";
      mainProgram = "my-npm-tool";
    };
  };
in
{
  environment.systemPackages = [ my-npm-tool ];
}
```

**Getting `npmDepsHash`:**

```bash
# Step 1: Set fakeHash and build (will fail with hash mismatch)
npmDepsHash = lib.fakeHash;

# Step 2: Run nixos-rebuild or nix build — it will error with:
#   got: sha256-ACTUAL_HASH_HERE=
# Step 3: Replace lib.fakeHash with the actual hash
```

**`buildNpmPackage` key parameters:**

| Parameter | Description |
|-----------|-------------|
| `pname` | Package name |
| `version` | Package version |
| `src` | Source derivation (fetchFromGitHub, fetchurl, etc.) |
| `npmDepsHash` | Hash of the npm dependency cache |
| `npmBuildScript` | npm script to run (default: `"build"`) |
| `npmInstallFlags` | Extra flags for `npm install` |
| `nodejs` | Node.js version to use (default: `pkgs.nodejs`) |
| `makeCacheWritable` | Allow modifying the npm cache during build |

### 4.3 Running Node.js as a systemd Service

```nix
# configuration.nix — Node.js app as a systemd service
{ config, pkgs, ... }:

let
  # Build the app as a Nix package
  my-agent = pkgs.buildNpmPackage {
    pname        = "my-agent";
    version      = "1.0.0";
    src          = ./my-agent-src;
    npmDepsHash  = "sha256-...";
  };
in
{
  # Create a dedicated service user
  users.users.my-agent = {
    isSystemUser = true;
    group        = "my-agent";
    home         = "/var/lib/my-agent";
    createHome   = true;
  };
  users.groups.my-agent = {};

  systemd.services.my-agent = {
    description   = "My Node.js agent";
    wantedBy      = [ "multi-user.target" ];
    after         = [ "network.target" ];

    serviceConfig = {
      ExecStart    = "${my-agent}/bin/my-agent";
      User         = "my-agent";
      Group        = "my-agent";
      WorkingDir   = "/var/lib/my-agent";
      StateDirectory = "my-agent";       # creates /var/lib/my-agent
      Restart      = "on-failure";
      RestartSec   = "5s";

      # Security hardening
      PrivateTmp      = true;
      NoNewPrivileges = true;
    };

    # Environment variables
    environment = {
      NODE_ENV = "production";
      HOME     = "/var/lib/my-agent";
    };
  };
}
```

**Using a flake input for the app:**

```nix
# flake.nix
{
  inputs.my-agent.url = "github:vendor/my-agent";

  outputs = { self, nixpkgs, my-agent, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit my-agent; };
      modules = [ ./configuration.nix ];
    };
  };
}

# configuration.nix
{ pkgs, my-agent, ... }:
{
  systemd.services.my-agent.serviceConfig.ExecStart =
    "${my-agent.packages.${pkgs.system}.default}/bin/my-agent";
}
```

### 4.4 Using `nodePackages` with a Different Node Version

To use a specific Node.js version for all `nodePackages`:

```nix
# overlay to pin nodePackages to Node 20
nixpkgs.overlays = [
  (final: prev: {
    nodejs = prev.nodejs_20;
  })
];
```

### 4.5 npm "Global" Install Alternatives on NixOS

`npm install -g` fails because `/nix/store` is read-only. Options:

```nix
# Option 1: Add to user profile via home-manager
home.packages = with pkgs; [
  nodePackages.some-tool
];

# Option 2: npm prefix to home directory (imperative, not declarative)
# npm set prefix ~/.npm-global
# export PATH=$HOME/.npm-global/bin:$PATH

# Option 3: nix-shell for one-off usage
# nix-shell -p nodePackages.create-react-app
```

### 4.6 Common Gotchas

1. **`package-lock.json` is required:** `buildNpmPackage` fails without a `package-lock.json`. For projects using `pnpm` or `yarn`, use `pkgs.pnpm.fetchDeps` or `mkYarnPackage` instead.
2. **`npmDepsHash` is brittle:** Any change to `package-lock.json` (even indirect dependency bumps) invalidates it — regenerate using `lib.fakeHash`.
3. **Electron apps:** Add `ELECTRON_SKIP_BINARY_DOWNLOAD = "1"` to `env` to prevent Electron from trying to download binaries during the Nix build.
4. **Private registries:** `buildNpmPackage` does not support `.npmrc` authentication natively — use `fetchNpmDeps` with `npmRegistryOverrides` for mirrors.

---

## 5. NixOS Wireguard + Tailscale

**References:** [NixOS Wiki – WireGuard](https://wiki.nixos.org/wiki/WireGuard) | [NixOS Wiki – Tailscale](https://wiki.nixos.org/wiki/Tailscale) | [MyNixOS services.tailscale.authKeyFile](https://mynixos.com/nixpkgs/option/services.tailscale.authKeyFile)

### 5.1 `networking.wireguard` Module

#### Server (Hub/Gateway) Configuration

```nix
# configuration.nix — WireGuard server
{ config, pkgs, ... }:
{
  # Key generation (one-time, outside Nix):
  # umask 077
  # wg genkey > /etc/wireguard/private.key
  # wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key

  networking.wireguard.interfaces.wg0 = {
    # Server's VPN IP
    ips         = [ "10.0.0.1/24" ];
    listenPort  = 51820;

    # Use a file reference (never inline the key!)
    privateKeyFile = "/etc/wireguard/private.key";
    # Or with agenix: config.age.secrets.wg-private.path

    # NAT for client internet access
    postSetup = ''
      ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
    '';
    postShutdown = ''
      ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
    '';

    peers = [
      {
        publicKey           = "CLIENT_PUBLIC_KEY=";
        allowedIPs          = [ "10.0.0.2/32" ];
        # No endpoint — server accepts from any address
      }
    ];
  };

  # NAT
  networking.nat = {
    enable           = true;
    externalInterface = "eth0";
    internalInterfaces = [ "wg0" ];
  };

  # Firewall
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
    # Open specific ports only on the wg0 interface:
    interfaces.wg0.allowedTCPPorts = [ 5222 5223 ];  # Prosody
  };
}
```

#### Client Configuration

```nix
# Client — routes all traffic through VPN
networking.wireguard.interfaces.wg0 = {
  ips           = [ "10.0.0.2/32" ];
  listenPort    = 51820;
  privateKeyFile = config.age.secrets.wg-client-key.path;

  peers = [
    {
      publicKey         = "SERVER_PUBLIC_KEY=";
      allowedIPs        = [ "0.0.0.0/0" ];     # full tunnel
      endpoint          = "server.example.com:51820";
      persistentKeepalive = 25;
    }
  ];
};

# Required for full tunnel (0.0.0.0/0) to work
networking.firewall.checkReversePath = "loose";
```

#### Peer-to-Peer (Mesh) Configuration

```nix
# Each machine has its own VPN IP
networking.wireguard.interfaces.wg0 = {
  ips        = [ "10.0.0.3/32" ];
  listenPort = 51820;
  privateKeyFile = "/etc/wireguard/private.key";

  peers = [
    {
      publicKey  = "PEER1_PUBLIC_KEY=";
      allowedIPs = [ "10.0.0.1/32" ];
      endpoint   = "192.168.1.10:51820";
    }
    {
      publicKey  = "PEER2_PUBLIC_KEY=";
      allowedIPs = [ "10.0.0.2/32" ];
      # No endpoint — will accept incoming connections
    }
  ];
};
```

#### `networking.wireguard.interfaces.<name>` Options

| Option | Description |
|--------|-------------|
| `ips` | List of IP/CIDR addresses for this peer |
| `listenPort` | UDP port to listen on (default: random) |
| `privateKey` | Inline private key (avoid in configs!) |
| `privateKeyFile` | Path to private key file |
| `peers` | List of peer configurations |
| `peers.*.publicKey` | Peer's public key |
| `peers.*.allowedIPs` | IP ranges routed to this peer |
| `peers.*.endpoint` | `"host:port"` for the peer |
| `peers.*.persistentKeepalive` | Keepalive interval in seconds |
| `peers.*.presharedKeyFile` | Path to pre-shared key for extra security |
| `postSetup` | Shell commands run after interface up |
| `postShutdown` | Shell commands run after interface down |
| `mtu` | Override MTU (default: 1420) |

### 5.2 `services.tailscale` Module

#### Basic Setup

```nix
services.tailscale = {
  enable = true;
  # authKeyFile = config.age.secrets.tailscale-key.path;
};

# Firewall
networking.firewall = {
  enable           = true;
  trustedInterfaces = [ "tailscale0" ];     # fully trust Tailscale traffic
  allowedUDPPorts  = [ config.services.tailscale.port ];  # default: 41641
};
```

#### Full Tailscale Configuration with nftables

```nix
{ config, pkgs, ... }:
{
  services.tailscale = {
    enable      = true;

    # Pre-auth key for unattended setup (from agenix/sops)
    authKeyFile = config.age.secrets.tailscale-auth-key.path;

    # Subnet router / exit node support
    useRoutingFeatures = "server";   # "client" | "server" | "both"

    # Allow a service to use Tailscale's cert API (for HTTPS)
    # permitCertUid = "caddy";
  };

  networking.nftables.enable = true;
  networking.firewall = {
    enable           = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts  = [ config.services.tailscale.port ];
    # For exit node — allow reverse path
    checkReversePath = "loose";
  };

  # Force tailscaled to use nftables (avoids iptables-compat issues)
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  # Optional: faster boot
  systemd.network.wait-online.enable           = false;
  boot.initrd.systemd.network.wait-online.enable = false;
}
```

#### `services.tailscale` Option Reference

| Option | Type | Description |
|--------|------|-------------|
| `services.tailscale.enable` | bool | Enable the Tailscale daemon |
| `services.tailscale.port` | int | UDP port (default: 41641) |
| `services.tailscale.authKeyFile` | path or null | Pre-auth key file path |
| `services.tailscale.useRoutingFeatures` | string | Enable subnet routing/exit node: `"none"`, `"client"`, `"server"`, `"both"` |
| `services.tailscale.permitCertUid` | string | Unix user allowed to access Tailscale TLS cert API |
| `services.tailscale.interfaceName` | string | Interface name (default: `"tailscale0"`; use `"userspace-networking"` for userspace mode) |

### 5.3 Binding Services to VPN Interface Only

**For Wireguard (bind Prosody to wg0 only):**

```nix
services.prosody.extraConfig = ''
  -- Only listen on the Wireguard interface
  interfaces = { "10.0.0.1" }
  c2s_interfaces = { "10.0.0.1" }
  s2s_interfaces = { "10.0.0.1" }
'';

# Open ports only on wg0
networking.firewall.interfaces.wg0.allowedTCPPorts = [ 5222 5223 ];
# Do NOT open 5222 on the public interface
```

**For Tailscale (bind service to Tailscale IP):**

```nix
# Tailscale IP is dynamic — read at runtime
# A common pattern: bind to 100.64.0.0/10 (Tailscale CGNAT range)

# For Prosody, use extraConfig or wait for tailscale0 IP
services.prosody.extraConfig = ''
  -- Bind only on tailscale0 — fill in your Tailscale IP
  interfaces = { "100.x.y.z" }
'';

# Easier: use trustedInterfaces so firewall passes all tailscale traffic
networking.firewall.trustedInterfaces = [ "tailscale0" ];
```

**Ordering services after Tailscale:**

```nix
# Ensure Prosody (or any VPN-dependent service) starts after Tailscale
systemd.services.prosody = {
  after  = [ "tailscale.service" ];
  wants  = [ "tailscale.service" ];
};
```

### 5.4 Key Management with agenix

```nix
# secrets.nix (in your flake root)
let
  server    = "ssh-ed25519 AAAA...server_host_key";
  mykey     = "ssh-ed25519 AAAA...your_personal_key";
in {
  "wg-private.age".publicKeys = [ mykey server ];
  "tailscale-auth.age".publicKeys = [ mykey server ];
}

# In configuration.nix
age.secrets.wg-private = {
  file = ./secrets/wg-private.age;
  mode = "400";
};

networking.wireguard.interfaces.wg0.privateKeyFile =
  config.age.secrets.wg-private.path;
```

### 5.5 Common Gotchas

1. **RPfilter with WireGuard full tunnel:** `allowedIPs = [ "0.0.0.0/0" ]` breaks NixOS's default reverse path filter. Fix: `networking.firewall.checkReversePath = "loose"`.
2. **Inline private keys:** Never put `privateKey = "..."` directly in configuration.nix — it will be world-readable in `/nix/store`. Always use `privateKeyFile`.
3. **Tailscale bypasses NixOS firewall:** Tailscale sets its own `iptables` rules; traffic on `tailscale0` bypasses your NixOS firewall by default. Use `trustedInterfaces = [ "tailscale0" ]` intentionally.
4. **MTU issues:** WireGuard adds ~80 bytes of overhead. If your upstream MTU is exactly 1500, set `networking.wireguard.interfaces.wg0.mtu = 1420` or lower.
5. **`persistentKeepalive` + `privateKeyFile` bug:** In some NixOS versions, combining these causes the keepalive to be ignored. Workaround: use `postSetup` to set keepalive via `wg set wg0 peer <pubkey> persistent-keepalive 25`.

---

## 6. NixOS Flake Structure for Appliance

**References:** [NixOS Wiki – Flakes](https://wiki.nixos.org/wiki/Flakes) | [ryantm/agenix](https://github.com/ryantm/agenix) | [Mic92/sops-nix](https://github.com/Mic92/sops-nix) | [Michael Stapelberg – sops-nix 2025](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/) | [jblais493/nixos-config](https://github.com/jblais493/nixos-config)

### 6.1 Canonical Flake Structure

```
my-appliance/
├── flake.nix               # inputs, outputs, nixosConfigurations
├── flake.lock              # pinned versions (commit this!)
├── configuration.nix       # main NixOS system configuration
├── hardware-configuration.nix  # generated by nixos-generate-config
├── home.nix                # home-manager user config
├── secrets/
│   ├── secrets.nix         # agenix key declarations
│   ├── wireguard.age
│   ├── prosody-admin.age
│   └── tailscale-key.age
└── modules/
    ├── emacs.nix
    ├── prosody.nix
    ├── wireguard.nix
    └── services.nix
```

### 6.2 Complete `flake.nix` for a Single-Purpose Appliance

```nix
{
  description = "Agent appliance — single-purpose NixOS box";

  inputs = {
    # Stable channel
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Home-manager — must follow same nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Bleeding-edge Emacs (optional)
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zig packaging (if needed)
    # zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = { self, nixpkgs, home-manager, agenix, emacs-overlay, ... }:
    let
      system   = "x86_64-linux";
      hostname = "agent-box";
      username = "agent";

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          emacs-overlay.overlays.default
        ];
        config.allowUnfree = false;
      };
    in {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        inherit system pkgs;

        # Pass extra args to all modules
        specialArgs = { inherit hostname username; };

        modules = [
          # Core system config
          ./configuration.nix
          ./hardware-configuration.nix

          # Secrets
          agenix.nixosModules.default

          # Home Manager as a NixOS module (single rebuild command)
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs     = true;   # share pkgs with NixOS
            home-manager.useUserPackages   = true;   # install to /etc/profiles
            home-manager.backupFileExtension = "backup";
            home-manager.users.${username} = import ./home.nix;
            home-manager.extraSpecialArgs  = { inherit username; };
          }
        ];
      };
    };
}
```

### 6.3 `configuration.nix` for an Appliance

```nix
# configuration.nix
{ config, pkgs, lib, hostname, username, ... }:
{
  imports = [
    ./modules/emacs.nix
    ./modules/prosody.nix
    ./modules/wireguard.nix
  ];

  # Basic system
  networking.hostName = hostname;
  time.timeZone       = "UTC";

  # Enable flakes
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
  };

  # Periodic garbage collection
  nix.gc = {
    automatic  = true;
    dates      = "weekly";
    options    = "--delete-older-than 30d";
  };

  users.users.${username} = {
    isNormalUser    = true;
    extraGroups     = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... your-key"
    ];
  };

  services.openssh = {
    enable                = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin        = "no";
  };

  system.stateVersion = "24.11";
}
```

### 6.4 `home.nix` for the Agent User

```nix
# home.nix
{ config, pkgs, username, ... }:
{
  home.username      = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion  = "24.11";

  programs.home-manager.enable = true;

  # Emacs daemon
  programs.emacs = {
    enable  = true;
    package = pkgs.emacs-nox-unstable;
  };
  services.emacs = {
    enable        = true;
    defaultEditor = true;
  };

  # Declarative dotfiles via mkOutOfStoreSymlink
  home.file.".config/emacs" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixos-config/dotfiles/emacs";
  };

  home.packages = with pkgs; [
    git
    ripgrep
    fd
    jq
  ];
}
```

### 6.5 Deploying the Appliance

```bash
# First deployment (from the target machine after a minimal NixOS install)
nixos-rebuild switch --flake .#agent-box

# Deploy from another machine using nixos-anywhere
nix run github:nix-community/nixos-anywhere -- \
  --flake .#agent-box \
  root@192.168.1.100

# Subsequent updates (on the machine itself or via SSH)
nixos-rebuild switch --flake github:yourname/nixos-config#agent-box

# Roll back if something breaks
nixos-rebuild --rollback switch

# Test a new config without making it the boot default
nixos-rebuild test --flake .#agent-box
```

### 6.6 Secrets Management

#### Option A: agenix (SSH key-based)

```nix
# secrets/secrets.nix — declares which keys can decrypt each secret
let
  # Your personal SSH public key (for editing secrets)
  admin = "ssh-ed25519 AAAA...your_personal_key";

  # Target machine's host SSH key (for decryption at boot)
  # Obtain with: ssh-keyscan <machine-ip> | grep ed25519
  agent-box = "ssh-ed25519 AAAA...host_ed25519_key";
in {
  "wireguard.age".publicKeys       = [ admin agent-box ];
  "prosody-admin.age".publicKeys   = [ admin agent-box ];
  "tailscale-key.age".publicKeys   = [ admin agent-box ];
}
```

```bash
# Create/edit a secret (opens $EDITOR with decrypted content)
agenix -e secrets/wireguard.age

# Rekey all secrets after adding a new machine key
agenix --rekey
```

```nix
# In configuration.nix — reference secrets
age.secrets.wireguard = {
  file = ./secrets/wireguard.age;
  mode = "400";
};

networking.wireguard.interfaces.wg0.privateKeyFile =
  config.age.secrets.wireguard.path;
```

#### Option B: sops-nix (age + YAML, supports multiple backends)

```nix
# flake.nix
inputs.sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In modules list:
sops-nix.nixosModules.sops
```

```yaml
# secrets/example.yaml — encrypted with sops
# Edit with: sops secrets/example.yaml
wireguard_key: ENC[AES256_GCM,data:...,type:str]
prosody_password: ENC[AES256_GCM,data:...,type:str]
sops:
  age:
    - recipient: age1...machine_key
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
```

```nix
# configuration.nix — sops-nix usage
sops = {
  defaultSopsFile = ./secrets/example.yaml;
  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  secrets = {
    wireguard_key = {};
    prosody_password = {
      owner = "prosody";
      mode  = "400";
    };
  };
};

networking.wireguard.interfaces.wg0.privateKeyFile =
  config.sops.secrets.wireguard_key.path;
```

**Choosing between agenix and sops-nix:**

| Feature | agenix | sops-nix |
|---------|--------|---------|
| Format | `.age` files | YAML/JSON/dotenv/binary |
| Backends | SSH keys (age) | age, GPG, AWS KMS, GCP KMS, Azure Key Vault |
| Complexity | Simple | More flexible |
| Multiple secrets per file | No (1 secret = 1 file) | Yes (YAML dict) |
| git-friendly | Yes (binary blobs) | Yes (shows changed keys) |

### 6.7 Module Structure Best Practices

```nix
# modules/prosody.nix — self-contained module
{ config, pkgs, lib, ... }:
{
  # Only activate if explicitly enabled
  options.myApp.prosody.enable = lib.mkEnableOption "Prosody XMPP server";

  config = lib.mkIf config.myApp.prosody.enable {
    services.prosody = { ... };
    networking.firewall.interfaces.wg0.allowedTCPPorts = [ 5222 ];
  };
}
```

### 6.8 Putting It All Together: Annotated `flake.nix`

```nix
# Complete annotated flake.nix for an agent appliance
{
  description = "Agent box — single-purpose NixOS appliance";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-24.11";
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url       = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
  };

  outputs = inputs @ { self, nixpkgs, home-manager, agenix, emacs-overlay, ... }:
    let
      system   = "x86_64-linux";
      hostname = "agent-box";
      username = "agent";
    in {
      # The NixOS configuration for this machine.
      # Deploy with: nixos-rebuild switch --flake .#agent-box
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs hostname username; };

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ emacs-overlay.overlays.default ];
        };

        modules = [
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          { home-manager.users.${username} = import ./home.nix; }
          ./configuration.nix
          ./hardware-configuration.nix
          ./modules/emacs.nix
          ./modules/prosody.nix
          ./modules/wireguard.nix
        ];
      };

      # Convenience: format Nix files
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
```

### 6.9 Common Gotchas

1. **`home.stateVersion` vs `system.stateVersion`:** These are independent. Both must be set and should match the NixOS release you first deployed on. Do not bump them arbitrarily.
2. **`home-manager.useGlobalPkgs = true`:** Required if you use `nixpkgs.overlays` — without it, home-manager uses its own `nixpkgs` instance that doesn't have your overlays.
3. **`specialArgs` vs `extraSpecialArgs`:** NixOS modules use `specialArgs`; home-manager modules use `home-manager.extraSpecialArgs`. Both must be set separately.
4. **Flakes copy source to store:** Every `nixos-rebuild switch` copies your entire flake directory into `/nix/store`. This makes `mkOutOfStoreSymlink` with relative paths point into the store copy — use absolute paths (see §1.4).
5. **`agenix --rekey` must be run after adding new hosts:** Secrets are encrypted to specific public keys. After adding a new machine, all secrets must be rekeyed before that machine can boot.
6. **`hardware-configuration.nix` is machine-specific:** Never commit a single `hardware-configuration.nix` for a multi-host repo. Put it in `hosts/<hostname>/hardware-configuration.nix`.
7. **`nixos-rebuild switch --flake .`:** The trailing `.` tells Nix to use the current directory as the flake. The hostname is read from `networking.hostName` to select the right `nixosConfigurations` entry. To override: `--flake .#other-host`.

---

## Quick Reference: NixOS Option Names

| Component | Key Option |
|-----------|-----------|
| Emacs daemon (system) | `services.emacs.enable` |
| Emacs daemon (home-manager) | `services.emacs.enable` (in HM) |
| Emacs package selection | `services.emacs.package` |
| Emacs default editor | `services.emacs.defaultEditor` |
| Emacs socket activation | `services.emacs.socketActivation.enable` |
| Emacs packages | `(emacsPackagesFor pkg).emacsWithPackages` |
| Prosody enable | `services.prosody.enable` |
| Prosody admin | `services.prosody.admins` |
| Prosody registration | `services.prosody.allowRegistration` |
| Prosody TLS enforcement | `services.prosody.c2sRequireEncryption` |
| Prosody MUC | `services.prosody.muc` |
| Prosody virtual hosts | `services.prosody.virtualHosts.<name>` |
| Prosody raw config | `services.prosody.extraConfig` |
| WireGuard interface | `networking.wireguard.interfaces.<name>` |
| WireGuard private key | `networking.wireguard.interfaces.<n>.privateKeyFile` |
| WireGuard peers | `networking.wireguard.interfaces.<n>.peers` |
| Tailscale enable | `services.tailscale.enable` |
| Tailscale auth key | `services.tailscale.authKeyFile` |
| Tailscale routing | `services.tailscale.useRoutingFeatures` |
| Firewall TCP ports | `networking.firewall.allowedTCPPorts` |
| Firewall UDP ports | `networking.firewall.allowedUDPPorts` |
| Interface-scoped firewall | `networking.firewall.interfaces.<if>.allowedTCPPorts` |
| Trusted interfaces | `networking.firewall.trustedInterfaces` |
| agenix secrets | `age.secrets.<name>.file` |
| agenix secret path ref | `config.age.secrets.<name>.path` |
| sops secrets | `sops.secrets.<name>` |
| sops secret path ref | `config.sops.secrets.<name>.path` |
| npm package | `pkgs.buildNpmPackage { ... }` |
| npm package hash | `npmDepsHash` |
| Node.js systemd service | `systemd.services.<name>.serviceConfig.ExecStart` |
| Zig build (zig2nix) | `env.package { src = ./.; }` |
| mkOutOfStoreSymlink | `config.lib.file.mkOutOfStoreSymlink "/abs/path"` |
| Flake experimental | `nix.settings.experimental-features = [ "nix-command" "flakes" ]` |
