step_jj() {
step "Jujutsu"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving jj alone"
elif have jj; then
  say "jj $(jj --version 2>/dev/null | awk '{print $2}')"
elif [[ $BOOTSTRAP -eq 0 ]]; then
  say "jj missing, --no-bootstrap passed, leaving it alone"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would install jj via homebrew"
elif ! need_brew; then
  say "could not get homebrew, install jj by hand: https://jj-vcs.github.io/jj/latest/install-and-setup/"
else
  brew install jj
  have jj && say "jj installed" || say "brew finished but jj is not on PATH"
fi
}
