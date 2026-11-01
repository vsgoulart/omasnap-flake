# omasnap-flake

A Nix flake that tracks the latest [Omasnap](https://github.com/omacom/omasnap)
releases. Omasnap is a Wayland screenshot and annotation editor. The package is
repackaged from the official upstream release artifact (nothing is built from
source), so new releases land here within hours.

| Package             | Command   | Notes                                    |
| ------------------- | --------- | ---------------------------------------- |
| `omasnap` (default) | `omasnap` | Upstream behaviour (Hyprland)            |
| `omasnap-niri`      | `omasnap` | Adds a `hyprctl` stand-in backed by niri |

Supported system: `x86_64-linux` (the only upstream build).

## Run

```console
nix run github:vsgoulart/omasnap-flake
nix run github:vsgoulart/omasnap-flake#omasnap-niri -- --capture-region
```

## Install

```console
nix profile install github:vsgoulart/omasnap-flake
```

### NixOS / home-manager

```nix
{
  inputs.omasnap = {
    url = "github:vsgoulart/omasnap-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # ...
  nixpkgs.overlays = [ inputs.omasnap.overlays.default ];
  home.packages = [ pkgs.omasnap ]; # or pkgs.omasnap-niri
}
```

Without the overlay, reference the packages directly, e.g.
`inputs.omasnap.packages.${pkgs.stdenv.hostPlatform.system}.omasnap-niri`.

## niri support

Upstream only supports Hyprland: it discovers monitors and windows through
`hyprctl`. `omasnap-niri` puts a small `hyprctl` replacement on Omasnap's
`PATH` that answers those queries with `niri msg`:

- Fullscreen and region capture work on the focused output.
- Window capture is unavailable (no windows are reported).
- Hyprland window rules (`hyprctl eval`) are accepted and ignored, so
  previews, pins and Save As windows open. Add equivalent niri window rules to
  place them (see below).
- Other Hyprland-only extras (pin placement, natural-scroll detection) fail
  and Omasnap falls back to its defaults.

The stand-in shadows any real `hyprctl`, so use `omasnap` on Hyprland. It runs
the `niri` on your `PATH` (so `niri msg` matches the running compositor) and
falls back to nixpkgs' niri.

Omasnap 1.16.0 and later capture through the `ext-image-copy-capture` Wayland
protocol. niri supports it for outputs since
[niri-wm/niri#4554](https://github.com/niri-wm/niri/pull/4554), which is newer
than niri 26.04: use a niri build from `main` until a release includes it.

Since 1.21.0, a fresh capture copies to the clipboard and shows a floating
preview with an Edit button. Pass `--editor overlay` to annotate straight
away, as before. niri window rules that mirror the ones Omasnap registers on
Hyprland (with niri-flake's `programs.niri.settings`):

```nix
window-rules = [
  {
    matches = [ { app-id = "^omasnap$"; title = "^omasnap-pin [0-9]+$"; } ];
    open-floating = true;
    open-focused = false;
    default-floating-position = { x = 16; y = 16; relative-to = "bottom-right"; };
    border.enable = false;
    focus-ring.enable = false;
    shadow.enable = false;
  }
  {
    matches = [ { app-id = "^omasnap$"; title = "^Save screenshot as$"; } ];
    open-floating = true;
  }
];
```

## Differences from upstream

- `wl-clipboard`, `xdg-utils` and `tesseract` (English) are added to Omasnap's
  `PATH`. `hyprctl` is expected from the system on Hyprland.
- `omarchy-notification-send` is not provided; notifications are skipped
  unless it is on `PATH`.

## Updates

`.github/workflows/update.yml` runs twice a day (05:17 and 17:17 UTC) and
whenever it is triggered manually:

1. `scripts/update.sh` finds the newest stable GitHub release with all needed
   assets and pins it in `sources.json`. GitHub publishes SHA-256 digests for
   release assets, so only metadata is downloaded. Versions never go backwards.
2. Both packages are built.
3. If the builds pass, the change is committed to `main`. A failed build fails
   the workflow run, and the update is retried on the next run.

To update a local checkout manually (requires `gh`, `jq` and `nix`):

```console
bash scripts/update.sh
nix build .#omasnap .#omasnap-niri
```
