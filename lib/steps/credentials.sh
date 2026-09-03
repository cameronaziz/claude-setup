step_credentials() {
step "Git credentials"
CRED_HELPER="$(git config --global credential.helper || true)"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving credential.helper alone"
elif [[ "$(uname -s)" != "Darwin" ]]; then
  say "not macOS, skipping osxkeychain"
elif [[ -n "$CRED_HELPER" ]]; then
  say "credential.helper already set to '$CRED_HELPER', not overwriting"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would set credential.helper to osxkeychain"
else
  git config --global credential.helper osxkeychain
  say "set credential.helper to osxkeychain"
fi

if [[ $UNINSTALL -eq 0 && "$(uname -s)" == "Darwin" ]]; then
  if printf 'protocol=https\nhost=dev.azure.com\n\n' \
     | git credential-osxkeychain get 2>/dev/null | grep -q '^password='; then
    say "dev.azure.com credential found in Keychain"
  else
    say "no dev.azure.com credential yet, first clone will prompt for a PAT:"
    say "  git clone https://dev.azure.com/precisionfilter/ERP/_git/<repo>"
  fi
fi
}
