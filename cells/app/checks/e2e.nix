# NixOS VM test that starts the readaloud service, seeds test data,
# and runs puppeteer-based smoke/e2e tests against it.
{
  self,
  pkgs,
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

  chapterContent = pkgs.writeText "chapter-1.html" "<p>Test content for e2e testing.</p>";
in
pkgs.testers.nixosTest {
  name = "readaloud-e2e";

  nodes.server =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.readaloud ];

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

    # Basic smoke test: service responds to HTTP
    server.succeed("curl -sf http://localhost:4000/ > /dev/null")

    # Seed test data: insert a book and a chapter with content file
    server.succeed("""
      sqlite3 /var/lib/readaloud/readaloud.db "
        INSERT INTO books (title, author, source_type, total_chapters, inserted_at, updated_at)
        VALUES ('Test Book', 'Test Author', 'epub', 3, datetime('now'), datetime('now'));

        INSERT INTO chapters (book_id, title, number, content_path, word_count, inserted_at, updated_at)
        VALUES (1, 'Chapter 1', 1, '${chapterContent}', 5, datetime('now'), datetime('now'));

        INSERT INTO chapters (book_id, title, number, content_path, word_count, inserted_at, updated_at)
        VALUES (1, 'Chapter 2', 2, '${chapterContent}', 5, datetime('now'), datetime('now'));

        INSERT INTO chapters (book_id, title, number, content_path, word_count, inserted_at, updated_at)
        VALUES (1, 'Chapter 3', 3, '${chapterContent}', 5, datetime('now'), datetime('now'));
      "
    """)

    # Verify seeded data
    server.succeed("sqlite3 /var/lib/readaloud/readaloud.db 'SELECT count(*) FROM books;' | grep -q 1")
    server.succeed("sqlite3 /var/lib/readaloud/readaloud.db 'SELECT count(*) FROM chapters;' | grep -q 3")

    # Verify the app can serve the book page with chapters
    server.succeed("curl -sf http://localhost:4000/books/1 | grep -q 'Chapter 1'")

    # Set up the e2e test directory with pre-built node_modules
    server.succeed("cp -r ${self}/e2e /tmp/e2e")
    server.succeed("chmod -R u+w /tmp/e2e")
    server.succeed("ln -sf ${e2eNodeModules}/lib/node_modules /tmp/e2e/node_modules")

    # Run the smoke test suite via puppeteer
    server.succeed("""
      cd /tmp/e2e && \
      PUPPETEER_EXECUTABLE_PATH="${pkgs.chromium}/bin/chromium" \
      BASE_URL="http://localhost:4000" \
      BOOK_ID="1" \
      HEADLESS="true" \
      node --test tests/smoke.test.js
    """)
  '';
}
