cask "keyminder" do
  version "0.1.101"
  sha256 "4e337e13c1539e23026d11672b9a9ea488e01792a856fbef5de2da57aef986a6"

  url "https://keyminder.app/KeyMinder_#{version}.zip"
  name "KeyMinder"
  desc "Menu-bar app that shows keyboard shortcuts of the frontmost app"
  homepage "https://keyminder.app"

  depends_on macos: ">= :sonoma"

  app "KeyMinder.app"

  zap trash: "~/Library/Preferences/org.afaik.KeyMinder.plist"
end
