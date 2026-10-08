cask "portly" do
  version "1.1.0"
  sha256 "c53248d59d64cc5c9aada5d505bf91f7b7af72e3e2dbb06e5f6ec8b87c62e4cc"

  url "https://github.com/code7551/homebrew-portly/releases/download/v#{version}/Portly-#{version}.zip"
  name "Portly"
  desc "Menu bar widget that shows local dev servers and their ports"
  homepage "https://github.com/code7551/homebrew-portly"

  depends_on macos: :sonoma

  app "Portly.app"
  binary "#{appdir}/Portly.app/Contents/MacOS/Portly", target: "portly"

  # Ad-hoc signed, not notarized: drop the download quarantine so Gatekeeper doesn't block it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Portly.app"], must_succeed: false
  end

  uninstall quit: "com.code7551.portly"

  zap trash: "~/Library/Preferences/com.code7551.portly.plist"

  caveats <<~EOS
    Start Portly now with:
      open -a Portly
    From then on it starts at login (turn that off in its ⋯ menu). Toggle it anywhere with ⌃⌥B.
  EOS
end
