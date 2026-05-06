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
  e2eNodeModules = pkgs.buildNpmPackage {
    pname = "readaloud-e2e-deps";
    version = "0.1.0";
    src = "${self}/e2e";

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

      # VM resources — chromium needs decent memory
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
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

    # Run the full e2e suite. --test-reporter=spec surfaces skip
    # messages and per-test timing in the build log; the default 'tap'
    # reporter buries them.
    server.succeed(
        "cd /tmp/e2e && "
        "PUPPETEER_EXECUTABLE_PATH=\"${pkgs.chromium}/bin/chromium\" "
        "BASE_URL=\"http://localhost:4000\" "
        "BOOK_ID=\"1\" "
        "HEADLESS=\"true\" "
        "node --test --test-reporter=spec tests/*.test.js"
    )
  '';
}
