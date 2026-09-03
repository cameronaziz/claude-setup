# az writes to ~/.azure on every invocation, so a sandbox that denies it makes
# even `az version` fail. Report that rather than calling the CLI healthy.
az_installed_version() {
  local out
  if out="$(az version --query '"azure-cli"' -o tsv 2>&1)"; then
    printf '%s' "$out"
    return 0
  fi
  if grep -q "\.azure" <<<"$out"; then
    printf 'installed but cannot write ~/.azure'
  else
    printf 'installed but not running'
  fi
  return 1
}

az_install() {
  if [[ $BOOTSTRAP -eq 0 ]]; then
    say "az missing, --no-bootstrap passed, leaving it alone"
    return 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    say "would ask to install az via homebrew"
    return 1
  fi
  confirm "Install the Azure CLI? It is a large download." || { say "skipped az"; return 1; }
  need_brew || {
    say "could not get homebrew, install az by hand:"
    say "  https://learn.microsoft.com/cli/azure/install-azure-cli"
    return 1
  }
  brew install azure-cli
  have az || { say "brew finished but az is not on PATH"; return 1; }
  say "az $(az_installed_version) installed"
}

# az login opens a browser and waits, so it needs someone at the keyboard. --yes
# answers the prompt but cannot complete a sign in, so a non-tty is left alone.
az_auth() {
  if az account show >/dev/null 2>&1; then
    say "signed in as $(az account show --query user.name -o tsv 2>/dev/null)"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    say "would ask to run az login"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    say "not signed in, and az login needs a browser. Run 'az login' yourself."
    return 0
  fi
  confirm "Run az login now? It opens a browser." || { say "skipped az login"; return 0; }
  az login >/dev/null || { say "az login did not complete"; return 0; }
  say "signed in as $(az account show --query user.name -o tsv 2>/dev/null)"
}

step_az() {
step "Azure CLI"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving az alone"
elif have az; then
  say "az $(az_installed_version)"
  az_auth
elif az_install; then
  az_auth
fi
}
