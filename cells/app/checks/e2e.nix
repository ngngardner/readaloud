# NixOS VM test that starts the readaloud service, seeds the canonical
# e2e fixture via a release rpc call, and runs the full puppeteer suite
# against it. Single source of truth for the fixture shape lives in
# `ReadaloudAudiobook.Fixtures.E2E.seed!/1` — this check just calls it.
{
  self,
  pkgs,
  package,
  readaloudModule,
}:
let
  # Pre-build node_modules for the e2e test suite.
  # This avoids running npm install inside the VM (no network access).
  #
  # src is just the npm manifest files — NOT the whole e2e/ dir — so
  # editing a test never invalidates this derivation and re-runs npm ci.
  e2eNpmSrc = pkgs.runCommand "readaloud-e2e-npm-src" { } ''
    mkdir $out
    cp ${self}/e2e/package.json ${self}/e2e/package-lock.json $out/
  '';
  e2eNodeModules = pkgs.buildNpmPackage {
    pname = "readaloud-e2e-deps";
    version = "0.1.0";
    src = e2eNpmSrc;

    npmDepsHash = "sha256-8n5jlf01D5w2VsIBvzKUe0tWwB2nQ7odzB9Ah6LeisA=";

    # Skip puppeteer's bundled chromium download — we provide system chromium
    env.PUPPETEER_SKIP_DOWNLOAD = "true";

    # We only need node_modules, not a build output
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib
      cp -r node_modules $out/lib/node_modules
      runHook postInstall
    '';
  };

  secretKeyFile = pkgs.writeText "test-secret-key" "this-is-a-test-secret-key-base-that-is-at-least-sixty-four-bytes-long-for-phoenix";
in
pkgs.testers.nixosTest {
  name = "readaloud-e2e";

  nodes.server =
    { pkgs, ... }:
    {
      imports = [ readaloudModule ];

      services.readaloud = {
        enable = true;
        port = 4000;
        host = "localhost";
        secretKeyBaseFile = secretKeyFile;
      };

      # Chromium and Node.js for running puppeteer tests
      environment.systemPackages = with pkgs; [
        nodejs_22
        chromium
        sqlite
        curl
      ];

      # Puppeteer should use the system chromium, not download its own
      environment.variables.PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";

      # VM resources — chromium needs decent memory, and per-file browser
      # launches + page renders are CPU-bound. The dev host has plenty of
      # headroom (24 cores / 62 GB); CI runners that don't will just
      # timeshare the vCPUs.
      virtualisation.memorySize = 8192;
      virtualisation.cores = 8;
    };

  testScript = ''
    server.wait_for_unit("readaloud.service")
    server.wait_for_open_port(4000)

    # Sanity: the service responds to HTTP before we touch the DB.
    server.succeed("curl -sf http://localhost:4000/ > /dev/null")

    # Seed the canonical e2e fixture via release rpc. This runs inside
    # the running BEAM node, so the writes share the service's view of
    # the filesystem (PrivateTmp namespace) and the SQLite pool.
    server.succeed(
        "runuser -u readaloud -- env "
        "RELEASE_COOKIE=readaloud "
        "HOME=/var/lib/readaloud "
        "${package}/bin/readaloud rpc "
        "'ReadaloudAudiobook.Fixtures.E2E.seed!()'"
    )

    # Verify seeded data — defensive sanity, not a substitute for the suite.
    server.succeed("sqlite3 /var/lib/readaloud/readaloud.db 'SELECT count(*) FROM books;' | grep -q '^1$'")
    server.succeed("sqlite3 /var/lib/readaloud/readaloud.db 'SELECT count(*) FROM chapters;' | grep -q '^3$'")
    server.succeed("sqlite3 /var/lib/readaloud/readaloud.db 'SELECT count(*) FROM chapter_audios;' | grep -q '^2$'")
    server.succeed("curl -sf http://localhost:4000/books/1 | grep -q 'Chapter 1'")

    # Set up the e2e test directory with pre-built node_modules.
    server.succeed("cp -r ${self}/e2e /tmp/e2e")
    server.succeed("chmod -R u+w /tmp/e2e")
    server.succeed("ln -sf ${e2eNodeModules}/lib/node_modules /tmp/e2e/node_modules")

    # Launch ONE shared Chromium for the whole suite. node --test runs
    # each file in its own process; without this every file pays a full
    # browser launch in before(). helpers.setup() connects via
    # BROWSER_WS_ENDPOINT and gets an isolated incognito context.
    server.succeed(
        "systemd-run --unit=e2e-browser "
        "-p WorkingDirectory=/tmp/e2e "
        "-p Environment=PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium "
        "-p Environment=WS_ENDPOINT_FILE=/tmp/e2e-ws-endpoint "
        "-p Environment=HEADLESS=true "
        "${pkgs.nodejs_22}/bin/node browser-server.js"
    )
    server.wait_until_succeeds("test -s /tmp/e2e-ws-endpoint", timeout=60)

    # Run the full e2e suite. --test-reporter=spec surfaces skip
    # messages and per-test timing; print() lands the report in the
    # build log even when the suite passes.
    #
    # --test-concurrency=1 forces files to run sequentially. Files share
    # the BEAM/SQLite — accidental-navigation.test.js's modal triggers
    # are gated on `ReadingProgress` being a known chapter at a known
    # moment, which races horribly when reader-styles-persist or audio
    # tests rewrite progress in parallel. Sequential is ~2× slower but
    # deterministic, which is the tradeoff this suite is for.
    print(server.succeed(
        "cd /tmp/e2e && "
        "PUPPETEER_EXECUTABLE_PATH=\"${pkgs.chromium}/bin/chromium\" "
        "BROWSER_WS_ENDPOINT=\"$(cat /tmp/e2e-ws-endpoint)\" "
        "BASE_URL=\"http://localhost:4000\" "
        "BOOK_ID=\"1\" "
        "HEADLESS=\"true\" "
        "node --test --test-concurrency=1 --test-reporter=spec tests/*.test.js"
    ))
    server.succeed("systemctl stop e2e-browser")
  '';
}
