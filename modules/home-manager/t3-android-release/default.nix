# `t3-android-release`: publish the Android app's release of erik/main (Erik's
# T3 Code fork) without GitHub Actions. It runs the same script the workflow
# runs (scripts/erik-android-release.sh in the fork, docs/erik-updates.md) on
# the homelab worker through `heavy`, in a fresh full clone of erik/main, with
# the workflow's secrets taken from sops. Use it when Actions is unavailable
# (e.g. "Actions has been disabled for this repository"), never alongside a
# running erik-android.yml run.
#
#   t3-android-release                 JS update or APK, whichever erik/main needs
#   t3-android-release --apk           always build an APK
#   t3-android-release --test-abi x86_64
#                                      also build an unpublished x86_64 APK of the
#                                      same release (emulator checks); copied to
#                                      ~/.cache/t3-android-release/<run>/out
#   t3-android-release --accept-dropped-commits
#                                      see the guard in docs/erik-updates.md
#   t3-android-release --commit SHA --prebuilt /work/<run>/out/<apk>
#                                      publish an APK an earlier run built on the
#                                      worker but could not publish (no rebuild)
{ pkgs, ... }:
let
  t3-android-release = pkgs.writeShellApplication {
    name = "t3-android-release";
    runtimeInputs = with pkgs; [
      sops
      gh
      coreutils
    ];
    text = ''
      force_apk=false
      accept=false
      test_abi=""
      commit=""
      prebuilt=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --apk) force_apk=true ;;
          --accept-dropped-commits) accept=true ;;
          --test-abi) test_abi="$2"; shift ;;
          --commit) commit="$2"; shift ;;
          --prebuilt) prebuilt="$2"; force_apk=true; shift ;;
          -h | --help) echo "usage: t3-android-release [--apk] [--test-abi ABI] [--commit SHA] [--prebuilt WORKER-APK] [--accept-dropped-commits]"; exit 0 ;;
          *) echo "unknown argument $1" >&2; exit 2 ;;
        esac
        shift
      done

      dotfiles="$HOME/.dotfiles"
      secret() { sops -d --extract "[\"$2\"]" "$dotfiles/$1"; }
      stage="$HOME/.cache/t3-android-release/$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$stage"
      chmod 700 "$stage"
      # The secrets only exist in this file until the worker loads them. If
      # the job never starts (a failed submit, or killed while queued), sync
      # the empty stage again so the uploaded copy is deleted on the worker.
      started=0
      cleanup() {
        rm -f "$stage/secrets.env"
        if [ "$started" = 0 ] && [ -e "$stage/run.sh" ]; then
          (cd "$stage" && heavy sync > /dev/null 2>&1) || true
        fi
      }
      trap cleanup EXIT
      trap 'exit 130' INT TERM
      (
        umask 077
        {
          printf 'GH_REPO=%q\n' ErikFrankling/t3code
          printf 'GH_TOKEN=%q\n' "$(gh auth token)"
          printf 'GOOGLE_SERVICES_JSON=%q\n' "$(secret secrets/notify.yaml t3code-google-services-json)"
          printf 'T3CODE_FCM_SERVICE_ACCOUNT_JSON=%q\n' "$(secret secrets/notify.yaml t3code-fcm-service-account)"
          printf 'ERIK_UPDATES_PRIVATE_KEY=%q\n' "$(secret hosts/pc/secrets/secrets.yaml t3code-updates-private-key)"
          printf 'ANDROID_KEYSTORE_B64=%q\n' "$(secret hosts/pc/secrets/secrets.yaml t3code-android-keystore)"
          printf 'ANDROID_KEYSTORE_PASSWORD=%q\n' "$(secret hosts/pc/secrets/secrets.yaml t3code-android-keystore-password)"
          printf 'ANDROID_KEY_ALIAS=%q\n' t3code-erik
          printf 'FORCE_APK=%q\nACCEPT_DROPPED_COMMITS=%q\nEXTRA_TEST_ABI=%q\n' "$force_apk" "$accept" "$test_abi"
          printf 'COMMIT=%q\nPREBUILT_APK=%q\n' "$commit" "$prebuilt"
          # No Actions run will publish a newer commit, so this one may go out
          # while erik/main moves on (scripts/erik-updates-guard.sh).
          printf 'ALLOW_BEHIND_TIP=true\n'
        } > "$stage/secrets.env"
      )
      cat > "$stage/run.sh" <<'EOF'
      set -euo pipefail
      set -a
      . ./secrets.env
      set +a
      rm -f secrets.env
      rm -rf repo out
      # The worker image has nix; take git from it too.
      PATH="$(nix build --no-link --print-out-paths nixpkgs#git)/bin:$PATH"
      git clone --quiet "https://github.com/$GH_REPO.git" repo
      cd repo
      if [ -n "$COMMIT" ]; then
        # Also a commit a rebase removed from erik/main (GitHub still has it).
        git fetch --quiet origin "$COMMIT"
        git checkout --quiet --detach "$COMMIT"
        # The release tooling always comes from erik/main, whatever commit
        # is released (an older commit carries older guards).
        git checkout --quiet origin/erik/main -- scripts/erik-android-release.sh \
          scripts/erik-updates-guard.sh scripts/erik-updates-release.sh \
          scripts/erik-updates.mjs scripts/erik-updates-ping.mjs
      else
        git checkout --quiet --detach origin/erik/main
      fi
      echo "release of erik/main at $(git rev-parse --short HEAD)"
      [ -n "$PREBUILT_APK" ] || unset PREBUILT_APK
      tools="$(nix build --no-link --print-out-paths nixpkgs#gh)/bin:$(nix build --no-link --print-out-paths nixpkgs#unzip)/bin"
      # Gradle inside the worker's 10 GB job cap: two workers, no Kotlin daemon.
      export OUT="$PWD/../out" GRADLE_ARGS="--max-workers=2 -Pkotlin.compiler.execution.strategy=in-process -Dorg.gradle.jvmargs=-Xmx3g"
      nix develop .#android -c bash -c "export PATH=\"\$PATH:$tools\"
        CI=true pnpm install --frozen-lockfile --filter=@t3tools/mobile... > ../install.log 2>&1 || { tail -30 ../install.log; exit 1; }
        scripts/erik-android-release.sh"
      EOF
      cd "$stage"
      echo "staging in $stage"
      # A background job keeps running on the worker if this PC-side command
      # dies (an agent session restart); `heavy logs -f <name>` reattaches.
      name="t3-android-release-$(date +%H%M%S)"
      # Publishing a prebuilt APK builds nothing: the small slot is enough.
      class=--big
      if [ -n "$prebuilt" ]; then class=--small; fi
      heavy bg "$name" "$class" --no-develop -- bash run.sh
      started=1
      heavy logs -f "$name"
      if [ -n "$test_abi" ]; then heavy pull out; fi
    '';
  };
in
{
  home.packages = [ t3-android-release ];
}
