step_toolchain() {
step "Toolchain"

NODE_PENDING=0
if adopt_node; then
  say "node $(node -v)"
elif [[ $BOOTSTRAP -eq 0 ]]; then
  echo "node >= $NODE_MIN was not found and --no-bootstrap was passed." >&2
  exit 1
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would install node >= $NODE_MIN via homebrew"
  NODE_PENDING=1
else
  need_brew || {
    cat >&2 <<'MSG'
Could not get Homebrew. Install node >= 18 another way, then re-run:
  https://nodejs.org/en/download
  curl -fsSL https://fnm.vercel.app/install | bash
MSG
    exit 1
  }
  say "homebrew $(brew --version | head -1 | awk '{print $2}')"
  say "installing node via homebrew"
  brew install node
  adopt_node || { echo "brew install node finished but node >= $NODE_MIN is still not on PATH." >&2; exit 1; }
  say "node $(node -v) installed"
fi

if [[ $NODE_PENDING -eq 1 ]]; then
  say "pnpm check deferred, it needs node"
elif have pnpm; then
  say "pnpm $(pnpm -v)"
elif [[ $BOOTSTRAP -eq 0 ]]; then
  say "pnpm missing, --no-bootstrap passed, leaving it alone"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would enable pnpm via corepack"
elif have corepack && corepack enable pnpm >/dev/null 2>&1 && have pnpm; then
  say "pnpm $(pnpm -v) enabled via corepack"
elif have npm; then
  npm install -g pnpm >/dev/null 2>&1 || { echo "npm install -g pnpm failed." >&2; exit 1; }
  have pnpm || { echo "pnpm installed but is not on PATH." >&2; exit 1; }
  say "pnpm $(pnpm -v) installed via npm"
else
  echo "Neither corepack nor npm is available to install pnpm." >&2
  exit 1
fi

if [[ $NODE_PENDING -eq 1 ]]; then
  step "Done"
  say "dry run stops here: the settings preview needs node, which is not installed yet"
  say "re-run without --dry-run to bootstrap the toolchain, or install node and dry-run again"
  exit 0
fi
}
