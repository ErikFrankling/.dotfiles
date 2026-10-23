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
      while [ $# -gt 0 ]; do
        case "$1" in
          --apk) force_apk=true ;;
          --accept-dropped-commits) accept=true ;;
          --test-abi) test_abi="$2"; shift ;;
          -h | --help) echo "usage: t3-android-release [--apk] [--test-abi ABI] [--accept-dropped-commits]"; exit 0 ;;
          *) echo "unknown argument $1" >&2; exit 2 ;;
        esac
        shift
      done

      dotfiles="$HOME/.dotfiles"
      secret() { sops -d --extract "[\"$2\"]" "$dotfiles/$1"; }
      stage="$HOME/.cache/t3-android-release/$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$stage"
      chmod 700 "$stage"
      # The secrets only exist in this file until the worker loads them.
      trap 'rm -f "$stage/secrets.env"' EXIT
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
      git checkout --quiet --detach origin/erik/main
      echo "release of erik/main at $(git rev-parse --short HEAD)"
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
      heavy bg --big "$name" --no-develop -- bash run.sh
      heavy logs -f "$name"
      if [ -n "$test_abi" ]; then heavy pull out; fi
    '';
  };
in
{
  home.packages = [ t3-android-release ];
}
