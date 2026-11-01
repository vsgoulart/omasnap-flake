# Repackages the upstream prebuilt Omasnap (Arch Linux build).
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  qt6,
  kdePackages,
  wayland,
  libdeflate,
  libglvnd,
  gcc-unwrapped,
  wl-clipboard,
  xdg-utils,
  tesseract,
  jq,
  niri,

  # Entry of sources.json: { version, <system> = { url, hash }; }
  source,
  # Put a hyprctl stand-in backed by `niri msg` on PATH, so Omasnap can capture
  # on niri. It shadows any real hyprctl, so leave it off on Hyprland.
  niriCompat ? false,
}:
let
  inherit (stdenvNoCC.hostPlatform) system;
  artifact = source.${system} or (throw "omasnap: unsupported system ${system}");

  tesseract-eng = tesseract.override { enableLanguages = [ "eng" ]; };

  hyprctl-niri = stdenvNoCC.mkDerivation {
    pname = "hyprctl-niri-compat";
    version = "1";

    dontUnpack = true;
    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall

      install -Dm755 ${./hyprctl-niri} $out/bin/hyprctl
      # Prefer the system's niri so `niri msg` matches the running compositor.
      wrapProgram $out/bin/hyprctl \
        --prefix PATH : ${lib.makeBinPath [ jq ]} \
        --suffix PATH : ${lib.makeBinPath [ niri ]}

      runHook postInstall
    '';

    meta.platforms = lib.platforms.linux;
  };

  runtimeDeps = [
    wl-clipboard
    xdg-utils
    tesseract-eng
  ]
  ++ lib.optional niriCompat hyprctl-niri;
in
stdenvNoCC.mkDerivation {
  pname = "omasnap" + lib.optionalString niriCompat "-niri";
  inherit (source) version;

  src = fetchurl { inherit (artifact) url hash; };
  sourceRoot = ".";

  strictDeps = true;

  nativeBuildInputs = [
    autoPatchelfHook
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    kdePackages.layer-shell-qt
    wayland
    libdeflate
    libglvnd
    (lib.getLib gcc-unwrapped)
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r usr/. $out/

    runHook postInstall
  '';

  qtWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath runtimeDeps}" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -f $out/share/applications/omasnap.desktop
    QT_QPA_PLATFORM=offscreen $out/bin/omasnap --version | grep -F '${source.version}'

    runHook postInstallCheck
  '';

  passthru = { inherit source hyprctl-niri; };

  meta = {
    description = "Wayland screenshot and annotation editor";
    homepage = "https://github.com/omacom/omasnap";
    changelog = "https://github.com/omacom/omasnap/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "omasnap";
    platforms = lib.filter (s: s != "version") (lib.attrNames source);
  };
}
