step_az() {
step "Azure CLI"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving az alone"
elif have az; then
  say "az $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo installed)"
elif [[ $BOOTSTRAP -eq 0 ]]; then
  say "az missing, --no-bootstrap passed, leaving it alone"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would install az via homebrew"
elif ! need_brew; then
  say "could not get homebrew, install az by hand: https://learn.microsoft.com/cli/azure/install-azure-cli"
else
  say "installing azure-cli via homebrew, this one is large"
  brew install azure-cli
  have az && say "az installed" || say "brew finished but az is not on PATH"
fi
}
