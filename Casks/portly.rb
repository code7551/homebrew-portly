cask "portly" do
  version "1.2.0"
  sha256 "48b32a89aebddb0add3d01f5abb7cb2c7384d88948b21e7b250478f4b3f5b958"

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
